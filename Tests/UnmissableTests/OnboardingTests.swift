import Foundation
import Testing
@testable import Unmissable

@MainActor
struct OnboardingTests {
    private var preferencesManager: PreferencesManager
    private let testSuiteName: String

    init() {
        testSuiteName = "com.unmissable.onboarding-test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: testSuiteName)!
        preferencesManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: TestSafeLoginItemManager(),
        )
    }

    // MARK: - hasCompletedOnboarding Default

    @Test
    func hasCompletedOnboarding_defaultsToFalse() {
        #expect(
            !preferencesManager.hasCompletedOnboarding,
            "New installs should require onboarding",
        )
    }

    // MARK: - hasCompletedOnboarding Setter

    @Test
    func setHasCompletedOnboarding_true_persistsValue() {
        preferencesManager.setHasCompletedOnboarding(true)

        #expect(
            preferencesManager.hasCompletedOnboarding,
            "Value should update in-memory immediately",
        )
    }

    @Test
    func setHasCompletedOnboarding_false_persistsValue() {
        preferencesManager.setHasCompletedOnboarding(true)
        preferencesManager.setHasCompletedOnboarding(false)

        #expect(
            !preferencesManager.hasCompletedOnboarding,
            "Value should revert to false when explicitly set",
        )
    }

    // MARK: - hasCompletedOnboarding Persistence

    @Test
    func hasCompletedOnboarding_survivesReinitialization() throws {
        let testDefaults = try #require(UserDefaults(suiteName: testSuiteName))
        preferencesManager.setHasCompletedOnboarding(true)

        // Create a fresh PreferencesManager reading from the same UserDefaults suite
        let freshManager = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: ThemeManager(),
            loginItemManager: TestSafeLoginItemManager(),
        )

        #expect(
            freshManager.hasCompletedOnboarding,
            "Value should persist across PreferencesManager instances via UserDefaults",
        )
    }

    // MARK: - Demo Event Validity

    @Test
    func demoEvent_hasValidProperties() throws {
        let demoURL = try #require(
            URL(string: "https://meet.google.com/abc-defg-hij"),
            "Demo URL must be a valid URL",
        )
        #expect(demoURL.host == "meet.google.com")

        let event = Event(
            id: "onboarding-demo",
            title: "Team Standup",
            startDate: Date().addingTimeInterval(120),
            endDate: Date().addingTimeInterval(1920),
            organizer: "you@company.com",
            calendarId: "demo",
            links: [demoURL],
        )

        #expect(event.id == "onboarding-demo")
        #expect(event.title == "Team Standup")
        #expect(event.calendarId == "demo")

        let firstLink = try #require(event.links.first, "Demo event must contain at least one link")
        #expect(
            firstLink.host == "meet.google.com",
            "Demo event should contain a Google Meet link for realistic preview",
        )

        #expect(
            event.startDate > Date(),
            "Demo event should start in the future",
        )
        #expect(
            event.endDate > event.startDate,
            "Demo event end date should be after start date",
        )
        #expect(
            abs(event.duration - 1800) <= 1,
            "Demo event should be a 30-minute meeting",
        )
    }
}
