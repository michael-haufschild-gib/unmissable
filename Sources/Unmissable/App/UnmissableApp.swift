import SwiftUI

@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    var appDelegate
    @StateObject
    private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .environmentObject(appState.calendar)
                .themed(themeManager: appState.themeManager)
        } label: {
            MenuBarLabelView()
                .environmentObject(appState.menuBarPreview)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    @EnvironmentObject
    var menuBarPreview: MenuBarPreviewManager
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
