import Combine
import Foundation
import Observation
import OSLog
import Sparkle

/// Manages application auto-updates via Sparkle.
/// Requires an appcast URL configured before use.
@Observable
final class UpdateManager {
    private let logger = Logger(category: "UpdateManager")

    var canCheckForUpdates = false

    @ObservationIgnored
    private let updaterController: SPUStandardUpdaterController
    @ObservationIgnored
    private var cancellable: AnyCancellable?

    init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil,
        )
        // Bind canCheckForUpdates to the updater's state via KVO publisher
        cancellable = updaterController.updater.publisher(for: \.canCheckForUpdates)
            .sink { [weak self] value in
                self?.canCheckForUpdates = value
            }

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
