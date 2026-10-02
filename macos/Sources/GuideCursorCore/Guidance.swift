import CoreGraphics
import Foundation

public enum Guidance {
    // Accessibility coordinates start at the top-left of the primary display.
    public static func direction(pointer: CGPoint, target: CGRect) -> String {
        if target.contains(pointer) { return "On target. Click when ready." }
        let dx = max(target.minX, min(target.maxX, pointer.x)) - pointer.x
        let dy = max(target.minY, min(target.maxY, pointer.y)) - pointer.y
        if dx == 0 && dy == 0 { return "On target. Click when ready." }
        if abs(dx) > abs(dy) * 1.7 { return dx > 0 ? "Move right" : "Move left" }
        if abs(dy) > abs(dx) * 1.7 { return dy > 0 ? "Move down" : "Move up" }
        return "Move " + (dy > 0 ? "down" : "up") + (dx > 0 ? " and right" : " and left")
    }
    public static func appKitRect(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: primaryHeight - rect.maxY, width: rect.width, height: rect.height)
    }
    public static func region(target: CGRect, window: CGRect) -> String {
        guard window.width > 0, window.height > 0 else { return "position unknown" }
        let x = (target.midX - window.minX) / window.width
        let y = (target.midY - window.minY) / window.height
        let vertical = y < 1.0 / 3 ? "upper" : y > 2.0 / 3 ? "lower" : "middle"
        let horizontal = x < 1.0 / 3 ? "left" : x > 2.0 / 3 ? "right" : "center"
        return vertical + " " + horizontal + " area"
    }
    public static func terms(_ text: String) -> Set<String> {
        let ignored: Set<String> = ["help", "me", "find", "the", "a", "an", "please", "button", "control", "to", "i", "want", "can", "you", "my"]
        return Set(text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty && !ignored.contains($0) })
    }
    public static func score(request: String, label: String) -> Int {
        let wanted = terms(request), actual = terms(label)
        guard !wanted.isEmpty else { return 0 }
        // Exact words score highest; a shared stem ("download" / "Downloads") scores lower.
        let partial = wanted.subtracting(actual).filter { word in
            actual.contains { other in
                let (short, long) = word.count <= other.count ? (word, other) : (other, word)
                return short.count >= 4 && long.hasPrefix(short)
            }
        }
        return wanted.intersection(actual).count * 10 + partial.count * 6 + (wanted == actual ? 5 : 0)
    }
    public static func validatedIDs(_ ids: [Int], allowed: Set<Int>) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { allowed.contains($0) && seen.insert($0).inserted }
    }
}
