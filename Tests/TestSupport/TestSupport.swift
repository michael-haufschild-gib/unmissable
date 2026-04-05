import AppKit
import Clocks
import ConcurrencyExtras
import Foundation
import OSLog
import SwiftUI
@testable import Unmissable

// MARK: - Controllable Test Clock

/// Bridges PointFree's `TestClock<Duration>` to EventScheduler's closure-based
/// `sleepForSeconds` / `now` interface.
///
/// PointFree's TestClock uses continuation-based suspension: `sleep` suspends
/// the caller until the test explicitly calls `advance(by:)`. This eliminates
/// MainActor starvation — the monitoring loop simply suspends and never spins.
///
/// Usage:
/// ```swift
/// let clock = TestClock()
/// let scheduler = EventScheduler(sleepForSeconds: clock.sleepForSeconds,
///                                 now: clock.nowProvider)
/// // ... trigger scheduling ...
/// await clock.advance(by: .seconds(600))  // fires alerts 10 min in the future
/// ```
@preconcurrency @MainActor
public final class TestClock {
    /// The underlying PointFree TestClock that handles continuation-based sleep.
    public let underlying = Clocks.TestClock<Duration>()

    /// Wall-clock anchor: the real Date at the moment this TestClock was created.
    /// Used to convert between Duration offsets and absolute Dates.
    private let anchorDate: Date

    /// Accumulated Duration offset from anchor. Updated whenever `advance` is called.
    private var elapsed: Duration = .zero

    private static let attosecondsPerSecond: Double = 1e18
    private static let millisecondsPerSecond: Double = 1000

    /// Creates a test clock anchored at the given time.
    public init(startTime: Date = Date()) {
        anchorDate = startTime
    }

    /// The simulated current time as a Date.
    public var currentTime: Date {
        anchorDate.addingTimeInterval(Double(elapsed.components.seconds)
            + Double(elapsed.components.attoseconds) / Self.attosecondsPerSecond)
    }

    /// Closure suitable for `EventScheduler(sleepForSeconds:)`.
    /// Suspends via PointFree's TestClock — the caller blocks until
    /// `advance(by:)` is called from the test. No spinning, no starvation.
    public var sleepForSeconds: @Sendable (TimeInterval) async throws -> Void {
        { [weak underlying] seconds in
            guard let clock = underlying else { throw CancellationError() }
            try await clock.sleep(for: .milliseconds(Int(seconds * Self.millisecondsPerSecond)))
        }
    }

    /// Closure suitable for `EventScheduler(now:)`.
    public var nowProvider: @Sendable () -> Date {
        { [weak self] in
            guard let self else { return Date() }
            return MainActor.assumeIsolated { self.currentTime }
        }
    }

    /// Advance the clock by a Duration, releasing any suspended sleepers
    /// whose deadline falls within the advanced range.
    public func advance(by duration: Duration) async {
        elapsed += duration
        await underlying.advance(by: duration)
    }

    /// Advance by seconds (convenience).
    public func advance(bySeconds seconds: TimeInterval) async {
        await advance(by: .milliseconds(Int(seconds * Self.millisecondsPerSecond)))
    }

    /// Run all pending suspensions to completion.
    public func runToCompletion() async {
        await underlying.run()
    }
}

// MARK: - Test-Safe Implementations

/// Test-safe overlay manager that doesn't create actual UI elements
@preconcurrency @MainActor @Observable
public final class TestSafeOverlayManager: OverlayManaging {
    private let logger = Logger(category: "TestSupport")

    public var activeEvent: Event?
    public var isOverlayVisible = false

    /// Computed time until meeting starts (negative if meeting has started)
    public var timeUntilMeeting: TimeInterval {
        activeEvent?.startDate.timeIntervalSinceNow ?? 0
    }

    /// Max age (seconds) before auto-dismissing a non-snoozed overlay (mirrors production).
    private static let normalMaxAgeSeconds: TimeInterval = 300
    /// Max age (seconds) before auto-dismissing a snoozed overlay (mirrors production).
    private static let snoozeMaxAgeSeconds: TimeInterval = 1800

    private weak var eventScheduler: EventScheduler?
    private let isTestEnvironment: Bool
    private let foregroundAppDetector: (any ForegroundAppDetecting)?
    private let preferencesManager: PreferencesManager?

    /// Creates a test-safe overlay manager.
    /// Pass `foregroundAppDetector` and `preferencesManager` to enable smart suppression mirroring.
    /// Omit them (default) for tests that do not exercise suppression.
    public init(
        isTestEnvironment: Bool = false,
        foregroundAppDetector: (any ForegroundAppDetecting)? = nil,
        preferencesManager: PreferencesManager? = nil,
    ) {
        self.isTestEnvironment = isTestEnvironment
        self.foregroundAppDetector = foregroundAppDetector
        self.preferencesManager = preferencesManager
    }

    public func showOverlay(for event: Event, fromSnooze: Bool = false) {
        logger.debug("TEST-SAFE SHOW: Overlay for \(event.title), fromSnooze: \(fromSnooze)")

        // Mirror production dedup: skip if same event is already showing
        if isOverlayVisible, activeEvent?.id == event.id {
            logger.debug("TEST-SAFE: Skipping — overlay already visible for event \(event.id)")
            return
        }

        // Mirror production smart suppression when deps are provided
        if !fromSnooze,
           let prefs = preferencesManager, prefs.smartSuppression,
           let detector = foregroundAppDetector,
           let provider = event.provider
        {
            if detector.isMeetingAppInForeground(for: provider) {
                logger.debug("TEST-SAFE: Smart suppressed — native app in foreground")
                return
            }
            if provider == .meet, detector.isBrowserInForeground() {
                logger.debug("TEST-SAFE: Smart suppressed — browser in foreground for Meet")
                return
            }
        }

        // Auto-dismiss for meetings that started too long ago.
        // Uses wall-clock Date() intentionally — this guards against real-world staleness,
        // not simulated time. Events created relative to Date() should not be dismissed
        // just because a TestClock advanced virtual time past their start.
        let timeSinceStart = Date().timeIntervalSince(event.startDate)
        let maxAge: TimeInterval = fromSnooze
            ? Self.snoozeMaxAgeSeconds
            : Self.normalMaxAgeSeconds
        if timeSinceStart > maxAge {
            logger
                .debug(
                    "TEST-SAFE: Skipping overlay — meeting started \(Int(timeSinceStart))s ago (max \(Int(maxAge))s)",
                )
            activeEvent = nil
            isOverlayVisible = false
            return
        }

        activeEvent = event
        isOverlayVisible = true
        logger.debug("TEST-SAFE: Set overlay visible = true")
    }

    public func hideOverlay() {
        logger.debug("TEST-SAFE HIDE: Overlay")
        activeEvent = nil
        isOverlayVisible = false
    }

    public func snoozeOverlay(for minutes: Int) {
        guard let event = activeEvent else { return }
        logger.debug("TEST-SAFE SNOOZE: \(minutes) minutes for \(event.title)")
        hideOverlay()
        eventScheduler?.scheduleSnooze(for: event, minutes: minutes)
    }

    public func setEventScheduler(_ scheduler: EventScheduler) {
        eventScheduler = scheduler
    }
}

// MARK: - Test-Safe Notification Manager

/// Stubbed notification manager for tests.
/// Records notifications sent rather than delivering to UNUserNotificationCenter.
@preconcurrency @MainActor
public final class TestSafeNotificationManager: NotificationManaging {
    private let logger = Logger(category: "TestSupport")

    /// All notifications sent during the test.
    public private(set) var sentNotifications: [(event: Event, primaryLink: URL?)] = []

    /// Whether `requestPermission()` returns true.
    public var permissionGranted = true

    /// Whether `requestPermission()` was ever called.
    public private(set) var permissionRequested = false

    public init() {}

    // swiftlint:disable async_without_await - protocol requires async
    public func requestPermission() async -> Bool {
        permissionRequested = true
        return permissionGranted
    }

    public func sendMeetingNotification(for event: Event, primaryLink: URL?) async {
        logger.debug("TEST-SAFE: Notification for \(event.title)")
        sentNotifications.append((event: event, primaryLink: primaryLink))
    } // swiftlint:enable async_without_await

    /// Registers notification categories (no-op in tests).
    public func registerCategories() {
        logger.debug("TEST-SAFE: Registered notification categories")
    }
}

// MARK: - Test-Safe Meeting Details Popup

@preconcurrency @MainActor @Observable
public final class TestSafeMeetingDetailsPopupManager: MeetingDetailsPopupManaging {
    private let logger = Logger(category: "TestSupport")

    public private(set) var isPopupVisible = false
    public private(set) var lastShownEvent: Event?

    public init() {}

    public func showPopup(for event: Event, relativeTo _: NSWindow? = nil) {
        logger.debug("TEST-SAFE SHOW: Popup for \(event.title)")

        // Mirror real behavior: if already visible, just log
        if isPopupVisible {
            logger.debug("TEST-SAFE: Popup already visible")
            return
        }

        lastShownEvent = event
        isPopupVisible = true
    }

    public func hidePopup() {
        logger.debug("TEST-SAFE HIDE: Popup")
        lastShownEvent = nil
        isPopupVisible = false
    }
}

// MARK: - Test-Safe Foreground App Detector

/// Stubbed foreground app detector for tests.
/// Set `meetingAppInForeground` and `browserInForeground` to control test behavior.
@preconcurrency @MainActor
public final class TestSafeForegroundAppDetector: ForegroundAppDetecting {
    /// When true, `isMeetingAppInForeground(for:)` returns true for any provider.
    public var meetingAppInForeground = false

    /// When true, `isBrowserInForeground()` returns true.
    public var browserInForeground = false

    public init() {}

    public func isMeetingAppInForeground(for _: Provider) -> Bool {
        meetingAppInForeground
    }

    public func isBrowserInForeground() -> Bool {
        browserInForeground
    }
}

// MARK: - Test Menu Bar Environment

/// Provides a fully wired test-safe environment for rendering `MenuBarView`
/// and `MenuBarLabelView` in snapshot and E2E tests. Uses `TestSafeOverlayManager`
/// so no fullscreen UI or side effects are triggered.
///
/// Usage:
/// ```swift
/// let env = TestMenuBarEnvironment()
/// env.calendarService.isConnected = true
/// env.calendarService.events = [someEvent]
/// let controller = env.hostMenuBarView(size: CGSize(width: 340, height: 600))
/// assertSnapshot(of: controller, as: .image(...))
/// ```
@preconcurrency @MainActor
public final class TestMenuBarEnvironment {
    /// The test-scoped AppState (created with `isTestEnvironment: true`).
    public let appState: AppState
    /// The calendar service wired into the test AppState.
    public let calendarService: CalendarService
    /// The theme manager shared across all test views.
    public let themeManager: ThemeManager
    /// The menu bar preview manager for label state assertions.
    public let menuBarPreviewManager: MenuBarPreviewManager
    /// The preferences manager backed by an isolated UserDefaults suite.
    public let preferencesManager: PreferencesManager

    private let userDefaultsSuiteName: String

    public init() {
        let theme = ThemeManager()
        themeManager = theme

        userDefaultsSuiteName = "com.unmissable.menubar-test.\(UUID().uuidString)"
        // swiftlint:disable:next force_unwrapping
        let testDefaults = UserDefaults(suiteName: userDefaultsSuiteName)!
        let prefs = PreferencesManager(
            userDefaults: testDefaults,
            themeManager: theme,
            loginItemManager: TestSafeLoginItemManager(),
        )

        let dbManager = DatabaseManager()
        let overlayStub = TestSafeOverlayManager(isTestEnvironment: true)
        let services = ServiceContainer(
            databaseManager: dbManager,
            themeManager: theme,
            overlayManagerOverride: overlayStub,
            preferencesManagerOverride: prefs,
        )
        preferencesManager = services.preferencesManager
        appState = AppState(services: services, isTestEnvironment: true)
        calendarService = services.calendarService
        menuBarPreviewManager = services.menuBarPreviewManager
    }

    deinit {
        UserDefaults.standard.removePersistentDomain(forName: userDefaultsSuiteName)
    }

    /// Default width for the menu bar popover in test host views.
    public static let defaultPopoverWidth: CGFloat = 340
    /// Default height for the menu bar popover in test host views.
    public static let defaultPopoverHeight: CGFloat = 600
    /// Default width for the menu bar label in test host views.
    public static let defaultLabelWidth: CGFloat = 200
    /// Default height for the menu bar label in test host views.
    public static let defaultLabelHeight: CGFloat = 22

    /// Hosts `MenuBarView` in an `NSHostingController` with the correct environment.
    public func hostMenuBarView(
        size: CGSize = CGSize(
            width: TestMenuBarEnvironment.defaultPopoverWidth,
            height: TestMenuBarEnvironment.defaultPopoverHeight,
        ),
    ) -> NSHostingController<some View> {
        let view = MenuBarView()
            .environment(appState)
            .environment(calendarService)
            .themed(themeManager: themeManager)
            .frame(width: size.width, height: size.height)
        return NSHostingController(rootView: view)
    }

    /// Hosts `MenuBarLabelView` in an `NSHostingController` with the correct environment.
    public func hostMenuBarLabelView(
        size: CGSize = CGSize(
            width: TestMenuBarEnvironment.defaultLabelWidth,
            height: TestMenuBarEnvironment.defaultLabelHeight,
        ),
    ) -> NSHostingController<some View> {
        let view = MenuBarLabelView()
            .environment(menuBarPreviewManager)
            .themed(themeManager: themeManager)
            .frame(width: size.width, height: size.height)
        return NSHostingController(rootView: view)
    }
}

// MARK: - Accessibility Identifier Lookup

/// Recursively searches an `NSView` hierarchy for a descendant whose
/// `accessibilityIdentifier()` matches the given string.
///
/// Useful for verifying that SwiftUI views rendered via `NSHostingController`
/// contain the expected interactive elements.
///
///     let controller = env.hostMenuBarView()
///     controller.view.layoutSubtreeIfNeeded()
///     XCTAssertNotNil(findAccessibilityElement(identifier: "quit-button", in: controller.view))
@preconcurrency @MainActor
public func findAccessibilityElement(identifier: String, in view: NSView) -> NSView? {
    if view.accessibilityIdentifier() == identifier {
        return view
    }
    for subview in view.subviews {
        if let found = findAccessibilityElement(identifier: identifier, in: subview) {
            return found
        }
    }
    return nil
}
