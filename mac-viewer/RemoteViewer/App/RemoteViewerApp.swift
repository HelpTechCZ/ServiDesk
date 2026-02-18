import SwiftUI

@main
struct RemoteViewerApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .onAppear {
                    appState.connectIfNeeded()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 500, height: 600)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }
}
