import Foundation

/// Pure resolver for `DisplaySelectionMode` — decides which screens receive an overlay.
///
/// Extracted from `PreferencesManager.screensForOverlay()` so the resolution rules
/// (especially the fail-open fallbacks) can be unit-tested without an `NSScreen`
/// dependency. Callers adapt their concrete screen type to `ScreenDescriptor`, call
/// `resolve(...)`, then map the returned indices back to their concrete screens.
enum DisplayResolver {
    /// Minimal view of a screen needed for selection resolution.
    struct ScreenDescriptor: Equatable {
        let isBuiltIn: Bool
        let persistenceKey: String
    }

    /// Returns the indices (into `screens`) that should receive an overlay.
    ///
    /// Rules (all fail open — never return empty when `screens` is non-empty):
    /// - `.all`: every screen
    /// - `.mainOnly`: the screen at `mainScreenIndex`; empty if `mainScreenIndex` is nil
    /// - `.externalOnly`: all non-built-in screens; falls back to the main screen when
    ///   no externals are connected (e.g. laptop undocked)
    /// - `.selected`: screens whose `persistenceKey` is in `selectedKeys`; falls back to
    ///   all screens when `selectedKeys` is empty, or when none of the saved keys match
    ///   a currently connected screen (user's saved monitors are offline).
    static func resolve(
        mode: DisplaySelectionMode,
        selectedKeys: Set<String>,
        screens: [ScreenDescriptor],
        mainScreenIndex: Int?,
    ) -> [Int] {
        guard !screens.isEmpty else { return [] }

        switch mode {
        case .all:
            return Array(screens.indices)

        case .mainOnly:
            return mainScreenIndex.map { [$0] } ?? []

        case .externalOnly:
            let externals = screens.enumerated()
                .filter { !$0.element.isBuiltIn }
                .map(\.offset)
            if !externals.isEmpty { return externals }
            // Fall back to main if no externals connected (e.g. laptop undocked)
            return mainScreenIndex.map { [$0] } ?? []

        case .selected:
            guard !selectedKeys.isEmpty else {
                // No screens selected — treat as "all" to avoid showing nothing
                return Array(screens.indices)
            }
            let matched = screens.enumerated()
                .filter { selectedKeys.contains($0.element.persistenceKey) }
                .map(\.offset)
            // Fall back to all if none of the saved screens are connected
            return matched.isEmpty ? Array(screens.indices) : matched
        }
    }
}
