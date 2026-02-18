import Foundation
import Combine

class RequestListViewModel: ObservableObject {
    @Published var requests: [SupportRequest] = []
    @Published var isConnected = false
    @Published var connectionStatusText = "Odpojeno"

    private let relay: RelayConnection
    private var cancellables = Set<AnyCancellable>()
    private var refreshTimer: Timer?

    init(relay: RelayConnection) {
        self.relay = relay

        relay.$pendingRequests
            .receive(on: DispatchQueue.main)
            .assign(to: &$requests)

        relay.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                switch state {
                case .connected:
                    self?.isConnected = true
                    self?.connectionStatusText = "Připojeno k serveru"
                case .connecting:
                    self?.isConnected = false
                    self?.connectionStatusText = "Připojování..."
                case .disconnected:
                    self?.isConnected = false
                    self?.connectionStatusText = "Odpojeno"
                case .error(let msg):
                    self?.isConnected = false
                    self?.connectionStatusText = "Chyba: \(msg)"
                }
            }
            .store(in: &cancellables)

        // Refresh čekací časy každých 30s
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    func connect() {
        relay.connect()
    }

    func disconnect() {
        relay.disconnect()
    }

    func acceptRequest(_ request: SupportRequest) {
        relay.acceptRequest(request)
    }

    deinit {
        refreshTimer?.invalidate()
    }
}
