import Foundation
import Combine

class DeviceListViewModel: ObservableObject {
    @Published var devices: [Device] = []
    @Published var filterOnlineOnly = false
    @Published var showPasswordDialog = false
    @Published var showDeleteConfirm = false
    @Published var selectedDevice: Device?
    @Published var deviceToDelete: Device?
    @Published var unattendedPassword = ""

    private let relay: RelayConnection

    var filteredDevices: [Device] {
        if filterOnlineOnly {
            return devices.filter { $0.isOnline }
        }
        return devices
    }

    init(relay: RelayConnection) {
        self.relay = relay
    }

    func requestDeviceList() {
        relay.sendJSON([
            "type": "get_device_list",
            "payload": [:] as [String: Any]
        ])
    }

    func connectToDevice(_ device: Device) {
        selectedDevice = device
        unattendedPassword = ""
        showPasswordDialog = true
    }

    func submitUnattendedConnect() {
        guard let device = selectedDevice, !unattendedPassword.isEmpty else { return }
        relay.connectUnattended(agentId: device.id, password: unattendedPassword)
        showPasswordDialog = false
        unattendedPassword = ""
        selectedDevice = nil
    }

    func confirmDeleteDevice(_ device: Device) {
        deviceToDelete = device
        showDeleteConfirm = true
    }

    func deleteDevice() {
        guard let device = deviceToDelete else { return }
        relay.deleteDevice(agentId: device.id)
        // Optimisticky odebrat z lokálního seznamu hned
        devices.removeAll { $0.id == device.id }
        showDeleteConfirm = false
        deviceToDelete = nil
    }

    func removeDeviceFromList(agentId: String) {
        devices.removeAll { $0.id == agentId }
    }
}
