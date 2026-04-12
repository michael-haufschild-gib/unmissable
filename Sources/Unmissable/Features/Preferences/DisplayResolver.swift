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
    /// Rules:
    /// - `.all`: every screen. Never empty when `screens` is non-empty.
    /// - `.mainOnly`: the screen at `mainScreenIndex`; **empty** if `mainScreenIndex`
    ///   is nil. The caller (AppKit context) is responsible for ensuring a main
    ///   screen exists before selecting this mode.
    /// - `.externalOnly`: all non-built-in screens; falls back to the main screen
    ///   when no externals are connected (e.g. laptop undocked). **Empty** if neither
    ///   an external nor a main screen is available.
    /// - `.selected`: screens whose `persistenceKey` is in `selectedKeys`; fails
    ///   open to **all** screens when `selectedKeys` is empty, or when none of the
    ///   saved keys match a currently connected screen (user's saved monitors are
    ///   offline). Never empty when `screens` is non-empty.
    ///
    /// Only `.all` and `.selected` are fully fail-open. `.mainOnly` and `.externalOnly`
    /// can still return an empty array when the prerequisites for the chosen mode
    /// are absent — this is intentional and pinned by `DisplayResolverTests`.
    static func resolve(
        mode: DisplaySelectionMode,
        selectedKeys: Set<String>,
        screens: [ScreenDescriptor],
        mainScreenIndex: Int?,
    ) -> [Int] {
        guard !screens.isEmpty else { return [] }

        // Defensive bounds check: callers should only pass indices that refer
        // to `screens`, but `resolve` is a pure function with no way to enforce
        // that contract. A stale or out-of-range index would escape here and
        // trap at `screens[index]` in the caller's adapter, so drop invalid
        // values to `nil` and let the normal `.mainOnly` / `.externalOnly`
        // empty-result paths handle them.
        let safeMainIndex: Int? = {
            guard let mainScreenIndex, screens.indices.contains(mainScreenIndex) else {
                return nil
            }
            return mainScreenIndex
        }()

        switch mode {
        case .all:
            return Array(screens.indices)

        case .mainOnly:
            return safeMainIndex.map { [$0] } ?? []

        case .externalOnly:
            let externals = screens.enumerated()
                .filter { !$0.element.isBuiltIn }
                .map(\.offset)
            if !externals.isEmpty { return externals }
            // Fall back to main if no externals connected (e.g. laptop undocked)
            return safeMainIndex.map { [$0] } ?? []

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
