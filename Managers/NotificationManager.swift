import Foundation
import UserNotifications
import UIKit
import Combine

@MainActor
class NotificationManager: NSObject, ObservableObject {
    static let shared = NotificationManager()
    
    @Published var deviceToken: String?
    @Published var isRegisteredForRemoteNotifications = false
    
    private let apiService = APIService()
    private weak var authManager: AuthenticationManager?
    private var pendingToken: String? // Store token if received before login
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }
    
    func configure(authManager: AuthenticationManager) {
        self.authManager = authManager
        
        // If we have a pending token and now have auth, send it
        if let token = pendingToken, authManager.authToken != nil {
            print("📱 Auth token now available, sending pending device token...")
            pendingToken = nil
            sendDeviceTokenToBackend(token: token)
        }
    }
    
    // MARK: - Register for Push Notifications
    
    func registerForPushNotifications() {
        print("🔔 Starting push notification registration...")
        print("   Auth manager available: \(authManager != nil)")
        print("   Auth token available: \(authManager?.authToken != nil)")
        
        // Request notification permission first
        Task {
            print("🔔 Requesting notification permission...")
            let granted = await PermissionManager.shared.requestNotificationPermission()
            
            guard granted else {
                print("⚠️ Notification permission denied")
                return
            }
            
            print("✅ Notification permission granted")
            
            // Register for remote notifications
            // Note: This will fail silently if push notifications aren't supported
            // (e.g., with free Apple Developer accounts)
            await MainActor.run {
                print("🔔 Registering with APNs...")
                print("   Note: Push notifications require a paid Apple Developer account")
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }
    
    // Manual retry method to send pending token
    func retrySendingDeviceToken() {
        if let token = pendingToken ?? deviceToken {
            print("🔄 Retrying to send device token...")
            sendDeviceTokenToBackend(token: token)
        } else {
            print("⚠️ No device token available to send")
        }
    }
    
    // Call this when device token is received
    func didRegisterForRemoteNotifications(deviceToken: Data) {
        let tokenParts = deviceToken.map { data in String(format: "%02.2hhx", data) }
        let token = tokenParts.joined()
        self.deviceToken = token
        
        print("📱 Device token received: \(token)")
        print("📱 Auth manager available: \(authManager != nil)")
        print("📱 Auth token available: \(authManager?.authToken != nil)")
        
        // Try to send token to backend immediately
        // If auth token is not available, store it and retry later
        if authManager?.authToken != nil {
            sendDeviceTokenToBackend(token: token)
        } else {
            print("⚠️ Auth token not available yet, storing token for later")
            pendingToken = token
        }
    }
    
    // Call this if registration fails
    func didFailToRegisterForRemoteNotifications(error: Error) {
        let errorMessage = error.localizedDescription
        print("❌ Failed to register for remote notifications: \(errorMessage)")
        
        // Check if it's due to missing push notification capability
        if errorMessage.contains("aps-environment") || errorMessage.contains("Push Notifications") {
            print("⚠️ Push notifications are not available with a free Apple Developer account")
            print("⚠️ You need a paid Apple Developer Program membership ($99/year) to use push notifications")
            print("⚠️ The app will continue to work, but push notifications will be disabled")
        }
        
        isRegisteredForRemoteNotifications = false
    }
    
    // MARK: - Send Device Token to Backend
    
    private func sendDeviceTokenToBackend(token: String) {
        guard let authToken = authManager?.authToken else {
            print("⚠️ No auth token available. Cannot send device token.")
            print("⚠️ Storing token to retry later...")
            pendingToken = token
            return
        }
        
        print("📤 Sending device token to backend...")
        print("   Token: \(token)")
        print("   Auth token: \(authToken.prefix(20))...")
        
        Task {
            do {
                try await apiService.registerDeviceToken(token: token, authToken: authToken)
                await MainActor.run {
                    isRegisteredForRemoteNotifications = true
                    pendingToken = nil // Clear pending token on success
                }
                print("✅ Device token sent to backend successfully")
            } catch {
                print("❌ Failed to send device token to backend: \(error)")
                print("   Error details: \(error.localizedDescription)")
                // Keep pendingToken set so we can retry later
                pendingToken = token
            }
        }
    }
    
    // MARK: - Handle Incoming Notifications
    
    func handleNotification(userInfo: [AnyHashable: Any]) {
        print("📬 Received notification: \(userInfo)")
        
        // Extract notification data
        if let aps = userInfo["aps"] as? [String: Any] {
            if let alert = aps["alert"] as? [String: Any] {
                let title = alert["title"] as? String ?? ""
                let body = alert["body"] as? String ?? ""
                print("   Title: \(title)")
                print("   Body: \(body)")
            } else if let alert = aps["alert"] as? String {
                print("   Alert: \(alert)")
            }
            
            // Handle custom data
            if let rideRequestId = userInfo["rideRequestId"] as? String {
                print("   Ride Request ID: \(rideRequestId)")
                // Handle ride request notification
            }
            
            if let notificationType = userInfo["type"] as? String {
                print("   Type: \(notificationType)")
                // Handle different notification types
            }
        }
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension NotificationManager: UNUserNotificationCenterDelegate {
    // Handle notification when app is in foreground
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Show notification even when app is in foreground
        completionHandler([.banner, .sound, .badge])
        
        // Handle notification data
        Task { @MainActor in
            handleNotification(userInfo: notification.request.content.userInfo)
        }
    }
    
    // Handle notification tap/interaction
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Handle notification tap
        Task { @MainActor in
            handleNotification(userInfo: response.notification.request.content.userInfo)
        }
        
        completionHandler()
    }
}

