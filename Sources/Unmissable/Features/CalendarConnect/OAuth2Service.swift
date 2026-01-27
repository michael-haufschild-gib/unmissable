import AppAuth
import AppKit
import Foundation
import KeychainAccess
import OSLog

@MainActor
final class OAuth2Service: NSObject, ObservableObject {
  private let logger = Logger(subsystem: "com.unmissable.app", category: "OAuth2Service")
  private let keychain = Keychain(service: "com.unmissable.app.oauth")

  @Published var isAuthenticated = false
  @Published var userEmail: String?
  @Published var authorizationError: String?

  private var authState: OIDAuthState?
  private let keychainAccessTokenKey = "google_access_token"
  private let keychainRefreshTokenKey = "google_refresh_token"
  private let keychainUserEmailKey = "google_user_email"
  private let keychainAuthStateKey = "google_auth_state"  // Serialized OIDAuthState

  // URLSession with timeout configuration to prevent indefinite hangs
  private static let urlSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 30  // 30 seconds per request
    config.timeoutIntervalForResource = 60  // 60 seconds total
    return URLSession(configuration: config)
  }()

  override init() {
    super.init()
    loadAuthStateFromKeychain()

    // Listen for OAuth callback notifications
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(handleOAuthCallback(_:)),
      name: .oauthCallback,
      object: nil
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @objc private func handleOAuthCallback(_ notification: Notification) {
    guard let url = notification.object as? URL else {
      logger.error("❌ OAuth callback notification missing URL")
      return
    }

    logger.info("📥 Handling OAuth callback URL: \(url)")
    logger.info("   Scheme: \(url.scheme ?? "nil")")
    logger.info("   Host: \(url.host ?? "nil")")
    logger.info("   Query: \(url.query ?? "nil")")

    // Handle the callback URL with AppAuth
    if let currentAuthFlow = self.currentAuthorizationFlow {
      logger.info("✅ Found active authorization flow, resuming...")
      if currentAuthFlow.resumeExternalUserAgentFlow(with: url) {
        logger.info("🎉 Successfully resumed authorization flow")
        self.currentAuthorizationFlow = nil
      } else {
        logger.error("❌ Failed to resume authorization flow with URL")
      }
    } else {
      logger.warning("⚠️ No active authorization flow found - callback may have arrived too late")
    }
  }

  private var currentAuthorizationFlow: OIDExternalUserAgentSession?

  // MARK: - Public Interface

  func startAuthorizationFlow() async throws {
    logger.info("🚀 Starting OAuth 2.0 authorization flow")

    guard GoogleCalendarConfig.validateConfiguration() else {
      let error =
        "OAuth configuration not properly set up. Please configure your Google OAuth client ID."
      logger.error("❌ \(error)")
      authorizationError = error
      throw OAuth2Error.configurationError(error)
    }

    // Clear any existing error
    authorizationError = nil

    // Enhanced logging for debugging
    logger.info("📋 OAuth Configuration:")
    logger.info("   Client ID: \(GoogleCalendarConfig.clientId)")
    logger.info("   Redirect URI: \(GoogleCalendarConfig.redirectURI)")
    logger.info("   Scopes: \(GoogleCalendarConfig.scopes.joined(separator: ", "))")

    // Create service configuration
    let configuration = OIDServiceConfiguration(
      authorizationEndpoint: GoogleCalendarConfig.authorizationEndpoint,
      tokenEndpoint: GoogleCalendarConfig.tokenEndpoint,
      issuer: GoogleCalendarConfig.issuer
    )

    // Validate redirect URL before creating request
    guard let redirectURL = URL(string: GoogleCalendarConfig.redirectURI) else {
      let error = "Invalid redirect URI: \(GoogleCalendarConfig.redirectURI)"
      logger.error("❌ \(error)")
      authorizationError = error
      throw OAuth2Error.configurationError(error)
    }

    // Create authorization request
    let request = OIDAuthorizationRequest(
      configuration: configuration,
      clientId: GoogleCalendarConfig.clientId,
      scopes: GoogleCalendarConfig.scopes,
      redirectURL: redirectURL,
      responseType: OIDResponseTypeCode,
      additionalParameters: nil
    )

    // Perform authorization request
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      // Enhanced logging for debugging
      logger.info("🌐 Creating authorization request...")
      logger.info("   Authorization URL: \(request.authorizationRequestURL())")

      // Use external user agent (browser) for authorization
      // For menu bar apps, we need to ensure we have a proper presenting window
      let presentingWindow: NSWindow
      if let keyWindow = NSApplication.shared.keyWindow {
        presentingWindow = keyWindow
        logger.info("🪟 Using key window for OAuth presentation")
      } else if let mainWindow = NSApplication.shared.mainWindow {
        presentingWindow = mainWindow
        logger.info("🪟 Using main window for OAuth presentation")
      } else {
        // Create a proper window for OAuth presentation
        presentingWindow = NSWindow(
          contentRect: NSRect(x: 100, y: 100, width: 400, height: 300),
          styleMask: [.titled, .closable],
          backing: .buffered,
          defer: false
        )
        presentingWindow.title = "Unmissable OAuth"
        presentingWindow.makeKeyAndOrderFront(nil)
        logger.info("🪟 Created dedicated OAuth window")
      }

      let userAgent = OIDExternalUserAgentMac(presenting: presentingWindow)

      logger.info("🔑 Presenting authorization in browser...")

      self.currentAuthorizationFlow = OIDAuthorizationService.present(
        request,
        externalUserAgent: userAgent
      ) { [weak self] authorizationResponse, error in
        Task { @MainActor in
          self?.currentAuthorizationFlow = nil

          if let error = error {
            self?.logger.error("❌ Authorization failed: \(error.localizedDescription)")
            self?.logger.error("   Error domain: \((error as NSError).domain)")
            self?.logger.error("   Error code: \((error as NSError).code)")
            self?.authorizationError = "Authorization failed: \(error.localizedDescription)"
            continuation.resume(throwing: OAuth2Error.authorizationFailed(error))
          } else if let authResponse = authorizationResponse {
            self?.logger.info("✅ Authorization successful, exchanging code for tokens")

            // Exchange authorization code for tokens
            OIDAuthorizationService.perform(
              authResponse.tokenExchangeRequest()!
            ) { tokenResponse, tokenError in
              Task { @MainActor in
                if let tokenError = tokenError {
                  self?.logger.error("❌ Token exchange failed: \(tokenError.localizedDescription)")
                  self?.authorizationError =
                    "Token exchange failed: \(tokenError.localizedDescription)"
                  continuation.resume(throwing: OAuth2Error.authorizationFailed(tokenError))
                } else if let tokenResponse = tokenResponse {
                  self?.logger.info("🎉 Token exchange successful!")
                  // Create auth state with both responses
                  let newAuthState = OIDAuthState(
                    authorizationResponse: authResponse, tokenResponse: tokenResponse)
                  // Set up delegate to save state on changes (e.g., token refresh)
                  newAuthState.stateChangeDelegate = self
                  self?.authState = newAuthState
                  self?.saveAuthStateToKeychain()
                  await self?.fetchUserEmail()
                  self?.isAuthenticated = true
                  continuation.resume()
                } else {
                  let error = OAuth2Error.authorizationFailed(
                    NSError(
                      domain: "OAuth2Service", code: -1,
                      userInfo: [NSLocalizedDescriptionKey: "No token response received"]))
                  continuation.resume(throwing: error)
                }
              }
            }
          } else {
            self?.logger.error("❌ Unknown authorization error - no response received")
            let error = OAuth2Error.authorizationFailed(
              NSError(
                domain: "OAuth2Service", code: -1,
                userInfo: [
                  NSLocalizedDescriptionKey:
                    "Unknown authorization error - no response received. This may be due to corporate security policies or browser restrictions."
                ]))
            self?.authorizationError =
              "Authorization failed - no response received. Please check if your browser is blocking redirects or if corporate policies are interfering."
            continuation.resume(throwing: error)
          }
        }
      }

      // Add a safety check - if the flow didn't start properly
      if self.currentAuthorizationFlow == nil {
        logger.error("❌ Failed to start authorization flow - currentAuthorizationFlow is nil")
        let error = OAuth2Error.authorizationFailed(
          NSError(
            domain: "OAuth2Service", code: -2,
            userInfo: [
              NSLocalizedDescriptionKey:
                "Failed to start authorization flow. This may be due to browser restrictions or corporate security policies."
            ]))
        authorizationError =
          "Failed to start OAuth flow. Please ensure your default browser is available and not blocked by corporate policies."
        continuation.resume(throwing: error)
      }
    }
  }

  func getValidAccessToken() async throws -> String {
    guard let authState = authState else {
      logger.error("❌ getValidAccessToken called but authState is nil")
      // Update authorizationError so user sees feedback
      authorizationError = "Not authenticated. Please sign in again."
      throw OAuth2Error.notAuthenticated
    }

    return try await withCheckedThrowingContinuation {
      (continuation: CheckedContinuation<String, Error>) in
      authState.performAction { [weak self] accessToken, idToken, error in
        Task { @MainActor in
          if let error = error {
            self?.logger.error("❌ Token refresh failed: \(error.localizedDescription)")
            // Check if this is an auth error that requires re-authentication
            let nsError = error as NSError
            if nsError.domain == OIDOAuthTokenErrorDomain {
              self?.logger.error("🔐 OAuth token error - user needs to re-authenticate")
              self?.authorizationError = "Session expired. Please sign in again."
              self?.isAuthenticated = false
              self?.authState = nil
              self?.userEmail = nil
              self?.clearKeychain()
            }
            continuation.resume(throwing: OAuth2Error.tokenRefreshFailed(error))
          } else if let accessToken = accessToken {
            // Note: No need to save here - OIDAuthStateChangeDelegate.didChange handles it
            continuation.resume(returning: accessToken)
          } else {
            self?.authorizationError = "Unable to get access token. Please sign in again."
            continuation.resume(
              throwing: OAuth2Error.tokenRefreshFailed(
                NSError(
                  domain: "OAuth2Service", code: -1,
                  userInfo: [NSLocalizedDescriptionKey: "No access token available"])))
          }
        }
      }
    }
  }

  func signOut() {
    logger.info("Signing out user")

    authState = nil
    isAuthenticated = false
    userEmail = nil
    authorizationError = nil

    clearKeychain()
  }

  /// Validates the stored auth state by attempting a lightweight API call.
  /// Should be called on app launch to ensure tokens are still valid.
  func validateAuthState() async {
    guard isAuthenticated else {
      logger.info("🔍 validateAuthState: Not authenticated, skipping validation")
      return
    }

    guard authState != nil else {
      logger.warning("⚠️ validateAuthState: isAuthenticated=true but authState is nil - clearing auth")
      isAuthenticated = false
      userEmail = nil
      authorizationError = "Session expired. Please sign in again."
      clearKeychain()
      return
    }

    logger.info("🔍 Validating auth state on startup...")

    do {
      // Try to get a valid access token - this will trigger refresh if needed
      let _ = try await getValidAccessToken()
      logger.info("✅ Auth state validated successfully")
      authorizationError = nil  // Clear any previous errors
    } catch {
      logger.error("❌ Auth validation failed: \(error.localizedDescription)")
      // getValidAccessToken already updates authorizationError and clears state if needed
    }
  }

  // MARK: - Private Methods

  private func loadAuthStateFromKeychain() {
    do {
      // First, try to load the serialized OIDAuthState (preferred method)
      if let authStateData = try keychain.getData(keychainAuthStateKey) {
        if let restoredAuthState = try? NSKeyedUnarchiver.unarchivedObject(
          ofClass: OIDAuthState.self, from: authStateData)
        {
          logger.info("✅ Successfully restored OIDAuthState from keychain")
          self.authState = restoredAuthState
          userEmail = try keychain.get(keychainUserEmailKey)
          isAuthenticated = true

          // Set up state change handler to save updates
          restoredAuthState.stateChangeDelegate = self

          logger.info("User authenticated with restored auth state")
          return
        } else {
          logger.warning("⚠️ Failed to deserialize stored auth state, will clear and require re-auth")
        }
      }

      // Fallback: Check for legacy token storage (migration path)
      if let accessToken = try keychain.get(keychainAccessTokenKey),
        let refreshToken = try keychain.get(keychainRefreshTokenKey),
        !accessToken.isEmpty && !refreshToken.isEmpty
      {
        logger.warning("⚠️ Found legacy tokens without full auth state - user must re-authenticate")
        // Clear legacy tokens since we can't use them without OIDAuthState
        clearKeychain()
        authorizationError = "Session expired. Please sign in again."
      }
    } catch {
      logger.error("Failed to load auth state from keychain: \(error.localizedDescription)")
    }
  }

  private func saveAuthStateToKeychain() {
    guard let authState = authState else {
      logger.error("Cannot save auth state - authState is nil")
      return
    }

    do {
      // Serialize the entire OIDAuthState for proper restoration
      let authStateData = try NSKeyedArchiver.archivedData(
        withRootObject: authState, requiringSecureCoding: true)
      try keychain.set(authStateData, key: keychainAuthStateKey)

      // Also store tokens separately for debugging/migration purposes
      if let accessToken = authState.lastTokenResponse?.accessToken {
        try keychain.set(accessToken, key: keychainAccessTokenKey)
      }
      if let refreshToken = authState.lastTokenResponse?.refreshToken {
        try keychain.set(refreshToken, key: keychainRefreshTokenKey)
      }

      if let userEmail = userEmail {
        try keychain.set(userEmail, key: keychainUserEmailKey)
      }

      logger.info("✅ Auth state serialized and saved to keychain")
    } catch {
      logger.error("Failed to save auth state to keychain: \(error.localizedDescription)")
    }
  }

  private func clearKeychain() {
    // Use try? for each to ensure all keys are attempted even if one fails
    try? keychain.remove(keychainAuthStateKey)
    try? keychain.remove(keychainAccessTokenKey)
    try? keychain.remove(keychainRefreshTokenKey)
    try? keychain.remove(keychainUserEmailKey)
    logger.info("Keychain cleared")
  }

  private func fetchUserEmail() async {
    do {
      let accessToken = try await getValidAccessToken()
      let email = try await fetchUserInfoFromGoogle(accessToken: accessToken)
      userEmail = email
      logger.info("User email fetched: \(email)")
    } catch {
      logger.error("Failed to fetch user email: \(error.localizedDescription)")
    }
  }

  private func fetchUserInfoFromGoogle(accessToken: String) async throws -> String {
    let url = URL(string: "https://www.googleapis.com/oauth2/v2/userinfo")!
    var request = URLRequest(url: url)
    request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

    let (data, response) = try await Self.urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse,
      httpResponse.statusCode == 200
    else {
      throw OAuth2Error.userInfoFetchFailed
    }

    let userInfo = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    guard let email = userInfo?["email"] as? String else {
      throw OAuth2Error.userInfoFetchFailed
    }

    return email
  }
}

enum OAuth2Error: LocalizedError {
  case configurationError(String)
  case authorizationFailed(Error)
  case tokenRefreshFailed(Error)
  case notAuthenticated
  case userInfoFetchFailed

  var errorDescription: String? {
    switch self {
    case .configurationError(let message):
      return "Configuration Error: \(message)"
    case .authorizationFailed(let error):
      return "Authorization Failed: \(error.localizedDescription)"
    case .tokenRefreshFailed(let error):
      return "Token Refresh Failed: \(error.localizedDescription)"
    case .notAuthenticated:
      return "User not authenticated"
    case .userInfoFetchFailed:
      return "Failed to fetch user information"
    }
  }
}

// MARK: - OIDAuthStateChangeDelegate

extension OAuth2Service: OIDAuthStateChangeDelegate {
  nonisolated func didChange(_ state: OIDAuthState) {
    // OIDAuthState changed (e.g., tokens refreshed) - save to keychain
    Task { @MainActor in
      self.logger.info("🔄 OIDAuthState changed - saving updated state to keychain")
      self.saveAuthStateToKeychain()
    }
  }
}
