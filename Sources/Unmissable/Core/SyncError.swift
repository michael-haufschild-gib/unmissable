import Foundation

enum SyncError: LocalizedError {
    case apiFetchFailed(String)

    var errorDescription: String? {
        switch self {
        case let .apiFetchFailed(reason):
            "Calendar sync failed: \(reason)"
        }
    }
}
