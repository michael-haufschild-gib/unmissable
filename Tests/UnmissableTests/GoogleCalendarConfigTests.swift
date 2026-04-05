import Foundation
import Testing
@testable import Unmissable

struct GoogleCalendarConfigTests {
    // MARK: - Static URL Constants

    @Test
    func authorizationEndpointIsGoogleOAuth() {
        #expect(
            GoogleCalendarConfig.authorizationEndpoint.host == "accounts.google.com",
        )
        #expect(
            GoogleCalendarConfig.authorizationEndpoint.path.contains("auth"),
            "Authorization endpoint should contain 'auth' in path",
        )
    }

    @Test
    func tokenEndpointIsGoogleOAuth() {
        #expect(
            GoogleCalendarConfig.tokenEndpoint.host == "oauth2.googleapis.com",
        )
    }

    @Test
    func issuerIsGoogleAccounts() {
        #expect(
            GoogleCalendarConfig.issuer.absoluteString == "https://accounts.google.com",
        )
    }

    // MARK: - Scopes

    @Test
    func scopesIncludeCalendarReadOnly() {
        #expect(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/calendar.readonly",
            ),
            "Scopes should include calendar.readonly",
        )
    }

    @Test
    func scopesIncludeCalendarListReadOnly() {
        #expect(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/calendar.calendarlist.readonly",
            ),
            "Scopes should include calendarlist.readonly",
        )
    }

    @Test
    func scopesIncludeUserInfoEmail() {
        #expect(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/userinfo.email",
            ),
            "Scopes should include userinfo.email for identifying the user",
        )
    }

    @Test
    func scopesAreReadOnly() {
        for scope in GoogleCalendarConfig.scopes {
            #expect(
                scope.contains("readonly") || scope.contains("userinfo"),
                "All scopes should be read-only or user info, found: \(scope)",
            )
        }
    }

    // MARK: - API Base URL

    @Test
    func calendarAPIBaseURL() {
        #expect(
            GoogleCalendarConfig.calendarAPIBaseURL == "https://www.googleapis.com/calendar/v3",
        )
    }

    // MARK: - Redirect URI

    @Test
    func redirectURIEndsWithColon() {
        #expect(
            GoogleCalendarConfig.redirectURI.contains(":/"),
            "Redirect URI should have scheme format (scheme:/)",
        )
    }

    // MARK: - Configuration Detection

    @Test
    func isConfiguredReflectsClientIdState() {
        // In test environment, clientId is typically empty (no Config.plist or env var)
        // We test that isConfigured is consistent with clientId emptiness
        if GoogleCalendarConfig.clientId.isEmpty {
            #expect(
                !GoogleCalendarConfig.isConfigured,
                "isConfigured should be false when clientId is empty",
            )
        } else {
            #expect(
                GoogleCalendarConfig.isConfigured,
                "isConfigured should be true when clientId is non-empty",
            )
        }
    }
}
