@testable import Unmissable
import XCTest

@MainActor
final class OnboardingTests: XCTestCase {
    private var preferencesManager: PreferencesManager!
    private var testSuiteName: String!

    override func setUp() async throws {
        testSuiteName = "com.unmissable.onboarding-test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: TestSafeLoginItemManager(),
        )
        try await super.setUp()
    }

    override func tearDown() async throws {
        preferencesManager = nil
        if let suite = testSuiteName {
            UserDefaults.standard.removePersistentDomain(forName: suite)
        }
        testSuiteName = nil
        try await super.tearDown()
    }

    // MARK: - hasCompletedOnboarding Default

    func testHasCompletedOnboarding_defaultsToFalse() {
        XCTAssertFalse(
            preferencesManager.hasCompletedOnboarding,
            "New installs should require onboarding",
        )
    }

    // MARK: - hasCompletedOnboarding Setter

    func testSetHasCompletedOnboarding_true_persistsValue() {
        preferencesManager.setHasCompletedOnboarding(true)

        XCTAssertTrue(
            preferencesManager.hasCompletedOnboarding,
            "Value should update in-memory immediately",
        )
    }

    func testSetHasCompletedOnboarding_false_persistsValue() {
        preferencesManager.setHasCompletedOnboarding(true)
        preferencesManager.setHasCompletedOnboarding(false)

        XCTAssertFalse(
            preferencesManager.hasCompletedOnboarding,
            "Value should revert to false when explicitly set",
        )
    }

    // MARK: - hasCompletedOnboarding Persistence

    func testHasCompletedOnboarding_survivesReinitialization() throws {
        let testDefaults = try XCTUnwrap(UserDefaults(suiteName: testSuiteName))
        preferencesManager.setHasCompletedOnboarding(true)

        // Create a fresh PreferencesManager reading from the same UserDefaults suite
        let freshManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: TestSafeLoginItemManager(),
        )

        XCTAssertTrue(
            freshManager.hasCompletedOnboarding,
            "Value should persist across PreferencesManager instances via UserDefaults",
        )
    }

    // MARK: - Demo Event Validity

    func testDemoEvent_hasValidProperties() throws {
        let demoURL = try XCTUnwrap(
            URL(string: "https://meet.google.com/abc-defg-hij"),
            "Demo URL must be a valid URL",
        )
        XCTAssertEqual(demoURL.host, "meet.google.com")

        let event = Event(
            id: "onboarding-demo",
            title: "Team Standup",
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(1920),
            organizer: "you@company.com",
            calendarId: "demo",
            links: [demoURL],
        )

        XCTAssertEqual(event.id, "onboarding-demo")
        XCTAssertEqual(event.title, "Team Standup")
        XCTAssertEqual(event.calendarId, "demo")

        let firstLink = try XCTUnwrap(event.links.first, "Demo event must contain at least one link")
        XCTAssertEqual(
            firstLink.host,
            "meet.google.com",
            "Demo event should contain a Google Meet link for realistic preview",
        )

        XCTAssertGreaterThan(
            event.startDate,
            Date(),
            "Demo event should start in the future",
        )
        XCTAssertGreaterThan(
            event.endDate,
            event.startDate,
            "Demo event end date should be after start date",
        )
        XCTAssertEqual(
            event.duration,
            1800,
            accuracy: 1,
            "Demo event should be a 30-minute meeting",
        )
    }
}
