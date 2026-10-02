import CoreGraphics
import Foundation
import GuideCursorCore
import ImageIO

// Offline benchmark of on-device text location on generated screens only (no screen capture).
// Usage: swift run -c release --package-path macos GuideCursorVisionBench [repeats] [--lines]
// --lines prints what Vision returned for each generated screen (synthetic text only).
// --correction enables Vision's language correction (off by default).
// --png DIR writes each generated screen as a PNG for inspection (never real screen content).

typealias C = SyntheticScreen.Control
/// `absent`: requests whose correct answer is no suggestion (the named control is not on screen,
/// although labels containing its words may be). Any suggestion for them lowers precision.
struct Screen { let name: String; let size: CGSize; let scale: CGFloat; let dark: Bool; let controls: [C]; var absent: [String] = [] }

func row(_ labels: [String], y: CGFloat, x: CGFloat = 16, gap: CGFloat = 14, height: CGFloat = 28, font: CGFloat? = nil) -> [C] {
    var left = x
    return labels.map { label in
        let width = CGFloat(label.count) * 8.5 + 24
        defer { left += width + gap }
        return C(label: label, rect: CGRect(x: left, y: y, width: width, height: height), fontSize: font)
    }
}
func list(_ labels: [String], x: CGFloat, y: CGFloat, step: CGFloat = 24, font: CGFloat = 13) -> [C] {
    labels.enumerated().map { i, label in
        C(label: label, rect: CGRect(x: x, y: y + CGFloat(i) * step, width: 190, height: step - 2), fontSize: font, style: .plain)
    }
}

let screens: [Screen] = [
    Screen(name: "toolbar (one baseline)", size: CGSize(width: 900, height: 120), scale: 2, dark: false,
           controls: row(["Back", "Forward", "Search", "Share", "New Folder", "Downloads"], y: 20), absent: ["Folder"]),
    Screen(name: "opposite actions only", size: CGSize(width: 560, height: 260), scale: 2, dark: false,
           controls: row(["Don't Save", "Don't Delete", "Cancel"], y: 190, x: 120)
               + [C(label: "Save as PDF", rect: CGRect(x: 20, y: 40, width: 140, height: 22), fontSize: 13, style: .plain),
                  C(label: "Deleted items", rect: CGRect(x: 20, y: 80, width: 160, height: 22), fontSize: 13, style: .plain)],
           absent: ["Save", "Delete"]),
    Screen(name: "sidebar list", size: CGSize(width: 400, height: 360), scale: 2, dark: false,
           controls: list(["Recents", "Applications", "Desktop", "Documents", "Downloads", "iCloud Drive", "Shared", "Trash"], x: 12, y: 20)),
    Screen(name: "dialog with duplicates", size: CGSize(width: 520, height: 300), scale: 2, dark: false,
           controls: row(["Save", "Don't Save", "Cancel"], y: 230, x: 160)
               + [C(label: "Save", rect: CGRect(x: 20, y: 40, width: 70, height: 28)),
                  C(label: "Save as PDF", rect: CGRect(x: 20, y: 100, width: 130, height: 22), fontSize: 13, style: .plain)]),
    Screen(name: "dark, small, 1x", size: CGSize(width: 600, height: 300), scale: 1, dark: true,
           controls: list(["Inbox", "Drafts", "Sent", "Archive", "Junk"], x: 12, y: 16, step: 20, font: 11)
               + row(["Reply", "Forward", "Attach file", "Send"], y: 250, x: 220, height: 24, font: 12)),
    Screen(name: "dense file list", size: CGSize(width: 520, height: 480), scale: 2, dark: false,
           controls: list(["Invoice 2026.pdf", "Downloads", "Download log.txt", "Budget draft.numbers", "Photos",
                           "Project plan.pages", "Notes.txt", "Old downloads", "Reading list", "Receipts",
                           "Recipes", "Résumé.pdf", "Screenshots", "Settings backup", "Travel", "Videos"], x: 16, y: 16, step: 26, font: 12))
]

func median(_ values: [Double]) -> Double { let s = values.sorted(); return s[s.count / 2] }
let repeats = CommandLine.arguments.dropFirst().compactMap(Int.init).first ?? 5
let showLines = CommandLine.arguments.contains("--lines")
let correction = CommandLine.arguments.contains("--correction")
let pngDirectory = CommandLine.arguments.firstIndex(of: "--png").flatMap { i in
    CommandLine.arguments.indices.contains(i + 1) ? URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true) : nil
}
func writePNG(_ image: CGImage, named name: String) {
    guard let directory = pngDirectory else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let url = directory.appendingPathComponent(name.filter { $0.isLetter || $0.isNumber || $0 == " " } + ".png")
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
    CGImageDestinationAddImage(destination, image, nil); CGImageDestinationFinalize(destination)
}

func run() async throws {
    var info = utsname(); uname(&info)
    let machine = withUnsafeBytes(of: &info.machine) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
    var size = 0; sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
    var brand = [CChar](repeating: 0, count: size); sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0)
    print("System: \(String(cString: brand)) (\(machine)), \(ProcessInfo.processInfo.physicalMemory >> 30) GB, \(ProcessInfo.processInfo.operatingSystemVersionString)")
    print("Repeats per screen/level: \(repeats) (after one warm-up). Language correction: \(correction ? "on" : "off"). Requests: every distinct label on each screen, plus absent requests that must return nothing.\n")

    var cold: [String: Double] = [:]
    for level in [VisionTextAnalyzer.Level.accurate, .fast] {
        let analyzer = VisionTextAnalyzer(level: level, languageCorrection: correction)
        var hits = 0, predictions = 0, expected = 0, exactRequests = 0, requests = 0, ambiguousOK = 0, ambiguous = 0
        var ious: [Double] = [], latencies: [Double] = []
        print("== \(level.rawValue)")
        for screen in screens {
            guard let rendered = SyntheticScreen.render(size: screen.size, scale: screen.scale, dark: screen.dark, controls: screen.controls) else { continue }
            if level == .accurate { writePNG(rendered.image, named: screen.name) }
            let start = Date(); let lines = try await analyzer.recognize(rendered.image)
            if cold[level.rawValue] == nil { cold[level.rawValue] = Date().timeIntervalSince(start) * 1000 }
            var times: [Double] = []
            for _ in 0..<repeats {
                let t = Date(); _ = try await analyzer.recognize(rendered.image); times.append(Date().timeIntervalSince(t) * 1000)
            }
            latencies += times
            if showLines {
                for line in lines {
                    print("    line \"\(line.text)\" conf \(line.confidence): " + line.words.map { "\($0.text)@\(Int($0.rect.minX))-\(Int($0.rect.maxX))" }.joined(separator: " "))
                }
            }
            var screenHits = 0, screenExpected = 0, screenPredictions = 0, misses: [String] = []
            for label in Set(screen.controls.map(\.label)).sorted() + screen.absent {
                let wanted = rendered.truth.indices.filter { Guidance.terms(rendered.truth[$0].label) == Guidance.terms(label) }
                let found = TextMatcher.candidates(lines: lines, request: label)
                let boxes = found.map { LabeledBox(label: $0.label, rect: $0.imageRect) }
                let score = VisualEvaluation.centreHits(predictions: boxes, controls: wanted.map { rendered.truth[$0] })
                let text = VisualEvaluation.evaluate(predictions: boxes, truth: wanted.map { rendered.text[$0] })
                if text.truePositives > 0 { ious.append(text.meanIoU) }
                screenHits += score.truePositives; screenExpected += wanted.count; screenPredictions += found.count
                requests += 1
                if score.truePositives == wanted.count && found.count == wanted.count { exactRequests += 1 } else { misses.append("\(label)→\(found.map(\.label))") }
                if wanted.count > 1 { ambiguous += 1; if score.truePositives == wanted.count && found.count == wanted.count { ambiguousOK += 1 } }
            }
            hits += screenHits; expected += screenExpected; predictions += screenPredictions
            print(String(format: "  %-24@ %4dx%-4d  found %2d/%-2d  extra %d  median %6.1f ms  max %6.1f ms%@",
                         screen.name as NSString, rendered.image.width, rendered.image.height, screenHits, screenExpected,
                         screenPredictions - screenHits, median(times), times.max() ?? 0,
                         (misses.isEmpty ? "" : "  misses: " + misses.joined(separator: "; ")) as NSString))
        }
        print(String(format: "  TOTAL requests exactly right %d/%d · recall %.3f · precision %.3f · duplicate-label requests %d/%d · mean text-box IoU %.3f · median %.1f ms · first call at this level %.0f ms\n",
                     exactRequests, requests, Double(hits) / Double(max(expected, 1)), Double(hits) / Double(max(predictions, 1)),
                     ambiguousOK, ambiguous, ious.isEmpty ? 0 : ious.reduce(0, +) / Double(ious.count), median(latencies), cold[level.rawValue] ?? 0))
    }
}

let finished = DispatchSemaphore(value: 0)
Task.detached { do { try await run() } catch { print("Benchmark failed: \(error)") }; finished.signal() }
finished.wait()
