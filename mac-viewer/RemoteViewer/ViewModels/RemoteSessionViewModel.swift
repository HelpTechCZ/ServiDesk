import Foundation
import Combine

class RemoteSessionViewModel: ObservableObject {
    @Published var session: RemoteSession
    @Published var isStreaming = false
    @Published var fpsDisplay: Int = 0
    @Published var latencyDisplay: Int = 0
    @Published var chatMessages: [ChatMessage] = []
    @Published var monitors: [MonitorDetail] = []
    @Published var activeMonitorIndex: Int = 0
    @Published var remoteScreenSize: CGSize

    private let relay: RelayConnection
    private let config: AppConfig
    let mouseTracker = MouseTracker()
    let keyboardTracker: KeyboardTracker
    private let clipboardManager = ClipboardManager()
    let fileTransfer = FileTransferManager()

    var onFrameReady: ((Data) -> Void)?
    var onRegionsReady: (([RegionUpdate]) -> Void)?

    private var frameCount = 0
    private var fpsTimer: Timer?

    init(session: RemoteSession, relay: RelayConnection, config: AppConfig) {
        self.session = session
        self.relay = relay
        self.config = config
        self.remoteScreenSize = CGSize(width: session.screenWidth, height: session.screenHeight)
        self.keyboardTracker = KeyboardTracker()
        self.keyboardTracker.mapCmdToCtrl = config.mapCmdToCtrl

        setupBinaryHandler()
        setupChatHandler()
        setupClipboard()
        setupMonitorHandler()
        setupFileTransfer()
        setupRttHandler()
        startFpsCounter()
    }

    // MARK: - Setup

    private var binaryCount = 0

    private func setupBinaryHandler() {
        relay.onBinaryData = { [weak self] data in
            guard let self = self else { return }
            self.binaryCount += 1
            if self.binaryCount <= 5 || self.binaryCount % 100 == 0 {
                print(">>> [BIN] #\(self.binaryCount): \(data.count) bytes, first 4: \(Array(data.prefix(4)))")
            }

            // Detekce regionálního updatu (0x05)
            if data.count >= 7 && data[0] == BinaryMessageType.regionalUpdate.rawValue {
                if let regions = MessageParser.parseRegionalUpdate(data) {
                    DispatchQueue.main.async {
                        self.frameCount += 1
                        self.onRegionsReady?(regions)
                    }
                }
                return
            }

            // Full frame (0x01)
            guard let frameData = MessageParser.parseVideoFrame(data) else {
                if self.binaryCount <= 5 {
                    print(">>> [BIN] parseVideoFrame FAILED")
                }
                return
            }
            if self.binaryCount <= 5 {
                print(">>> [BIN] JPEG payload: \(frameData.count) bytes")
            }
            DispatchQueue.main.async {
                self.frameCount += 1
                self.onFrameReady?(frameData)
            }
        }
    }

    private func startFpsCounter() {
        fpsTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.fpsDisplay = self.frameCount
                self.frameCount = 0
            }
        }
    }

    private func setupClipboard() {
        // Local clipboard changed → send to remote
        clipboardManager.onClipboardChanged = { [weak self] text in
            self?.relay.sendClipboardText(text)
        }

        // Remote clipboard received → set locally
        relay.onClipboardData = { [weak self] text in
            self?.clipboardManager.setClipboardText(text)
        }

        clipboardManager.startMonitoring()
    }

    private func setupMonitorHandler() {
        relay.onMonitorInfo = { [weak self] info in
            DispatchQueue.main.async {
                self?.monitors = info.monitors
                self?.activeMonitorIndex = info.active_index
            }
        }

        relay.onMonitorSwitched = { [weak self] switched in
            DispatchQueue.main.async {
                self?.activeMonitorIndex = switched.monitor_index
                self?.remoteScreenSize = CGSize(width: switched.width, height: switched.height)
            }
        }
    }

    func switchMonitor(_ index: Int) {
        relay.switchMonitor(index: index)
    }

    private func setupFileTransfer() {
        fileTransfer.onSendJson = { [weak self] json in
            self?.relay.sendJSON(json)
        }
        fileTransfer.onSendBinary = { [weak self] data in
            self?.relay.sendBinaryData(data)
        }

        // Handle incoming file control messages
        relay.onFileTransferControl = { [weak self] type, payload in
            self?.fileTransfer.handleControlMessage(type: type, payload: payload)
        }
    }

    private func setupChatHandler() {
        relay.onChatMessage = { [weak self] msg in
            DispatchQueue.main.async {
                self?.chatMessages.append(msg)
            }
        }
    }

    func sendChatMessage(_ text: String) {
        let msg = ChatMessage(message: text, sender: "admin", timestamp: ISO8601DateFormatter().string(from: Date()))
        chatMessages.append(msg)
        relay.sendChatMessage(text)
    }

    // MARK: - Input

    func sendMouseEvent(_ event: [String: Any]) {
        relay.sendInputEvent(event)
    }

    func sendKeyEvent(_ event: [String: Any]) {
        relay.sendInputEvent(event)
    }

    func sendCtrlAltDel() {
        relay.sendInputEvent([
            "type": "special_key",
            "combination": "ctrl_alt_del"
        ])
    }

    private func setupRttHandler() {
        relay.onRttUpdate = { [weak self] rtt in
            DispatchQueue.main.async {
                self?.latencyDisplay = rtt
            }
        }
    }

    // MARK: - Quality

    func setQuality(_ quality: StreamQuality) {
        session.quality = quality
        if quality == .auto {
            relay.changeQuality(fps: 0, quality: .auto, requestKeyframe: false)
            return
        }
        let fps = quality == .low ? 15 : (quality == .medium ? 20 : 30)
        relay.changeQuality(fps: fps, quality: quality, requestKeyframe: true)
    }

    // MARK: - Disconnect

    func disconnect() {
        relay.endSession(sessionId: session.sessionId, reason: "completed")
        isStreaming = false
    }

    deinit {
        fpsTimer?.invalidate()
        clipboardManager.stopMonitoring()
    }
}
