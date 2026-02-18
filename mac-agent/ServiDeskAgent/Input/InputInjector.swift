import Foundation
import CoreGraphics
import AppKit

/// Injekce vstupních událostí (myš + klávesnice) pomocí CGEvent API.
/// Vyžaduje Accessibility oprávnění v System Preferences.
class InputInjector {

    /// Převede normalizované souřadnice (0.0-1.0) na screen coordinates
    private func screenPoint(normalizedX: Double, normalizedY: Double) -> CGPoint {
        let screen = NSScreen.main ?? NSScreen.screens.first
        let frame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1920, height: 1080)
        return CGPoint(
            x: normalizedX * frame.width,
            y: normalizedY * frame.height
        )
    }

    // MARK: - Mouse

    /// Přesune myš na normalizovanou pozici
    func moveTo(normalizedX: Double, normalizedY: Double) {
        let point = screenPoint(normalizedX: normalizedX, normalizedY: normalizedY)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: point, mouseButton: .left) else { return }
        event.post(tap: .cghidEventTap)
    }

    /// Kliknutí myší
    func click(button: String, action: String, normalizedX: Double, normalizedY: Double) {
        let point = screenPoint(normalizedX: normalizedX, normalizedY: normalizedY)

        let mouseButton: CGMouseButton
        let downType: CGEventType
        let upType: CGEventType

        switch button {
        case "right":
            mouseButton = .right
            downType = .rightMouseDown
            upType = .rightMouseUp
        case "middle":
            mouseButton = .center
            downType = .otherMouseDown
            upType = .otherMouseUp
        default: // "left"
            mouseButton = .left
            downType = .leftMouseDown
            upType = .leftMouseUp
        }

        let eventType: CGEventType
        switch action {
        case "down":
            eventType = downType
        case "up":
            eventType = upType
        default:
            return
        }

        guard let event = CGEvent(mouseEventSource: nil, mouseType: eventType, mouseCursorPosition: point, mouseButton: mouseButton) else { return }

        // Pro double-click nastavit clickCount
        if action == "down" {
            event.setIntegerValueField(.mouseEventClickState, value: 1)
        }

        event.post(tap: .cghidEventTap)
    }

    /// Scrollování
    func scroll(deltaX: Int, deltaY: Int) {
        // Windows WHEEL_DELTA = 120 per notch, macOS používá line units
        // Převod: Windows delta / 120 = počet řádků
        let macDeltaY = Int32(-deltaY / 120) // Invertovat pro macOS konvenci
        let macDeltaX = Int32(deltaX / 120)

        if let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 2, wheel1: macDeltaY, wheel2: macDeltaX, wheel3: 0) {
            event.post(tap: .cghidEventTap)
        }
    }

    // MARK: - Keyboard

    /// Stisknutí klávesy
    func keyDown(vkCode: Int, modifiers: [String: Bool]? = nil) {
        guard let macCode = KeyCodeMapper.macKeyCode(fromVK: vkCode) else { return }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: macCode, keyDown: true) else { return }
        applyModifiers(event, modifiers: modifiers)
        event.post(tap: .cghidEventTap)
    }

    /// Uvolnění klávesy
    func keyUp(vkCode: Int, modifiers: [String: Bool]? = nil) {
        guard let macCode = KeyCodeMapper.macKeyCode(fromVK: vkCode) else { return }

        guard let event = CGEvent(keyboardEventSource: nil, virtualKey: macCode, keyDown: false) else { return }
        applyModifiers(event, modifiers: modifiers)
        event.post(tap: .cghidEventTap)
    }

    /// Aplikuje modifikátory na CGEvent
    private func applyModifiers(_ event: CGEvent, modifiers: [String: Bool]?) {
        guard let mods = modifiers else { return }
        var flags = CGEventFlags()

        if mods["ctrl"] == true { flags.insert(.maskControl) }
        if mods["alt"] == true { flags.insert(.maskAlternate) }
        if mods["shift"] == true { flags.insert(.maskShift) }
        if mods["win"] == true { flags.insert(.maskCommand) }

        if !flags.isEmpty {
            event.flags = flags
        }
    }

    // MARK: - Permission check

    /// Zkontroluje, zda má aplikace Accessibility oprávnění
    static func checkPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    /// Požádá o Accessibility oprávnění (zobrazí systémový dialog)
    static func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }
}
