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
