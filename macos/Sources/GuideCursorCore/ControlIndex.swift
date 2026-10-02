import CoreGraphics
import Foundation

/// A small, testable representation of the macOS accessibility tree.
/// `value` is populated only for static text; editable field contents are never read.
public struct ControlNode {
    public let id: Int
    public let parent: Int?
    public let role: String
    public let title: String?
    public let description: String?
    public let help: String?
    public let staticText: String?
    public let frame: CGRect?
    public let enabled: Bool

    public init(id: Int, parent: Int?, role: String, title: String? = nil,
                description: String? = nil, help: String? = nil, staticText: String? = nil,
                frame: CGRect? = nil, enabled: Bool = true) {
        self.id = id; self.parent = parent; self.role = role
        self.title = title; self.description = description; self.help = help
        self.staticText = staticText; self.frame = frame; self.enabled = enabled
    }
}

public struct IndexedControl {
    public let nodeID: Int
    public let label: String
    public let role: String
    public let frame: CGRect
}

public enum ControlIndex {
    private static let directRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXComboBox", "AXLink", "AXMenuItem", "AXRow", "AXCell"
    ]
    private static let preferredRoles: Set<String> = [
        "AXButton", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
        "AXTextField", "AXComboBox", "AXLink", "AXMenuItem"
    ]

    private static func trimmed(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return String(text.prefix(160))
    }

    /// Enabled, on-screen nodes with an interactive role, labelled or not. Used for diagnostics counts.
    public static func interactiveIDs(in nodes: [ControlNode]) -> Set<Int> {
        Set(nodes.filter { directRoles.contains($0.role) && $0.enabled && $0.frame != nil }.map(\.id))
    }

    public static func candidates(in nodes: [ControlNode]) -> [IndexedControl] {
        let byID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        var labels: [Int: String] = [:]

        for node in nodes where directRoles.contains(node.role) && node.enabled && node.frame != nil {
            labels[node.id] = trimmed(node.title) ?? trimmed(node.description) ?? trimmed(node.help)
        }

        // Finder sidebar entries can be AXRow → AXCell → AXStaticText. The row may
        // have no label of its own, while the visible text has the AXValue "Downloads".
        for node in nodes where node.role == "AXStaticText" {
            guard let text = trimmed(node.staticText) ?? trimmed(node.title), let parent = node.parent else { continue }
            var ancestor: Int? = parent
            var row: Int?, cell: Int?, direct: Int?, steps = 0
            while let id = ancestor, let candidate = byID[id], steps < 8 {
                if candidate.enabled && candidate.frame != nil {
                    if preferredRoles.contains(candidate.role) { direct = id; break }
                    if candidate.role == "AXRow" { row = id }
                    if candidate.role == "AXCell" && cell == nil { cell = id }
                }
                ancestor = candidate.parent; steps += 1
            }
            guard let host = direct ?? row ?? cell else { continue }
            if let existing = labels[host] {
                if !existing.localizedCaseInsensitiveContains(text) {
                    labels[host] = String((existing + " " + text).prefix(160))
                }
            } else {
                labels[host] = text
            }
        }

        return labels.keys.sorted().compactMap { id in
            guard let node = byID[id], let frame = node.frame, let label = labels[id] else { return nil }
            return IndexedControl(nodeID: id, label: label, role: node.role, frame: frame)
        }
    }
}
