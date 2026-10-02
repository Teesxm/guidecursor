import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Uses Apple's user-configured accessibility shortcut; does not change Zoom preferences.
enum Magnification {
    static func sendToggle(shortcutConfirmed: Bool) -> String {
        guard shortcutConfirmed else { return "First enable ‘Use keyboard shortcuts to zoom’ in macOS Accessibility → Zoom and confirm the shortcut is Option–Command–8." }
        guard AXIsProcessTrusted() else { return "Enable GuideCursor's Accessibility permission before using the Zoom shortcut." }
        guard let source = CGEventSource(stateID: .combinedSessionState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_8), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_8), keyDown: false) else {
            return "The Zoom shortcut could not be created. You can use Option–Command–8 yourself."
        }
        down.flags = [.maskAlternate, .maskCommand]
        up.flags = [.maskAlternate, .maskCommand]
        down.post(tap: .cghidEventTap); up.post(tap: .cghidEventTap)
        return "Zoom shortcut sent. If nothing changed, check the macOS Zoom keyboard setting. Press Option–Command–8 again to toggle back."
    }
}
