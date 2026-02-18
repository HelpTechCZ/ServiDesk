import SwiftUI

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ConnectionStatusView()

            Divider()

            // Content
            if appState.activeSession != nil {
                RemoteDesktopView()
            } else {
                // Tab bar
                HStack(spacing: 0) {
                    TabButton(title: "Žádosti", systemImage: "person.2", isActive: appState.activeTab == .requests) {
                        appState.activeTab = .requests
                    }
                    TabButton(title: "Zařízení", systemImage: "desktopcomputer", isActive: appState.activeTab == .devices) {
                        appState.activeTab = .devices
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)

                Divider()

                switch appState.activeTab {
                case .requests:
                    RequestListView()
                case .devices:
                    if let vm = appState.deviceListVM {
                        DeviceListView(viewModel: vm)
                    }
                }

                Divider()

                // Patička s verzí
                HStack {
                    Text("ServiDesk Viewer v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("HelpTech.cz")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(.bar)
            }
        }
        .frame(minWidth: 450, minHeight: 400)
    }
}

struct TabButton: View {
    let title: String
    let systemImage: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
        .foregroundColor(isActive ? .accentColor : .secondary)
    }
}
