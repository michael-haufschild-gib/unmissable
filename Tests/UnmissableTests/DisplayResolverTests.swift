import Foundation
import Testing
@testable import Unmissable

/// Exhaustive coverage of DisplayResolver.resolve — the pure selection logic that
/// decides which screens receive an overlay. These tests pin the fail-open behavior
/// documented on the resolver: the app should never accidentally return "no screens"
/// when something is connected, because "overlay on nothing" defeats the product.
struct DisplayResolverTests {
    // MARK: - Test Fixtures

    private static let builtInDisplay = DisplayResolver.ScreenDescriptor(
        isBuiltIn: true,
        persistenceKey: "610-40960-0",
    )

    private static let externalA = DisplayResolver.ScreenDescriptor(
        isBuiltIn: false,
        persistenceKey: "1715-10092-16843009",
    )

    private static let externalB = DisplayResolver.ScreenDescriptor(
        isBuiltIn: false,
        persistenceKey: "1552-41054-200",
    )

    // MARK: - Empty Screens Guard

    @Test
    func resolve_emptyScreens_returnsEmpty() {
        let result = DisplayResolver.resolve(
            mode: .all,
            selectedKeys: [],
            screens: [],
            mainScreenIndex: nil,
        )
        #expect(result.isEmpty)
    }

    @Test
    func resolve_emptyScreens_allModesReturnEmpty() {
        for mode in DisplaySelectionMode.allCases {
            let result = DisplayResolver.resolve(
                mode: mode,
                selectedKeys: ["whatever"],
                screens: [],
                mainScreenIndex: 0,
            )
            #expect(
                result.isEmpty,
                "Mode \(mode) must return empty when no screens are connected",
            )
        }
    }

    // MARK: - .all Mode

    @Test
    func resolve_all_returnsAllIndices() {
        let result = DisplayResolver.resolve(
            mode: .all,
            selectedKeys: [],
            screens: [Self.builtInDisplay, Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1, 2])
    }

    @Test
    func resolve_all_ignoresSelectedKeys() {
        let result = DisplayResolver.resolve(
            mode: .all,
            selectedKeys: ["totally-bogus-key"],
            screens: [Self.builtInDisplay, Self.externalA],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1])
    }

    // MARK: - .mainOnly Mode

    @Test
    func resolve_mainOnly_returnsMainIndex() {
        let result = DisplayResolver.resolve(
            mode: .mainOnly,
            selectedKeys: [],
            screens: [Self.externalA, Self.builtInDisplay, Self.externalB],
            mainScreenIndex: 1,
        )
        #expect(result == [1])
    }

    @Test
    func resolve_mainOnly_mainIsNil_returnsEmpty() {
        // Documented behavior: when NSScreen.main is nil (rare — typically means
        // the session has no screens or is in a weird state), return nothing
        // rather than picking an arbitrary screen. This matches the old
        // [NSScreen.main].compactMap behavior.
        let result = DisplayResolver.resolve(
            mode: .mainOnly,
            selectedKeys: [],
            screens: [Self.externalA, Self.externalB],
            mainScreenIndex: nil,
        )
        #expect(result.isEmpty)
    }

    // MARK: - .externalOnly Mode

    @Test
    func resolve_externalOnly_returnsNonBuiltInIndices() {
        let result = DisplayResolver.resolve(
            mode: .externalOnly,
            selectedKeys: [],
            screens: [Self.builtInDisplay, Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [1, 2])
    }

    @Test
    func resolve_externalOnly_noExternals_fallsBackToMain() {
        // Laptop undocked — only built-in screen connected. Rather than returning
        // empty (defeats the app), fall back to showing on the main screen.
        let result = DisplayResolver.resolve(
            mode: .externalOnly,
            selectedKeys: [],
            screens: [Self.builtInDisplay],
            mainScreenIndex: 0,
        )
        #expect(result == [0])
    }

    @Test
    func resolve_externalOnly_noExternalsAndNoMain_returnsEmpty() {
        let result = DisplayResolver.resolve(
            mode: .externalOnly,
            selectedKeys: [],
            screens: [Self.builtInDisplay],
            mainScreenIndex: nil,
        )
        #expect(result.isEmpty)
    }

    @Test
    func resolve_externalOnly_allExternals_returnsAll() {
        let result = DisplayResolver.resolve(
            mode: .externalOnly,
            selectedKeys: [],
            screens: [Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1])
    }

    // MARK: - .selected Mode

    @Test
    func resolve_selected_matchesByPersistenceKey() {
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: [Self.externalA.persistenceKey],
            screens: [Self.builtInDisplay, Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [1])
    }

    @Test
    func resolve_selected_multipleMatches_returnsAllMatchingIndices() {
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: [Self.externalA.persistenceKey, Self.externalB.persistenceKey],
            screens: [Self.builtInDisplay, Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [1, 2])
    }

    @Test
    func resolve_selected_emptyKeys_fallsBackToAllScreens() {
        // Fail-open: user is in .selected mode but has not picked anything yet.
        // Show on all screens rather than nothing, so they are not surprised by
        // a missed meeting while they finish configuring.
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: [],
            screens: [Self.builtInDisplay, Self.externalA],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1])
    }

    @Test
    func resolve_selected_noMatchingKeys_fallsBackToAllScreens() {
        // User's saved monitors are all disconnected (e.g. travelling without the
        // dock). Rather than returning empty, fall back to showing on all connected
        // screens. Better to show the overlay somewhere than to silently miss it.
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: ["1-2-3", "4-5-6"],
            screens: [Self.externalA, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1])
    }

    @Test
    func resolve_selected_partialMatch_returnsOnlyMatching() {
        // Subtle: if at least one saved key matches, do NOT fall back — honor the
        // partial match. User connected one of two saved monitors; show only there.
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: [Self.externalA.persistenceKey, "9-9-9"],
            screens: [Self.builtInDisplay, Self.externalA],
            mainScreenIndex: 0,
        )
        #expect(result == [1])
    }

    @Test
    func resolve_selected_identicalMonitorsShareKey_bothMatch() {
        // Documented behavior: identical monitors (same vendor+model+serial) share
        // one persistenceKey and are treated as a group. Selecting the key activates
        // every screen matching it. See DisplayIdentifier docstring.
        let duplicate = DisplayResolver.ScreenDescriptor(
            isBuiltIn: false,
            persistenceKey: Self.externalA.persistenceKey,
        )
        let result = DisplayResolver.resolve(
            mode: .selected,
            selectedKeys: [Self.externalA.persistenceKey],
            screens: [Self.externalA, duplicate, Self.externalB],
            mainScreenIndex: 0,
        )
        #expect(result == [0, 1])
    }
}
