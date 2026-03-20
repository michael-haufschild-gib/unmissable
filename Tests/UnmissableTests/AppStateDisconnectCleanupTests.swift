@testable import Unmissable
import XCTest

@MainActor
final class AppStateDisconnectCleanupTests: XCTestCase {
    private var appState: AppState!

    override func setUp() async throws {
        try await super.setUp()
        appState = AppState()
        appState.disconnectFromCalendar()
    }

    override func tearDown() async throws {
        appState?.disconnectFromCalendar()
        appState = nil
        try await super.tearDown()
    }

    func testDisconnectFromCalendar_hidesActiveOverlay() async throws {
        let overlayManager = try extractOverlayManager(from: appState)
        let event = TestUtilities.createTestEvent(id: "disconnect-overlay")

        overlayManager.showOverlay(for: event)

        let state = try XCTUnwrap(appState)
        try await TestUtilities.waitForAsync(timeout: 1.0) { @MainActor @Sendable in
            state.activeOverlay?.id == event.id
        }

        appState.disconnectFromCalendar()

        XCTAssertFalse(overlayManager.isOverlayVisible)
        XCTAssertNil(appState.activeOverlay)
    }

    // swiftlint:disable:next no_real_overlay_manager_in_tests
    private func extractOverlayManager(from appState: AppState) throws -> OverlayManager {
        let mirror = Mirror(reflecting: appState)
        // swiftlint:disable:next no_real_overlay_manager_in_tests
        guard let overlayManager = mirror.children.first(where: { $0.label == "overlayManager" })?
            .value as? OverlayManager
        else {
            throw XCTestError(.failureWhileWaiting)
        }
        return overlayManager
    }
}
