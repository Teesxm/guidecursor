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
        let (wanted, exact, partial) = matches(request: request, label: label)
        guard !wanted.isEmpty else { return 0 }
        return exact.count * 10 + partial.count * 6 + (wanted == terms(label) ? 5 : 0)
    }
    /// Strict name equality for unverified visual text (not used by accessibility search).
    /// Every searchable request word must appear in the label, and every label word (apart from
    /// "the", "a", "an") must appear in the request as typed. Words are equal only when identical or
    /// differing by a plural "s"/"es". Extra words that change the action ("Don't Save", "Save as PDF")
    /// and other inflections ("Deleted") therefore never match; a missed match is the safe outcome.
    public static func sameName(request: String, label: String) -> Bool {
        let wanted = terms(request), typed = words(request)
        let shown = words(label).filter { !["the", "a", "an"].contains($0) }
        guard !wanted.isEmpty, !shown.isEmpty else { return false }
        func equal(_ a: String, _ b: String) -> Bool { a == b || a + "s" == b || b + "s" == a || a + "es" == b || b + "es" == a }
        return wanted.allSatisfy { w in shown.contains { equal(w, $0) } }
            && shown.allSatisfy { s in typed.contains { equal(s, $0) } }
    }
    private static func words(_ text: String) -> [String] {
        text.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }
    private static func matches(request: String, label: String) -> (wanted: Set<String>, exact: Set<String>, partial: Set<String>) {
        let wanted = terms(request), actual = terms(label)
        // Exact words score highest; a shared stem ("download" / "Downloads") scores lower.
        let partial = wanted.subtracting(actual).filter { word in
            actual.contains { other in
                let (short, long) = word.count <= other.count ? (word, other) : (other, word)
                return short.count >= 4 && long.hasPrefix(short)
            }
        }
        return (wanted, wanted.intersection(actual), partial)
    }
    public static func validatedIDs(_ ids: [Int], allowed: Set<Int>) -> [Int] {
        var seen = Set<Int>()
        return ids.filter { allowed.contains($0) && seen.insert($0).inserted }
    }
}
