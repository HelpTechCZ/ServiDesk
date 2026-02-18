import SwiftUI

struct UnattendedSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var password: String = ""
    @State private var confirmPassword: String = ""
    @State private var showSavedAlert = false
    @State private var errorMessage: String?

    private var isEnabled: Bool {
        appState.config.unattendedAccessEnabled
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Vzdálený přístup bez dozoru")
                .font(.headline)

            Text("Umožní technikovi se připojit k tomuto počítači i bez vaší přítomnosti. Vyžaduje nastavení hesla.")
                .font(.caption)
                .foregroundColor(.secondary)

            Divider()

            if isEnabled {
                // Stav: povoleno
                HStack {
                    Image(systemName: "checkmark.shield.fill")
                        .foregroundColor(.green)
                    Text("Vzdálený přístup je povolen")
                        .font(.body)
                    Spacer()
                }

                Text("Agent ID: \(appState.config.agentId)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .textSelection(.enabled)

                Divider()

                Text("Změnit nebo zrušit heslo")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Password fields
            VStack(alignment: .leading, spacing: 8) {
                SecureField("Nové heslo", text: $password)
                    .textFieldStyle(.roundedBorder)

                SecureField("Potvrdit heslo", text: $confirmPassword)
                    .textFieldStyle(.roundedBorder)
            }

            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
            }

            HStack(spacing: 12) {
                Button("Uložit") {
                    savePassword()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(password.isEmpty)

                if isEnabled {
                    Button("Vypnout") {
                        disableUnattended()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
            }

            if showSavedAlert {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Nastavení uloženo")
                        .font(.caption)
                }
                .transition(.opacity)
            }

            Spacer()
        }
        .padding()
        .animation(.easeInOut, value: showSavedAlert)
    }

    private func savePassword() {
        errorMessage = nil

        guard password.count >= 4 else {
            errorMessage = "Heslo musí mít alespoň 4 znaky"
            return
        }

        guard password == confirmPassword else {
            errorMessage = "Hesla se neshodují"
            return
        }

        appState.config.setUnattendedPassword(password)
        appState.config.save()

        // Aktualizovat na serveru pokud jsme připojeni
        if case .registered = appState.relay.connectionState {
            appState.relay.updateAgentInfo()
        }

        password = ""
        confirmPassword = ""
        showSavedAlert = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            showSavedAlert = false
        }
    }

    private func disableUnattended() {
        appState.config.unattendedAccessEnabled = false
        appState.config.unattendedAccessPasswordHash = ""
        appState.config.save()

        if case .registered = appState.relay.connectionState {
            appState.relay.updateAgentInfo()
        }

        password = ""
        confirmPassword = ""
    }
}
