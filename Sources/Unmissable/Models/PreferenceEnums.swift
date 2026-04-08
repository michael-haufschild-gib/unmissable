import Foundation

nonisolated enum FontSize: String, CaseIterable {
    case small
    case medium
    case large

    private static let smallScale: Double = 0.8
    private static let mediumScale: Double = 1.0
    private static let largeScale: Double = 1.4

    var scale: Double {
        switch self {
        case .small:
            Self.smallScale

        case .medium:
            Self.mediumScale

        case .large:
            Self.largeScale
        }
    }
}

nonisolated enum DisplaySelectionMode: String, CaseIterable {
    case all
    case mainOnly
    case externalOnly
    case selected

    var displayName: String {
        switch self {
        case .all:
            "All Displays"

        case .mainOnly:
            "Main Display Only"

        case .externalOnly:
            "External Displays Only"

        case .selected:
            "Choose Displays…"
        }
    }
}

nonisolated enum MenuBarDisplayMode: String, CaseIterable {
    case icon
    case timer
    case nameTimer

    var displayName: String {
        switch self {
        case .icon:
            "Icon Only"

        case .timer:
            "Timer"

        case .nameTimer:
            "Name + Timer"
        }
    }
}
