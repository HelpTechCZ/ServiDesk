import SwiftUI
import Combine
import UserNotifications

struct SessionEndInfo {
    let reason: String
    let endedBy: String
}

enum AppTab {
    case requests
    case devices
}

class AppState: ObservableObject {
    @Published var config: AppConfig
    @Published var relay: RelayConnection {
        didSet { subscribeToRelay() }
    }
    @Published var activeSession: RemoteSessionViewModel?
    @Published var showSettings = false
    @Published var sessionEndInfo: SessionEndInfo?
    @Published var activeTab: AppTab = .requests
    @Published var deviceListVM: DeviceListViewModel?

    private var relayCancellable: AnyCancellable?

    init() {
        let config = AppConfig.load()
        self.config = config
        self.relay = RelayConnection(config: config)

        subscribeToRelay()
        setupSessionHandler()
        setupDeviceHandlers()
        requestNotificationPermission()
    }

    /// Propojení relay.objectWillChange → appState.objectWillChange
    /// Díky tomu SwiftUI vidí změny connectionState, pendingRequests atd.
    private func subscribeToRelay() {
        relayCancellable = relay.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
    }

    private func setupSessionHandler() {
        relay.onSessionStarted = { [weak self] payload in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.sessionEndInfo = nil
                let session = RemoteSession(
                    sessionId: payload.session_id,
                    customerName: self.relay.pendingRequests.first { $0.id == payload.session_id }?.customerName ?? "Zákazník",
                    hostname: "",
                    screenWidth: payload.screen_width,
                    screenHeight: payload.screen_height,
                    startedAt: Date()
                )
                self.activeSession = RemoteSessionViewModel(
                    session: session,
                    relay: self.relay,
                    config: self.config
                )
            }
        }

        relay.onSessionEnded = { [weak self] reason, endedBy in
            DispatchQueue.main.async {
                guard self?.activeSession != nil else { return }
                self?.sessionEndInfo = SessionEndInfo(reason: reason, endedBy: endedBy)
            }
        }
    }

    private func setupDeviceHandlers() {
        let vm = DeviceListViewModel(relay: relay)
        self.deviceListVM = vm

        relay.onDeviceList = { [weak self] devices in
            DispatchQueue.main.async {
                self?.deviceListVM?.devices = devices
            }
        }

        relay.onDeviceStatusChanged = { [weak self] agentId, isOnline in
            DispatchQueue.main.async {
                if let index = self?.deviceListVM?.devices.firstIndex(where: { $0.id == agentId }) {
                    self?.deviceListVM?.devices[index].isOnline = isOnline
                } else {
                    // Nové zařízení – požádáme o celý seznam
                    self?.deviceListVM?.requestDeviceList()
                }
            }
        }

        relay.onDeviceDeleted = { [weak self] agentId in
            DispatchQueue.main.async {
                self?.deviceListVM?.removeDeviceFromList(agentId: agentId)
            }
        }
    }

    func dismissSessionEnd(reconnect: Bool) {
        activeSession = nil
        sessionEndInfo = nil
        if !reconnect {
            relay.disconnect()
        }
    }

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func connectIfNeeded() {
        if !config.adminToken.isEmpty {
            relay.connect()
        }
    }

    /// Vytvořit nový relay a znovu připojit (po změně nastavení)
    func reconnectWithNewConfig() {
        relay.disconnect()
        relay = RelayConnection(config: config)
        setupSessionHandler()
        setupDeviceHandlers()
        connectIfNeeded()
    }
}
