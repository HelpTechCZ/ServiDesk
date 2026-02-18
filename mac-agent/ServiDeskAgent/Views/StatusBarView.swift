import SwiftUI

struct StatusBarView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)

            Spacer()

            Text("v\(appState.config.agentVersion)")
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var statusColor: Color {
        switch appState.state {
        case .idle: return .gray
        case .connecting, .registered: return .yellow
        case .waiting: return .orange
        case .connected: return .green
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch appState.state {
        case .idle: return "Odpojeno"
        case .connecting: return "Připojování..."
        case .registered: return "Registrováno"
        case .waiting: return "Čekání na technika"
        case .connected(let name): return "Připojeno – \(name)"
        case .disconnected: return "Session ukončena"
        case .error(let msg): return "Chyba: \(msg)"
        }
    }
}
