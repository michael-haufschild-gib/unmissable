@testable import Unmissable
import XCTest

final class GoogleCalendarConfigTests: XCTestCase {
    // MARK: - Static URL Constants

    func testAuthorizationEndpointIsGoogleOAuth() {
        XCTAssertEqual(
            GoogleCalendarConfig.authorizationEndpoint.host,
            "accounts.google.com"
        )
        XCTAssert(
            GoogleCalendarConfig.authorizationEndpoint.path.contains("auth"),
            "Authorization endpoint should contain 'auth' in path"
        )
    }

    func testTokenEndpointIsGoogleOAuth() {
        XCTAssertEqual(
            GoogleCalendarConfig.tokenEndpoint.host,
            "oauth2.googleapis.com"
        )
    }

    func testIssuerIsGoogleAccounts() {
        XCTAssertEqual(
            GoogleCalendarConfig.issuer.absoluteString,
            "https://accounts.google.com"
        )
    }

    // MARK: - Scopes

    func testScopesIncludeCalendarReadOnly() {
        XCTAssert(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/calendar.readonly"
            ),
            "Scopes should include calendar.readonly"
        )
    }

    func testScopesIncludeCalendarListReadOnly() {
        XCTAssert(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/calendar.calendarlist.readonly"
            ),
            "Scopes should include calendarlist.readonly"
        )
    }

    func testScopesIncludeUserInfoEmail() {
        XCTAssert(
            GoogleCalendarConfig.scopes.contains(
                "https://www.googleapis.com/auth/userinfo.email"
            ),
            "Scopes should include userinfo.email for identifying the user"
        )
    }

    func testScopesAreReadOnly() {
        for scope in GoogleCalendarConfig.scopes {
            XCTAssert(
                scope.contains("readonly") || scope.contains("userinfo"),
                "All scopes should be read-only or user info, found: \(scope)"
            )
        }
    }

    // MARK: - API Base URL

    func testCalendarAPIBaseURL() {
        XCTAssertEqual(
            GoogleCalendarConfig.calendarAPIBaseURL,
            "https://www.googleapis.com/calendar/v3"
        )
    }

    // MARK: - Redirect URI

    func testRedirectURIEndsWithColon() {
        XCTAssert(
            GoogleCalendarConfig.redirectURI.contains(":/"),
            "Redirect URI should have scheme format (scheme:/)"
        )
    }

    // MARK: - Configuration Detection

    func testIsConfiguredReflectsClientIdState() {
        // In test environment, clientId is typically empty (no Config.plist or env var)
        // We test that isConfigured is consistent with clientId emptiness
        if GoogleCalendarConfig.clientId.isEmpty {
            XCTAssertFalse(
                GoogleCalendarConfig.isConfigured,
                "isConfigured should be false when clientId is empty"
            )
        } else {
            XCTAssertTrue(
                GoogleCalendarConfig.isConfigured,
                "isConfigured should be true when clientId is non-empty"
            )
        }
    }
}
