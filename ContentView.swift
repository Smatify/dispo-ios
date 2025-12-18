import SwiftUI

struct ContentView: View {
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var locationManager: LocationManager
    @AppStorage("hasSeenPermissions") private var hasSeenPermissions = false
    
    var body: some View {
        Group {
            if !hasSeenPermissions {
                PermissionsIntroductionView()
            } else if !authManager.isAuthenticated {
                LoginView()
            } else {
                MainView()
            }
        }
    }
}

