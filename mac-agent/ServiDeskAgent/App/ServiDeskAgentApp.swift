import SwiftUI

@main
struct ServiDeskAgentApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environmentObject(appState)
                .frame(width: 480, height: 580)
                .fixedSize()
        }
        .windowResizability(.contentSize)
    }
}
