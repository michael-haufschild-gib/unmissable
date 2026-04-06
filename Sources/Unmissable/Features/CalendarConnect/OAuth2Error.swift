import Foundation

/// Errors that can occur during the OAuth 2.0 authorization and token management flow.
enum OAuth2Error: LocalizedError {
    case configurationError(String)
    case authorizationFailed(Error)
    case tokenRefreshFailed(Error)
    case notAuthenticated
    case userInfoFetchFailed
    case timeout
    case invalidTokenRequest

    var errorDescription: String? {
        switch self {
        case let .configurationError(message):
            "Configuration Error: \(message)"
        case .authorizationFailed:
            "Authorization failed"
        case .tokenRefreshFailed:
            "Token refresh failed"
        case .notAuthenticated:
            "User not authenticated"
        case .userInfoFetchFailed:
            "Failed to fetch user information"
        case .timeout:
            "Authorization timed out. Please try again."
        case .invalidTokenRequest:
            "Invalid token exchange request"
        }
    }
}
