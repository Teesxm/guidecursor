import AppKit
import SwiftUI
@preconcurrency import ApplicationServices
import AVFoundation
import GuideCursorCore

@MainActor final class Model: ObservableObject {
    @Published var trusted = AXIsProcessTrusted()
    @Published var appName = "Choose an application"
    @Published var request = "" {
        // An offer belongs to the request it was scanned for; any edit needs a fresh scan.
        didSet { if request != oldValue { screenOffer = nil } }
    }
    @Published var modelName = ""
    @Published var useAI = false
    @Published var speech = true
    @Published var candidates: [Control] = []
    @Published var status = "Choose an app, enter a control to find, then review the matches."
    @Published var busy = false
    /// Counts-only summary of the last scan (no labels or screen text), for troubleshooting.
    @Published var scanDetails = ""
    @Published var guiding = false
    @Published var zoomShortcutConfirmed = false
    @Published var apps: [NSRunningApplication] = []
    @Published var selectedPID: Int32 = 0
    /// Kept for the future visual-guidance path; not shown and never captured from in this build.
    /// Cleared by stop() (app change, new scan) and by any request edit.
    private(set) var screenOffer: CaptureOffer?
    private let overlay = Overlay()
    private let voice = AVSpeechSynthesizer()
    private let reader = DispatchQueue(label: "guidecursor.accessibility")
    private var target: Control?
    private var window: AXUIElement?
    private var generation = 0
    private var checking = false
    private var timer: Timer?
    private var monitor: Any?
    private var lastSpoken = ""
    private var lastSpeechAt = Date.distantPast
    private var pollNumber = 0

    init() {
        refreshApps()
        timer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in
            Task { @MainActor [weak model = self] in model?.tick() }
        }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.guiding, let target = self.target,
                      NSWorkspace.shared.frontmostApplication?.processIdentifier == self.selectedPID,
                      let primary = NSScreen.screens.first else { return }
                let p = NSEvent.mouseLocation
                if target.rect.contains(CGPoint(x: p.x, y: primary.frame.height - p.y)) {
                    self.stop(message: "You clicked near the target. Check the result, then find the next control in the updated window.")
                }
            }
        }
    }
    func toggleZoom() { status = Magnification.sendToggle(shortcutConfirmed: zoomShortcutConfirmed) }
    func silence() { voice.stopSpeaking(at: .immediate); lastSpoken = "" }
    func refreshApps() {
        apps = NSWorkspace.shared.runningApplications.filter { $0.activationPolicy == .regular && $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }
            .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }
        if !apps.contains(where: { $0.processIdentifier == selectedPID }) { selectedPID = apps.first?.processIdentifier ?? 0 }
    }
    func permission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        trusted = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }
    func stop(message: String = "Guidance stopped.") {
        generation += 1; target = nil; window = nil; candidates = []; guiding = false; busy = false
        overlay.hide(); voice.stopSpeaking(at: .immediate); lastSpoken = ""; status = message
        screenOffer = nil
    }
    func copyScanDetails() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("GuideCursor scan details — " + scanDetails, forType: .string)
    }
    func find() {
        stop(); candidates = []; scanDetails = ""
        guard AXIsProcessTrusted() else { trusted = false; status = Diagnostics.message(.permissionMissing, appName: "", stats: ScanStats(window: .permissionDenied)); return }
        guard let app = apps.first(where: { $0.processIdentifier == selectedPID }) else { status = "Choose an open application."; return }
        guard !app.isTerminated else { status = Diagnostics.message(.appUnavailable, appName: app.localizedName ?? "That app", stats: ScanStats(window: .appUnavailable)); return }
        guard !request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Enter the control or task you need help with."; return }
        guard useAI || !Guidance.terms(request).isEmpty else { status = Diagnostics.message(.unsearchableRequest, appName: "", stats: ScanStats(window: .found)); return }
        guard !useAI || !modelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { status = "Enter the name of a downloaded local Ollama model."; return }
        busy = true; appName = app.localizedName ?? "Application"; status = "Reading controls in \(appName)…"
        let token = generation, pid = selectedPID, query = request, ai = useAI, model = modelName
        reader.async {
            let result = Accessibility.scan(pid: pid)
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.window = result.window
                self.scanDetails = Diagnostics.summary(result.stats, appName: self.appName)
                let usable = result.stats.window == .found && !result.controls.isEmpty
                if usable && ai {
                    self.status = "Asking your local model to suggest targets…"
                    do {
                        let ids = try await Ollama.select(request: query, controls: result.controls, model: model)
                        guard self.generation == token else { return }
                        self.candidates = ids.compactMap { id in result.controls.first { $0.id == id } }
                    } catch {
                        guard self.generation == token else { return }
                        self.busy = false; self.status = "Local AI failed: \(error.localizedDescription) You can switch to label search."; return
                    }
                } else if usable {
                    self.candidates = result.controls.filter { Guidance.score(request: query, label: $0.label) > 0 }
                        .sorted { Guidance.score(request: query, label: $0.label) > Guidance.score(request: query, label: $1.label) }.prefix(12).map { $0 }
                }
                self.busy = false
                let diagnosis = Diagnostics.diagnose(trusted: AXIsProcessTrusted(), stats: result.stats, request: query,
                                                     matches: self.candidates.count, usedModel: ai)
                if diagnosis == .permissionMissing { self.trusted = false }
                if case .matches = diagnosis {
                    self.status = "Choose the intended control below. \(ai ? "Local AI suggestions" : "Label search — no AI used")."
                    if result.stats.incomplete { self.status += " " + Diagnostics.incompleteNote(result.stats) }
                } else {
                    self.status = Diagnostics.message(diagnosis, appName: self.appName, stats: result.stats)
                }
                // Edits during the scan already cleared the offer; do not attach this scan to a newer request.
                self.screenOffer = self.request == query && self.selectedPID == pid
                    ? CaptureOffer(decision: ScreenFallback.decide(diagnosis, stats: result.stats), pid: pid, request: query, windowFrame: result.windowFrame)
                    : nil
            }
        }
    }
    func guide(_ control: Control) {
        guard let app = NSRunningApplication(processIdentifier: selectedPID), !app.isTerminated else { stop(message: "That app has closed. Refresh the application list."); return }
        guard let storedWindow = window else { stop(message: "The selected window or control changed. Find controls again before guiding."); return }
        // Accessibility reads can block on the other app, so validate on the background queue.
        generation += 1; busy = true; status = "Checking \(control.label)…"
        let token = generation, pid = selectedPID
        reader.async {
            let activeWindow = Accessibility.focusedWindow(pid)
            let valid = activeWindow.map { CFEqual(storedWindow, $0) } == true
                && Accessibility.enabled(control.element) && Accessibility.rect(control.element) != nil
            Task { @MainActor [weak self] in
                guard let self, self.generation == token else { return }
                self.busy = false
                guard valid else { self.stop(message: "The selected window or control changed. Find controls again before guiding."); return }
                self.generation += 1; self.target = control; self.guiding = true; self.lastSpoken = ""
                self.status = "Guiding to \(control.label). You move and click. Stop with the menu bar or this window."
                app.activate(options: [.activateIgnoringOtherApps])
            }
        }
    }
    private func tick() {
        pollNumber += 1
        if pollNumber % 6 == 0 { trusted = AXIsProcessTrusted() }
        guard guiding, let current = target else { return }
        guard trusted else { stop(message: "Accessibility permission was removed. Guidance stopped."); return }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == selectedPID else {
            overlay.hide(); voice.stopSpeaking(at: .immediate); lastSpoken = ""; return
        }
        guard !checking else { return }
        checking = true
        let token = generation, pid = selectedPID, expectedWindow = window
        reader.async {
            let activeWindow = Accessibility.focusedWindow(pid)
            let frame = Accessibility.rect(current.element)
            let enabled = Accessibility.enabled(current.element)
            let sameWindow = expectedWindow != nil && activeWindow != nil && CFEqual(expectedWindow!, activeWindow!)
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.checking = false
                guard self.generation == token, self.guiding else { return }
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { self.overlay.hide(); return }
                guard sameWindow, enabled, let frame else { self.stop(message: "The window or control changed. Find the next control before continuing."); return }
                guard let primary = NSScreen.screens.first else { return }
                let rect = Guidance.appKitRect(frame, primaryHeight: primary.frame.height)
                guard NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) else { self.stop(message: "The target is off screen. Bring it into view and search again."); return }
                self.target = Control(id: current.id, label: current.label, role: current.role, region: current.region, element: current.element, rect: frame)
                let p = NSEvent.mouseLocation
                let instruction = Guidance.direction(pointer: CGPoint(x: p.x, y: primary.frame.height - p.y), target: frame)
                self.overlay.show(rect: rect, label: current.label, direction: instruction)
                if self.speech && instruction != self.lastSpoken && Date().timeIntervalSince(self.lastSpeechAt) > 1.5 {
                    self.voice.stopSpeaking(at: .immediate)
                    let utterance = AVSpeechUtterance(string: instruction)
                    utterance.rate = 0.45; self.voice.speak(utterance)
                    self.lastSpoken = instruction; self.lastSpeechAt = Date()
                }
            }
        }
    }
}
