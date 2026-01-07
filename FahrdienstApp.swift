import SwiftUI
import UserNotifications

@main
struct FahrdienstApp: App {
    @UIApplicationDelegateAdaptor(FahrdienstAppDelegate.self) var appDelegate
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var locationManager: LocationManager
    @StateObject private var notificationManager = NotificationManager.shared
    @StateObject private var nfcManager = NFCManager()
    
    init() {
        let auth = AuthenticationManager()
        _authManager = StateObject(wrappedValue: auth)
        let locationMgr = LocationManager(authManager: auth)
        _locationManager = StateObject(wrappedValue: locationMgr)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(locationManager)
                .environmentObject(nfcManager)
                .onAppear {
                    // Use LocationManager from AppDelegate if it exists (created for background launches)
                    // Otherwise store this one in AppDelegate
                    if let existingManager = appDelegate.locationManager {
                        // AppDelegate already has a LocationManager (from background launch)
                        // Update its auth manager reference and use it
                        existingManager.updateAuthManager(authManager)
                        // Note: We can't replace the @StateObject, but AppDelegate's instance will handle background updates
                        print("✅ Using LocationManager from AppDelegate (background launch)")
                    } else {
                        // Store LocationManager reference in app delegate to keep it alive when app backgrounds
                        appDelegate.locationManager = locationManager
                        print("✅ Storing LocationManager in AppDelegate")
                    }
                    
                    // Configure notification manager with the correct auth manager instance
                    notificationManager.configure(authManager: authManager)
                    
                    // Register for push notifications when app launches (after login)
                    if authManager.isAuthenticated {
                        print("🔔 User already authenticated, registering for push notifications...")
                        notificationManager.registerForPushNotifications()
                    } else {
                        print("🔔 User not authenticated yet, will register after login")
                    }
                }
                .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
                    // Update auth manager reference when auth state changes
                    notificationManager.configure(authManager: authManager)
                    
                    // Register for push notifications when user logs in
                    if isAuthenticated {
                        print("🔔 User logged in, registering for push notifications...")
                        notificationManager.registerForPushNotifications()
                    }
                }
        }
    }
}

