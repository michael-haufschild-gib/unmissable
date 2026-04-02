import Foundation
import OSLog
import Sparkle

/// Manages application auto-updates via Sparkle.
/// Requires an appcast URL configured before use.
@MainActor
final class UpdateManager: ObservableObject {
    private let logger = Logger(category: "UpdateManager")

    @Published
    var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        // Bind canCheckForUpdates to the updater's state
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        logger.info("Update manager initialized")
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController.updater.automaticallyChecksForUpdates }
        set { updaterController.updater.automaticallyChecksForUpdates = newValue }
    }
}
