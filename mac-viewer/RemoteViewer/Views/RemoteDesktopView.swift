import SwiftUI
import MetalKit

struct RemoteDesktopView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let sessionVM = appState.activeSession {
            SessionContentView(sessionVM: sessionVM)
                .environmentObject(appState)
        }
    }
}

/// Samostatný view s @ObservedObject pro sledování změn na sessionVM (FPS, kvalita, atd.)
struct SessionContentView: View {
    @ObservedObject var sessionVM: RemoteSessionViewModel
    @EnvironmentObject var appState: AppState
    @State private var showChat = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Toolbar
                HStack {
                    Text("\(sessionVM.session.customerName) – \(sessionVM.session.hostname)")
                        .font(.headline)

                    Spacer()

                    // Quality picker
                    Picker("Kvalita", selection: Binding(
                        get: { sessionVM.session.quality },
                        set: { newQuality in
                            DispatchQueue.main.async { sessionVM.setQuality(newQuality) }
                        }
                    )) {
                        Text("Auto").tag(StreamQuality.auto)
                        Text("Low").tag(StreamQuality.low)
                        Text("Medium").tag(StreamQuality.medium)
                        Text("High").tag(StreamQuality.high)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)

                    // Monitor picker (only if multi-monitor)
                    if sessionVM.monitors.count > 1 {
                        Picker("Monitor", selection: Binding(
                            get: { sessionVM.activeMonitorIndex },
                            set: { newIndex in
                                DispatchQueue.main.async { sessionVM.switchMonitor(newIndex) }
                            }
                        )) {
                            ForEach(sessionVM.monitors) { monitor in
                                Text("Monitor \(monitor.index + 1)")
                                    .tag(monitor.index)
                            }
                        }
                        .frame(width: 130)
                    }

                    // Chat toggle
                    Button {
                        withAnimation { showChat.toggle() }
                    } label: {
                        Image(systemName: showChat ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right")
                    }
                    .buttonStyle(.bordered)
                    .help("Chat")

                    // File transfer
                    if sessionVM.fileTransfer.isTransferring {
                        ProgressView(value: sessionVM.fileTransfer.transferProgress)
                            .frame(width: 80)
                        Text(sessionVM.fileTransfer.transferFileName)
                            .font(.caption)
                            .lineLimit(1)
                    } else {
                        Button {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            panel.canChooseDirectories = false
                            if panel.runModal() == .OK, let url = panel.url {
                                sessionVM.fileTransfer.sendFile(url: url)
                            }
                        } label: {
                            Image(systemName: "paperplane")
                        }
                        .buttonStyle(.bordered)
                        .help("Odeslat soubor")
                    }

                    Button("Ctrl+Alt+Del") {
                        sessionVM.sendCtrlAltDel()
                    }
                    .buttonStyle(.bordered)

                    Button("Odpojit") {
                        sessionVM.disconnect()
                        appState.activeSession = nil
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.bar)

                Divider()

                // Content: Desktop + optional Chat sidebar
                HSplitView {
                    // Remote Desktop – Metal view s korektním poměrem stran
                    GeometryReader { geo in
                        let remoteAspect = sessionVM.remoteScreenSize.width / max(sessionVM.remoteScreenSize.height, 1)
                        let viewAspect = geo.size.width / max(geo.size.height, 1)
                        let fittedSize: CGSize = {
                            if viewAspect > remoteAspect {
                                let h = geo.size.height
                                return CGSize(width: h * remoteAspect, height: h)
                            } else {
                                let w = geo.size.width
                                return CGSize(width: w, height: w / remoteAspect)
                            }
                        }()

                        RemoteDesktopMetalView(sessionVM: sessionVM)
                            .frame(width: fittedSize.width, height: fittedSize.height)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .background(Color.black)

                    if showChat {
                        ChatPanelView(sessionVM: sessionVM)
                            .frame(minWidth: 250, maxWidth: 350)
                    }
                }

                Divider()

                // Status bar
                HStack(spacing: 16) {
                    Label("FPS: \(sessionVM.fpsDisplay)", systemImage: "speedometer")
                    Label("Kvalita: \(sessionVM.session.quality.rawValue.capitalized)", systemImage: "dial.medium")
                    if sessionVM.latencyDisplay > 0 {
                        Label("RTT: \(sessionVM.latencyDisplay) ms", systemImage: "antenna.radiowaves.left.and.right")
                    }
                    if !sessionVM.chatMessages.isEmpty {
                        Label("\(sessionVM.chatMessages.count) zpráv", systemImage: "bubble.left")
                    }
                    Spacer()
                }
                .font(.caption)
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.bar)
            }

            // Overlay po odpojeni klienta
            if appState.sessionEndInfo != nil {
                Color.black.opacity(0.6)
                    .ignoresSafeArea()

                VStack(spacing: 20) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)

                    Text("Klient se odpojil")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text(appState.sessionEndInfo?.reason ?? "")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    HStack(spacing: 16) {
                        Button("Znovu připojit") {
                            appState.dismissSessionEnd(reconnect: true)
                        }
                        .buttonStyle(.borderedProminent)

                        Button("Ukončit") {
                            appState.dismissSessionEnd(reconnect: false)
                        }
                        .buttonStyle(.bordered)
                    }
                }
                .padding(40)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }
}

/// NSViewRepresentable wrapper pro MTKView s mouse/keyboard tracking.
struct RemoteDesktopMetalView: NSViewRepresentable {
    let sessionVM: RemoteSessionViewModel

    func makeNSView(context: Context) -> RemoteDesktopNSView {
        let view = RemoteDesktopNSView(sessionVM: sessionVM)
        return view
    }

    func updateNSView(_ nsView: RemoteDesktopNSView, context: Context) {}
}

/// Custom NSView s MTKView pro rendering + mouse/keyboard events.
class RemoteDesktopNSView: NSView {
    private var mtkView: MTKView!
    private var renderer: FrameRenderer?
    private let sessionVM: RemoteSessionViewModel

    init(sessionVM: RemoteSessionViewModel) {
        self.sessionVM = sessionVM
        super.init(frame: .zero)
        setupMetal()
    }

    required init?(coder: NSCoder) { fatalError() }

    private func setupMetal() {
        mtkView = MTKView(frame: bounds)
        mtkView.autoresizingMask = [.width, .height]
        addSubview(mtkView)

        renderer = FrameRenderer(mtkView: mtkView)

        sessionVM.onFrameReady = { [weak self] jpegData in
            self?.renderer?.displayFrame(jpegData)
        }

        sessionVM.onRegionsReady = { [weak self] regions in
            self?.renderer?.displayRegions(regions)
        }
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    /// Zachytit klávesové zkratky dřív než je macOS pošle do menu
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown {
            keyDown(with: event)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Mouse Events

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseMoved(localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseClick(button: "left", action: "down", localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseClick(button: "left", action: "up", localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    override func rightMouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseClick(button: "right", action: "down", localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    override func rightMouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseClick(button: "right", action: "up", localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    override func mouseDragged(with event: NSEvent) {
        mouseMoved(with: event)
    }

    override func scrollWheel(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let ev = sessionVM.mouseTracker.onMouseScroll(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY, localPoint: point, viewSize: bounds.size)
        sessionVM.sendMouseEvent(ev)
    }

    // MARK: - Keyboard Events

    override func keyDown(with event: NSEvent) {
        let ev = sessionVM.keyboardTracker.onKeyEvent(event: event, isDown: true)
        sessionVM.sendKeyEvent(ev)
    }

    override func keyUp(with event: NSEvent) {
        let ev = sessionVM.keyboardTracker.onKeyEvent(event: event, isDown: false)
        sessionVM.sendKeyEvent(ev)
    }

    override func flagsChanged(with event: NSEvent) {
        let ev = sessionVM.keyboardTracker.onKeyEvent(event: event, isDown: event.modifierFlags.contains(modifierFlag(for: event.keyCode)))
        sessionVM.sendKeyEvent(ev)
    }

    /// Mapování keyCode na odpovídající modifier flag
    private func modifierFlag(for keyCode: UInt16) -> NSEvent.ModifierFlags {
        switch keyCode {
        case 0x37, 0x36: return .command    // Left/Right Command
        case 0x38, 0x3C: return .shift      // Left/Right Shift
        case 0x3A, 0x3D: return .option     // Left/Right Option
        case 0x3B, 0x3E: return .control    // Left/Right Control
        case 0x39:       return .capsLock    // Caps Lock
        default:         return []
        }
    }

    // MARK: - Tracking Area

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }
}
