import AppKit
import AVFoundation
import Foundation
import OSLog

@MainActor
final class SoundManager: ObservableObject {
    private let logger = Logger(subsystem: "com.unmissable.app", category: "SoundManager")

    private var audioPlayer: AVAudioPlayer?
    private let preferencesManager: PreferencesManager

    init(preferencesManager: PreferencesManager) {
        self.preferencesManager = preferencesManager
    }

    func playAlertSound() {
        guard preferencesManager.playAlertSound else {
            logger.info("Alert sound disabled in preferences")
            return
        }

        do {
            // Use system alert sound for compatibility
            guard let soundURL = Bundle.main.url(forResource: "alert", withExtension: "aiff") else {
                // Fallback to system sound
                playSystemAlertSound()
                return
            }

            audioPlayer = try AVAudioPlayer(contentsOf: soundURL)
            audioPlayer?.volume = Float(preferencesManager.alertVolume)
            audioPlayer?.play()

            logger.info("Playing alert sound at volume \(preferencesManager.alertVolume)")

        } catch {
            logger.error("Failed to play alert sound: \(error.localizedDescription)")
            // Fallback to system sound
            playSystemAlertSound()
        }
    }

    private func playSystemAlertSound() {
        // Use NSSound for system alert sound as fallback
        NSSound.beep()
        logger.info("Playing system beep sound")
    }

    func stopSound() {
        audioPlayer?.stop()
        audioPlayer = nil
    }
}
