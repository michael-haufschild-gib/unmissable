import OSLog

extension Logger {
    /// Shared subsystem identifier for all Unmissable loggers.
    /// Matches the app's bundle identifier so Console.app filtering works correctly.
    static let subsystemID = "com.unmissable.app"

    /// Convenience initializer using the shared subsystem.
    /// `nonisolated` because `Logger` is thread-safe and callers may log from any isolation context.
    nonisolated init(category: String) {
        self.init(subsystem: Self.subsystemID, category: category)
    }
}
