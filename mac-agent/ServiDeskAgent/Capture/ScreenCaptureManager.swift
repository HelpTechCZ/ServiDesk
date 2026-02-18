import Foundation
import ScreenCaptureKit
import CoreMedia
import AppKit

/// Wrapper nad ScreenCaptureKit pro zachytávání obrazovky.
/// Vyžaduje Screen Recording oprávnění v System Preferences.
class ScreenCaptureManager: NSObject, SCStreamOutput {
    private var stream: SCStream?
    private var availableDisplays: [SCDisplay] = []
    private var activeDisplayIndex: Int = 0

    var onFrameCaptured: ((CMSampleBuffer) -> Void)?

    /// Inicializuje a enumeruje dostupné displeje
    func initialize() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        availableDisplays = content.displays

        guard !availableDisplays.isEmpty else {
            throw CaptureError.noDisplaysFound
        }
    }

    /// Vrátí informace o monitorech pro odeslání vieweru
    func getMonitorInfo() -> MonitorInfo {
        let monitors = availableDisplays.enumerated().map { index, display in
            MonitorDetail(
                index: index,
                name: "Display \(index + 1)",
                width: display.width,
                height: display.height,
                is_primary: index == 0
            )
        }
        return MonitorInfo(monitors: monitors, active_index: activeDisplayIndex)
    }

    /// Vrátí rozměry aktivního displeje
    func getActiveDisplaySize() -> (width: Int, height: Int) {
        guard activeDisplayIndex < availableDisplays.count else {
            return (1920, 1080)
        }
        let display = availableDisplays[activeDisplayIndex]
        return (display.width, display.height)
    }

    /// Spustí zachytávání obrazovky
    func startCapture(fps: Int = 30) async throws {
        guard activeDisplayIndex < availableDisplays.count else {
            throw CaptureError.noDisplaysFound
        }

        let display = availableDisplays[activeDisplayIndex]

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let config = SCStreamConfiguration()
        config.width = display.width
        config.height = display.height
        config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(fps))
        config.pixelFormat = kCVPixelFormatType_32BGRA
        config.showsCursor = true

        let newStream = SCStream(filter: filter, configuration: config, delegate: nil)
        try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: .global(qos: .userInteractive))
        try await newStream.startCapture()

        stream = newStream
    }

    /// Zastaví zachytávání
    func stopCapture() async {
        guard let stream = stream else { return }
        try? await stream.stopCapture()
        self.stream = nil
    }

    /// Přepne na jiný monitor
    func switchMonitor(to index: Int) async throws {
        guard index >= 0, index < availableDisplays.count else {
            throw CaptureError.invalidMonitorIndex
        }

        let wasCapturing = stream != nil
        if wasCapturing {
            await stopCapture()
        }

        activeDisplayIndex = index

        if wasCapturing {
            try await startCapture()
        }
    }

    // MARK: - SCStreamOutput

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard sampleBuffer.isValid else { return }
        onFrameCaptured?(sampleBuffer)
    }

    // MARK: - Permission check

    /// Zkontroluje, zda má aplikace Screen Recording oprávnění
    static func checkPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - Errors

enum CaptureError: LocalizedError {
    case noDisplaysFound
    case invalidMonitorIndex

    var errorDescription: String? {
        switch self {
        case .noDisplaysFound: return "Nebyly nalezeny žádné displeje."
        case .invalidMonitorIndex: return "Neplatný index monitoru."
        }
    }
}
