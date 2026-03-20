import Foundation
import OSLog

/// Logging utility that wraps OSLog with optional stdout output in debug builds.
/// File I/O is gated behind #if DEBUG to avoid production overhead.
final class DebugLogger: Sendable {
    private let logger: Logger

    init(subsystem: String, category: String) {
        logger = Logger(subsystem: subsystem, category: category)
    }

    func debug(_ message: String) {
        #if DEBUG
            print("[DEBUG] \(message)")
        #endif
        logger.debug("\(message)")
    }

    func info(_ message: String) {
        #if DEBUG
            print("[INFO] \(message)")
        #endif
        logger.info("\(message)")
    }

    func error(_ message: String) {
        #if DEBUG
            print("[ERROR] \(message)")
        #endif
        logger.error("\(message)")
    }
}
