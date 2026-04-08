import AppKit
import Carbon.HIToolbox
import Magnet
import Sauce
import SwiftUI

/// A clickable shortcut field that records a new global key combination.
///
/// In idle state, it displays the current shortcut as keycaps.
/// When clicked, it enters recording mode and captures the next key + modifier combo.
/// Validates via `HotKey.register()` and surfaces errors on conflict.
struct ShortcutRecorderView: View {
    /// The current keycap labels (e.g. `["⌘", "Esc"]`).
    let currentLabels: [String]
    /// Called when the user records a valid new key combo.
    let onRecord: (KeyCombo) -> Bool
    /// Called when the user clicks "Reset".
    let onReset: () -> Void

    @Environment(\.design)
    private var design

    @State
    private var isRecording = false
    @State
    private var showError = false

    private enum Metrics {
        static let fieldMinWidth: CGFloat = 120
        static let fieldHeight: CGFloat = 32
        static let borderWidth: CGFloat = 1
        static let recordingBorderWidth: CGFloat = 1.5
        static let errorDisplaySeconds: Double = 2
        static let resetButtonSize: Size = .sm
    }

    private enum Size {
        case sm
    }

    var body: some View {
        HStack(spacing: design.spacing.sm) {
            recorderField
            resetButton
        }
    }

    // MARK: - Recorder Field

    private var recorderField: some View {
        Group {
            if isRecording {
                recordingContent
            } else if showError {
                errorContent
            } else {
                idleContent
            }
        }
        .frame(minWidth: Metrics.fieldMinWidth, minHeight: Metrics.fieldHeight)
        .padding(.horizontal, design.spacing.md)
        .background(isRecording ? design.colors.accentSubtle : design.colors.surface)
        .clipShape(RoundedRectangle(cornerRadius: design.corners.md))
        .overlay(
            RoundedRectangle(cornerRadius: design.corners.md)
                .stroke(
                    isRecording ? design.colors.accent : design.colors.borderDefault,
                    lineWidth: isRecording ? Metrics.recordingBorderWidth : Metrics.borderWidth,
                ),
        )
        .contentShape(Rectangle())
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel(isRecording ? "Recording shortcut" : "Click to change shortcut")
        .onTapGesture {
            isRecording.toggle()
            showError = false
        }
        .background(
            ShortcutRecorderEventHandler(
                isRecording: $isRecording,
                onKeyCombo: handleRecordedCombo,
            ),
        )
    }

    private var idleContent: some View {
        HStack(spacing: design.spacing.xs) {
            ForEach(Array(currentLabels.enumerated()), id: \.offset) { _, label in
                UMKeyCap(label: label)
            }
        }
    }

    private var recordingContent: some View {
        Text("Type shortcut…")
            .font(design.fonts.caption)
            .foregroundColor(design.colors.accent)
    }

    private var errorContent: some View {
        Text("Already in use")
            .font(design.fonts.caption)
            .foregroundColor(design.colors.error)
    }

    // MARK: - Reset Button

    private var resetButton: some View {
        Button {
            onReset()
            showError = false
        } label: {
            Image(systemName: "arrow.counterclockwise")
                .font(design.fonts.caption)
        }
        .buttonStyle(UMButtonStyle(.ghost, size: .sm))
        .accessibilityLabel("Reset to default shortcut")
    }

    // MARK: - Event Handling

    private func handleRecordedCombo(_ keyCombo: KeyCombo) {
        isRecording = false
        if onRecord(keyCombo) {
            showError = false
        } else {
            showError = true
            Task {
                try? await Task.sleep(for: .seconds(Metrics.errorDisplaySeconds))
                showError = false
            }
        }
    }
}

// MARK: - NSEvent Monitor Bridge

/// An invisible NSViewRepresentable that installs a local event monitor
/// while `isRecording` is true.
private struct ShortcutRecorderEventHandler: NSViewRepresentable {
    @Binding
    var isRecording: Bool
    let onKeyCombo: (KeyCombo) -> Void

    func makeNSView(context _: Context) -> NSView {
        NSView()
    }

    func updateNSView(_: NSView, context: Context) {
        if isRecording {
            context.coordinator.startMonitoring(onKeyCombo: onKeyCombo, stopRecording: {
                isRecording = false
            })
        } else {
            context.coordinator.stopMonitoring()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        private var monitor: Any?

        func startMonitoring(
            onKeyCombo: @escaping (KeyCombo) -> Void,
            stopRecording: @escaping () -> Void,
        ) {
            guard monitor == nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
                // Escape without modifiers cancels recording
                let rawModifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                if event.keyCode == UInt16(kVK_Escape), rawModifiers.isEmpty {
                    stopRecording()
                    return nil
                }

                let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    .intersection([.command, .option, .shift, .control])

                // Require at least one modifier
                guard !modifiers.isEmpty else { return nil }

                guard let key = Key(QWERTYKeyCode: Int(event.keyCode)) else { return nil }
                guard let keyCombo = KeyCombo(key: key, cocoaModifiers: modifiers) else { return nil }

                onKeyCombo(keyCombo)
                return nil // Consume the event
            }
        }

        func stopMonitoring() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        deinit {
            stopMonitoring()
        }
    }
}
