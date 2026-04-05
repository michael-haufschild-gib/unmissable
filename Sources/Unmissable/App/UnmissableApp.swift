import AppKit
import MenuBarExtraAccess
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
    private var appState = AppState()
    @State
    private var isMenuPresented = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
                .introspectMenuBarExtraWindow { window in
                    window.setAccessibilityIdentifier(Accessibility.popoverIdentifier)
                }
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
        }
        .menuBarExtraAccess(isPresented: $isMenuPresented) { statusItem in
            configureStatusItem(statusItem)
        }
        .menuBarExtraStyle(.window)
    }

    private func configureStatusItem(_ statusItem: NSStatusItem) {
        statusItem.button?.setAccessibilityLabel(Accessibility.statusItemLabel)
        statusItem.button?.setAccessibilityIdentifier(Accessibility.statusItemIdentifier)
        statusItem.button?.setAccessibilityHelp(Accessibility.statusItemHelp)
        statusItem.button?.toolTip = Accessibility.statusItemHelp
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
