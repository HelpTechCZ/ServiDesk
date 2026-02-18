import SwiftUI

struct DeviceListView: View {
    @ObservedObject var viewModel: DeviceListViewModel
    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                Text("Spravovaná zařízení")
                    .font(.headline)

                Spacer()

                Toggle("Jen online", isOn: $viewModel.filterOnlineOnly)
                    .toggleStyle(.switch)
                    .controlSize(.small)

                Button {
                    viewModel.requestDeviceList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("Obnovit seznam")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if viewModel.filteredDevices.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "desktopcomputer.trianglebadge.exclamationmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text(viewModel.filterOnlineOnly ? "Žádné online zařízení" : "Žádná zařízení v adresáři")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(viewModel.filteredDevices) { device in
                            DeviceRowView(device: device, onConnect: {
                                viewModel.connectToDevice(device)
                            }, onDelete: {
                                viewModel.confirmDeleteDevice(device)
                            })
                        }
                    }
                    .padding(.horizontal, 16)
                }
            }

            Spacer()

            // Spodni bar
            HStack {
                let onlineCount = viewModel.devices.filter { $0.isOnline }.count
                Text("Celkem: \(viewModel.devices.count) | Online: \(onlineCount)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $viewModel.showPasswordDialog) {
            UnattendedPasswordDialog(viewModel: viewModel)
        }
        .alert("Smazat zařízení?", isPresented: $viewModel.showDeleteConfirm) {
            Button("Zrušit", role: .cancel) {}
            Button("Smazat", role: .destructive) {
                viewModel.deleteDevice()
            }
        } message: {
            Text("Zařízení \"\(viewModel.deviceToDelete?.hostname ?? "")\" bude trvale odstraněno z adresáře.")
        }
        .onAppear {
            viewModel.requestDeviceList()
        }
    }
}

struct DeviceRowView: View {
    let device: Device
    let onConnect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Online status
            Circle()
                .fill(device.isOnline ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                Text(device.hostname)
                    .font(.body)
                    .fontWeight(.medium)
                HStack(spacing: 8) {
                    if !device.customerName.isEmpty {
                        Text(device.customerName)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Text(device.osVersion)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("v\(device.agentVersion)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                if let hw = device.hwInfo {
                    Text(hw.summary)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if device.unattendedEnabled {
                Image(systemName: "lock.open")
                    .foregroundColor(.orange)
                    .help("Unattended přístup")
            }

            // Relativní čas
            Text(relativeTime(from: device.lastSeen))
                .font(.caption)
                .foregroundColor(.secondary)

            if device.isOnline && device.unattendedEnabled {
                Button("Připojit") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }

            // Smazat — jen offline zařízení
            if !device.isOnline {
                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
                .controlSize(.small)
                .help("Smazat zařízení")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }

    private func relativeTime(from date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "právě teď" }
        if interval < 3600 { return "\(Int(interval / 60)) min" }
        if interval < 86400 { return "\(Int(interval / 3600)) hod" }
        return "\(Int(interval / 86400)) dní"
    }
}

struct UnattendedPasswordDialog: View {
    @ObservedObject var viewModel: DeviceListViewModel

    var body: some View {
        VStack(spacing: 16) {
            Text("Připojení k \(viewModel.selectedDevice?.hostname ?? "")")
                .font(.headline)

            Text("Zadejte heslo pro unattended přístup:")
                .font(.body)

            SecureField("Heslo", text: $viewModel.unattendedPassword)
                .textFieldStyle(.roundedBorder)
                .frame(width: 250)
                .onSubmit {
                    viewModel.submitUnattendedConnect()
                }

            HStack(spacing: 12) {
                Button("Zrušit") {
                    viewModel.showPasswordDialog = false
                }
                .keyboardShortcut(.cancelAction)

                Button("Připojit") {
                    viewModel.submitUnattendedConnect()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.unattendedPassword.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 350)
    }
}
