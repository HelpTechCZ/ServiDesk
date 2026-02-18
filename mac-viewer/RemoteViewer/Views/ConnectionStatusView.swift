import SwiftUI

struct ConnectionStatusView: View {
    @EnvironmentObject var appState: AppState

    private var statusColor: Color {
        switch appState.relay.connectionState {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.relay.connectionState {
        case .connected: return "Připojeno k serveru"
        case .connecting: return "Připojování..."
        case .disconnected: return "Odpojeno"
        case .error(let msg): return "Chyba: \(msg)"
        }
    }

    var body: some View {
        HStack {
            // Logo / Title
            Text("ServiDesk")
                .font(.title2)
                .fontWeight(.bold)

            Spacer()

            // Stav
            HStack(spacing: 6) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            // Nastavení
            Button(action: { appState.showSettings = true }) {
                Image(systemName: "gear")
            }
            .buttonStyle(.borderless)
            .sheet(isPresented: $appState.showSettings) {
                SettingsView()
                    .environmentObject(appState)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
