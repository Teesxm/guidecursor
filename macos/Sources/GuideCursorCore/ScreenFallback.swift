import CoreGraphics
import Foundation

/// Whether a screen image of the chosen window may help, decided only from accessibility evidence.
/// The image is always the user's choice; this never captures anything by itself.
public enum FallbackDecision: Equatable {
    case notNeeded                      // accessibility found candidates
    case fixAccessFirst                 // permission, quit app or missing window: an image cannot fix this
    case retryAccessibility             // partial/failed scan or unresponsive app: not evidence that AX lacks the control
    case rephrase                       // complete scan, every control named, nothing matched
    case offerScreenImage(unlabelled: Int) // complete scan, and accessibility could not name or find the control
}

public enum ScreenFallback {
    public static func decide(_ diagnosis: Diagnosis, stats: ScanStats) -> FallbackDecision {
        switch diagnosis {
        case .matches: return .notNeeded
        case .permissionMissing, .appUnavailable, .noWindow: return .fixAccessFirst
        case .appNotResponding, .controlsNotFullyRead: return .retryAccessibility
        case .unsearchableRequest: return .rephrase
        case .noExposedControls(let unlabelled):
            return stats.incomplete ? .retryAccessibility : .offerScreenImage(unlabelled: unlabelled)
        case .noMatch, .modelChoseNone:
            if stats.incomplete { return .retryAccessibility }
            // Unnamed interactive controls are the evidence that the target may exist without a usable name.
            return stats.unlabelledInteractive > 0 ? .offerScreenImage(unlabelled: stats.unlabelledInteractive) : .rephrase
        }
    }
}

// MARK: Offer bound to its scan

/// A screen-image offer tied to the scan that produced it. Before any capture, the app must observe
/// the current state afresh (selected process, request text, focused window element and frame) and
/// capture only if `isCurrent` holds; otherwise the offer is dropped and a new scan is needed.
public struct CaptureOffer: Equatable {
    public let pid: Int32
    public let request: String
    public let windowFrame: CGRect
    public let unlabelled: Int

    /// Only an `.offerScreenImage` decision with a known window frame produces an offer.
    public init?(decision: FallbackDecision, pid: Int32, request: String, windowFrame: CGRect?) {
        guard case .offerScreenImage(let unlabelled) = decision, let windowFrame, pid > 0 else { return nil }
        self.pid = pid; self.request = request.trimmingCharacters(in: .whitespacesAndNewlines)
        self.windowFrame = windowFrame; self.unlabelled = unlabelled
    }

    public struct Observation {
        public let pid: Int32
        public let request: String
        /// Whether the focused window element is the same element that was scanned (CFEqual in the app).
        public let sameWindow: Bool
        public let windowFrame: CGRect?
        public init(pid: Int32, request: String, sameWindow: Bool, windowFrame: CGRect?) {
            self.pid = pid; self.request = request; self.sameWindow = sameWindow; self.windowFrame = windowFrame
        }
    }

    public func isCurrent(_ now: Observation, tolerance: CGFloat = 1) -> Bool {
        guard now.pid == pid, now.sameWindow, let frame = now.windowFrame,
              now.request.trimmingCharacters(in: .whitespacesAndNewlines) == request else { return false }
        return abs(frame.minX - windowFrame.minX) <= tolerance && abs(frame.minY - windowFrame.minY) <= tolerance
            && abs(frame.width - windowFrame.width) <= tolerance && abs(frame.height - windowFrame.height) <= tolerance
    }
}

// MARK: Bounded waiting

public enum BoundedWaitError: Error, Equatable { case timedOut }

/// Waits for an async operation for at most `seconds`, even if the operation ignores cancellation
/// (task-group cancellation would still wait for it). After the deadline the operation is asked to
/// cancel but may keep running until it returns; a late result is handed to `discardLate` and is
/// neither returned nor kept.
public enum BoundedWait {
    private final class Gate: @unchecked Sendable {
        private let lock = NSLock()
        private var open = true
        func claim() -> Bool { lock.lock(); defer { lock.unlock() }; if open { open = false; return true }; return false }
    }

    public static func run<T>(seconds: TimeInterval, _ operation: @escaping @Sendable () async throws -> T,
                              discardLate: @escaping @Sendable (T) -> Void = { _ in }) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let gate = Gate()
            let work = Task {
                do {
                    let value = try await operation()
                    if gate.claim() { continuation.resume(returning: value) } else { discardLate(value) }
                } catch {
                    if gate.claim() { continuation.resume(throwing: error) }
                }
            }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
                if gate.claim() { continuation.resume(throwing: BoundedWaitError.timedOut); work.cancel() }
            }
        }
    }
}

// MARK: Capture geometry

/// Maps pixels of a captured window image to global screen points (accessibility coordinates:
/// top-left of the primary display). Rejects images whose shape does not match the window.
public struct CaptureGeometry: Equatable {
    public let windowFrame: CGRect
    public let imageSize: CGSize
    public let scale: CGFloat

    public init?(windowFrame: CGRect, imageSize: CGSize) {
        let values = [windowFrame.minX, windowFrame.minY, windowFrame.width, windowFrame.height, imageSize.width, imageSize.height]
        guard values.allSatisfy(\.isFinite), windowFrame.width > 0, windowFrame.height > 0,
              imageSize.width >= 1, imageSize.height >= 1 else { return nil }
        let sx = imageSize.width / windowFrame.width, sy = imageSize.height / windowFrame.height
        // Pixel rounding allows a small difference between axes; more means a different window or cropping.
        guard sx >= 0.25, sx <= 4, abs(sx - sy) / max(sx, sy) <= 0.03 else { return nil }
        self.windowFrame = windowFrame; self.imageSize = imageSize; self.scale = sx
    }

    /// nil when the rectangle is empty, non-finite or not inside the image.
    public func screenRect(imageRect r: CGRect) -> CGRect? {
        guard [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite), r.width > 0, r.height > 0,
              r.minX >= -1, r.minY >= -1, r.maxX <= imageSize.width + 1, r.maxY <= imageSize.height + 1 else { return nil }
        return CGRect(x: windowFrame.minX + r.minX / scale, y: windowFrame.minY + r.minY / scale,
                      width: r.width / scale, height: r.height / scale)
    }
}

// MARK: Window matching

/// A capturable window as reported by the capture API, reduced to what matching needs.
public struct CaptureWindow: Equatable {
    public let id: UInt32
    public let pid: Int32
    public let frame: CGRect
    public let layer: Int
    public let onScreen: Bool
    public init(id: UInt32, pid: Int32, frame: CGRect, layer: Int = 0, onScreen: Bool = true) {
        self.id = id; self.pid = pid; self.frame = frame; self.layer = layer; self.onScreen = onScreen
    }
}

public enum WindowMatch: Equatable {
    case match(CaptureWindow)
    case notFound
    case ambiguous(Int)
}

public enum WindowMatcher {
    /// Matches the accessibility window to exactly one normal, on-screen window of the same
    /// process whose frame agrees within `tolerance` points. Refuses to guess between several.
    public static func match(pid: Int32, accessibilityFrame: CGRect, in windows: [CaptureWindow], tolerance: CGFloat = 4) -> WindowMatch {
        let hits = windows.filter { window in
            window.pid == pid && window.onScreen && window.layer == 0
                && abs(window.frame.minX - accessibilityFrame.minX) <= tolerance
                && abs(window.frame.minY - accessibilityFrame.minY) <= tolerance
                && abs(window.frame.width - accessibilityFrame.width) <= tolerance
                && abs(window.frame.height - accessibilityFrame.height) <= tolerance
        }
        switch hits.count {
        case 0: return .notFound
        case 1: return .match(hits[0])
        default: return .ambiguous(hits.count)
        }
    }

    /// Output size for a capture: native pixels, scaled down so the long edge is at most `maxLongEdge`.
    public static func outputSize(points: CGSize, pixelScale: CGFloat, maxLongEdge: CGFloat = 2048) -> CGSize {
        let native = CGSize(width: points.width * max(pixelScale, 0.1), height: points.height * max(pixelScale, 0.1))
        let factor = min(1, maxLongEdge / max(native.width, native.height, 1))
        return CGSize(width: max(1, (native.width * factor).rounded()), height: max(1, (native.height * factor).rounded()))
    }
}

// MARK: Visual proposals

/// What a future vision analyser may return: pixel boxes in the captured image.
public struct VisualCandidate: Equatable {
    public let label: String
    public let imageRect: CGRect
    public let confidence: Double
    public init(label: String, imageRect: CGRect, confidence: Double) {
        self.label = label; self.imageRect = imageRect; self.confidence = confidence
    }
}

/// A visual estimate mapped to screen points. It is never an accessibility control: it cannot be
/// re-validated live, so guidance must present it as unverified and leave the click to the user.
public struct VisualTarget: Equatable {
    public let label: String
    public let screenRect: CGRect
    public let confidence: Double
    public let verified = false
}

/// Analyses one in-memory window image. No implementation is configured yet.
public protocol VisualAnalyzer {
    func candidates(in image: CGImage, request: String) async throws -> [VisualCandidate]
}

public enum VisualProposals {
    /// Drops malformed, out-of-image, tiny or implausibly large boxes and out-of-range confidences,
    /// then keeps at most `limit`, highest confidence first.
    public static func validate(_ candidates: [VisualCandidate], geometry: CaptureGeometry, minimumConfidence: Double = 0.5, limit: Int = 5) -> [VisualTarget] {
        let imageArea = geometry.imageSize.width * geometry.imageSize.height
        let valid: [VisualTarget] = candidates.compactMap { candidate in
            let label = String(candidate.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
            guard !label.isEmpty, candidate.confidence.isFinite, (0...1).contains(candidate.confidence),
                  candidate.confidence >= minimumConfidence,
                  candidate.imageRect.width >= 4, candidate.imageRect.height >= 4,
                  candidate.imageRect.width * candidate.imageRect.height <= imageArea * 0.5,
                  let rect = geometry.screenRect(imageRect: candidate.imageRect) else { return nil }
            return VisualTarget(label: label, screenRect: rect, confidence: candidate.confidence)
        }
        return Array(valid.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }
}
