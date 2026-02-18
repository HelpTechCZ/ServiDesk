import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var serverURL: String = ""
    @State private var adminToken: String = ""
    @State private var adminName: String = ""
    @State private var autoReconnect: Bool = true
    @State private var soundEnabled: Bool = true
    @State private var notificationsEnabled: Bool = true
    @State private var mapCmdToCtrl: Bool = true
    @State private var defaultQuality: StreamQuality = .auto

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Nastavení")
                .font(.title2)
                .fontWeight(.bold)

            Form {
                Section("Server") {
                    TextField("Server URL:", text: $serverURL)
                        .textFieldStyle(.roundedBorder)

                    SecureField("Admin token:", text: $adminToken)
                        .textFieldStyle(.roundedBorder)

                    TextField("Jméno admina:", text: $adminName)
                        .textFieldStyle(.roundedBorder)
                }

                Section("Připojení") {
                    Toggle("Automatické připojení", isOn: $autoReconnect)
                }

                Section("Notifikace") {
                    Toggle("Zvukové upozornění", isOn: $soundEnabled)
                    Toggle("Systémové notifikace", isOn: $notificationsEnabled)
                }

                Section("Ovládání") {
                    Toggle("Cmd → Ctrl mapování", isOn: $mapCmdToCtrl)

                    Picker("Kvalita streamu:", selection: $defaultQuality) {
                        Text("Auto").tag(StreamQuality.auto)
                        Text("Low").tag(StreamQuality.low)
                        Text("Medium").tag(StreamQuality.medium)
                        Text("High").tag(StreamQuality.high)
                    }
                    .pickerStyle(.segmented)
                }
            }
            .formStyle(.grouped)

            HStack {
                Spacer()

                Button("Zrušit") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Uložit") {
                    saveSettings()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 450, height: 520)
        .onAppear { loadSettings() }
    }

    private func loadSettings() {
        serverURL = appState.config.relayServerURL
        adminToken = appState.config.adminToken
        adminName = appState.config.adminName
        autoReconnect = appState.config.autoReconnect
        soundEnabled = appState.config.soundEnabled
        notificationsEnabled = appState.config.notificationsEnabled
        mapCmdToCtrl = appState.config.mapCmdToCtrl
        defaultQuality = appState.config.defaultQuality
    }

    private func saveSettings() {
        appState.config.relayServerURL = serverURL
        appState.config.adminToken = adminToken
        appState.config.adminName = adminName
        appState.config.autoReconnect = autoReconnect
        appState.config.soundEnabled = soundEnabled
        appState.config.notificationsEnabled = notificationsEnabled
        appState.config.mapCmdToCtrl = mapCmdToCtrl
        appState.config.defaultQuality = defaultQuality
        appState.config.save()

        // Reconnect s novými údaji
        appState.reconnectWithNewConfig()
    }
}
