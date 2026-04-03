import Foundation

struct CalendarInfo: Identifiable, Codable {
    let id: String
    let name: String
    let description: String?
    let isSelected: Bool
    let isPrimary: Bool
    let colorHex: String?
    let sourceProvider: CalendarProviderType
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
            lastSyncAt: lastSyncAt,
            createdAt: createdAt,
            updatedAt: Date(),
        )
    }
}
