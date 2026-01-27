import Foundation
import OSLog

// Enhanced logging utility for Unmissable app
final class DebugLogger {
  private let logger: Logger
  private let logFile: String

  init(subsystem: String, category: String, logFile: String = "/tmp/unmissable_debug.log") {
    self.logger = Logger(subsystem: subsystem, category: category)
    self.logFile = logFile

    // Clear log file on init
    try? "".write(toFile: logFile, atomically: true, encoding: .utf8)
  }

  func debug(_ message: String) {
    let prefixed = "[DEBUG] \(message)"

    // 1. Print to stdout only in DEBUG builds (visible in terminal)
    #if DEBUG
      print(prefixed)
      fflush(stdout)
    #endif

    // 2. Write to file (persistent)
    logToFile(prefixed)

    // 3. System log (for Console.app)
    logger.debug("\(message)")
  }

  func info(_ message: String) {
    let prefixed = "[INFO] \(message)"

    #if DEBUG
      print(prefixed)
      fflush(stdout)
    #endif
    logToFile(prefixed)
    logger.info("\(message)")
  }

  func error(_ message: String) {
    let prefixed = "[ERROR] \(message)"

    #if DEBUG
      print(prefixed)
      fflush(stdout)
    #endif
    logToFile(prefixed)
    logger.error("\(message)")
  }

  private func logToFile(_ message: String) {
    let timestamped = "\(Date()): \(message)\n"
    if let data = timestamped.data(using: .utf8) {
      if FileManager.default.fileExists(atPath: logFile) {
        if let fileHandle = FileHandle(forWritingAtPath: logFile) {
          fileHandle.seekToEndOfFile()
          fileHandle.write(data)
          fileHandle.closeFile()
        }
      } else {
        try? data.write(to: URL(fileURLWithPath: logFile))
      }
    }
  }
}
