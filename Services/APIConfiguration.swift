import Foundation

/// Configuration for API endpoints
/// Update these values to point to your backend API
struct APIConfiguration {
    static let baseURL = "https://dispo.dev.smatify.dev/api/v1"
    
    /// Endpoint path for location updates
    static let locationUpdateEndpoint = "/locations/update"
    
    /// Endpoint path for shift start
    static let shiftStartEndpoint = "/shifts/start"
    
    /// Endpoint path for shift stop
    static let shiftStopEndpoint = "/shifts/stop"
    
    /// Endpoint path for device token registration
    static let deviceTokenEndpoint = "/devices/register"
    
    /// Endpoint for map driver locations
    static let projectLocationsEndpoint = "/projects/1/locations"
    
    /// Optional: Set this if your API requires authentication
    /// You can retrieve this from AuthenticationManager after login
    static var authToken: String? = nil
}

