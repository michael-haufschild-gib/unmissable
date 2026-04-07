import AppKit
import SwiftUI

@main
struct UnmissableApp: App {
    private enum Accessibility {
        static let popoverIdentifier = "unmissable-popover"
        static let statusItemIdentifier = "unmissable-status-item"
        static let statusItemLabel = "Unmissable"
        static let statusItemHelp = "Open Unmissable menu"
    }

    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate

    // CRITICAL: AppState MUST be initialized lazily in .task, NOT eagerly.
    // Eager init runs before NSApplication.didFinishLaunching, which breaks
    // the activation policy and blocks menu bar clicks. This took 2 days to
    // debug — do NOT change this to eager init.
    @State
    private var appState: AppState?

    var body: some Scene {
        MenuBarExtra {
            Group {
                if let appState {
                    MenuBarView()
                        .environment(appState)
                        .environment(appState.calendar)
                        .themed(themeManager: appState.themeManager)
                        .accessibilityIdentifier(Accessibility.popoverIdentifier)
                } else {
                    Text("Loading...")
                        .padding()
                }
            }
        } label: {
            MenuBarLabelView(menuBarPreview: appState?.menuBarPreview)
                .task {
                    if appState == nil {
                        appState = AppState(isTestEnvironment: AppRuntime.isRunningTests)
                    }
                }
                .accessibilityIdentifier(Accessibility.statusItemIdentifier)
                .accessibilityLabel(Accessibility.statusItemLabel)
                .help(Accessibility.statusItemHelp)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    var menuBarPreview: MenuBarPreviewManager?

    var body: some View {
        Group {
            if let menuBarPreview, !menuBarPreview.shouldShowIcon,
               let text = menuBarPreview.menuBarText
            {
                Text(text)
                    .font(DesignFonts.menuBarLabel)
            } else {
                Image(systemName: "calendar.badge.clock")
            }
        }
    }
}
