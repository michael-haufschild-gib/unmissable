import OSLog

extension Logger {
    /// Shared subsystem identifier for all Unmissable loggers.
    /// Matches the app's bundle identifier so Console.app filtering works correctly.
    static let subsystemID = "com.unmissable.app"

    /// Convenience initializer using the shared subsystem.
    init(category: String) {
        self.init(subsystem: Self.subsystemID, category: category)
    }
}
