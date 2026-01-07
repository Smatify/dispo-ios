import Foundation
import MapKit
import Combine
import SwiftUI

struct DriverAnnotation: Identifiable, Equatable {
    let driver: DriverMapResponse
    let clusterMembers: [DriverMapResponse]
    let displayCoordinate: CLLocationCoordinate2D
    let actualCoordinate: CLLocationCoordinate2D
    let pixelOffset: CGSize
    let clusterIndex: Int // Position in cluster (for consistent placement)
    let clusterSize: Int  // Total drivers in this cluster
    
    var id: String { driver.id }
    
    var hasOffset: Bool {
        abs(pixelOffset.width) > 2 || abs(pixelOffset.height) > 2
    }
    
    static func == (lhs: DriverAnnotation, rhs: DriverAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.displayCoordinate.latitude == rhs.displayCoordinate.latitude &&
        lhs.displayCoordinate.longitude == rhs.displayCoordinate.longitude &&
        lhs.clusterSize == rhs.clusterSize
    }
}

enum MapDisplayStyle: String, CaseIterable {
    case street = "Street"
    case satellite = "Satellite"
    case auto = "Auto"
    
    var label: String { rawValue }
}

@MainActor
final class DriverMapViewModel: ObservableObject {
    @Published var region: MKCoordinateRegion
    @Published var drivers: [DriverMapResponse] = []
    @Published var annotations: [DriverAnnotation] = []
    @Published var isLoading = false
    @Published var lastUpdated: Date?
    @Published var zoomLevel: Double = 12
    @Published var selectedMapStyle: MapDisplayStyle = .auto
    @Published private(set) var resolvedMapStyle: MapDisplayStyle = .street
    
    private let service = DriverMapService()
    private var zoomDebounceTask: Task<Void, Never>?
    private let autoSatelliteThresholdMeters: CLLocationDistance = 75
    
    // Dynamic thresholds based on zoom
    private var overlapThresholdDegrees: Double {
        // Higher base so nearby drivers cluster instead of stacking directly
        let baseThreshold = 0.00038
        let zoomFactor = pow(2, 12 - zoomLevel)
        return baseThreshold * zoomFactor
    }
    
    // Spread radius in pixels - larger when zoomed in
    private var spreadRadiusPixels: CGFloat {
        let base: CGFloat = 55
        let factor = min(max(zoomLevel / 12, 0.8), 1.5)
        return base * factor
    }
    
    init() {
        self.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 53.1435, longitude: 8.2146),
            span: MKCoordinateSpan(latitudeDelta: 0.2, longitudeDelta: 0.2)
        )
        updateZoomLevel()
        updateResolvedMapStyle()
    }
    
    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let fetched = try await service.fetchDrivers()
            print("📍 Fetched \(fetched.count) drivers from API")
            drivers = fetched
            // Do not adjust map viewport on refresh; keep user view stable
            updateZoomLevel()
            updateResolvedMapStyle()
            updateAnnotations()
            lastUpdated = Date()
        } catch {
            print("❌ Failed to load drivers: \(error.localizedDescription)")
        }
    }
    
    func recenterToDrivers() {
        guard !drivers.isEmpty else { return }
        region = fittedRegion(for: drivers)
        updateZoomLevel()
        updateAnnotations()
    }
    
    func onZoomChanged() {
        updateZoomLevel()
        updateResolvedMapStyle()
        updateAnnotations()
    }
    
    func cycleMapStyle() {
        guard let currentIndex = MapDisplayStyle.allCases.firstIndex(of: selectedMapStyle) else { return }
        let nextIndex = (currentIndex + 1) % MapDisplayStyle.allCases.count
        selectedMapStyle = MapDisplayStyle.allCases[nextIndex]
        updateResolvedMapStyle()
    }
    
    func center(on coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan = MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)) {
        region = MKCoordinateRegion(center: coordinate, span: span)
        updateZoomLevel()
        updateResolvedMapStyle()
        updateAnnotations()
    }
    
    @available(iOS 17.0, *)
    var mapKitStyle: MapStyle {
        switch resolvedMapStyle {
        case .street:
            return .standard
        case .satellite:
            return .imagery
        case .auto:
            // Auto resolves to street/satellite, but keep a sane default
            return .standard
        }
    }
    
    private func updateZoomLevel() {
        // Calculate zoom level from span (approximation)
        // zoom = log2(360 / span)
        let span = region.span.latitudeDelta
        zoomLevel = max(1, log2(360 / span))
        updateResolvedMapStyle()
    }
    
    private func updateAnnotations() {
        // Cluster when viewing more than ~0.38 km; closer views show individuals
        let shouldCluster = visibleDistanceMeters() > 380
        
        var result: [DriverAnnotation] = []
        
        if shouldCluster {
            // Build clusters of nearby drivers
            var clusters: [[DriverMapResponse]] = []
            var assigned: Set<String> = []
            
            for driver in drivers {
                guard !assigned.contains(driver.id) else { continue }
                
                var cluster: [DriverMapResponse] = [driver]
                assigned.insert(driver.id)
                
                // Find all drivers close to this one (recursively)
                var toCheck = [driver]
                while !toCheck.isEmpty {
                    let current = toCheck.removeFirst()
                    let currentCoord = CLLocationCoordinate2D(
                        latitude: current.latitude,
                        longitude: current.longitude
                    )
                    
                    for other in drivers where !assigned.contains(other.id) {
                        let otherCoord = CLLocationCoordinate2D(
                            latitude: other.latitude,
                            longitude: other.longitude
                        )
                        
                        if distanceDegrees(currentCoord, otherCoord) < overlapThresholdDegrees {
                            cluster.append(other)
                            assigned.insert(other.id)
                            toCheck.append(other)
                        }
                    }
                }
                
                clusters.append(cluster)
            }
            
            // Create annotations with spread positions
            for cluster in clusters {
                if cluster.count == 1 {
                    let driver = cluster[0]
                    let coord = CLLocationCoordinate2D(latitude: driver.latitude, longitude: driver.longitude)
                    result.append(DriverAnnotation(
                        driver: driver,
                        clusterMembers: [driver],
                        displayCoordinate: coord,
                        actualCoordinate: coord,
                        pixelOffset: .zero,
                        clusterIndex: 0,
                        clusterSize: 1
                    ))
                } else if let first = cluster.first {
                    let centroid = CLLocationCoordinate2D(
                        latitude: cluster.map(\.latitude).reduce(0, +) / Double(cluster.count),
                        longitude: cluster.map(\.longitude).reduce(0, +) / Double(cluster.count)
                    )
                    // Single cluster marker that contains all members (grid handles layout)
                    result.append(DriverAnnotation(
                        driver: first,
                        clusterMembers: cluster,
                        displayCoordinate: centroid,
                        actualCoordinate: centroid,
                        pixelOffset: .zero,
                        clusterIndex: 0,
                        clusterSize: cluster.count
                    ))
                }
            }
        } else {
            // No clustering: show actual positions
            for driver in drivers {
                let coord = CLLocationCoordinate2D(latitude: driver.latitude, longitude: driver.longitude)
                result.append(DriverAnnotation(
                    driver: driver,
                    clusterMembers: [driver],
                    displayCoordinate: coord,
                    actualCoordinate: coord,
                    pixelOffset: .zero,
                    clusterIndex: 0,
                    clusterSize: 1
                ))
            }
        }
        
        // Only update if changed to avoid unnecessary redraws
        if result != annotations {
            withAnimation(.easeInOut(duration: 0.25)) {
                annotations = result
            }
        }
    }
    
    private func spreadCluster(_ cluster: [DriverMapResponse]) -> [DriverAnnotation] {
        // Sort cluster by ID for consistent positioning
        let sortedCluster = cluster.sorted { $0.id < $1.id }
        
        // Calculate cluster centroid
        let avgLat = sortedCluster.map(\.latitude).reduce(0, +) / Double(sortedCluster.count)
        let avgLon = sortedCluster.map(\.longitude).reduce(0, +) / Double(sortedCluster.count)
        let centroid = CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon)
        
        // Calculate spread in meters (clamped) based on visible distance to keep offsets tight
        let metersPerDegreeLat = 111_000.0
        let metersPerDegreeLon = metersPerDegreeLat * cos(centroid.latitude * .pi / 180)
        
        let visibleMeters = visibleDistanceMeters()
        let spreadMeters = min(max(visibleMeters * 0.002, 6.0), 30.0)
        
        var annotations: [DriverAnnotation] = []
        let count = sortedCluster.count
        
        // Use golden angle for natural-looking distribution
        let goldenAngle = .pi * (3 - sqrt(5))
        
        for (index, driver) in sortedCluster.enumerated() {
            let actualCoord = CLLocationCoordinate2D(latitude: driver.latitude, longitude: driver.longitude)
            
            // Spiral/sunflower pattern for natural distribution
            let angle = Double(index) * goldenAngle
            let radiusFactor = sqrt(Double(index + 1) / Double(count + 1))
            let radiusMeters = spreadMeters * radiusFactor
            
            // For 2 drivers, place them on opposite sides
            let finalAngle: Double
            let finalRadius: Double
            if count == 2 {
                finalAngle = Double(index) * .pi - .pi / 2
                finalRadius = spreadMeters * 0.5
            } else {
                finalAngle = angle
                finalRadius = radiusMeters
            }
            
            let displayCoord = CLLocationCoordinate2D(
                latitude: centroid.latitude + (finalRadius * cos(finalAngle)) / metersPerDegreeLat,
                longitude: centroid.longitude + (finalRadius * sin(finalAngle) * 1.5) / metersPerDegreeLon // Wider horizontal spread
            )
            
            // Calculate pixel offset from display to actual position
            let latDiff = actualCoord.latitude - displayCoord.latitude
            let lonDiff = actualCoord.longitude - displayCoord.longitude
            let pixelsPerDegree = 400 / region.span.latitudeDelta
            
            let pixelOffset = CGSize(
                width: lonDiff * pixelsPerDegree / 1.5, // Compensate for horizontal stretch
                height: -latDiff * pixelsPerDegree
            )
            
            annotations.append(DriverAnnotation(
                driver: driver,
                clusterMembers: sortedCluster,
                displayCoordinate: displayCoord,
                actualCoordinate: actualCoord,
                pixelOffset: pixelOffset,
                clusterIndex: index,
                clusterSize: count
            ))
        }
        
        return annotations
    }
    
    private func distanceDegrees(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let latDiff = coord1.latitude - coord2.latitude
        let lonDiff = coord1.longitude - coord2.longitude
        return sqrt(latDiff * latDiff + lonDiff * lonDiff)
    }
    
    private func fittedRegion(for drivers: [DriverMapResponse]) -> MKCoordinateRegion {
        let lats = drivers.map(\.latitude)
        let lons = drivers.map(\.longitude)
        guard let minLat = lats.min(),
              let maxLat = lats.max(),
              let minLon = lons.min(),
              let maxLon = lons.max() else {
            return region
        }
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        
        // Add padding and ensure minimum span
        let latSpan = max((maxLat - minLat) * 1.4, 0.02)
        let lonSpan = max((maxLon - minLon) * 1.4, 0.02)
        
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
    }
    
    private func updateResolvedMapStyle() {
        let closeZoom = visibleDistanceMeters() <= autoSatelliteThresholdMeters
        let newResolved: MapDisplayStyle
        
        switch selectedMapStyle {
        case .street:
            newResolved = .street
        case .satellite:
            newResolved = .satellite
        case .auto:
            newResolved = closeZoom ? .satellite : .street
        }
        
        if newResolved != resolvedMapStyle {
            resolvedMapStyle = newResolved
        }
    }
    
    private func visibleDistanceMeters() -> CLLocationDistance {
        let center = region.center
        let halfLat = region.span.latitudeDelta / 2
        let halfLon = region.span.longitudeDelta / 2
        
        let top = CLLocation(latitude: center.latitude + halfLat, longitude: center.longitude)
        let bottom = CLLocation(latitude: center.latitude - halfLat, longitude: center.longitude)
        let left = CLLocation(latitude: center.latitude, longitude: center.longitude - halfLon)
        let right = CLLocation(latitude: center.latitude, longitude: center.longitude + halfLon)
        
        let vertical = top.distance(from: bottom)
        let horizontal = left.distance(from: right)
        return min(vertical, horizontal)
    }
}
