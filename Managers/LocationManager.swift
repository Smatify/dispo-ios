import Foundation
import CoreLocation
import SwiftUI
import Combine
import ActivityKit
import UIKit

class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    private let apiService = APIService()
    private weak var authManager: AuthenticationManager?
    
    @Published var isShiftActive = false {
        didSet {
            // Persist shift state so it can be restored if app is terminated and relaunched
            UserDefaults.standard.set(isShiftActive, forKey: "isShiftActive")
            if isShiftActive {
                UserDefaults.standard.set(Date(), forKey: "shiftStartTime")
            } else {
                UserDefaults.standard.removeObject(forKey: "shiftStartTime")
            }
        }
    }
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
        // Note: allowsBackgroundLocationUpdates will be set in startShift() after verifying "Always" permission
        locationManager.pausesLocationUpdatesAutomatically = false
        // Set distance filter to 30m - iOS will only call delegate when device moves this distance
        // This is MORE battery efficient than requestLocation() because iOS handles filtering at OS level
        locationManager.distanceFilter = minDistanceForUpdate // meters
        // Enable battery monitoring so we can attach battery percentage to location updates
        UIDevice.current.isBatteryMonitoringEnabled = true
        
        // Restore shift state if app was terminated and relaunched
        restoreShiftStateIfNeeded()
    }
    
    // Allow updating auth manager reference (useful when app relaunches and SwiftUI creates new instance)
    func updateAuthManager(_ authManager: AuthenticationManager?) {
        self.authManager = authManager
    }
    
    // Returns battery percentage as an integer 0-100 if available
    private func currentBatteryPercentage() -> Int? {
        let device = UIDevice.current
        if !device.isBatteryMonitoringEnabled {
            device.isBatteryMonitoringEnabled = true
        }
        
        let level = device.batteryLevel
        guard level >= 0 else { return nil } // -1 means unavailable
        return Int(round(level * 100))
    }
    
    var batteryPercentageValue: Int? {
        currentBatteryPercentage()
    }
    
    var isBatteryCharging: Bool {
        let state = UIDevice.current.batteryState
        return state == .charging || state == .full
    }
    
    var isLowPowerModeEnabled: Bool {
        ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    
    var isLocationPermissionGranted: Bool {
        locationManager.authorizationStatus == .authorizedAlways
    }
    
    @MainActor
    func requestSingleLocation() {
        let status = locationManager.authorizationStatus
        
        switch status {
        case .notDetermined:
            isRequestingLocationPermission = true
            locationManager.requestWhenInUseAuthorization()
            locationManager.requestLocation()
        case .authorizedWhenInUse, .authorizedAlways:
            locationManager.requestLocation()
        case .denied, .restricted:
            isRequestingLocationPermission = true
        @unknown default:
            break
        }
    }
    
    @MainActor
    private func restoreShiftStateIfNeeded() {
        let wasShiftActive = UserDefaults.standard.bool(forKey: "isShiftActive")
        if wasShiftActive {
            print("🔄 Restoring shift state after app relaunch")
            let status = locationManager.authorizationStatus
            if status == .authorizedAlways {
                // Restore shift state
                // Note: Don't set isShiftActive directly here to avoid triggering didSet
                // Instead, set the internal state and then update the property
                locationManager.allowsBackgroundLocationUpdates = true
                // Restart significant-change monitoring to survive system termination
                locationManager.startMonitoringSignificantLocationChanges()
                locationManager.startUpdatingLocation()
                
                // Set isShiftActive after configuring location manager
                // This will trigger didSet which saves to UserDefaults
                isShiftActive = true
                
                print("✅ Shift restored - location updates resumed")
                print("   Auth token available: \(authManager?.authToken != nil ? "Yes" : "No")")
            } else {
                // Permission lost, clear shift state
                print("⚠️ Cannot restore shift - 'Always' permission not granted")
                UserDefaults.standard.set(false, forKey: "isShiftActive")
            }
        } else {
            print("ℹ️ No active shift to restore")
        }
    }
    
    @MainActor
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
        
        // Enable background location updates - must be set after "Always" permission is granted
        // This allows location updates even when the app is closed/backgrounded
        locationManager.allowsBackgroundLocationUpdates = true
        
        // Reset all location tracking state - start completely fresh
        isShiftActive = true
        updateCount = 0
        lastLocation = nil  // Clear any cached location from previous shift
        lastSentLocation = nil
        lastUpdateTimestamp = nil
        lastUpdateTime = nil
        
        print("🔄 Starting new shift - all location state reset")
        print("📍 Background location updates enabled - will continue when app is closed")
        
        // Register significant-change monitoring so iOS can relaunch the app after termination
        // This survives system termination (not user force-quit) and restarts location delivery
        print("📍 Starting significant location change monitoring")
        locationManager.startMonitoringSignificantLocationChanges()
        
        // Start continuous location updates with distance filtering for higher update rate
        // iOS will automatically call delegate when device moves >30m (distanceFilter)
        // This is battery efficient because iOS handles filtering at OS level
        print("📍 Starting continuous location updates (distance filter: 30m)")
        locationManager.startUpdatingLocation()
        
        // Get initial location immediately for shift start
        locationManager.requestLocation()
        
        // Send shift start to API (will include location once received)
        Task { [weak self] in
            guard let self = self else { return }
            guard let authToken = self.authManager?.authToken else {
                print("⚠️ No auth token available. Cannot send shift start.")
                return
            }
            
            // Wait a bit for initial location, then send shift start
            try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
            
            do {
                try await self.apiService.sendShiftStart(
                    latitude: self.lastLocation?.coordinate.latitude,
                    longitude: self.lastLocation?.coordinate.longitude,
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
                guard let self else { return }
                self.checkTimeBasedUpdate()
            }
        }
        
        // Start Live Activity
        startLiveActivity()
    }
    
    @MainActor
    func stopShift() {
        guard isShiftActive else { return }
        
        print("🛑 Stopping shift - clearing location state")
        
        isShiftActive = false
        // Stop any pending location requests
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        // Disable background location updates when shift stops
        locationManager.allowsBackgroundLocationUpdates = false
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
    @MainActor
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
    @MainActor
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
    
    @MainActor
    private func sendLocationUpdate(location: CLLocation) {
        let speed = location.speed >= 0 ? location.speed : 0
        let batteryPercentage = batteryPercentageValue
        let isLocationPermissionGranted = isLocationPermissionGranted
        let isLowPowerModeEnabled = isLowPowerModeEnabled
        let isBatteryCharging = isBatteryCharging
        
        // Get auth token from AuthenticationManager
        guard let authToken = authManager?.authToken else {
            print("⚠️ No auth token available. Cannot send location update.")
            return
        }
        
        // Start background task to ensure network request completes even when app is backgrounded
        let application = UIApplication.shared
        let appState = application.applicationState
        let backgroundTaskID: UIBackgroundTaskIdentifier = {
            guard appState != .active else { return .invalid }
            var task: UIBackgroundTaskIdentifier = .invalid
            task = application.beginBackgroundTask(withName: "LocationUpdate") {
                print("⏰ Background task expired for location update")
                application.endBackgroundTask(task)
            }
            
            if task == .invalid {
                print("⚠️ Failed to create background task - may not complete if app is terminated")
            } else {
                print("🌐 Created background task \(task.rawValue) for location update")
            }
            return task
        }()
        
        // Use Task.detached to ensure it runs independently and won't be cancelled
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else {
                print("⚠️ LocationManager deallocated during network request")
                if backgroundTaskID != .invalid {
                    application.endBackgroundTask(backgroundTaskID)
                }
                return
            }
            
            do {
                print("🌐 Sending location update to API (background task: \(backgroundTaskID == .invalid ? "none" : "\(backgroundTaskID.rawValue)"))")
                try await self.apiService.sendLocationUpdate(
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    speed: speed,
                    batteryPercentage: batteryPercentage,
                    isLocationPermissionGranted: isLocationPermissionGranted,
                    isLowPowerModeEnabled: isLowPowerModeEnabled,
                    isBatteryCharging: isBatteryCharging,
                    authToken: authToken
                )
                
                print("✅ Location update sent successfully")
                
                await MainActor.run { [weak self] in
                    guard let self = self else { return }
                    self.lastSentLocation = location
                    self.lastUpdateTimestamp = Date()
                    self.updateCount += 1
                    self.lastUpdateTime = DateFormatter.timeFormatter.string(from: Date())
                    self.updateLiveActivity()
                }
            } catch {
                print("❌ Failed to send location update: \(error.localizedDescription)")
                if let urlError = error as? URLError {
                    print("   URL Error: \(urlError.code.rawValue) - \(urlError.localizedDescription)")
                }
            }
            
            // End background task
            if backgroundTaskID != .invalid {
                print("🏁 Ending background task \(backgroundTaskID.rawValue)")
                application.endBackgroundTask(backgroundTaskID)
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    // Delegate methods must be nonisolated to work in background
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        // Update on main actor for UI updates
        Task { @MainActor [weak self] in
            let appState = UIApplication.shared.applicationState
            let stateDescription = appState == .background ? "BACKGROUND" : (appState == .active ? "FOREGROUND" : "INACTIVE")
            guard let self = self else {
                print("⚠️ LocationManager deallocated, cannot process location update")
                return
            }
            
            print("📍 Location received [\(stateDescription)]: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude), accuracy=\(location.horizontalAccuracy)m")
            
            self.lastLocation = location
            
            // When location updates come in (triggered by distanceFilter), check if we should send to API
            // This handles distance-based updates (>30m movement)
            if self.isShiftActive {
                print("✅ Shift is active, checking if update should be sent...")
                self.checkAndSendUpdate()
            } else {
                print("⏸️ Shift is not active, skipping location update")
            }
        }
    }
    
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        
        Task { @MainActor in
            if status == .authorizedAlways {
                self.isRequestingLocationPermission = false
                // Enable background location updates when "Always" permission is granted
                self.locationManager.allowsBackgroundLocationUpdates = true
                // If shift is active, restart location updates
                if self.isShiftActive {
                    print("📍 Restarting location updates after permission granted...")
                    self.locationManager.startUpdatingLocation()
                    if self.lastLocation == nil {
                        // Request initial location immediately
                        self.locationManager.requestLocation()
                    }
                }
            } else if status == .authorizedWhenInUse {
                self.isRequestingLocationPermission = false
                // Background updates require "Always" permission
                self.locationManager.allowsBackgroundLocationUpdates = false
                if self.isShiftActive {
                    print("⚠️ 'When In Use' permission granted, but 'Always' is required for background updates")
                }
            } else if status == .denied || status == .restricted {
                self.isRequestingLocationPermission = true
                if self.isShiftActive {
                    self.stopShift()
                }
            }
        }
    }
    
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location error: \(error.localizedDescription)")
        
        // If it's a temporary error, we can retry
        if let clError = error as? CLError {
            switch clError.code {
            case .locationUnknown, .network:
                // Temporary errors - retry after a delay
                Task { @MainActor in
                    if self.isShiftActive {
                        try? await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                        self.locationManager.requestLocation()
                    }
                }
            default:
                break
            }
        }
    }
    
    // MARK: - Live Activity
    
    @MainActor
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
    
    @MainActor
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
    
    @MainActor
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

