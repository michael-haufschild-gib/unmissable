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
    private var appState = AppState(isTestEnvironment: AppRuntime.isRunningTests)

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
                .accessibilityIdentifier(Accessibility.popoverIdentifier)
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
                .accessibilityLabel(Accessibility.statusItemLabel)
                .accessibilityIdentifier(Accessibility.statusItemIdentifier)
                .help(Accessibility.statusItemHelp)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    @Environment(MenuBarPreviewManager.self)
    var menuBarPreview
    @Environment(\.design)
    private var design

    var body: some View {
        Group {
            if menuBarPreview.shouldShowIcon {
                Image(systemName: "calendar.badge.clock")
            } else if let text = menuBarPreview.menuBarText {
                Text(text)
                    .font(design.fonts.monoSmall)
            } else {
                Image(systemName: "calendar.badge.clock")
            }
        }
    }
}
