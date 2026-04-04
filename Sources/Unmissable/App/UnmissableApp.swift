import SwiftUI

@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @State
    private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
                .environment(appState.calendar)
                .themed(themeManager: appState.themeManager)
        } label: {
            MenuBarLabelView()
                .environment(appState.menuBarPreview)
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
