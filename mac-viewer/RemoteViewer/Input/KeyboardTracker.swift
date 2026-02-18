import AppKit

/// Zachytávání klávesnice + mapování macOS key codes → Windows virtual key codes.
class KeyboardTracker {

    var mapCmdToCtrl: Bool = true

    /// Mapování macOS key code → Windows Virtual Key code
    static let keyMap: [UInt16: Int] = [
        0x00: 0x41, // A
        0x01: 0x53, // S
        0x02: 0x44, // D
        0x03: 0x46, // F
        0x04: 0x48, // H
        0x05: 0x47, // G
        0x06: 0x5A, // Z
        0x07: 0x58, // X
        0x08: 0x43, // C
        0x09: 0x56, // V
        0x0B: 0x42, // B
        0x0C: 0x51, // Q
        0x0D: 0x57, // W
        0x0E: 0x45, // E
        0x0F: 0x52, // R
        0x10: 0x59, // Y
        0x11: 0x54, // T
        0x12: 0x31, // 1
        0x13: 0x32, // 2
        0x14: 0x33, // 3
        0x15: 0x34, // 4
        0x16: 0x36, // 6
        0x17: 0x35, // 5
        0x18: 0xBB, // =
        0x19: 0x39, // 9
        0x1A: 0x37, // 7
        0x1B: 0xBD, // -
        0x1C: 0x38, // 8
        0x1D: 0x30, // 0
        0x1E: 0xDD, // ]
        0x1F: 0x4F, // O
        0x20: 0x55, // U
        0x21: 0xDB, // [
        0x22: 0x49, // I
        0x23: 0x50, // P
        0x24: 0x0D, // Return → VK_RETURN
        0x25: 0x4C, // L
        0x26: 0x4A, // J
        0x27: 0xDE, // '
        0x28: 0x4B, // K
        0x29: 0xBA, // ;
        0x2A: 0xDC, // backslash
        0x2B: 0xBC, // ,
        0x2C: 0xBF, // /
        0x2D: 0x4E, // N
        0x2E: 0x4D, // M
        0x2F: 0xBE, // .
        0x30: 0x09, // Tab → VK_TAB
        0x31: 0x20, // Space → VK_SPACE
        0x32: 0xC0, // `
        0x33: 0x08, // Delete → VK_BACK
        0x35: 0x1B, // Escape → VK_ESCAPE
        0x37: 0x5B, // Command → VK_LWIN (nebo Ctrl)
        0x38: 0xA0, // Left Shift → VK_LSHIFT
        0x39: 0x14, // Caps Lock → VK_CAPITAL
        0x3A: 0xA4, // Left Option → VK_LMENU (Alt)
        0x3B: 0xA2, // Left Control → VK_LCONTROL
        0x3C: 0xA1, // Right Shift → VK_RSHIFT
        0x3D: 0xA5, // Right Option → VK_RMENU
        0x3E: 0xA3, // Right Control → VK_RCONTROL
        0x7A: 0x70, // F1
        0x78: 0x71, // F2
        0x63: 0x72, // F3
        0x76: 0x73, // F4
        0x60: 0x74, // F5
        0x61: 0x75, // F6
        0x62: 0x76, // F7
        0x64: 0x77, // F8
        0x65: 0x78, // F9
        0x6D: 0x79, // F10
        0x67: 0x7A, // F11
        0x6F: 0x7B, // F12
        0x7B: 0x25, // Left Arrow → VK_LEFT
        0x7C: 0x27, // Right Arrow → VK_RIGHT
        0x7D: 0x28, // Down Arrow → VK_DOWN
        0x7E: 0x26, // Up Arrow → VK_UP
        0x73: 0x24, // Home → VK_HOME
        0x77: 0x23, // End → VK_END
        0x74: 0x21, // Page Up → VK_PRIOR
        0x79: 0x22, // Page Down → VK_NEXT
        0x75: 0x2E, // Forward Delete → VK_DELETE
        0x72: 0x2D, // Insert (Help) → VK_INSERT

        // ── Numpad ──
        0x52: 0x60, // Numpad 0 → VK_NUMPAD0
        0x53: 0x61, // Numpad 1 → VK_NUMPAD1
        0x54: 0x62, // Numpad 2 → VK_NUMPAD2
        0x55: 0x63, // Numpad 3 → VK_NUMPAD3
        0x56: 0x64, // Numpad 4 → VK_NUMPAD4
        0x57: 0x65, // Numpad 5 → VK_NUMPAD5
        0x58: 0x66, // Numpad 6 → VK_NUMPAD6
        0x59: 0x67, // Numpad 7 → VK_NUMPAD7
        0x5A: 0x68, // Numpad 8 → VK_NUMPAD8
        0x5B: 0x69, // Numpad 9 → VK_NUMPAD9
        0x41: 0x6E, // Numpad . → VK_DECIMAL
        0x43: 0x6A, // Numpad * → VK_MULTIPLY
        0x45: 0x6B, // Numpad + → VK_ADD
        0x4B: 0x6F, // Numpad / → VK_DIVIDE
        0x4C: 0x0D, // Numpad Enter → VK_RETURN
        0x4E: 0x6D, // Numpad - → VK_SUBTRACT
        0x47: 0x90, // Numpad Clear → VK_NUMLOCK
    ]

    /// Numpad keyCodes — tyto se posílají vždy přes VK code (ne Unicode)
    static let numpadKeyCodes: Set<UInt16> = [
        0x41, 0x43, 0x45, 0x47, 0x4B, 0x4C, 0x4E,
        0x52, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5A, 0x5B
    ]

    func onKeyEvent(event: NSEvent, isDown: Bool) -> [String: Any] {
        var vkCode = Self.keyMap[event.keyCode] ?? Int(event.keyCode)

        // Cmd → Ctrl mapování
        let modifiers = event.modifierFlags
        var ctrl = modifiers.contains(.control)
        let alt = modifiers.contains(.option)
        let shift = modifiers.contains(.shift)
        let cmd = modifiers.contains(.command)

        if mapCmdToCtrl && cmd {
            ctrl = true
        }

        // Pokud je to samotná Command klávesa, mapovat na Ctrl
        if mapCmdToCtrl && event.keyCode == 0x37 {
            vkCode = 0x11 // VK_CONTROL
        }

        var result: [String: Any] = [
            "type": "key",
            "action": isDown ? "down" : "up",
            "key_code": vkCode,
            "modifiers": [
                "ctrl": ctrl,
                "alt": alt,
                "shift": shift,
                "win": cmd && !mapCmdToCtrl
            ]
        ]

        // Přidat Unicode znak pro české/speciální znaky
        // Pouze pro keyDown/keyUp (ne flagsChanged), ne pro numpad
        if (event.type == .keyDown || event.type == .keyUp),
           !Self.numpadKeyCodes.contains(event.keyCode),
           let chars = event.characters,
           let firstChar = chars.first {
            let scalar = firstChar.unicodeScalars.first!.value
            // Tisknutelné znaky: >= 0x20, ne DEL (0x7F), ne macOS function key range (>= 0xF700)
            if scalar >= 0x20 && scalar != 0x7F && scalar < 0xF700 {
                result["char"] = String(firstChar)
            }
        }

        return result
    }
}
