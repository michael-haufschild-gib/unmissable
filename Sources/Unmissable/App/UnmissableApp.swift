import SwiftUI

@main
struct UnmissableApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
                .customThemedEnvironment()
        } label: {
            MenuBarLabelView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabelView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Group {
            if appState.shouldShowIcon {
                Image(systemName: "calendar.badge.clock")
            } else if let text = appState.menuBarText {
                Text(text)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
            } else {
                Image(systemName: "calendar.badge.clock")
            }
        }
    }
}
