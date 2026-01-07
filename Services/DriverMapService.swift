import Foundation

struct DriverMapResponse: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let avatar: String
    let latitude: Double
    let longitude: Double
    let speed: Double
    let batteryPercentage: Double
    let isBatteryCharging: Bool
    let isLowPowerModeEnabled: Bool
    let isLocationPermissionGranted: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case avatar
        case latitude
        case longitude
        case speed
        case batteryPercentage = "battery_percentage"
        case isBatteryCharging = "isBatteryCharging"
        case isLowPowerModeEnabled = "isLowPowerModeEnabled"
        case isLocationPermissionGranted = "isLocationPermissionGranted"
    }
}

private struct DriverMapEnvelope: Codable {
    let project_id: String?
    let drivers: [DriverMapResponse]
}

class DriverMapService {
    func fetchDrivers() async throws -> [DriverMapResponse] {
        guard let url = URL(string: APIConfiguration.baseURL + APIConfiguration.projectLocationsEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Optional auth header if available
        if let token = APIConfiguration.authToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(message: "Status \(httpResponse.statusCode): \(message)")
        }
        
        do {
            // API returns { "project_id": "...", "drivers": [...] }
            // Note: Using CodingKeys for battery_percentage mapping, other fields match API exactly
            let envelope = try JSONDecoder().decode(DriverMapEnvelope.self, from: data)
            print("✅ Loaded \(envelope.drivers.count) drivers from API")
            return envelope.drivers
        } catch {
            print("❌ Decoding error: \(error)")
            if let jsonString = String(data: data, encoding: .utf8) {
                print("   Response: \(jsonString.prefix(500))")
            }
            throw APIError.encodingError
        }
    }
}

