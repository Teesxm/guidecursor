import CoreGraphics
import Foundation
import Vision

/// A recognised word, in image pixels with a top-left origin.
public struct RecognizedWord: Equatable {
    public let text: String
    public let rect: CGRect
    public init(text: String, rect: CGRect) { self.text = text; self.rect = rect }
}

/// One line as Vision reports it. Vision may merge separate controls on the same baseline into one line.
public struct RecognizedLine: Equatable {
    public let text: String
    public let confidence: Double
    public let words: [RecognizedWord]
    public init(text: String, confidence: Double, words: [RecognizedWord]) {
        self.text = text; self.confidence = confidence; self.words = words
    }
}

public enum VisionGeometry {
    /// Vision's normalised rectangle (0...1, origin bottom-left) → image pixels (origin top-left).
    /// nil for empty, non-finite or out-of-image rectangles.
    public static func pixelRect(normalized r: CGRect, width: Int, height: Int) -> CGRect? {
        guard width > 0, height > 0, [r.minX, r.minY, r.width, r.height].allSatisfy(\.isFinite), r.width > 0, r.height > 0,
              r.minX >= -0.01, r.minY >= -0.01, r.maxX <= 1.01, r.maxY <= 1.01 else { return nil }
        let w = CGFloat(width), h = CGFloat(height)
        return CGRect(x: r.minX * w, y: (1 - r.maxY) * h, width: r.width * w, height: r.height * h)
    }
}

public enum TextMatcher {
    /// Splits each line into segments at large horizontal gaps (more than `gapFactor` × word height),
    /// since one segment is more likely to be one control's label. A segment qualifies only if it has
    /// the same name as the request (`Guidance.sameName`): visual matches are unverified, so a label
    /// with extra or missing words, such as "Don't Save" for "Save", is never suggested. All qualifying
    /// segments are returned so duplicates stay ambiguous.
    /// A segment is visible text, not a verified clickable control.
    public static func candidates(lines: [RecognizedLine], request: String, gapFactor: CGFloat = 0.8) -> [VisualCandidate] {
        var scored: [(score: Int, candidate: VisualCandidate)] = []
        for line in lines {
            var segment: [RecognizedWord] = []
            func flush() {
                defer { segment = [] }
                guard let first = segment.first else { return }
                let label = segment.map(\.text).joined(separator: " ")
                guard Guidance.sameName(request: request, label: label) else { return }
                let score = Guidance.score(request: request, label: label)
                let rect = segment.dropFirst().reduce(first.rect) { $0.union($1.rect) }
                scored.append((score, VisualCandidate(label: label, imageRect: rect, confidence: line.confidence)))
            }
            for word in line.words {
                if let last = segment.last, word.rect.minX - last.rect.maxX > gapFactor * max(last.rect.height, word.rect.height) { flush() }
                segment.append(word)
            }
            flush()
        }
        guard let best = scored.map(\.score).max() else { return [] }
        return scored.filter { $0.score == best }.map(\.candidate)
    }
}

/// On-device text recognition with Apple's Vision framework (built into macOS; no model download).
/// Recognition runs on a background queue; images stay in memory and are never written or sent.
public struct VisionTextAnalyzer: VisualAnalyzer {
    public enum Level: String, Sendable { case accurate, fast }
    public let level: Level
    public let languageCorrection: Bool
    public init(level: Level = .accurate, languageCorrection: Bool = false) { self.level = level; self.languageCorrection = languageCorrection }

    public func recognize(_ image: CGImage) async throws -> [RecognizedLine] {
        let level = level, correction = languageCorrection
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do { continuation.resume(returning: try Self.recognizeNow(image, level: level, languageCorrection: correction)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    public func candidates(in image: CGImage, request: String) async throws -> [VisualCandidate] {
        TextMatcher.candidates(lines: try await recognize(image), request: request)
    }

    /// Blocking; call off the main thread.
    static func recognizeNow(_ image: CGImage, level: Level, languageCorrection: Bool) throws -> [RecognizedLine] {
        guard image.width > 0, image.height > 0 else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = level == .accurate ? .accurate : .fast
        request.usesLanguageCorrection = languageCorrection
        try VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first else { return nil }
            let confidence = Double(best.confidence)
            let text = best.string
            guard confidence.isFinite, (0...1).contains(confidence),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            var words: [RecognizedWord] = []
            text.enumerateSubstrings(in: text.startIndex..<text.endIndex, options: .byWords) { word, range, _, _ in
                guard let word, let box = try? best.boundingBox(for: range),
                      let rect = VisionGeometry.pixelRect(normalized: box.boundingBox, width: image.width, height: image.height) else { return }
                words.append(RecognizedWord(text: word, rect: rect))
            }
            return words.isEmpty ? nil : RecognizedLine(text: text, confidence: confidence, words: words)
        }
    }
}
