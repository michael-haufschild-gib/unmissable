import Foundation
import OSLog

/// Bounded ring buffer that captures `DiagnosticRecord`s for post-hoc analysis.
///
/// Thread-safe via `OSAllocatedUnfairLock` so it can be called from any isolation
/// domain (MainActor, custom actors, nonisolated). The lock is uncontended in
/// practice because diagnostic writes are infrequent.
///
/// Records are stored in memory and exported on demand to JSONL or markdown.
final nonisolated class FlightRecorder: Sendable {
    /// Maximum records retained. Oldest records are dropped when full.
    static let defaultCapacity = 500

    private let storage: OSAllocatedUnfairLock<RingBuffer>

    nonisolated init(capacity: Int = FlightRecorder.defaultCapacity) {
        storage = OSAllocatedUnfairLock(initialState: RingBuffer(capacity: capacity))
    }

    /// Appends a record to the ring buffer. O(1), lock-protected.
    nonisolated func append(_ record: DiagnosticRecord) {
        storage.withLock { $0.append(record) }
    }

    /// Returns a snapshot of all records in chronological order.
    nonisolated func snapshot() -> [DiagnosticRecord] {
        storage.withLock { $0.snapshot() }
    }

    /// Number of records currently stored.
    nonisolated var count: Int {
        storage.withLock { $0.count }
    }

    /// Removes all stored records.
    nonisolated func clear() {
        storage.withLock { $0.clear() }
    }

    /// Exports all records as newline-delimited JSON (JSONL).
    /// Each line is one JSON-encoded `DiagnosticRecord`.
    nonisolated func exportJSONL() -> Data {
        let records = snapshot()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys

        var lines: [Data] = []
        for record in records {
            if let line = try? encoder.encode(record) {
                lines.append(line)
            }
        }
        let newline = Data([UInt8(ascii: "\n")])
        return lines.reduce(Data()) { $0 + $1 + newline }
    }

    /// Writes the JSONL export to the given file URL.
    nonisolated func exportJSONL(to url: URL) throws {
        let data = exportJSONL()
        try data.write(to: url, options: .atomic)
    }

    /// Returns the most recent `count` records in chronological order.
    nonisolated func tail(_ count: Int) -> [DiagnosticRecord] {
        let all = snapshot()
        return Array(all.suffix(count))
    }
}

// MARK: - Ring Buffer (internal, not Sendable — protected by lock)

/// Fixed-capacity circular buffer for `DiagnosticRecord`.
/// Only accessed inside `OSAllocatedUnfairLock` — no isolation needed.
private nonisolated struct RingBuffer {
    private var buffer: [DiagnosticRecord?]
    private var writeIndex = 0
    private(set) var count = 0
    private let capacity: Int

    init(capacity: Int = FlightRecorder.defaultCapacity) {
        self.capacity = capacity
        buffer = Array(repeating: nil, count: capacity)
    }

    mutating func append(_ record: DiagnosticRecord) {
        buffer[writeIndex] = record
        writeIndex = (writeIndex + 1) % capacity
        if count < capacity {
            count += 1
        }
    }

    func snapshot() -> [DiagnosticRecord] {
        // `count` is a stored Int tracking appended records, not a Collection property.
        // swiftlint:disable:next empty_count
        guard count > 0 else { return [] }
        if count < capacity {
            // Buffer hasn't wrapped — records are in order from index 0
            return buffer.prefix(count).compactMap(\.self)
        }
        // Buffer has wrapped — oldest record is at writeIndex
        let tail = buffer[writeIndex...].compactMap(\.self)
        let head = buffer[..<writeIndex].compactMap(\.self)
        return tail + head
    }

    mutating func clear() {
        buffer = Array(repeating: nil, count: capacity)
        writeIndex = 0
        count = 0
    }
}
