import UIKit
import UserNotifications

class FahrdienstAppDelegate: NSObject, UIApplicationDelegate {
    // Keep strong reference to LocationManager to ensure it persists when app is backgrounded/terminated
    var locationManager: LocationManager?
    private var authManager: AuthenticationManager?
    
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        // Set up notification delegate
        UNUserNotificationCenter.current().delegate = NotificationManager.shared
        
        // Check if app was launched in background for location updates
        let isBackgroundLaunch = launchOptions?[.location] != nil
        if isBackgroundLaunch {
            print("🔄 App launched in background for location update")
        }
        
        // Create LocationManager early so it works even if SwiftUI doesn't fully initialize
        // This is critical for background location updates when app is terminated
        // Use async to avoid blocking, but ensure it happens quickly
        Task { @MainActor in
            self.setupLocationManager()
        }
        
        // Also try to set it up synchronously on main thread if possible (for immediate background launches)
        if Thread.isMainThread {
            setupLocationManagerSync()
        }
        
        return true
    }
    
    @MainActor
    private func setupLocationManager() {
        // Only create if not already created
        guard locationManager == nil else {
            print("ℹ️ LocationManager already exists in AppDelegate")
            return
        }
        
        setupLocationManagerSync()
    }
    
    @MainActor
    private func setupLocationManagerSync() {
        // Create AuthenticationManager to restore auth token from UserDefaults
        let auth = AuthenticationManager()
        self.authManager = auth
        
        // Create LocationManager with auth manager
        // This ensures location updates can send API requests even when app is terminated
        let locationMgr = LocationManager(authManager: auth)
        self.locationManager = locationMgr
        
        print("✅ LocationManager created in AppDelegate - ready for background updates")
        print("   Auth token available: \(auth.authToken != nil ? "Yes" : "No")")
        print("   Shift active: \(UserDefaults.standard.bool(forKey: "isShiftActive"))")
        
        // If shift was active, LocationManager will restore it automatically in its init
    }
    
    // Called when device token is successfully registered
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            NotificationManager.shared.didRegisterForRemoteNotifications(deviceToken: deviceToken)
        }
    }
    
    // Called if registration fails
    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            NotificationManager.shared.didFailToRegisterForRemoteNotifications(error: error)
        }
    }
    
    // Handle remote notification when app is launched from notification
    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Task { @MainActor in
            NotificationManager.shared.handleNotification(userInfo: userInfo)
        }
        completionHandler(.newData)
    }
}

