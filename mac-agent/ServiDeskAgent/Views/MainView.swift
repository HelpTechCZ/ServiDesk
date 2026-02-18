import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "desktopcomputer")
                    .font(.title2)
                    .foregroundColor(.orange)
                Text("ServiDesk Agent")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Tab View
            TabView(selection: $selectedTab) {
                supportTab
                    .tabItem {
                        Label("Podpora", systemImage: "headphones")
                    }
                    .tag(0)

                UnattendedSettingsView()
                    .tabItem {
                        Label("Vzdálený přístup", systemImage: "lock.shield")
                    }
                    .tag(1)
            }
            .padding(.top, 4)

            Divider()

            // Status bar
            StatusBarView()
        }
    }

    @ViewBuilder
    private var supportTab: some View {
        switch appState.state {
        case .idle:
            SupportFormView()
        case .connecting, .registered:
            WaitingView(message: "Připojování k serveru...")
        case .waiting:
            WaitingView(message: "Čekání na technika...")
        case .connected(let adminName):
            ConnectedView(adminName: adminName)
        case .disconnected(let reason):
            DisconnectedView(reason: reason)
        case .error(let message):
            DisconnectedView(reason: message)
        }
    }
}
