import SwiftUI
import MapKit

struct DriverMapView: View {
    @ObservedObject var viewModel: DriverMapViewModel
    @EnvironmentObject var locationManager: LocationManager
    @available(iOS 17.0, *)
    @State private var cameraPosition: MapCameraPosition = .automatic
    
    private struct RegionIdentity: Equatable {
        let centerLat: Double
        let centerLon: Double
        let spanLat: Double
        let spanLon: Double
        
        init(region: MKCoordinateRegion) {
            centerLat = region.center.latitude
            centerLon = region.center.longitude
            spanLat = region.span.latitudeDelta
            spanLon = region.span.longitudeDelta
        }
    }
    
    var body: some View {
        ZStack {
            styledMap
            
            VStack(alignment: .trailing, spacing: 8) {
                if let updated = viewModel.lastUpdated {
                    Text("Updated \(relativeDateString(from: updated))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                
                Button {
                    Task { await viewModel.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
            
            VStack(alignment: .trailing, spacing: 10) {
                Button {
                    focusOnUser()
                } label: {
                    Image(systemName: "location.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
                
                Button {
                    viewModel.cycleMapStyle()
                } label: {
                    Label(mapStyleButtonTitle, systemImage: "globe.europe.africa.fill")
                        .font(.footnote.weight(.semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }
    
    @ViewBuilder
    private var styledMap: some View {
        if #available(iOS 17.0, *) {
            let regionIdentity = RegionIdentity(region: viewModel.region)
            
            Map(position: $cameraPosition, interactionModes: .all) {
                ForEach(viewModel.annotations) { annotation in
                    Annotation("", coordinate: annotation.displayCoordinate) {
                        DriverMarkerView(annotation: annotation, zoomLevel: viewModel.zoomLevel)
                    }
                }
            }
            .mapStyle(viewModel.mapKitStyle)
            .ignoresSafeArea()
            .onMapCameraChange { context in
                viewModel.region = context.region
                viewModel.onZoomChanged()
            }
            .onChange(of: regionIdentity) { _, _ in
                cameraPosition = .region(viewModel.region)
            }
            .onAppear {
                cameraPosition = .region(viewModel.region)
            }
        } else {
            legacyMap
        }
    }
    
    @available(iOS, introduced: 14.0, deprecated: 17.0)
    private var legacyMap: some View {
        Map(
            coordinateRegion: $viewModel.region,
            interactionModes: .all,
            showsUserLocation: false,
            annotationItems: viewModel.annotations
        ) { annotation in
            MapAnnotation(coordinate: annotation.displayCoordinate) {
                DriverMarkerView(annotation: annotation, zoomLevel: viewModel.zoomLevel)
            }
        }
        .ignoresSafeArea()
        .onChange(of: viewModel.region.span.latitudeDelta) { _, _ in
            viewModel.onZoomChanged()
        }
    }
    
    private var mapStyleButtonTitle: String {
        switch viewModel.selectedMapStyle {
        case .auto:
            return "Auto (\(viewModel.resolvedMapStyle.label))"
        case .street, .satellite:
            return viewModel.selectedMapStyle.label
        }
    }
    
    private func focusOnUser() {
        locationManager.requestSingleLocation()
        guard let coordinate = locationManager.lastLocation?.coordinate else { return }
        
        let closeSpan = MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        withAnimation(.easeInOut) {
            viewModel.center(on: coordinate, span: closeSpan)
        }
    }
    
    private func relativeDateString(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Driver Marker View

struct DriverMarkerView: View {
    let annotation: DriverAnnotation
    let zoomLevel: Double
    
    @State private var appeared = false
    
    // Dynamic marker size based on zoom
    private var markerSize: CGFloat {
        let baseSize: CGFloat = 46
        let zoomFactor = min(max(zoomLevel / 12, 0.75), 1.25)
        return baseSize * zoomFactor
    }
    
    private let lineColor = Color(white: 0.4)
    
    var body: some View {
        ZStack {
            if annotation.clusterSize > 1 {
                ClusterMarkerView(
                    drivers: annotation.clusterMembers,
                    size: markerSize
                )
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
            } else {
                ProfileMarkerView(
                    avatarURL: annotation.driver.avatar,
                    size: markerSize,
                    batteryLevel: annotation.driver.batteryPercentage,
                    isCharging: annotation.driver.isBatteryCharging,
                    isLowPowerModeEnabled: annotation.driver.isLowPowerModeEnabled
                )
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appeared = true
            }
        }
    }
}

// MARK: - Profile Marker View

struct ProfileMarkerView: View {
    let avatarURL: String
    let size: CGFloat
    let batteryLevel: Double
    let isCharging: Bool
    let isLowPowerModeEnabled: Bool
    
    private var batteryColor: Color {
        if isLowPowerModeEnabled { return .yellow }
        if isCharging { return .green }
        if batteryLevel > 50 { return .green }
        if batteryLevel > 20 { return .orange }
        return .red
    }
    
    private var showBatteryIndicator: Bool {
        batteryLevel < 30
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            // Main profile image
            AsyncImage(url: URL(string: avatarURL)) { phase in
                switch phase {
                case .empty:
                    placeholderView
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: size, height: size)
                        .clipShape(Circle())
                case .failure:
                    placeholderView
                @unknown default:
                    placeholderView
                }
            }
            .frame(width: size, height: size)
            .background(Color.white)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.white, lineWidth: 3)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 4, x: 0, y: 2)
            
            // Battery indicator (only show if low or charging)
            if showBatteryIndicator {
                BatteryIndicatorView(
                    level: batteryLevel,
                    isCharging: isCharging,
                    color: batteryColor
                )
                .offset(x: 4, y: 4)
            }
        }
    }
    
    private var placeholderView: some View {
        Circle()
            .fill(
                LinearGradient(
                    colors: [Color.gray.opacity(0.4), Color.gray.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: size, height: size)
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.white)
                    .font(.system(size: size * 0.4))
            )
    }
}

// MARK: - Cluster Marker View

struct ClusterMarkerView: View {
    let drivers: [DriverMapResponse]
    let size: CGFloat
    
    private var displayedDrivers: [DriverMapResponse] {
        Array(drivers.prefix(4))
    }
    
    private var overflowCount: Int {
        max(drivers.count - 4, 0)
    }
    
    private var count: Int {
        displayedDrivers.count
    }
    
    private var gridPadding: CGFloat {
        8
    }
    
    private var gridSpacing: CGFloat {
        switch count {
        case 2: return -6
        case 3: return -8
        default: return -10
        }
    }
    
    private var avatarSize: CGFloat {
        switch count {
        case 2: return size * 0.9
        case 3: return size * 0.82
        default: return size * 0.75
        }
    }
    
    private var gridSize: CGSize {
        let padding = gridPadding * 2
        switch count {
        case 1:
            let side = avatarSize + padding
            return CGSize(width: side, height: side)
        case 2:
            let width = (avatarSize * 2) + gridSpacing + padding
            let height = avatarSize + padding
            return CGSize(width: width, height: height)
        case 3:
            let width = (avatarSize * 2) + gridSpacing + padding
            let height = (avatarSize * 2) + (gridSpacing * 0.6) + padding
            return CGSize(width: width, height: height)
        default:
            let side = (avatarSize * 2) + gridSpacing + padding
            return CGSize(width: side, height: side)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.ultraThinMaterial)
                .frame(width: gridSize.width, height: gridSize.height)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.35), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.18), radius: 6, x: 0, y: 3)
            
            content
                .frame(
                    width: gridSize.width - (gridPadding * 2),
                    height: gridSize.height - (gridPadding * 2)
                )
                .padding(gridPadding)
            
            if overflowCount > 0 {
                Text("+\(overflowCount)")
                    .font(.system(size: 11, weight: .bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.black.opacity(0.75), in: Capsule())
                    .foregroundColor(.white)
                    .offset(x: 6, y: 6)
            }
        }
        .frame(width: gridSize.width, height: gridSize.height)
    }
    
    @ViewBuilder
    private var content: some View {
        switch count {
        case 1:
            avatar(at: 0)
        case 2:
            HStack(spacing: gridSpacing) {
                avatar(at: 0)
                avatar(at: 1)
            }
        case 3:
            VStack(spacing: gridSpacing) {
                avatar(at: 0)
                HStack(spacing: gridSpacing) {
                    avatar(at: 1)
                    avatar(at: 2)
                }
            }
        default:
            VStack(spacing: gridSpacing) {
                HStack(spacing: gridSpacing) {
                    avatar(at: 0)
                    avatar(at: 1)
                }
                HStack(spacing: gridSpacing) {
                    avatar(at: 2)
                    avatar(at: 3)
                }
            }
        }
    }
    
    @ViewBuilder
    private func avatar(at index: Int) -> some View {
        if displayedDrivers.indices.contains(index) {
            let driver = displayedDrivers[index]
            AsyncImage(url: URL(string: driver.avatar)) { phase in
                switch phase {
                case .empty:
                    placeholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    placeholder
                @unknown default:
                    placeholder
                }
            }
            .frame(width: avatarSize, height: avatarSize)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Color.black.opacity(0.18), radius: 4, x: 0, y: 2)
        } else {
            Color.clear
                .frame(width: avatarSize, height: avatarSize)
        }
    }
    
    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.gray.opacity(0.25))
            .overlay(
                Image(systemName: "person.fill")
                    .foregroundColor(.white.opacity(0.7))
                    .font(.system(size: 16, weight: .semibold))
            )
    }
}

// MARK: - Battery Indicator

struct BatteryIndicatorView: View {
    let level: Double
    let isCharging: Bool
    let color: Color
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.white)
                .frame(width: 18, height: 18)
            
            if isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            } else {
                Image(systemName: "battery.25")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(color)
            }
        }
        .shadow(color: Color.black.opacity(0.15), radius: 2, x: 0, y: 1)
    }
}

// MARK: - Connection Line View

struct ConnectionLineView: View {
    let offset: CGSize
    let lineColor: Color
    let animated: Bool
    
    private let arrowHeadSize: CGFloat = 5
    
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            
            // Calculate line length for animation
            let lineLength = sqrt(offset.width * offset.width + offset.height * offset.height)
            let animatedLength = animated ? lineLength : 0
            let animatedRatio = animatedLength / max(lineLength, 1)
            
            let animatedEnd = CGPoint(
                x: center.x + offset.width * animatedRatio,
                y: center.y + offset.height * animatedRatio
            )
            
            // Draw dashed connecting line
            var linePath = Path()
            linePath.move(to: center)
            linePath.addLine(to: animatedEnd)
            
            context.stroke(
                linePath,
                with: .color(lineColor.opacity(0.7)),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [4, 3])
            )
            
            // Draw arrow head at the end
            let angle = atan2(offset.height, offset.width)
            let arrowAngle1 = angle + .pi * 0.75
            let arrowAngle2 = angle - .pi * 0.75
            
            var arrowPath = Path()
            arrowPath.move(to: animatedEnd)
            arrowPath.addLine(to: CGPoint(
                x: animatedEnd.x - cos(arrowAngle1) * arrowHeadSize,
                y: animatedEnd.y - sin(arrowAngle1) * arrowHeadSize
            ))
            arrowPath.move(to: animatedEnd)
            arrowPath.addLine(to: CGPoint(
                x: animatedEnd.x - cos(arrowAngle2) * arrowHeadSize,
                y: animatedEnd.y - sin(arrowAngle2) * arrowHeadSize
            ))
            
            context.stroke(
                arrowPath,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
            )
            
            // Small pin dot at the actual location
            let dotSize: CGFloat = 8
            let pinPath = Path(ellipseIn: CGRect(
                x: animatedEnd.x - dotSize / 2,
                y: animatedEnd.y - dotSize / 2,
                width: dotSize,
                height: dotSize
            ))
            
            // Pin with border
            context.fill(pinPath, with: .color(lineColor))
            context.stroke(pinPath, with: .color(.white), lineWidth: 1.5)
        }
        .frame(width: 200, height: 200)
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.3), value: animated)
    }
}

// MARK: - Map Screen

struct DriverMapScreen: View {
    @StateObject private var viewModel = DriverMapViewModel()
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ZStack(alignment: .topLeading) {
            DriverMapView(viewModel: viewModel)
                .task {
                    await viewModel.refresh()
                }
                .onAppear {
                    if viewModel.drivers.isEmpty {
                        Task { await viewModel.refresh() }
                    }
                }
            
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.primary)
                    .padding(10)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .padding(16)
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .navigationBar)
    }
}
