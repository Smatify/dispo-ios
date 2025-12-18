import Foundation
import SwiftUI
import Combine

class AuthenticationManager: ObservableObject {
    @Published var isAuthenticated = false
    @Published var currentUser: User?
    @Published var authToken: String?
    
    struct User {
        let email: String
        let id: String
    }
    
    init() {
        // Check if user is already logged in (from UserDefaults or Keychain)
        if let email = UserDefaults.standard.string(forKey: "userEmail") {
            currentUser = User(email: email, id: UUID().uuidString)
            // Restore auth token if available
            authToken = UserDefaults.standard.string(forKey: "authToken")
            isAuthenticated = true
        }
    }
    
    func login(email: String, password: String) {
        // For PoC, generate a simple token based on email
        // In production, this would make an API call and receive a token
        let token = generateToken(for: email)
        
        currentUser = User(email: email, id: UUID().uuidString)
        authToken = token
        
        // Store credentials
        UserDefaults.standard.set(email, forKey: "userEmail")
        UserDefaults.standard.set(token, forKey: "authToken")
        isAuthenticated = true
    }
    
    func logout() {
        currentUser = nil
        authToken = nil
        isAuthenticated = false
        UserDefaults.standard.removeObject(forKey: "userEmail")
        UserDefaults.standard.removeObject(forKey: "authToken")
    }
    
    // Generate a token for PoC (in production, this comes from the API)
    private func generateToken(for email: String) -> String {
        // For PoC: create a simple token
        // In production, this would be returned from the login API
        let data = "\(email):\(Date().timeIntervalSince1970)".data(using: .utf8)!
        return data.base64EncodedString()
    }
}

