import CoreGraphics
import CoreText
import Foundation

/// A labelled box in image pixels (top-left origin), used for ground truth and predictions.
public struct LabeledBox: Equatable {
    public let label: String
    public let rect: CGRect
    public init(label: String, rect: CGRect) { self.label = label; self.rect = rect }
}

public struct EvaluationResult: Equatable {
    public let truePositives: Int
    public let predictions: Int
    public let truths: Int
    public let meanIoU: Double
    public var precision: Double { predictions == 0 ? 0 : Double(truePositives) / Double(predictions) }
    public var recall: Double { truths == 0 ? 0 : Double(truePositives) / Double(truths) }
}

/// Offline scoring for candidate vision models on synthetic or public screens.
/// A prediction counts only if its label matches and its box overlaps the truth enough.
public enum VisualEvaluation {
    public static func iou(_ a: CGRect, _ b: CGRect) -> Double {
        let overlap = a.intersection(b)
        guard !overlap.isNull, overlap.width > 0, overlap.height > 0 else { return 0 }
        let intersection = overlap.width * overlap.height
        return Double(intersection / (a.width * a.height + b.width * b.height - intersection))
    }

    public static func evaluate(predictions: [LabeledBox], truth: [LabeledBox], threshold: Double = 0.5) -> EvaluationResult {
        var unmatched = Array(truth.indices)
        var matchedIoU: [Double] = []
        for prediction in predictions {
            let wanted = Guidance.terms(prediction.label)
            let best = unmatched
                .filter { Guidance.terms(truth[$0].label) == wanted }
                .map { ($0, iou(prediction.rect, truth[$0].rect)) }
                .max { $0.1 < $1.1 }
            if let (index, overlap) = best, overlap >= threshold {
                unmatched.removeAll { $0 == index }
                matchedIoU.append(overlap)
            }
        }
        return EvaluationResult(truePositives: matchedIoU.count, predictions: predictions.count, truths: truth.count,
                                meanIoU: matchedIoU.isEmpty ? 0 : matchedIoU.reduce(0, +) / Double(matchedIoU.count))
    }
}

/// Renders a synthetic window (no real screen content) with known control boxes, so a vision
/// model can be evaluated without capturing anyone's screen. Rendering stays in memory.
public enum SyntheticScreen {
    public struct Control {
        public let label: String
        public let rect: CGRect   // points, top-left origin
        public init(label: String, rect: CGRect) { self.label = label; self.rect = rect }
    }

    public static func render(size: CGSize, scale: CGFloat = 2, controls: [Control]) -> (image: CGImage, truth: [LabeledBox])? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Draw in top-left point coordinates.
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        context.setFillColor(CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        var truth: [LabeledBox] = []
        for control in controls {
            context.setFillColor(CGColor(srgbRed: 0.27, green: 0.25, blue: 0.62, alpha: 1))
            context.fill(control.rect)
            let font = CTFontCreateWithName("Helvetica" as CFString, min(14, control.rect.height * 0.6), nil)
            let text = NSAttributedString(string: control.label, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)])
            let line = CTLineCreateWithAttributedString(text)
            context.saveGState()
            // Text is drawn upright: flip locally around the control's baseline.
            context.translateBy(x: control.rect.minX + 6, y: control.rect.midY + 5); context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero; CTLineDraw(line, context)
            context.restoreGState()
            truth.append(LabeledBox(label: control.label, rect: CGRect(x: control.rect.minX * scale, y: control.rect.minY * scale,
                                                                        width: control.rect.width * scale, height: control.rect.height * scale)))
        }
        guard let image = context.makeImage() else { return nil }
        return (image, truth)
    }
}
