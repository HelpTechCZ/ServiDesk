import Foundation
import Combine

enum AgentConnectionState: Equatable {
    case disconnected
    case connecting
    case registered
    case waiting
    case connected
    case error(String)

    static func == (lhs: AgentConnectionState, rhs: AgentConnectionState) -> Bool {
        switch (lhs, rhs) {
        case (.disconnected, .disconnected),
             (.connecting, .connecting),
             (.registered, .registered),
             (.waiting, .waiting),
             (.connected, .connected):
            return true
        case (.error(let a), .error(let b)):
            return a == b
        default:
            return false
        }
    }
}

/// WebSocket klient pro agent roli.
/// Klíčové rozdíly od viewer RelayConnection:
/// - Posílá agent_register (ne admin_auth)
/// - Posílá request_support (ne accept_support)
/// - Přijímá session_accepted (ne session_started)
/// - Posílá video framy, přijímá input eventy
class RelayConnection: ObservableObject {
    @Published var connectionState: AgentConnectionState = .disconnected

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private let config: AgentConfig
    private var heartbeatTimer: Timer?
    private var reconnectAttempts = 0
    private var maxReconnectAttempts = 5
    private var isReconnecting = false
    private let e2eCrypto = E2ECrypto()
    private var sessionId: String?

    // MARK: - Callbacks

    var onRegistered: ((String) -> Void)?              // session_id
    var onSessionAccepted: ((SessionAcceptedPayload) -> Void)?
    var onSessionEnded: ((String, String) -> Void)?     // reason, ended_by
    var onInputEvent: ((Data) -> Void)?                 // binární 0x02 input event
    var onChatMessage: ((ChatMessage) -> Void)?
    var onE2EKeyExchange: ((String) -> Void)?           // peer public key
    var onQualityChange: ((String, Int) -> Void)?       // quality, fps
    var onClipboardData: ((String) -> Void)?
    var onFileTransferControl: ((String, [String: Any]) -> Void)?
    var onFileTransferData: ((Data) -> Void)?           // raw 0x04 binary
    var onMonitorSwitch: ((Int) -> Void)?               // monitor index
    var onError: ((String, String) -> Void)?            // code, message

    init(config: AgentConfig) {
        self.config = config
    }

    var isE2EReady: Bool { e2eCrypto.isReady }

    // MARK: - Connect

    func connect() {
        guard case .disconnected = connectionState else { return }
        guard !config.relayServerURL.isEmpty else {
            connectionState = .error("URL serveru není nastavena")
            return
        }

        connectionState = .connecting
        reconnectAttempts = 0

        let cleanURL = config.relayServerURL.trimmingCharacters(in: .whitespacesAndNewlines)
        connectToURL(cleanURL)
    }

    private func connectToURL(_ urlString: String) {
        guard let url = URL(string: urlString) else {
            connectionState = .error("Neplatná URL serveru")
            return
        }

        cleanupCurrentConnection()

        print(">>> Agent connecting to: \(urlString)")

        session = URLSession(configuration: .default)
        webSocket = session?.webSocketTask(with: url)
        webSocket?.resume()

        // Odeslat agent_register jako první zprávu
        let hostname = Host.current().localizedName ?? ProcessInfo.processInfo.hostName
        let osVersion = ProcessInfo.processInfo.operatingSystemVersionString

        let registerPayload: [String: Any] = [
            "agent_id": config.agentId,
            "customer_name": hostname,
            "hostname": hostname,
            "os_version": "macOS \(osVersion)",
            "agent_version": config.agentVersion,
            "unattended_enabled": config.unattendedAccessEnabled,
            "unattended_password_hash": config.unattendedAccessPasswordHash,
            "hw_info": HardwareInfoCollector.collect()
        ]

        sendJSON([
            "type": "agent_register",
            "payload": registerPayload
        ])

        startReceiving()
        startHeartbeat()
    }

    func disconnect(reason: String = "completed") {
        // Ukončit session pokud existuje
        if let sid = sessionId {
            sendJSON([
                "type": "session_end",
                "payload": [
                    "session_id": sid,
                    "reason": reason
                ]
            ])
        }

        cleanupCurrentConnection()
        e2eCrypto.reset()
        connectionState = .disconnected
        sessionId = nil
        isReconnecting = false
    }

    private func cleanupCurrentConnection() {
        stopHeartbeat()
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil
    }

    // MARK: - Request Support

    func requestSupport(customerName: String, message: String, screenWidth: Int, screenHeight: Int) {
        let payload: [String: Any] = [
            "customer_name": customerName,
            "message": message,
            "screen_width": screenWidth,
            "screen_height": screenHeight
        ]

        sendJSON([
            "type": "request_support",
            "payload": payload
        ])

        connectionState = .waiting
    }

    // MARK: - Update agent info (unattended)

    func updateAgentInfo() {
        sendJSON([
            "type": "update_agent_info",
            "payload": [
                "unattended_enabled": config.unattendedAccessEnabled,
                "unattended_password_hash": config.unattendedAccessPasswordHash
            ]
        ])
    }

    // MARK: - E2E Key Exchange (agent responds to viewer's key)

    func sendE2EPublicKey() {
        let publicKey = e2eCrypto.generateKeyPair()
        print(">>> E2E Agent: Sending public key to viewer")
        sendJSON([
            "type": "e2e_key_exchange",
            "payload": ["public_key": publicKey]
        ])
    }

    func deriveSharedKey(peerPublicKeyBase64: String) throws {
        try e2eCrypto.deriveSharedKey(peerPublicKeyBase64: peerPublicKeyBase64)
    }

    // MARK: - Send binary data (video frames, clipboard)

    func sendBinaryData(_ data: Data) {
        let toSend = e2eCrypto.isReady ? (try? e2eCrypto.encrypt(data)) ?? data : data
        webSocket?.send(.data(toSend)) { error in
            if let error = error {
                print(">>> Binary send error: \(error)")
            }
        }
    }

    func sendClipboardText(_ text: String) {
        guard let payload = text.data(using: .utf8) else { return }
        var packet = Data()
        packet.append(BinaryMessageType.clipboardData.rawValue)
        var length = UInt32(payload.count).littleEndian
        packet.append(Data(bytes: &length, count: 4))
        packet.append(payload)

        sendBinaryData(packet)
    }

    // MARK: - Chat

    func sendChatMessage(_ text: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())

        if e2eCrypto.isReady {
            let plainPayload: [String: Any] = ["message": text, "sender": "customer", "timestamp": timestamp]
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
                    "sender": "customer",
                    "timestamp": timestamp
                ]
            ])
        }
    }

    // MARK: - Monitor info

    func sendMonitorInfo(_ info: MonitorInfo) {
        guard let data = try? JSONEncoder().encode(info),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }

        sendJSON([
            "type": "monitor_info",
            "payload": dict
        ])
    }

    // MARK: - JSON sending

    func sendJSON(_ dict: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: dict),
              let string = String(data: data, encoding: .utf8) else { return }

        guard webSocket != nil else { return }

        webSocket?.send(.string(string)) { [weak self] error in
            if let error = error {
                print(">>> Send error: \(error)")
                self?.handleDisconnect()
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
                    self?.handleTextMessage(text)
                case .data(let data):
                    self?.handleBinaryData(data)
                @unknown default:
                    break
                }
                self?.startReceiving()

            case .failure(let error):
                print("<<< WS receive error: \(error)")
                self?.handleDisconnect()
            }
        }
    }

    private func handleTextMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        let payloadDict = json["payload"] as? [String: Any]
        let payloadData = payloadDict.flatMap { try? JSONSerialization.data(withJSONObject: $0) }

        DispatchQueue.main.async { [weak self] in
            self?.processMessage(type: type, payloadDict: payloadDict, payloadData: payloadData)
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

        guard decrypted.count >= 5 else { return }

        let msgType = decrypted[0]

        if msgType == BinaryMessageType.inputEvent.rawValue {
            // Input event od vieweru: [0x02][4B len][JSON]
            onInputEvent?(decrypted)
        } else if msgType == BinaryMessageType.clipboardData.rawValue {
            // Clipboard: [0x03][4B len][text]
            let length = decrypted.subdata(in: 1..<5).withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
            let payloadEnd = 5 + Int(length)
            guard decrypted.count >= payloadEnd else { return }
            if let text = String(data: decrypted.subdata(in: 5..<payloadEnd), encoding: .utf8) {
                DispatchQueue.main.async { [weak self] in
                    self?.onClipboardData?(text)
                }
            }
        } else if msgType == BinaryMessageType.fileTransfer.rawValue {
            // File transfer data: [0x04][4B len][1B id_len][transfer_id][data]
            onFileTransferData?(decrypted)
        }
    }

    private func processMessage(type: String, payloadDict: [String: Any]?, payloadData: Data?) {
        switch type {
        case "agent_registered":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(AgentRegisteredPayload.self, from: data) else { return }

            sessionId = payload.session_id
            connectionState = .registered
            reconnectAttempts = 0
            isReconnecting = false
            print(">>> Agent registered, session_id: \(payload.session_id)")
            onRegistered?(payload.session_id)

        case "session_accepted":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(SessionAcceptedPayload.self, from: data) else { return }

            connectionState = .connected
            print(">>> Session accepted by: \(payload.admin_name)")
            onSessionAccepted?(payload)

        case "session_ended":
            guard let data = payloadData,
                  let payload = try? JSONDecoder().decode(SessionEndedPayload.self, from: data) else { return }

            e2eCrypto.reset()
            sessionId = nil
            onSessionEnded?(payload.reason, payload.ended_by)

        case "e2e_key_exchange":
            if let peerPublicKey = payloadDict?["public_key"] as? String {
                print(">>> E2E Agent: Received viewer public key")
                onE2EKeyExchange?(peerPublicKey)
            }

        case "chat_message":
            if let payloadDict = payloadDict {
                if let encryptedBase64 = payloadDict["encrypted"] as? String, e2eCrypto.isReady {
                    if let decryptedString = try? e2eCrypto.decryptFromBase64(encryptedBase64),
                       let decryptedData = decryptedString.data(using: .utf8),
                       let decryptedJson = try? JSONSerialization.jsonObject(with: decryptedData) as? [String: Any] {
                        let msg = ChatMessage(
                            message: decryptedJson["message"] as? String ?? "",
                            sender: decryptedJson["sender"] as? String ?? "admin",
                            timestamp: decryptedJson["timestamp"] as? String ?? ""
                        )
                        onChatMessage?(msg)
                    }
                } else {
                    let msg = ChatMessage(
                        message: payloadDict["message"] as? String ?? "",
                        sender: payloadDict["sender"] as? String ?? "admin",
                        timestamp: payloadDict["timestamp"] as? String ?? ""
                    )
                    onChatMessage?(msg)
                }
            }

        case "file_offer", "file_accept", "file_error", "file_complete":
            if let payloadDict = payloadDict {
                onFileTransferControl?(type, payloadDict)
            }

        case "error":
            if let data = payloadData,
               let payload = try? JSONDecoder().decode(ErrorPayload.self, from: data) {
                print(">>> Relay error: \(payload.code) – \(payload.message)")
                onError?(payload.code, payload.message)
            }

        case "heartbeat_ack":
            break // Heartbeat acknowledged

        default:
            print(">>> Unknown message type: \(type)")
        }
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
            guard let self = self, !self.isReconnecting else { return }

            self.stopHeartbeat()
            self.webSocket?.cancel(with: .goingAway, reason: nil)
            self.webSocket = nil
            self.session?.invalidateAndCancel()
            self.session = nil

            if self.reconnectAttempts < self.maxReconnectAttempts {
                self.isReconnecting = true
                self.reconnectAttempts += 1
                self.connectionState = .connecting
                let delay = min(pow(2.0, Double(self.reconnectAttempts)), 30)
                print(">>> Reconnect attempt \(self.reconnectAttempts)/\(self.maxReconnectAttempts) in \(delay)s")
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                    guard let self = self else { return }
                    self.isReconnecting = false
                    self.connectionState = .disconnected
                    self.connect()
                }
            } else {
                self.connectionState = .error("Spojení ztraceno")
                self.isReconnecting = false
            }
        }
    }

    func resetE2E() {
        e2eCrypto.reset()
    }
}
