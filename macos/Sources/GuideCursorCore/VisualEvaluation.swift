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
    public enum Style { case button, plain }
    public struct Control {
        public let label: String
        public let rect: CGRect   // points, top-left origin
        public let fontSize: CGFloat?
        public let style: Style
        public init(label: String, rect: CGRect, fontSize: CGFloat? = nil, style: Style = .button) {
            self.label = label; self.rect = rect; self.fontSize = fontSize; self.style = style
        }
    }

    /// `truth`: control boxes in image pixels. `text`: boxes of the drawn label text in image pixels.
    public static func render(size: CGSize, scale: CGFloat = 2, dark: Bool = false, controls: [Control])
        -> (image: CGImage, truth: [LabeledBox], text: [LabeledBox])? {
        let width = Int((size.width * scale).rounded()), height = Int((size.height * scale).rounded())
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Draw in top-left point coordinates.
        context.translateBy(x: 0, y: CGFloat(height)); context.scaleBy(x: scale, y: -scale)
        context.setFillColor(dark ? CGColor(srgbRed: 0.12, green: 0.12, blue: 0.14, alpha: 1) : CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))
        var truth: [LabeledBox] = [], text: [LabeledBox] = []
        func pixels(_ r: CGRect) -> CGRect { CGRect(x: r.minX * scale, y: r.minY * scale, width: r.width * scale, height: r.height * scale) }
        for control in controls {
            let ink: CGColor
            if control.style == .button {
                context.setFillColor(CGColor(srgbRed: 0.27, green: 0.25, blue: 0.62, alpha: 1))
                context.fill(control.rect)
                ink = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)
            } else {
                ink = dark ? CGColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1) : CGColor(srgbRed: 0.13, green: 0.13, blue: 0.15, alpha: 1)
            }
            let font = CTFontCreateWithName("Helvetica" as CFString, control.fontSize ?? min(14, control.rect.height * 0.6), nil)
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: control.label, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): ink]))
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let advance = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
            // Vertically centre the text; the baseline is in top-left coordinates.
            let baseline = control.rect.midY + (ascent - descent) / 2
            let origin = control.rect.minX + 6
            context.saveGState()
            context.translateBy(x: origin, y: baseline); context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero; CTLineDraw(line, context)
            context.restoreGState()
            truth.append(LabeledBox(label: control.label, rect: pixels(control.rect)))
            text.append(LabeledBox(label: control.label, rect: pixels(CGRect(x: origin, y: baseline - ascent, width: advance, height: ascent + descent))))
        }
        guard let image = context.makeImage() else { return nil }
        return (image, truth, text)
    }
}

extension VisualEvaluation {
    /// Guidance-oriented scoring: a prediction is a hit when its label matches and its centre lies
    /// inside a not-yet-matched control of that label (the place a user would click).
    public static func centreHits(predictions: [LabeledBox], controls: [LabeledBox]) -> EvaluationResult {
        var unmatched = Array(controls.indices), overlaps: [Double] = []
        for prediction in predictions {
            let wanted = Guidance.terms(prediction.label)
            let centre = CGPoint(x: prediction.rect.midX, y: prediction.rect.midY)
            if let index = unmatched.first(where: { Guidance.terms(controls[$0].label) == wanted && controls[$0].rect.contains(centre) }) {
                unmatched.removeAll { $0 == index }
                overlaps.append(iou(prediction.rect, controls[index].rect))
            }
        }
        return EvaluationResult(truePositives: overlaps.count, predictions: predictions.count, truths: controls.count,
                                meanIoU: overlaps.isEmpty ? 0 : overlaps.reduce(0, +) / Double(overlaps.count))
    }
}
