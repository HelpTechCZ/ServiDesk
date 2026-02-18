import AppKit

/// Zachytávání myši nad remote desktop view.
/// Převod souřadnic: lokální view → normalizované 0.0-1.0.
class MouseTracker {

    func onMouseMoved(localPoint: NSPoint, viewSize: NSSize) -> [String: Any] {
        let (x, y) = convertCoords(localPoint: localPoint, viewSize: viewSize)
        return [
            "type": "mouse_move",
            "x": x,
            "y": y
        ]
    }

    func onMouseClick(button: String, action: String, localPoint: NSPoint, viewSize: NSSize) -> [String: Any] {
        let (x, y) = convertCoords(localPoint: localPoint, viewSize: viewSize)
        return [
            "type": "mouse_click",
            "button": button,
            "action": action,
            "x": x,
            "y": y
        ]
    }

    func onMouseScroll(deltaX: CGFloat, deltaY: CGFloat, localPoint: NSPoint, viewSize: NSSize) -> [String: Any] {
        let (x, y) = convertCoords(localPoint: localPoint, viewSize: viewSize)
        return [
            "type": "mouse_scroll",
            "delta_x": Int(deltaX * -3),
            "delta_y": Int(deltaY * -120),
            "x": x,
            "y": y
        ]
    }

    private func convertCoords(localPoint: NSPoint, viewSize: NSSize) -> (Double, Double) {
        guard viewSize.width > 0 && viewSize.height > 0 else { return (0, 0) }

        let x = Double(localPoint.x / viewSize.width)
        // macOS má Y axis invertovaný oproti Windows
        let y = Double((viewSize.height - localPoint.y) / viewSize.height)

        return (
            max(0, min(1, x)),
            max(0, min(1, y))
        )
    }
}
