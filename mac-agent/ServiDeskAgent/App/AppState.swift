import Foundation
import Combine
import AppKit

/// Centrální koordinátor aplikace – srdce Mac agenta.
/// Koordinuje: RelayConnection, ScreenCaptureManager, FrameEncoder,
///             InputInjector, ClipboardManager, FileTransferManager
class AppState: ObservableObject {

    enum State: Equatable {
        case idle
        case connecting
        case registered
        case waiting
        case connected(adminName: String)
        case disconnected(reason: String)
        case error(String)
    }

    @Published var state: State = .idle
    @Published var chatMessages: [ChatMessage] = []
    @Published var hasScreenRecordingPermission = false
    @Published var hasAccessibilityPermission = false
    @Published var sessionId: String?

    let config: AgentConfig
    let relay: RelayConnection
    let captureManager = ScreenCaptureManager()
    let frameEncoder = FrameEncoder()
    let inputInjector = InputInjector()
    let clipboardManager = ClipboardManager()
    let fileTransferManager = FileTransferManager()

    private var cancellables = Set<AnyCancellable>()
    private var streamingTask: Task<Void, Never>?
    private var e2eKeyExchangeTimeout: DispatchWorkItem?
    private var useE2E = false

    init() {
        config = AgentConfig.load()
        relay = RelayConnection(config: config)
        setupCallbacks()
        checkPermissions()
    }

    // MARK: - Permission checks

    func checkPermissions() {
        hasAccessibilityPermission = InputInjector.checkPermission()

        Task {
            let screenOk = await ScreenCaptureManager.checkPermission()
            await MainActor.run {
                hasScreenRecordingPermission = screenOk
            }
        }
    }

    func requestAccessibilityPermission() {
        InputInjector.requestPermission()
        // Periodicky kontrolovat, zda uživatel udělil oprávnění
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.checkPermissions()
        }
    }

    // MARK: - Support flow

    func requestSupport(customerName: String, message: String) {
        state = .connecting
        relay.connect()

        // Počkat na registraci a pak poslat request
        relay.onRegistered = { [weak self] _ in
            guard let self = self else { return }
            self.state = .registered

            let displaySize = self.captureManager.getActiveDisplaySize()
            self.relay.requestSupport(
                customerName: customerName,
                message: message,
                screenWidth: displaySize.width,
                screenHeight: displaySize.height
            )
            self.state = .waiting
        }
    }

    func cancelRequest() {
        relay.disconnect(reason: "cancelled")
        state = .idle
        stopStreaming()
    }

    func endSession() {
        relay.disconnect(reason: "completed")
        stopStreaming()
        state = .disconnected(reason: "Ukončeno zákazníkem")
    }

    func resetToIdle() {
        state = .idle
        chatMessages = []
        sessionId = nil
    }

    // MARK: - Chat

    func sendChat(_ text: String) {
        relay.sendChatMessage(text)
        let msg = ChatMessage(message: text, sender: "customer", timestamp: ISO8601DateFormatter().string(from: Date()))
        chatMessages.append(msg)
    }

    // MARK: - Callbacks setup

    private func setupCallbacks() {
        // Session accepted → zahájit streaming
        relay.onSessionAccepted = { [weak self] payload in
            guard let self = self else { return }
            self.state = .connected(adminName: payload.admin_name)
            self.startSessionFlow(unattended: payload.unattended ?? false)
        }

        // Session ended
        relay.onSessionEnded = { [weak self] reason, endedBy in
            guard let self = self else { return }
            self.stopStreaming()
            self.state = .disconnected(reason: endedBy == "admin" ? "Technik ukončil session" : reason)
        }

        // E2E key exchange – viewer poslal svůj veřejný klíč
        relay.onE2EKeyExchange = { [weak self] peerPublicKey in
            guard let self = self else { return }
            self.e2eKeyExchangeTimeout?.cancel()

            do {
                // Vygenerovat vlastní klíč a poslat vieweru
                self.relay.sendE2EPublicKey()
                // Odvodit sdílený klíč z viewer's public key
                try self.relay.deriveSharedKey(peerPublicKeyBase64: peerPublicKey)
                self.useE2E = true
                print(">>> E2E Agent: Encryption established!")
            } catch {
                print(">>> E2E Agent: Failed to derive shared key: \(error)")
                self.useE2E = false
            }
        }

        // Input events od vieweru
        relay.onInputEvent = { [weak self] data in
            self?.handleInputEvent(data)
        }

        // Chat messages
        relay.onChatMessage = { [weak self] message in
            self?.chatMessages.append(message)
        }

        // Clipboard
        relay.onClipboardData = { [weak self] text in
            self?.clipboardManager.setClipboardText(text)
        }

        // File transfer control
        relay.onFileTransferControl = { [weak self] type, payload in
            self?.fileTransferManager.handleControlMessage(type: type, payload: payload)
        }

        // File transfer binary data
        relay.onFileTransferData = { [weak self] data in
            self?.fileTransferManager.handleFileData(data)
        }

        // Quality change (přijde jako input event type)
        relay.onQualityChange = { [weak self] quality, fps in
            guard let self = self else { return }
            self.frameEncoder.changeQuality(quality: quality, fps: fps)
            // Restartovat capture s novým FPS
            Task {
                await self.captureManager.stopCapture()
                try? await self.captureManager.startCapture(fps: fps)
            }
        }

        // Monitor switch
        relay.onMonitorSwitch = { [weak self] index in
            guard let self = self else { return }
            Task {
                try? await self.captureManager.switchMonitor(to: index)
                // Poslat aktualizované monitor_info
                let info = self.captureManager.getMonitorInfo()
                self.relay.sendMonitorInfo(info)
            }
        }

        // Error
        relay.onError = { [weak self] code, message in
            print(">>> Relay error: \(code) – \(message)")
            if code == "AGENT_NOT_FOUND" || code == "INVALID_DATA" {
                self?.state = .error(message)
            }
        }

        // Clipboard outgoing
        clipboardManager.onClipboardChanged = { [weak self] text in
            self?.relay.sendClipboardText(text)
        }

        // File transfer JSON sending
        fileTransferManager.onSendJson = { [weak self] dict in
            self?.relay.sendJSON(dict)
        }

        // Sledovat stav připojení
        relay.$connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] connState in
                guard let self = self else { return }
                switch connState {
                case .error(let msg):
                    if case .connecting = self.state {
                        self.state = .error(msg)
                    }
                case .disconnected:
                    if case .connected = self.state {
                        self.stopStreaming()
                        self.state = .disconnected(reason: "Spojení ztraceno")
                    }
                default:
                    break
                }
            }
            .store(in: &cancellables)
    }

    // MARK: - Session flow

    private func startSessionFlow(unattended: Bool) {
        // E2E fallback: čekat max 5s na key exchange od vieweru
        useE2E = false
        let timeout = DispatchWorkItem { [weak self] in
            guard let self = self, !self.useE2E else { return }
            print(">>> E2E: Timeout – streaming bez šifrování (legacy viewer)")
        }
        e2eKeyExchangeTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: timeout)

        // Inicializovat capture a spustit streaming
        Task {
            do {
                try await captureManager.initialize()

                // Odeslat monitor info
                let monitorInfo = captureManager.getMonitorInfo()
                relay.sendMonitorInfo(monitorInfo)

                // Spustit capture
                try await captureManager.startCapture(fps: frameEncoder.activeFps)

                // Spustit clipboard monitoring
                await MainActor.run {
                    clipboardManager.startMonitoring()
                }

                startStreamingLoop()
            } catch {
                print(">>> Capture error: \(error)")
                await MainActor.run {
                    state = .error("Chyba screen capture: \(error.localizedDescription)")
                }
            }
        }
    }

    private func startStreamingLoop() {
        captureManager.onFrameCaptured = { [weak self] sampleBuffer in
            guard let self = self else { return }
            guard case .connected = self.state else { return }

            // Encode frame → JPEG
            guard let jpegData = self.frameEncoder.encode(sampleBuffer) else { return }

            // Build packet: [0x01][4B length][JPEG]
            let packet = self.frameEncoder.buildFullFramePacket(jpegData)

            // Send
            self.relay.sendBinaryData(packet)
        }
    }

    private func stopStreaming() {
        captureManager.onFrameCaptured = nil
        clipboardManager.stopMonitoring()
        relay.resetE2E()
        useE2E = false
        e2eKeyExchangeTimeout?.cancel()

        Task {
            await captureManager.stopCapture()
        }
    }

    // MARK: - Input event routing

    private func handleInputEvent(_ data: Data) {
        // Parse: [0x02][4B len][JSON payload]
        guard let parsed = MessageParser.parseBinaryMessage(data),
              parsed.type == .inputEvent,
              let json = try? JSONSerialization.jsonObject(with: parsed.payload) as? [String: Any],
              let eventType = json["type"] as? String else { return }

        switch eventType {
        case "mouse_move":
            let x = json["x"] as? Double ?? 0
            let y = json["y"] as? Double ?? 0
            inputInjector.moveTo(normalizedX: x, normalizedY: y)

        case "mouse_click":
            let x = json["x"] as? Double ?? 0
            let y = json["y"] as? Double ?? 0
            let button = json["button"] as? String ?? "left"
            let action = json["action"] as? String ?? "down"
            inputInjector.click(button: button, action: action, normalizedX: x, normalizedY: y)

        case "mouse_scroll":
            let deltaX = json["delta_x"] as? Int ?? 0
            let deltaY = json["delta_y"] as? Int ?? 0
            inputInjector.scroll(deltaX: deltaX, deltaY: deltaY)

        case "key":
            let vkCode = json["key_code"] as? Int ?? 0
            let action = json["action"] as? String ?? "down"
            let modifiers = json["modifiers"] as? [String: Bool]

            if action == "down" {
                inputInjector.keyDown(vkCode: vkCode, modifiers: modifiers)
            } else {
                inputInjector.keyUp(vkCode: vkCode, modifiers: modifiers)
            }

        case "quality_change":
            let quality = json["quality"] as? String ?? "medium"
            let fps = json["fps"] as? Int ?? 20
            frameEncoder.changeQuality(quality: quality, fps: fps)
            // Restartovat capture s novým FPS
            Task {
                await captureManager.stopCapture()
                try? await captureManager.startCapture(fps: fps)
            }

        case "switch_monitor":
            let index = json["monitor_index"] as? Int ?? 0
            Task {
                try? await captureManager.switchMonitor(to: index)
                let info = captureManager.getMonitorInfo()
                relay.sendMonitorInfo(info)
            }

        default:
            print(">>> Unknown input event type: \(eventType)")
        }
    }

    // MARK: - Unattended access

    /// Při spuštění, pokud je unattended povoleno, automaticky se připojit
    func checkUnattendedAutoConnect() {
        guard config.unattendedAccessEnabled, !config.unattendedAccessPasswordHash.isEmpty else { return }
        // Agent se jen zaregistruje a čeká – viewer se připojí přes connect_unattended
        state = .connecting
        relay.connect()

        relay.onRegistered = { [weak self] _ in
            guard let self = self else { return }
            self.state = .registered
            print(">>> Unattended mode: registered and waiting for viewer")
        }
    }
}
