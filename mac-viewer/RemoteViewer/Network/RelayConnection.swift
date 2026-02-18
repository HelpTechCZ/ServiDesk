import Foundation
import CommonCrypto
import Combine
import UserNotifications

enum ConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

class RelayConnection: ObservableObject {
    @Published var connectionState: ConnectionState = .disconnected
    @Published var pendingRequests: [SupportRequest] = []

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let config: AppConfig
    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0
    private var fallbackTimeoutWork: DispatchWorkItem?
    private var isReconnecting = false
    private let e2eCrypto = E2ECrypto()

    var onSessionStarted: ((SessionStartedPayload) -> Void)?
    var onSessionEnded: ((String, String) -> Void)?
    var onBinaryData: ((Data) -> Void)?
    var onChatMessage: ((ChatMessage) -> Void)?
    var onClipboardData: ((String) -> Void)?
    var onMonitorInfo: ((MonitorInfoPayload) -> Void)?
    var onMonitorSwitched: ((MonitorSwitchedPayload) -> Void)?
    var onFileTransferControl: ((String, [String: Any]) -> Void)?
    var onRttUpdate: ((Int) -> Void)?
    var onDeviceList: (([Device]) -> Void)?
    var onDeviceStatusChanged: ((String, Bool) -> Void)?
    var onDeviceDeleted: ((String) -> Void)?

    init(config: AppConfig) {
        self.config = config
    }

    private static let fallbackURL = "ws://192.168.x.x:8090/ws"
    private var usingFallback = false

    // MARK: - Connect

    func connect() {
        guard case .disconnected = connectionState else { return }
        guard !config.relayServerURL.isEmpty, !config.adminToken.isEmpty else {
            connectionState = .error("Nastavte URL serveru a admin token")
            return
        }

        connectionState = .connecting
        reconnectAttempts = 0
        usingFallback = false

        // Trim URL - odstranění mezer a newlines
        let cleanURL = config.relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        connectToURL(cleanURL)
    }

    private func cleanupCurrentConnection() {
        fallbackTimeoutWork?.cancel()
        fallbackTimeoutWork = nil
        stopHeartbeat()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    private func connectToURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            connectionState = .error("Neplatná URL serveru")
            return
        }

        // Vyčistit předchozí spojení
        cleanupCurrentConnection()

        print(">>> Connecting to: \(urlString)")

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Timeout – pokud se nepřipojí do 5s a nejsme na fallbacku, zkusit lokální
        if !usingFallback {
            let workItem = DispatchWorkItem { [weak self] in
                guard let self = self else { return }
                if case .connecting = self.connectionState {
                    print(">>> Primary URL timeout, trying fallback: \(Self.fallbackURL)")
                    self.usingFallback = true
                    self.connectToURL(Self.fallbackURL)
                }
            }
            fallbackTimeoutWork = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: workItem)
        }

        // Odeslat admin_auth
        let authMessage: [String: Any] = [
            "type": "admin_auth",
            "payload": [
                "admin_token": config.adminToken,
                "admin_name": config.adminName
            ]
        ]

        sendJSON(authMessage)
        startReceiving()
        startHeartbeat()
    }

    func disconnect() {
        cleanupCurrentConnection()
        e2eCrypto.reset()
        connectionState = .disconnected
        pendingRequests = []
        isReconnecting = false
    }

    // MARK: - Session management

    func acceptRequest(_ request: SupportRequest) {
        print(">>> Accepting request: \(request.id)")
        let message: [String: Any] = [
            "type": "accept_support",
            "payload": [
                "session_id": request.id,
                "admin_token": config.adminToken
            ]
        ]
        print(">>> Sending accept_support for session: \(request.id)")
        sendJSON(message)
    }

    func endSession(sessionId: String, reason: String = "completed") {
        let message: [String: Any] = [
            "type": "session_end",
            "payload": [
                "session_id": sessionId,
                "reason": reason
            ]
        ]
        sendJSON(message)
    }

    func sendChatMessage(_ text: String, sender: String = "admin") {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if e2eCrypto.isReady {
            // E2E: šifrovat payload jako base64
            let plainPayload: [String: Any] = ["message": text, "sender": sender, "timestamp": timestamp]
            if let payloadData = try? JSONSerialization.data(withJSONObject: plainPayload),
               let payloadString = String(data: payloadData, encoding: .utf8),
               let encrypted = try? e2eCrypto.encryptToBase64(payloadString) {
                sendJSON([
                    "type": "chat_message",
                    "payload": ["encrypted": encrypted]
                ])
            }
        } else {
            sendJSON([
                "type": "chat_message",
                "payload": [
                    "message": text,
                    "sender": sender,
                    "timestamp": timestamp
                ]
            ])
        }
    }

    func changeQuality(fps: Int, quality: StreamQuality, requestKeyframe: Bool = false) {
        // Posílat jako binární input event (stejný pipeline jako myš/klávesnice)
        sendInputEvent([
            "type": "quality_change",
            "fps": fps,
            "quality": quality.rawValue,
            "request_keyframe": requestKeyframe
        ])
    }

    // MARK: - Input events

    func sendInputEvent(_ event: [String: Any]) {
        let jsonData = try? JSONSerialization.data(withJSONObject: event)
        guard let jsonData = jsonData else { return }

        // Binární zpráva: [0x02][4B délka][JSON payload]
        var packet = Data()
        packet.append(BinaryMessageType.inputEvent.rawValue)
        var length = UInt32(jsonData.count).littleEndian
        packet.append(Data(bytes: &length, count: 4))
        packet.append(jsonData)

        let toSend = e2eCrypto.isReady ? (try? e2eCrypto.encrypt(packet)) ?? packet : packet
        webSocket?.send(.data(toSend)) { _ in }
    }

    // MARK: - Sending

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else {
            print(">>> sendJSON: failed to serialize")
            return
        }

        print(">>> sendJSON: \(string)")

        guard webSocket != nil else {
            print(">>> sendJSON: webSocket is nil!")
            return
        }

        webSocket?.send(.string(string)) { [weak self] error in
            if let error = error {
                print(">>> Send error: \(error)")
                self?.handleDisconnect()
            } else {
                print(">>> Send OK")
            }
        }
    }

    // MARK: - Receiving

    private func startReceiving() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("<<< WS text (\(text.prefix(100)))")
                    self?.handleTextMessage(text)
                case .data(let data):
                    print("<<< WS binary (\(data.count) bytes)")
                    self?.handleBinaryData(data)
                @unknown default:
                    break
                }
                // Pokračovat v přijímání
                self?.startReceiving()

            case .failure(let error):
                print("<<< WS receive error: \(error)")
                self?.handleDisconnect()
            }
        }
    }

    private func handleBinaryData(_ data: Data) {
        // Dešifrovat pokud E2E je aktivní
        let decrypted: Data
        if e2eCrypto.isReady {
            guard let d = try? e2eCrypto.decrypt(data) else {
                print(">>> E2E: Failed to decrypt binary data")
                return
            }
            decrypted = d
        } else {
            decrypted = data
        }

        guard decrypted.count >= 5 else {
            onBinaryData?(decrypted)
            return
        }

        let msgType = decrypted[0]
        if msgType == BinaryMessageType.clipboardData.rawValue {
            let length = decrypted.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            let payloadEnd = 5 + Int(length)
            guard decrypted.count >= payloadEnd else { return }
            if let text = String(data: decrypted.subdata(in: 5..<payloadEnd), encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.onClipboardData?(text)
                }
            }
        } else {
            onBinaryData?(decrypted)
        }
    }

    func sendClipboardText(_ text: String) {
        guard let payload = text.data(using: .utf8) else { return }
        var packet = Data()
        packet.append(BinaryMessageType.clipboardData.rawValue)
        var length = UInt32(payload.count).littleEndian
        packet.append(Data(bytes: &length, count: 4))
        packet.append(payload)

        let toSend = e2eCrypto.isReady ? (try? e2eCrypto.encrypt(packet)) ?? packet : packet
        webSocket?.send(.data(toSend)) { _ in }
    }

    func sendBinaryData(_ data: Data) {
        let toSend = e2eCrypto.isReady ? (try? e2eCrypto.encrypt(data)) ?? data : data
        webSocket?.send(.data(toSend)) { _ in }
    }

    func switchMonitor(index: Int) {
        sendInputEvent([
            "type": "switch_monitor",
            "monitor_index": index
        ])
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        print("<<< received: \(type)")

        let payloadData = (json["payload"] as? [String: Any])
            .flatMap { try? JSONSerialization.data(withJSONObject: $0) }

        DispatchQueue.main.async { [weak self] in
            self?.processMessage(type: type, payloadData: payloadData)
        }
    }

    private func processMessage(type: String, payloadData: Data?) {
        switch type {
        case "admin_auth_result":
            guard let data = payloadData,
                  let result = try? JSONDecoder().decode(AdminAuthResultPayload.self, from: data) else { return }

            if result.success {
                // Zrušit fallback timeout - jsme úspěšně připojeni
                fallbackTimeoutWork?.cancel()
                fallbackTimeoutWork = nil

                connectionState = .connected
                reconnectAttempts = 0
                isReconnecting = false
                pendingRequests = result.pending_requests?.map { SupportRequest.from(payload: $0) } ?? []
                print(">>> Connected successfully, pending requests: \(pendingRequests.count)")
            } else {
                connectionState = .error("Autentizace selhala")
                disconnect()
            }

        case "support_request":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(SupportRequestPayload.self, from: data) else { return }

            let request = SupportRequest.from(payload: payload)
            if !pendingRequests.contains(where: { $0.id == request.id }) {
                pendingRequests.append(request)
            }

            // Notifikace
            if config.notificationsEnabled {
                showNotification(request: request)
            }

        case "session_started":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(SessionStartedPayload.self, from: data) else { return }

            print(">>> Session started: \(payload.session_id)")
            // Odebrat z pending
            pendingRequests.removeAll { $0.id == payload.session_id }
            onSessionStarted?(payload)

            // Zahájit E2E key exchange
            initiateE2EKeyExchange()

        case "session_ended":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(SessionEndedPayload.self, from: data) else { return }
            e2eCrypto.reset()
            onSessionEnded?(payload.reason, payload.ended_by)

        case "chat_message":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                // Detekce šifrované zprávy
                if let encryptedBase64 = json["encrypted"] as? String, e2eCrypto.isReady {
                    if let decryptedString = try? e2eCrypto.decryptFromBase64(encryptedBase64),
                       let decryptedData = decryptedString.data(using: String.Encoding.utf8),
                       let decryptedJson = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] {
                        let msg = ChatMessage(
                            message: decryptedJson["message"] as? String ?? "",
                            sender: decryptedJson["sender"] as? String ?? "unknown",
                            timestamp: decryptedJson["timestamp"] as? String ?? ""
                        )
                        onChatMessage?(msg)
                    } else {
                        print(">>> E2E: Failed to decrypt chat message")
                    }
                } else {
                    let msg = ChatMessage(
                        message: json["message"] as? String ?? "",
                        sender: json["sender"] as? String ?? "unknown",
                        timestamp: json["timestamp"] as? String ?? ""
                    )
                    onChatMessage?(msg)
                }
            }

        case "e2e_key_exchange":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let peerPublicKey = json["public_key"] as? String {
                do {
                    try e2eCrypto.deriveSharedKey(peerPublicKeyBase64: peerPublicKey)
                    print(">>> E2E: Encryption established!")
                } catch {
                    print(">>> E2E: Failed to derive shared key: \(error)")
                }
            }

        case "file_accept", "file_error":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                onFileTransferControl?(type, json)
            }

        case "monitor_info":
            if let data = payloadData,
               let payload = try? JSONDecoder().decode(MonitorInfoPayload.self, from: data) {
                onMonitorInfo?(payload)
            }

        case "monitor_switched":
            if let data = payloadData,
               let payload = try? JSONDecoder().decode(MonitorSwitchedPayload.self, from: data) {
                onMonitorSwitched?(payload)
            }

        case "device_list":
            print(">>> device_list received, payloadData=\(payloadData != nil)")
            if let data = payloadData {
                if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let devicesArray = json["devices"] as? [[String: Any]] {
                    print(">>> device_list: \(devicesArray.count) devices in JSON")
                    if let devicesData = try? JSONSerialization.data(withJSONObject: devicesArray) {
                        do {
                            let devices = try JSONDecoder().decode([Device].self, from: devicesData)
                            print(">>> device_list: decoded \(devices.count) devices OK")
                            onDeviceList?(devices)
                        } catch {
                            print(">>> device_list: decode error: \(error)")
                        }
                    }
                } else {
                    let raw = String(data: data, encoding: .utf8) ?? "nil"
                    print(">>> device_list: failed to parse JSON, raw=\(raw)")
                }
            }

        case "device_status_changed":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let agentId = json["agent_id"] as? String,
               let isOnline = json["is_online"] as? Bool {
                onDeviceStatusChanged?(agentId, isOnline)
            }

        case "device_deleted":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let agentId = json["agent_id"] as? String {
                onDeviceDeleted?(agentId)
            }

        case "error":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) else { return }
            print("Relay error: \(payload.code) – \(payload.message)")

        case "heartbeat_ack":
            if let data = payloadData,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let sentTimestamp = json["timestamp"] as? Int64 {
                let now = Int64(Date().timeIntervalSince1970 * 1000)
                let rtt = Int(now - sentTimestamp)
                if rtt >= 0 {
                    onRttUpdate?(rtt)
                }
            }

        default:
            break
        }
    }

    // MARK: - Device list & Unattended

    func requestDeviceList() {
        sendJSON([
            "type": "get_device_list",
            "payload": [:] as [String: Any]
        ])
    }

    func connectUnattended(agentId: String, password: String) {
        // SHA-256 hash hesla
        let passwordData = password.data(using: .utf8)!
        let hash = passwordData.withUnsafeBytes { bytes -> String in
            var digest = [UInt8](repeating: 0, count: 32)
            CC_SHA256(bytes.baseAddress, UInt32(bytes.count), &digest)
            return digest.map { String(format: "%02x", $0) }.joined()
        }

        sendJSON([
            "type": "connect_unattended",
            "payload": [
                "agent_id": agentId,
                "password": hash,
                "admin_token": config.adminToken
            ]
        ])
    }

    func deleteDevice(agentId: String) {
        sendJSON([
            "type": "delete_device",
            "payload": ["agent_id": agentId]
        ])
    }

    // MARK: - E2E Key Exchange

    private func initiateE2EKeyExchange() {
        let publicKey = e2eCrypto.generateKeyPair()
        print(">>> E2E: Sending public key to agent")
        sendJSON([
            "type": "e2e_key_exchange",
            "payload": ["public_key": publicKey]
        ])
    }

    // MARK: - Heartbeat

    private func startHeartbeat() {
        stopHeartbeat()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
            self?.sendJSON(["type": "heartbeat", "payload": ["timestamp": timestamp] as [String: Any]])
        }
    }

    private func stopHeartbeat() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
    }

    // MARK: - Reconnect

    private func handleDisconnect() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // Zabránit vícenásobným reconnect pokusům
            guard !self.isReconnecting else { return }

            self.stopHeartbeat()
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            self.session?.invalidateAndCancel()
            self.session = nil

            // Pokud jsme na primární URL a ještě jsme se nepřipojili, zkusit fallback
            if !self.usingFallback, case .connecting = self.connectionState {
                print(">>> Primary failed, trying fallback: \(Self.fallbackURL)")
                self.usingFallback = true
                self.connectToURL(Self.fallbackURL)
                return
            }

            // Pokud jsme byli připojeni, zkusit reconnect
            if self.config.autoReconnect && self.reconnectAttempts < self.config.reconnectMaxRetries {
                self.isReconnecting = true
                self.reconnectAttempts += 1
                self.connectionState = .connecting
                let delay = min(pow(2.0, Double(self.reconnectAttempts)), 30)
                print(">>> Reconnect attempt \(self.reconnectAttempts)/\(self.config.reconnectMaxRetries) in \(delay)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    self.isReconnecting = false
                    self.connectionState = .disconnected
                    self.usingFallback = false
                    self.connect()
                }
            } else {
                self.connectionState = .error("Spojení ztraceno")
                self.isReconnecting = false
            }
        }
    }

    // MARK: - Notifications

    private func showNotification(request: SupportRequest) {
        let content = UNMutableNotificationContent()
        content.title = "Nová žádost o podporu"
        content.body = "\(request.customerName) – \(request.hostname)"
        if config.soundEnabled {
            content.sound = .default
        }

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(req)
    }
}
