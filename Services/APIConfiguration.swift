import Foundation

/// Configuration for API endpoints
/// Update these values to point to your backend API
struct APIConfiguration {
    /// Base URL for the API (e.g., "https://api.yourdomain.com")
    static let baseURL = "https://webhook.site/9fad595f-8b1b-4d67-abf7-bfb485bd2946"
    
    /// Endpoint path for location updates
    static let locationUpdateEndpoint = "/location/update"
    
    /// Endpoint path for shift start
    static let shiftStartEndpoint = "/shift/start"
    
    /// Endpoint path for shift stop
    static let shiftStopEndpoint = "/shift/stop"
    
    /// Endpoint path for device token registration
    static let deviceTokenEndpoint = "/device/register"
    
    /// Optional: Set this if your API requires authentication
    /// You can retrieve this from AuthenticationManager after login
    static var authToken: String? = nil
}

