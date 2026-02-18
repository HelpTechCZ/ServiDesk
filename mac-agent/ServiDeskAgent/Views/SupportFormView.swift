import SwiftUI

struct SupportFormView: View {
    @EnvironmentObject var appState: AppState
    @State private var customerName: String = ""
    @State private var message: String = ""

    private var hostname: String {
        Host.current().localizedName ?? ProcessInfo.processInfo.hostName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Varování oprávnění
            if !appState.hasScreenRecordingPermission || !appState.hasAccessibilityPermission {
                permissionWarning
            }

            // Formulář
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Název počítače")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(hostname)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(NSColor.controlBackgroundColor))
                        .cornerRadius(6)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Vaše jméno")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextField("Zadejte vaše jméno", text: $customerName)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Popis problému")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TextEditor(text: $message)
                        .font(.body)
                        .frame(height: 80)
                        .border(Color(NSColor.separatorColor), width: 1)
                        .cornerRadius(4)
                }
            }

            Spacer()

            // Tlačítko
            Button(action: startSupport) {
                HStack {
                    Image(systemName: "hand.raised.fill")
                    Text("Povolit připojení")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(customerName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding()
        .onAppear {
            appState.checkPermissions()
        }
    }

    private func startSupport() {
        let name = customerName.trimmingCharacters(in: .whitespaces)
        appState.requestSupport(customerName: name, message: message)
    }

    @ViewBuilder
    private var permissionWarning: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
                Text("Chybějící oprávnění")
                    .font(.headline)
            }

            if !appState.hasScreenRecordingPermission {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Screen Recording – nutné pro sdílení obrazovky")
                        .font(.caption)
                }
            }

            if !appState.hasAccessibilityPermission {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text("Accessibility – nutné pro vzdálené ovládání")
                        .font(.caption)
                    Spacer()
                    Button("Povolit") {
                        appState.requestAccessibilityPermission()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }

            Text("Otevřete Nastavení systému → Soukromí a zabezpečení")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(12)
        .background(Color.orange.opacity(0.1))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }
}
