import Foundation

// MARK: - Alert Mode

/// Controls how a calendar's meeting alerts are delivered.
enum AlertMode: String, Codable, CaseIterable {
    /// Full-screen blocking overlay (default, existing behavior).
    case overlay

    /// Standard macOS Notification Center notification.
    case notification

    /// No alert — event appears in menu bar only.
    case none

    /// Human-readable name for UI display.
    var displayName: String {
        switch self {
        case .overlay: "Full-Screen Overlay"
        case .notification: "Notification"
        case .none: "None"
        }
    }
}

// MARK: - Calendar Info

struct CalendarInfo: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let description: String?
    let isSelected: Bool
    let isPrimary: Bool
    let colorHex: String?
    let sourceProvider: CalendarProviderType
    let alertMode: AlertMode
    let lastSyncAt: Date?
    let createdAt: Date
    let updatedAt: Date

    init(
        id: String,
        name: String,
        description: String? = nil,
        isSelected: Bool = false,
        isPrimary: Bool = false,
        colorHex: String? = nil,
        sourceProvider: CalendarProviderType = .google,
        alertMode: AlertMode = .overlay,
        lastSyncAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.isSelected = isSelected
        self.isPrimary = isPrimary
        self.colorHex = colorHex
        self.sourceProvider = sourceProvider
        self.alertMode = alertMode
        self.lastSyncAt = lastSyncAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Returns a copy with updated selection status and current timestamp.
    ///
    /// **Maintenance note:** This method lists every stored property explicitly so that
    /// adding a new required property to `CalendarInfo.init` will cause a compile error here,
    /// forcing the developer to decide how the new field should be handled in copies.
    func withSelection(_ isSelected: Bool) -> Self {
        Self(
            id: id,
            name: name,
            description: description,
            isSelected: isSelected,
            isPrimary: isPrimary,
            colorHex: colorHex,
            sourceProvider: sourceProvider,
            alertMode: alertMode,
            lastSyncAt: lastSyncAt,
            createdAt: createdAt,
            updatedAt: Date(),
        )
    }

    /// Returns a copy with updated alert mode and current timestamp.
    func withAlertMode(_ alertMode: AlertMode) -> Self {
        Self(
            id: id,
            name: name,
            description: description,
            isSelected: isSelected,
            isPrimary: isPrimary,
            colorHex: colorHex,
            sourceProvider: sourceProvider,
            alertMode: alertMode,
            lastSyncAt: lastSyncAt,
            createdAt: createdAt,
            updatedAt: Date(),
        )
    }
}
