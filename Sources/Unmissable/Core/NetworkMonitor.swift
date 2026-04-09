import Foundation
import Network
import Observation
import OSLog

/// Shared network reachability monitor. Replaces per-`SyncManager`
/// `NWPathMonitor` instances with a single shared observer, reducing
/// background queue overhead and preventing duplicate wake-time syncs.
@MainActor
@Observable
final class NetworkMonitor {
    private let logger = Logger(category: "NetworkMonitor")

    /// Current network reachability status.
    private(set) var isOnline: Bool = true

    /// Registered callbacks fired when the network transitions from offline to online.
    /// Keyed for removal. Debounced internally (500ms) to coalesce rapid transitions
    /// (e.g., during system wake).
    @ObservationIgnored
    private var onReconnectCallbacks: [String: @MainActor () async -> Void] = [:]

    @ObservationIgnored
    private var monitor: NWPathMonitor?
    @ObservationIgnored
    private var monitorTask: Task<Void, Never>?
    @ObservationIgnored
    private var pendingUpdate: Task<Void, Never>?

    /// Debounce delay for network status changes (milliseconds).
    private static let debounceMs: UInt64 = 500

    init() {
        startMonitoring()
    }

    deinit {
        monitorTask?.cancel()
        pendingUpdate?.cancel()
        monitor?.cancel()
    }

    /// Registers a callback that fires when the network transitions offline → online.
    func registerOnReconnect(
        key: String,
        callback: @escaping @MainActor () async -> Void,
    ) {
        onReconnectCallbacks[key] = callback
    }

    /// Removes a previously registered reconnect callback.
    func unregisterOnReconnect(key: String) {
        onReconnectCallbacks.removeValue(forKey: key)
    }

    private func startMonitoring() {
        let pathMonitor = NWPathMonitor()
        monitor = pathMonitor

        let pathStream = AsyncStream<NWPath> { continuation in
            pathMonitor.pathUpdateHandler = { path in
                continuation.yield(path)
            }
            continuation.onTermination = { _ in
                pathMonitor.cancel()
            }
        }

        pathMonitor.start(queue: DispatchQueue(label: "com.unmissable.network", qos: .utility))

        monitorTask = Task { @MainActor [weak self] in
            for await path in pathStream {
                guard !Task.isCancelled else { break }
                self?.handlePathUpdate(path)
            }
        }

        logger.info("Network monitoring started")
    }

    private func handlePathUpdate(_ path: NWPath) {
        pendingUpdate?.cancel()

        pendingUpdate = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(for: .milliseconds(Self.debounceMs))
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            let wasOnline = isOnline
            isOnline = path.status == .satisfied

            if !wasOnline, isOnline {
                logger.info("Network restored — notifying \(self.onReconnectCallbacks.count) subscribers")
                for (key, callback) in onReconnectCallbacks {
                    logger.debug("Reconnect callback: '\(key)'")
                    await callback()
                }
            } else if !isOnline {
                logger.warning("Network connection lost")
            }
        }
    }
}
