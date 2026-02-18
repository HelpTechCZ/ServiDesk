import AppKit

/// Monitoruje macOS schránku pomocí changeCount polling.
/// Odesílá změny přes callback, přijímá text z remote a nastavuje lokální schránku.
class ClipboardManager {
    private var lastChangeCount: Int
    private var suppressNextChange = false
    private var timer: Timer?

    var onClipboardChanged: ((String) -> Void)?

    init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkClipboard()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkClipboard() {
        let currentCount = NSPasteboard.general.changeCount
        guard currentCount != lastChangeCount else { return }
        lastChangeCount = currentCount

        if suppressNextChange {
            suppressNextChange = false
            return
        }

        if let text = NSPasteboard.general.string(forType: .string), !text.isEmpty {
            onClipboardChanged?(text)
        }
    }

    /// Nastaví lokální schránku z remote textu (s echo suppression)
    func setClipboardText(_ text: String) {
        suppressNextChange = true
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        lastChangeCount = NSPasteboard.general.changeCount
    }
}
