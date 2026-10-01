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
        var stack: [(element: AXUIElement, parent: Int?, depth: Int)] = [(window, nil, 0)]
        var visited = Set<CFHashCode>(), nodes: [ControlNode] = [], elements: [AXUIElement] = []
        let deadline = Date().addingTimeInterval(3)
        while let item = stack.popLast(), visited.count < 1200, Date() < deadline {
            // Hash collisions only omit candidates; they can never select a wrong target.
            let node = item.element
            guard visited.insert(CFHash(node)).inserted, item.depth < 30 else { continue }
            let role = value(node, kAXRoleAttribute) as? String ?? ""
            let id = nodes.count
            nodes.append(ControlNode(
                id: id, parent: item.parent, role: role,
                title: value(node, kAXTitleAttribute) as? String,
                description: value(node, kAXDescriptionAttribute) as? String,
                help: value(node, kAXHelpAttribute) as? String,
                staticText: role == "AXStaticText" ? value(node, kAXValueAttribute) as? String : nil,
                frame: rect(node), enabled: enabled(node)
            ))
            elements.append(node)

            // Finder and other outline views can expose rows separately from children.
            var children = value(node, kAXVisibleChildrenAttribute) as? [AXUIElement] ?? []
            if children.isEmpty { children = value(node, kAXChildrenAttribute) as? [AXUIElement] ?? [] }
            if role == "AXOutline" || role == "AXTable" {
                let visibleRows = value(node, kAXVisibleRowsAttribute) as? [AXUIElement] ?? []
                children += visibleRows.isEmpty ? (value(node, kAXRowsAttribute) as? [AXUIElement] ?? []) : visibleRows
            }
            stack.append(contentsOf: children.reversed().map { ($0, id, item.depth + 1) })
        }
        let controls = ControlIndex.candidates(in: nodes).map { candidate in
            Control(id: candidate.nodeID, label: candidate.label, role: candidate.role,
                    region: windowFrame.map { Guidance.region(target: candidate.frame, window: $0) } ?? "position unknown",
                    element: elements[candidate.nodeID], rect: candidate.frame)
        }
        return Scan(controls: controls, window: window, limited: !stack.isEmpty)
    }
}
