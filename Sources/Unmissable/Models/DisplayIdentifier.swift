import AppKit
import CoreGraphics

/// Stable hardware fingerprint for a connected display.
///
/// Combines CoreGraphics vendor, model, and serial numbers into a string
/// that survives reboots for most monitors. When multiple identical monitors
/// share the same fingerprint (same vendor+model+serial), all matching
/// screens are treated as a group — selecting one selects all duplicates.
struct DisplayIdentifier: Hashable, Codable, CustomStringConvertible {
    let vendor: UInt32
    let model: UInt32
    let serial: UInt32
    let isBuiltIn: Bool

    /// Human-readable name assigned by macOS (e.g. "PA278CV (2)").
    /// Stored for display purposes only — not used for matching.
    let localizedName: String

    /// Stable string key used for UserDefaults persistence.
    var persistenceKey: String {
        "\(vendor)-\(model)-\(serial)"
    }

    var description: String {
        localizedName
    }

    private static let screenNumberKey = NSDeviceDescriptionKey("NSScreenNumber")

    /// Creates an identifier from a live `NSScreen`.
    @MainActor
    init?(screen: NSScreen) {
        guard let screenNumber = screen.deviceDescription[Self.screenNumberKey]
            as? CGDirectDisplayID
        else {
            return nil
        }
        self.vendor = CGDisplayVendorNumber(screenNumber)
        self.model = CGDisplayModelNumber(screenNumber)
        self.serial = CGDisplaySerialNumber(screenNumber)
        self.isBuiltIn = CGDisplayIsBuiltin(screenNumber) != 0
        self.localizedName = screen.localizedName
    }

    /// Creates an identifier from persisted values (for matching against live screens).
    init(vendor: UInt32, model: UInt32, serial: UInt32, isBuiltIn: Bool = false, localizedName: String = "") {
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltIn = isBuiltIn
        self.localizedName = localizedName
    }

    /// Two identifiers match if their hardware fingerprints are equal.
    /// `localizedName` and `isBuiltIn` are excluded — they're metadata, not identity.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.vendor == rhs.vendor && lhs.model == rhs.model && lhs.serial == rhs.serial
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(vendor)
        hasher.combine(model)
        hasher.combine(serial)
    }

    /// Returns identifiers for all currently connected screens.
    @MainActor
    static func allConnected() -> [(screen: NSScreen, identifier: Self)] {
        NSScreen.screens.compactMap { screen in
            guard let id = Self(screen: screen) else { return nil }
            return (screen, id)
        }
    }
}
