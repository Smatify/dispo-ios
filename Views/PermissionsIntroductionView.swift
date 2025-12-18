import SwiftUI
import UserNotifications
import CoreLocation

struct PermissionsIntroductionView: View {
    @AppStorage("hasSeenPermissions") private var hasSeenPermissions = false
    @StateObject private var permissionManager = PermissionManager.shared
    @State private var currentStep = 0
    @State private var isRequestingPermission = false
    
    let permissionSteps: [PermissionStep] = [
        PermissionStep(
            id: 0,
            title: "Notifications",
            description: "We need to send you notifications about new ride requests, important updates, and shift reminders. This ensures you never miss a dispatch.",
            icon: "bell.fill",
            color: .blue,
            type: .notifications
        ),
        PermissionStep(
            id: 1,
            title: "Critical Notifications",
            description: "Critical notifications allow us to alert you even when your phone is in Do Not Disturb mode. This is essential for urgent ride dispatches that require immediate attention.",
            icon: "exclamationmark.triangle.fill",
            color: .orange,
            type: .criticalNotifications
        ),
        PermissionStep(
            id: 2,
            title: "Location Access",
            description: "We need access to your location to track your position while you're on shift. This helps us match you with nearby passengers.",
            icon: "location.fill",
            color: .green,
            type: .locationWhenInUse
        ),
        PermissionStep(
            id: 3,
            title: "Always Allow Location",
            description: "We need continuous location access even when the app is in the background. This ensures we can track your position throughout your entire shift.",
            icon: "location.fill.viewfinder",
            color: .green,
            type: .locationAlways
        )
    ]
    
    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<permissionSteps.count, id: \.self) { index in
                    Circle()
                        .fill(index <= currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 60)
            .padding(.bottom, 40)
            
            // Content
            TabView(selection: $currentStep) {
                ForEach(0..<permissionSteps.count, id: \.self) { index in
                    PermissionStepView(step: permissionSteps[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            
            // Buttons
            VStack(spacing: 16) {
                Button(action: {
                    requestCurrentPermission()
                }) {
                    HStack {
                        if isRequestingPermission {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .padding(.trailing, 8)
                        }
                        Text(getButtonText())
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(getButtonColor())
                    .cornerRadius(12)
                }
                .disabled(isRequestingPermission)
                
                if currentStep < permissionSteps.count - 1 {
                    Button(action: {
                        withAnimation {
                            currentStep += 1
                        }
                    }) {
                        Text("Skip for now")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
                
                if currentStep > 0 {
                    Button(action: {
                        withAnimation {
                            currentStep -= 1
                        }
                    }) {
                        Text("Back")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
        }
        .onChange(of: currentStep) { _ in
            // Auto-advance if permission is already granted
            checkAndAdvanceIfNeeded()
        }
        .onChange(of: permissionManager.locationPermissionStatus) { _ in
            // Auto-advance when location permission status changes
            checkAndAdvanceIfNeeded()
        }
        .onAppear {
            // Check permissions on appear
            permissionManager.checkPermissionStatuses()
            checkAndAdvanceIfNeeded()
        }
    }
    
    private func getButtonText() -> String {
        if isRequestingPermission {
            return "Requesting..."
        }
        
        let step = permissionSteps[currentStep]
        switch step.type {
        case .notifications, .criticalNotifications:
            return "Allow Notifications"
        case .locationWhenInUse:
            return "Allow Location Access"
        case .locationAlways:
            return "Allow Always"
        }
    }
    
    private func getButtonColor() -> Color {
        let step = permissionSteps[currentStep]
        return step.color
    }
    
    private func requestCurrentPermission() {
        let step = permissionSteps[currentStep]
        isRequestingPermission = true
        
        Task {
            switch step.type {
            case .notifications:
                _ = await permissionManager.requestNotificationPermission()
                
            case .criticalNotifications:
                _ = await permissionManager.requestCriticalNotificationPermission()
                
            case .locationWhenInUse:
                permissionManager.requestLocationWhenInUsePermission()
                // Wait a moment for the system dialog to appear
                try? await Task.sleep(nanoseconds: 500_000_000)
                
            case .locationAlways:
                permissionManager.requestLocationAlwaysPermission()
                // Wait a moment for the system dialog to appear
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
            
            await MainActor.run {
                isRequestingPermission = false
                
                // Refresh permission status
                permissionManager.checkPermissionStatuses()
                
                // For location permissions, don't auto-advance immediately
                // User needs to interact with the system dialog first
                let step = permissionSteps[currentStep]
                if case .locationWhenInUse = step.type {
                    // Wait a bit longer for user to respond to location dialog
                    // The onChange will handle advancing if permission is granted
                    return
                }
                
                // If this is the last step, mark permissions as seen
                if currentStep == permissionSteps.count - 1 {
                    hasSeenPermissions = true
                } else {
                    // Auto-advance to next step after a short delay (for non-location permissions)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
            }
        }
    }
    
    private func checkAndAdvanceIfNeeded() {
        let step = permissionSteps[currentStep]
        
        // Check if permission is already granted and advance if so
        switch step.type {
        case .notifications, .criticalNotifications:
            if permissionManager.notificationPermissionStatus == .authorized {
                // Already granted, advance to next step
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation {
                        if currentStep < permissionSteps.count - 1 {
                            currentStep += 1
                        }
                    }
                }
            }
        case .locationWhenInUse:
            // Check if "when in use" or "always" is granted
            if permissionManager.locationPermissionStatus == .authorizedWhenInUse ||
               permissionManager.locationPermissionStatus == .authorizedAlways {
                // Permission granted, advance to next step
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation {
                        if currentStep < permissionSteps.count - 1 {
                            currentStep += 1
                        }
                    }
                }
            }
        case .locationAlways:
            if permissionManager.locationPermissionStatus == .authorizedAlways {
                // "Always" permission granted, mark as complete
                hasSeenPermissions = true
            } else if permissionManager.locationPermissionStatus == .authorizedWhenInUse {
                // Still only "when in use" - user can proceed manually or grant "always" later
            }
        }
    }
}

enum PermissionType {
    case notifications
    case criticalNotifications
    case locationWhenInUse
    case locationAlways
}

struct PermissionStep {
    let id: Int
    let title: String
    let description: String
    let icon: String
    let color: Color
    let type: PermissionType
}

struct PermissionStepView: View {
    let step: PermissionStep
    
    var body: some View {
        VStack(spacing: 32) {
            Image(systemName: step.icon)
                .font(.system(size: 80))
                .foregroundColor(step.color)
            
            VStack(spacing: 16) {
                Text(step.title)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
                
                Text(step.description)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            
            Spacer()
        }
        .padding(.top, 60)
    }
}

