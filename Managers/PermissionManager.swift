import Foundation
import UserNotifications
import CoreLocation
import Combine

@MainActor
class PermissionManager: NSObject, ObservableObject {
    static let shared = PermissionManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var notificationPermissionStatus: UNAuthorizationStatus = .notDetermined
    @Published var locationPermissionStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkPermissionStatuses()
    }
    
    func checkPermissionStatuses() {
        Task {
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationPermissionStatus = settings.authorizationStatus
            locationPermissionStatus = locationManager.authorizationStatus
        }
    }
    
    // MARK: - Notification Permissions
    
    func requestNotificationPermission() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge]
            )
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationPermissionStatus = settings.authorizationStatus
            return granted
        } catch {
            print("Notification permission error: \(error)")
            return false
        }
    }
    
    func requestCriticalNotificationPermission() async -> Bool {
        // Critical alerts require special entitlement from Apple
        // For PoC, we'll request it as part of the regular notification permission
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(
                options: [.alert, .sound, .badge, .criticalAlert]
            )
            let settings = await UNUserNotificationCenter.current().notificationSettings()
            notificationPermissionStatus = settings.authorizationStatus
            return granted
        } catch {
            print("Critical notification permission error: \(error)")
            return false
        }
    }
    
    // MARK: - Location Permissions
    
    func requestLocationWhenInUsePermission() {
        let currentStatus = locationManager.authorizationStatus
        if currentStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        } else {
            // Already requested or granted, update status
            locationPermissionStatus = currentStatus
        }
    }
    
    func requestLocationAlwaysPermission() {
        // iOS requires "when in use" permission first before requesting "always"
        let currentStatus = locationManager.authorizationStatus
        
        switch currentStatus {
        case .authorizedWhenInUse:
            // User has granted "when in use", now request "always"
            locationManager.requestAlwaysAuthorization()
            
        case .notDetermined:
            // If not determined, we need to request "when in use" first
            // This should have been done in the previous step
            // But if user skipped, request it now
            locationManager.requestWhenInUseAuthorization()
            
        case .authorizedAlways:
            // Already granted "always" permission
            locationPermissionStatus = currentStatus
            
        default:
            // Denied or restricted - user needs to go to Settings
            locationPermissionStatus = currentStatus
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension PermissionManager: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            locationPermissionStatus = manager.authorizationStatus
        }
    }
}

