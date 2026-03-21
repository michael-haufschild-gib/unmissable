import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case offline
    case error(String)

    var isSyncing: Bool {
        if case .syncing = self { return true }
        return false
    }

    var isError: Bool {
        if case .error = self { return true }
        return false
    }

    var description: String {
        switch self {
        case .idle:
            "Ready"
        case .syncing:
            "Syncing..."
        case .offline:
            "Offline"
        case let .error(message):
            "Error: \(message)"
        }
    }
}
