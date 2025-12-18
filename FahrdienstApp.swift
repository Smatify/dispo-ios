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
        _locationManager = StateObject(wrappedValue: LocationManager(authManager: auth))
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(authManager)
                .environmentObject(locationManager)
                .environmentObject(nfcManager)
                .onAppear {
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
                .onChange(of: authManager.isAuthenticated) { isAuthenticated in
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

