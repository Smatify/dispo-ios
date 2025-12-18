import Foundation
import CoreLocation
import SwiftUI
import Combine
import ActivityKit

@MainActor
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiService = APIService()
    private weak var authManager: AuthenticationManager?
    
    @Published var isShiftActive = false
    @Published var lastLocation: CLLocation?
    @Published var updateCount = 0
    @Published var lastUpdateTime: String?
    @Published var isRequestingLocationPermission = false
    
    private var updateTimer: Timer?
    private var lastSentLocation: CLLocation?
    private var lastUpdateTimestamp: Date?
    
    // Configuration
    private let minDistanceForUpdate: CLLocationDistance = 30 // meters - send update when moved this far
    private let minTimeForUpdate: TimeInterval = 60 // seconds - send update at least once per minute
    
    private var liveActivity: Activity<ShiftStatusAttributes>?
    
    init(authManager: AuthenticationManager? = nil) {
        super.init()
        self.authManager = authManager
        locationManager.delegate = self
        // Use reduced accuracy for better battery life
        // kCLLocationAccuracyHundredMeters is sufficient for ride dispatching
        locationManager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        locationManager.allowsBackgroundLocationUpdates = true
        locationManager.pausesLocationUpdatesAutomatically = false
        // Set distance filter to 30m - iOS will only call delegate when device moves this distance
        // This is MORE battery efficient than requestLocation() because iOS handles filtering at OS level
        locationManager.distanceFilter = 30 // meters
    }
    
    func startShift() {
        guard !isShiftActive else { return }
        
        // Check location permission status
        let status = locationManager.authorizationStatus
        
        // Require "always" permission for background location updates
        guard status == .authorizedAlways else {
            isRequestingLocationPermission = true
            print("⚠️ Location permission not granted. Please grant 'Always' permission in Settings.")
            return
        }
        
        isRequestingLocationPermission = false
        
        // Reset all location tracking state - start completely fresh
        isShiftActive = true
        updateCount = 0
        lastLocation = nil  // Clear any cached location from previous shift
        lastSentLocation = nil
        lastUpdateTimestamp = nil
        lastUpdateTime = nil
        
        print("🔄 Starting new shift - all location state reset")
        
        // Start continuous location updates with distance filtering
        // iOS will automatically call delegate when device moves >30m (distanceFilter)
        // This is battery efficient because iOS handles filtering at OS level
        print("📍 Starting continuous location updates (distance filter: 30m)")
        locationManager.startUpdatingLocation()
        
        // Get initial location immediately for shift start
        locationManager.requestLocation()
        
        // Send shift start to API (will include location once received)
        Task {
            guard let authToken = authManager?.authToken else {
                print("⚠️ No auth token available. Cannot send shift start.")
                return
            }
            
            // Wait a bit for initial location, then send shift start
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            do {
                try await apiService.sendShiftStart(
                    latitude: lastLocation?.coordinate.latitude,
                    longitude: lastLocation?.coordinate.longitude,
                    authToken: authToken
                )
            } catch {
                print("Failed to send shift start: \(error)")
            }
        }
        
        // Start periodic timer to ensure updates are sent at least once per minute
        // This handles the case where device is stationary or moving slowly
        // The distance-based updates handle fast movement (>30m)
        updateTimer = Timer.scheduledTimer(withTimeInterval: minTimeForUpdate, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkTimeBasedUpdate()
            }
        }
        
        // Start Live Activity
        startLiveActivity()
    }
    
    func stopShift() {
        guard isShiftActive else { return }
        
        print("🛑 Stopping shift - clearing location state")
        
        isShiftActive = false
        // Stop any pending location requests
        locationManager.stopUpdatingLocation()
        updateTimer?.invalidate()
        updateTimer = nil
        
        // Clear location state to ensure fresh start on next shift
        // Note: We keep lastLocation for UI display, but reset tracking state
        lastSentLocation = nil
        lastUpdateTimestamp = nil
        
        // End Live Activity
        endLiveActivity()
        
        // Send shift stop to API
        Task {
            guard let authToken = authManager?.authToken else {
                print("⚠️ No auth token available. Cannot send shift stop.")
                return
            }
            
            do {
                try await apiService.sendShiftStop(authToken: authToken)
            } catch {
                print("Failed to send shift stop: \(error)")
            }
        }
    }
    
    // Check if we need to send an update based on time threshold
    // This ensures updates are sent at least once per minute even if stationary
    private func checkTimeBasedUpdate() {
        guard isShiftActive else { return }
        
        guard let location = lastLocation else {
            print("⚠️ No location available for time-based update check")
            return
        }
        
        // Check if enough time has passed since last update
        if let lastUpdate = lastUpdateTimestamp {
            let timeElapsed = Date().timeIntervalSince(lastUpdate)
            if timeElapsed >= minTimeForUpdate {
                print("⏰ Time threshold met (\(Int(timeElapsed))s) - sending location update")
                sendLocationUpdate(location: location)
            } else {
                print("⏱️ Time threshold not met - only \(Int(timeElapsed))s since last update")
            }
        } else {
            // No previous update, send this one
            print("⏰ First time-based update")
            sendLocationUpdate(location: location)
        }
    }
    
    // Check if location update should be sent based on distance and time thresholds
    // Called when location updates arrive (triggered by distanceFilter >30m)
    // Sends update if: moved >30m OR enough time has passed since last update
    private func checkAndSendUpdate() {
        guard let location = lastLocation else {
            print("⚠️ No location available for update check")
            return
        }
        
        var shouldUpdate = false
        
        // Check distance threshold (30 meters)
        // This is the primary trigger - iOS distanceFilter ensures we only get callbacks when moved >30m
        if let lastSent = lastSentLocation {
            let distance = location.distance(from: lastSent)
            if distance >= minDistanceForUpdate {
                shouldUpdate = true
                print("✅ Distance threshold met: \(Int(distance))m >= \(Int(minDistanceForUpdate))m")
            } else {
                print("⏭️ Distance too small: \(Int(distance))m < \(Int(minDistanceForUpdate))m")
            }
        } else {
            // First update - always send
            shouldUpdate = true
            print("✅ First location update")
        }
        
        // Check time threshold (60 seconds)
        // Ensures updates are sent even if stationary (handled by timer)
        if let lastUpdate = lastUpdateTimestamp {
            let timeElapsed = Date().timeIntervalSince(lastUpdate)
            if timeElapsed >= minTimeForUpdate {
                shouldUpdate = true
                print("✅ Time threshold met: \(Int(timeElapsed))s >= \(Int(minTimeForUpdate))s")
            } else if !shouldUpdate {
                print("⏭️ Time too short: \(Int(timeElapsed))s < \(Int(minTimeForUpdate))s")
            }
        } else {
            // First update - always send
            shouldUpdate = true
        }
        
        if shouldUpdate {
            sendLocationUpdate(location: location)
        } else {
            print("⏭️ Update skipped - thresholds not met (will retry on next location update or timer)")
        }
    }
    
    private func sendLocationUpdate(location: CLLocation) {
        let speed = location.speed >= 0 ? location.speed : 0
        
        // Get auth token from AuthenticationManager
        guard let authToken = authManager?.authToken else {
            print("⚠️ No auth token available. Cannot send location update.")
            return
        }
        
        Task {
            do {
                try await apiService.sendLocationUpdate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    speed: speed,
                    authToken: authToken
                )
                
                await MainActor.run {
                    lastSentLocation = location
                    lastUpdateTimestamp = Date()
                    updateCount += 1
                    lastUpdateTime = DateFormatter.timeFormatter.string(from: Date())
                    updateLiveActivity()
                }
            } catch {
                print("Failed to send location update: \(error)")
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        print("📍 Location received: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude), accuracy=\(location.horizontalAccuracy)m")
        
        lastLocation = location
        
        // When location updates come in (triggered by distanceFilter), check if we should send to API
        // This handles distance-based updates (>30m movement)
        if isShiftActive {
            checkAndSendUpdate()
        }
    }
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        if status == .authorizedAlways || status == .authorizedWhenInUse {
            isRequestingLocationPermission = false
            // If shift is active, restart location updates
            if isShiftActive {
                print("📍 Restarting location updates after permission granted...")
                locationManager.startUpdatingLocation()
                if lastLocation == nil {
                    // Request initial location immediately
                    locationManager.requestLocation()
                }
            }
        } else if status == .denied || status == .restricted {
            isRequestingLocationPermission = true
            if isShiftActive {
                stopShift()
            }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        // If it's a temporary error, we can retry
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown, .network:
                // Temporary errors - retry after a delay
                if isShiftActive {
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        await MainActor.run {
                            requestLocationForUpdate()
                        }
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Live Activity
    
    private func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            print("Live Activities are not enabled")
            return
        }
        
        let attributes = ShiftStatusAttributes(name: "ShiftStatus")
        let contentState = ShiftStatusAttributes.ContentState(
            isActive: true,
            updateCount: updateCount,
            lastUpdate: lastUpdateTime ?? "Starting..."
        )
        
        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        
        do {
            liveActivity = try Activity.request(
                attributes: attributes,
                content: activityContent,
                pushType: nil
            )
        } catch {
            print("Failed to start Live Activity: \(error)")
        }
    }
    
    private func updateLiveActivity() {
        guard let liveActivity = liveActivity else { return }
        
        let contentState = ShiftStatusAttributes.ContentState(
            isActive: isShiftActive,
            updateCount: updateCount,
            lastUpdate: lastUpdateTime ?? "Never"
        )
        
        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        
        Task {
            await liveActivity.update(activityContent)
        }
    }
    
    private func endLiveActivity() {
        guard let liveActivity = liveActivity else { return }
        
        let contentState = ShiftStatusAttributes.ContentState(
            isActive: false,
            updateCount: updateCount,
            lastUpdate: lastUpdateTime ?? "Never"
        )
        
        let activityContent = ActivityContent(state: contentState, staleDate: nil)
        
        Task {
            await liveActivity.end(activityContent, dismissalPolicy: .immediate)
        }
        
        self.liveActivity = nil
    }
}

extension DateFormatter {
    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .medium
        return formatter
    }()
}

