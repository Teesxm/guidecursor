import AppKit

final class Overlay {
    private let bubble = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 310, height: 90), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let target = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private let text = NSTextField(wrappingLabelWithString: "")
    init() {
        for panel in [bubble, target] {
            panel.isOpaque = false; panel.backgroundColor = .clear
            panel.level = .floating; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false; panel.hasShadow = false
        }
        let background = NSView(frame: bubble.contentView!.bounds)
        background.wantsLayer = true; background.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.90).cgColor
        background.layer?.cornerRadius = 14
        text.frame = NSRect(x: 14, y: 10, width: 282, height: 70)
        text.font = .systemFont(ofSize: 17, weight: .semibold); text.textColor = .white
        background.addSubview(text); bubble.contentView = background
        let ring = NSView(); ring.wantsLayer = true
        ring.layer?.borderColor = NSColor.systemMint.cgColor; ring.layer?.borderWidth = 5; ring.layer?.cornerRadius = 8
        target.contentView = ring
    }
    func show(rect: CGRect, label: String, direction: String) {
        target.setFrame(rect.insetBy(dx: -5, dy: -5), display: true); target.orderFrontRegardless()
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        let bounds = screen?.visibleFrame ?? .zero
        let x = min(max(pointer.x + 22, bounds.minX), bounds.maxX - 310)
        let y = min(max(pointer.y - 112, bounds.minY), bounds.maxY - 90)
        bubble.setFrameOrigin(NSPoint(x: x, y: y))
        text.stringValue = "\(label)\n\(direction)"; bubble.orderFrontRegardless()
    }
    func hide() { bubble.orderOut(nil); target.orderOut(nil) }
    /// Whether either guidance panel is ordered on screen (engine state, not proof the user saw it).
    var isVisible: Bool { bubble.isVisible || target.isVisible }
}
