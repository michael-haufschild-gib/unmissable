import Foundation

enum SyncStatus: Equatable {
    case idle
    case syncing
    case offline
    case error(String)

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
