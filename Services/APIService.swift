import Foundation

// Simple JSON structure for location updates
struct LocationUpdate: Codable {
    let latitude: Double
    let longitude: Double
    let speed: Double
    let timestamp: String
    let batteryPercentage: Int?
    let isLocationPermissionGranted: Bool
    let isLowPowerModeEnabled: Bool
    let isBatteryCharging: Bool
    
    init(latitude: Double, longitude: Double, speed: Double, batteryPercentage: Int?, isLocationPermissionGranted: Bool, isLowPowerModeEnabled: Bool, isBatteryCharging: Bool) {
        self.latitude = latitude
        self.longitude = longitude
        self.speed = speed
        self.timestamp = ISO8601DateFormatter().string(from: Date())
        self.batteryPercentage = batteryPercentage
        self.isLocationPermissionGranted = isLocationPermissionGranted
        self.isLowPowerModeEnabled = isLowPowerModeEnabled
        self.isBatteryCharging = isBatteryCharging
    }
}

class APIService {
    private let baseURL: String
    private let endpoint: String
    
    init(baseURL: String = APIConfiguration.baseURL, 
         endpoint: String = APIConfiguration.locationUpdateEndpoint) {
        self.baseURL = baseURL
        self.endpoint = endpoint
    }
    
    func sendLocationUpdate(latitude: Double, longitude: Double, speed: Double, batteryPercentage: Int?, isLocationPermissionGranted: Bool, isLowPowerModeEnabled: Bool, isBatteryCharging: Bool, authToken: String) async throws {
        let locationData = LocationUpdate(
            latitude: latitude,
            longitude: longitude,
            speed: speed,
            batteryPercentage: batteryPercentage,
            isLocationPermissionGranted: isLocationPermissionGranted,
            isLowPowerModeEnabled: isLowPowerModeEnabled,
            isBatteryCharging: isBatteryCharging
        )
        
        // Create the full URL
        guard let url = URL(string: baseURL + endpoint) else {
            throw APIError.invalidURL
        }
        
        // Create the request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Add Authorization header with Bearer token
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        // Encode the JSON data
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted // Makes JSON readable for debugging
        request.httpBody = try encoder.encode(locationData)
        
        // Log the request for debugging
        if let jsonString = String(data: request.httpBody!, encoding: .utf8) {
            print("📍 Sending location update:")
            print("   URL: \(url.absoluteString)")
            print("   JSON: \(jsonString)")
        }
        
        // Send the request
        let (data, response) = try await URLSession.shared.data(for: request)
        
        // Check the response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        // Log response for debugging
        print("   Response Status: \(httpResponse.statusCode)")
        if let responseString = String(data: data, encoding: .utf8), !responseString.isEmpty {
            print("   Response Body: \(responseString)")
        }
        
        // Validate status code
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(message: "Server returned status \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    func sendShiftStart(latitude: Double?, longitude: Double?, authToken: String) async throws {
        let shiftData: [String: Any] = [
            "action": "start",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "latitude": latitude as Any,
            "longitude": longitude as Any
        ]
        
        guard let url = URL(string: APIConfiguration.baseURL + APIConfiguration.shiftStartEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: shiftData)
        
        print("🟢 Sending shift start:")
        print("   URL: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        print("   Response Status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(message: "Server returned status \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    func sendShiftStop(authToken: String) async throws {
        let shiftData: [String: Any] = [
            "action": "stop",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let url = URL(string: APIConfiguration.baseURL + APIConfiguration.shiftStopEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: shiftData)
        
        print("🔴 Sending shift stop:")
        print("   URL: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        print("   Response Status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(message: "Server returned status \(httpResponse.statusCode): \(errorMessage)")
        }
    }
    
    func registerDeviceToken(token: String, authToken: String) async throws {
        let deviceData: [String: Any] = [
            "deviceToken": token,
            "platform": "ios",
            "timestamp": ISO8601DateFormatter().string(from: Date())
        ]
        
        guard let url = URL(string: APIConfiguration.baseURL + APIConfiguration.deviceTokenEndpoint) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try JSONSerialization.data(withJSONObject: deviceData)
        
        print("📱 Registering device token:")
        print("   URL: \(url.absoluteString)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.networkError
        }
        
        print("   Response Status: \(httpResponse.statusCode)")
        
        guard (200...299).contains(httpResponse.statusCode) else {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw APIError.serverError(message: "Server returned status \(httpResponse.statusCode): \(errorMessage)")
        }
    }
}

enum APIError: Error, LocalizedError {
    case invalidURL
    case serverError(message: String)
    case networkError
    case encodingError
    
    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid API URL"
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError:
            return "Network connection error"
        case .encodingError:
            return "Failed to encode JSON data"
        }
    }
}

