import AppKit
import ApplicationServices
import GuideCursorCore

struct Control: Identifiable {
    let id: Int
    let label: String
    let role: String
    let region: String
    let element: AXUIElement
    let rect: CGRect
}
struct Scan {
    let controls: [Control]
    let window: AXUIElement?
    let limited: Bool
}
enum Accessibility {
    static func value(_ element: AXUIElement, _ key: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, key as CFString, &value) == .success else { return nil }
        return value
    }
    static func element(_ root: AXUIElement, _ key: String) -> AXUIElement? {
        guard let result = value(root, key), CFGetTypeID(result) == AXUIElementGetTypeID() else { return nil }
        return (result as! AXUIElement)
    }
    static func rect(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var point = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &point), AXValueGetValue(s as! AXValue, .cgSize, &size),
              point.x.isFinite, point.y.isFinite, size.width.isFinite, size.height.isFinite,
              size.width > 0, size.height > 0 else { return nil }
        return CGRect(origin: point, size: size)
    }
    static func enabled(_ element: AXUIElement) -> Bool {
        (value(element, kAXEnabledAttribute) as? Bool) != false
    }
    static func focusedWindow(_ pid: pid_t) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard var root = element(app, kAXFocusedWindowAttribute) else { return nil }
        for _ in 0..<4 {
            guard let sheet = (value(root, "AXSheets") as? [AXUIElement])?.last else { break }
            root = sheet
        }
        return root
    }
    static func scan(pid: pid_t) -> Scan {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.15)
        guard let window = focusedWindow(pid) else { return Scan(controls: [], window: nil, limited: false) }
        let windowFrame = rect(window)
        let allowed: Set<String> = [kAXButtonRole, kAXCheckBoxRole, kAXRadioButtonRole, kAXPopUpButtonRole, kAXMenuButtonRole, kAXTextFieldRole, kAXComboBoxRole, "AXLink"]
        var stack: [(AXUIElement, Int)] = [(window, 0)], visited = Set<CFHashCode>(), controls: [Control] = []
        let deadline = Date().addingTimeInterval(3)
        while let (node, depth) = stack.popLast(), visited.count < 1200, Date() < deadline {
            // Hash collisions only omit candidates; they can never select a wrong target.
            guard visited.insert(CFHash(node)).inserted, depth < 30 else { continue }
            let role = value(node, kAXRoleAttribute) as? String ?? ""
            if allowed.contains(role), enabled(node), let frame = rect(node) {
                let label = [kAXTitleAttribute, kAXDescriptionAttribute, kAXHelpAttribute].compactMap { value(node, $0) as? String }.first { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if let label { controls.append(Control(id: controls.count, label: String(label.prefix(160)), role: role, region: windowFrame.map { Guidance.region(target: frame, window: $0) } ?? "position unknown", element: node, rect: frame)) }
            }
            if let children = value(node, kAXChildrenAttribute) as? [AXUIElement] {
                stack.append(contentsOf: children.reversed().map { ($0, depth + 1) })
            }
        }
        return Scan(controls: controls, window: window, limited: !stack.isEmpty)
    }
}
