import SwiftUI
import CoreLocation

enum MainTab: CaseIterable {
    case home, jobs, dates, timeTracking, more
    
    var title: String {
        switch self {
        case .home: return "Home"
        case .jobs: return "Jobs"
        case .dates: return "Dates"
        case .timeTracking: return "Time Tracking"
        case .more: return "More"
        }
    }
    
    var systemImage: String {
        switch self {
        case .home: return "house.fill"
        case .jobs: return "list.bullet.rectangle.portrait"
        case .dates: return "calendar"
        case .timeTracking: return "clock.arrow.circlepath"
        case .more: return "ellipsis.circle"
        }
    }
}

enum MoreItem: CaseIterable {
    case settings
    
    var title: String {
        switch self {
        case .settings: return "Settings"
        }
    }
    
    var subtitle: String {
        switch self {
        case .settings: return "Profile, preferences, and app configuration."
        }
    }
    
    var systemImage: String {
        switch self {
        case .settings: return "gearshape"
        }
    }
}

struct QuickLink: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let systemImage: String
    let color: Color
}

struct Trip: Identifiable {
    let id = UUID()
    let title: String
    let pickup: String
    let dropoff: String
    let start: Date
    let end: Date
}

struct ScheduledShift: Identifiable {
    let id = UUID()
    let title: String
    let start: Date
    let end: Date
    let location: String
}

struct MainView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var authManager: AuthenticationManager
    @EnvironmentObject var nfcManager: NFCManager
    @State private var showLogoutAlert = false
    @State private var showNFCResult = false
    @State private var selectedTab: MainTab = .home
    @State private var selectedMoreItem: MoreItem = .settings
    
    private let accentGreen = Color(red: 0.13, green: 0.78, blue: 0.60)
    private let accentRed = Color(red: 0.85, green: 0.24, blue: 0.26)
    private let cardSurface = Color(red: 0.12, green: 0.12, blue: 0.15)
    
    private let trips: [Trip] = [
        Trip(title: "Airport Run", pickup: "City Center", dropoff: "Airport T1", start: Date().addingTimeInterval(-900), end: Date().addingTimeInterval(1200)),
        Trip(title: "Hotel Pickup", pickup: "Airport T2", dropoff: "Grand Hotel", start: Date().addingTimeInterval(3600 * 2), end: Date().addingTimeInterval(3600 * 2.5)),
        Trip(title: "Shuttle Loop", pickup: "Depot A", dropoff: "Campus Main", start: Date().addingTimeInterval(3600 * 4), end: Date().addingTimeInterval(3600 * 5)),
        Trip(title: "Evening Transfer", pickup: "Stadium", dropoff: "Downtown", start: Date().addingTimeInterval(3600 * 6), end: Date().addingTimeInterval(3600 * 7))
    ]
    
    private let upcomingShifts: [ScheduledShift] = [
        ScheduledShift(title: "Morning Shift", start: Date().addingTimeInterval(3600 * 4), end: Date().addingTimeInterval(3600 * 8), location: "Depot A"),
        ScheduledShift(title: "Evening Shift", start: Date().addingTimeInterval(3600 * 12), end: Date().addingTimeInterval(3600 * 16), location: "Depot B")
    ]
    
    private var quickLinks: [QuickLink] {
        [
            QuickLink(title: "Map", subtitle: "Live zones", systemImage: "map.fill", color: accentGreen),
            QuickLink(title: "Fleet", subtitle: "Vehicles", systemImage: "car.2.fill", color: Color.blue),
            QuickLink(title: "History", subtitle: "Past trips", systemImage: "clock.arrow.circlepath", color: Color.purple),
            QuickLink(title: "Time Log", subtitle: "Hours", systemImage: "clock.badge", color: Color.orange)
        ]
    }
    
    var body: some View {
        TabView(selection: $selectedTab) {
            homeTab
            .tabItem {
                Label(MainTab.home.title, systemImage: MainTab.home.systemImage)
            }
            .tag(MainTab.home)
            
            tabWrapper(title: MainTab.jobs.title) {
                PlaceholderTab(title: "Jobs", subtitle: "Incoming and assigned jobs will appear here.")
            }
            .tabItem {
                Label(MainTab.jobs.title, systemImage: MainTab.jobs.systemImage)
            }
            .tag(MainTab.jobs)
            
            tabWrapper(title: MainTab.dates.title) {
                PlaceholderTab(title: "Dates", subtitle: "Manage upcoming dates and schedules.")
            }
            .tabItem {
                Label(MainTab.dates.title, systemImage: MainTab.dates.systemImage)
            }
            .tag(MainTab.dates)
            
            tabWrapper(title: MainTab.timeTracking.title) {
                PlaceholderTab(title: "Time Tracking", subtitle: "Clock-in/out history and hours summary.")
            }
            .tabItem {
                Label(MainTab.timeTracking.title, systemImage: MainTab.timeTracking.systemImage)
            }
            .tag(MainTab.timeTracking)
            
            tabWrapper(title: MainTab.more.title) {
                moreTabContent
            }
            .tabItem {
                Label(MainTab.more.title, systemImage: MainTab.more.systemImage)
            }
            .tag(MainTab.more)
        }
        .tint(accentGreen)
        .alert("Logout", isPresented: $showLogoutAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Logout", role: .destructive) {
                locationManager.stopShift()
                authManager.logout()
            }
        } message: {
            Text("Are you sure you want to logout?")
        }
    }
    
    private var homeTab: some View {
        NavigationView {
            homeTabContent
                .toolbar(.hidden, for: .navigationBar)
        }
    }
    
    private func tabWrapper<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    content()
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private var homeTabContent: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.10, blue: 0.12), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 18) {
                    homeHeader
                    shiftControlButton
                    activeTripSection
                    upcomingTripsSection
                    quickLinksSection
                    nfcSection
                    diagnosticsSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
        }
    }
    
    private var homeHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Home")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text(headerDateText)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            Image(systemName: "line.3.horizontal")
                .foregroundColor(.white)
                .padding(12)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
        }
        .foregroundColor(.white)
    }
    
    private var shiftControlButton: some View {
        Button(action: toggleShift) {
            HStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(0.15))
                        .frame(width: 56, height: 56)
                    if locationManager.isShiftActive {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.white)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .offset(x: 2)
                            .font(.system(size: 20, weight: .bold))
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(locationManager.isShiftActive ? "End Shift" : "Start Shift")
                        .font(.headline)
                        .fontWeight(.bold)
                    Text(locationManager.isShiftActive ? "Clock out and stop tracking" : "Clock in and begin tracking")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                Spacer()
                Image(systemName: locationManager.isShiftActive ? "power" : "play.circle.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundColor(.white.opacity(0.9))
            }
            .padding(18)
            .background(
                LinearGradient(
                    colors: locationManager.isShiftActive ? [accentRed, Color(red: 0.65, green: 0.0, blue: 0.0)] : [accentGreen, Color(red: 0.14, green: 0.62, blue: 0.45)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(22)
            .shadow(color: (locationManager.isShiftActive ? accentRed : accentGreen).opacity(0.35), radius: 14, x: 0, y: 10)
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(locationManager.isRequestingLocationPermission)
    }
    
    private var activeTripSection: some View {
        Group {
            if locationManager.isShiftActive, let trip = currentTrip {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 10) {
                        Circle()
                            .fill(accentGreen)
                            .frame(width: 10, height: 10)
                            .opacity(0.9)
                        Text("Active Trip")
                            .font(.headline)
                        Spacer()
                        Text(timeRange(for: trip))
                            .font(.subheadline)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    tripStopRow(icon: "mappin.circle.fill", title: "Pickup", subtitle: trip.pickup, color: .red)
                    tripStopRow(icon: "location.north.line.fill", title: "Drop-off", subtitle: trip.dropoff, color: Color.blue)
                    
                    NavigationLink {
                        DriverMapScreen()
                    } label: {
                        Text("Navigate")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(accentGreen)
                            .foregroundColor(.black)
                            .cornerRadius(12)
                    }
                }
                .padding()
                .background(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .stroke(accentGreen.opacity(0.35), lineWidth: 1)
                )
                .cornerRadius(18)
                .foregroundColor(.white)
            }
        }
    }
    
    private func tripStopRow(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.headline)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.6))
                Text(subtitle)
                    .font(.headline)
                    .foregroundColor(.white)
            }
            Spacer()
        }
    }
    
    private var upcomingTripsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Upcoming Trips")
                .font(.headline)
                .foregroundColor(.white)
            
            if upcomingTrips.isEmpty {
                Text("No upcoming trips scheduled.")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.subheadline)
            } else {
                VStack(spacing: 12) {
                    ForEach(upcomingTrips) { trip in
                        upcomingTripCard(trip)
                    }
                }
            }
        }
    }
    
    private func upcomingTripCard(_ trip: Trip) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "clock")
                    .foregroundColor(.white.opacity(0.6))
                Text(timeRange(for: trip))
                    .foregroundColor(.white.opacity(0.8))
                    .font(.subheadline)
                Spacer()
            }
            tripStopRow(icon: "mappin.circle.fill", title: "Pickup", subtitle: trip.pickup, color: .red)
            tripStopRow(icon: "location.north.line.fill", title: "Drop-off", subtitle: trip.dropoff, color: Color.blue)
        }
        .padding()
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(16)
        .foregroundColor(.white)
    }
    
    private var quickLinksSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick Access")
                .font(.headline)
                .foregroundColor(.white)
            
            let columns = [GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(quickLinks) { link in
                    if link.title == "Map" {
                        NavigationLink {
                            DriverMapScreen()
                        } label: {
                            HomeQuickAccessCard(link: link)
                        }
                        .buttonStyle(PlainButtonStyle())
                    } else {
                        HomeQuickAccessCard(link: link)
                    }
                }
            }
        }
    }
    
    private var nfcSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("NFC")
                    .font(.headline)
                Spacer()
                if nfcManager.isScanning {
                    Text("Scanning...")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.7))
                }
            }
            .foregroundColor(.white)
            
            Button(action: {
                nfcManager.startScanning()
            }) {
                HStack {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                        .font(.system(size: 20, weight: .bold))
                    Text(nfcManager.isScanning ? "Hold near a tag" : "Start NFC Scan")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .foregroundColor(.black)
                .padding()
                .background(accentGreen)
                .cornerRadius(12)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(nfcManager.isScanning)
            
            if let result = nfcManager.lastScanResult {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Last Scan")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                    DebugRow(label: "Tag ID", value: result.tagID)
                    if let cmac = result.cmac {
                        DebugRow(label: "CMAC", value: cmac)
                    } else {
                        DebugRow(label: "CMAC", value: "Not available (requires authentication)")
                    }
                    DebugRow(label: "Scanned At", value: DateFormatter.timeFormatter.string(from: result.timestamp))
                }
                .foregroundColor(.white)
            }
            
            if let errorMessage = nfcManager.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding()
        .background(cardSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(16)
    }
    
    private var diagnosticsSection: some View {
        Group {
            if locationManager.isShiftActive {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("Shift Diagnostics")
                            .font(.headline)
                        Spacer()
                        Text(currentShiftTimeText)
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.7))
                    }
                    
                    DebugRow(label: "Status", value: "Active")
                    DebugRow(label: "Latitude", value: String(format: "%.6f", locationManager.lastLocation?.coordinate.latitude ?? 0))
                    DebugRow(label: "Longitude", value: String(format: "%.6f", locationManager.lastLocation?.coordinate.longitude ?? 0))
                    DebugRow(label: "Speed", value: String(format: "%.2f m/s", locationManager.lastLocation?.speed ?? 0))
                    DebugRow(label: "Battery", value: batteryText)
                    DebugRow(label: "Charging", value: chargingText)
                    DebugRow(label: "Low Power Mode", value: lowPowerText)
                    DebugRow(label: "Location Permission", value: permissionText)
                    DebugRow(label: "Updates Sent", value: "\(locationManager.updateCount)")
                    DebugRow(label: "Last Update", value: locationManager.lastUpdateTime ?? "Never")
                }
                .padding()
                .background(cardSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.white.opacity(0.05), lineWidth: 1)
                )
                .cornerRadius(16)
                .foregroundColor(.white)
            }
        }
    }
    
    private var moreTabContent: some View {
        VStack(spacing: 16) {
            settingsRow
            logoutRow
            
            PlaceholderTab(title: selectedMoreItem.title, subtitle: selectedMoreItem.subtitle)
        }
    }
    
    private var batteryText: String {
        if let percentage = locationManager.batteryPercentageValue {
            return "\(percentage)%"
        }
        return "N/A"
    }
    
    private var chargingText: String {
        locationManager.isBatteryCharging ? "Yes" : "No"
    }
    
    private var lowPowerText: String {
        locationManager.isLowPowerModeEnabled ? "On" : "Off"
    }
    
    private var permissionText: String {
        locationManager.isLocationPermissionGranted ? "Always" : "Not Always"
    }
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }
    
    private var currentShiftTimeText: String {
        if let start = UserDefaults.standard.object(forKey: "shiftStartTime") as? Date {
            return "Started at \(timeFormatter.string(from: start))"
        }
        return "Active"
    }
    
    private var currentTrip: Trip? {
        trips.first
    }
    
    private var upcomingTrips: [Trip] {
        Array(trips.dropFirst().prefix(3))
    }
    
    private func toggleShift() {
        if locationManager.isShiftActive {
            locationManager.stopShift()
        } else {
            locationManager.startShift()
        }
    }
    
    private func timeRange(for trip: Trip) -> String {
        "\(timeFormatter.string(from: trip.start)) - \(timeFormatter.string(from: trip.end))"
    }
    
    private var headerDateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEEE, MMM d"
        return formatter.string(from: Date())
    }
    
    private var settingsRow: some View {
        Button {
            selectedMoreItem = .settings
        } label: {
            HStack {
                Image(systemName: MoreItem.settings.systemImage)
                    .foregroundColor(.blue)
                Text("Settings")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private var logoutRow: some View {
        Button {
            showLogoutAlert = true
        } label: {
            HStack {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .foregroundColor(.red)
                Text("Logout")
                    .foregroundColor(.primary)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.1))
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct HomeQuickAccessCard: View {
    let link: QuickLink
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                Circle()
                    .fill(link.color.opacity(0.18))
                    .frame(width: 42, height: 42)
                Image(systemName: link.systemImage)
                    .foregroundColor(link.color)
                    .font(.system(size: 18, weight: .semibold))
            }
            
            Text(link.title)
                .font(.headline)
                .foregroundColor(.white)
            Text(link.subtitle)
                .font(.caption)
                .foregroundColor(.white.opacity(0.72))
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.14, green: 0.14, blue: 0.17))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.white.opacity(0.05), lineWidth: 1)
        )
        .cornerRadius(14)
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label + ":")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
        }
    }
}

struct PlaceholderTab: View {
    let title: String
    let subtitle: String
    
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text(title)
                .font(.title2)
                .fontWeight(.semibold)
            Text(subtitle)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, minHeight: 300)
    }
}

