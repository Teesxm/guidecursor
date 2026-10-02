import AppKit
import ApplicationServices
import GuideCursorCore
import Security

/// Identity of the running binary, enough to tell the installed app from source builds and other copies.
struct BuildIdentity: Encodable {
    let version: String
    let revision: String          // stamped by build.sh; "unknown" for `swift run` builds
    let dirty: Bool?              // uncommitted changes under macos/ at build time
    let builtAt: String?
    let signingRequested: String? // what build.sh was asked to use
    let signature: String         // observed: "ad_hoc", "identity" or "unsigned"
    let teamId: String?
    let cdhash: String?
    let designatedRequirement: String?
    let bundlePath: String
    let bundleIdentifier: String?

    static func current() -> BuildIdentity {
        let info = Bundle.main.infoDictionary ?? [:]
        var signature = "unsigned", teamId: String?, cdhash: String?, requirement: String?
        var code: SecCode?, staticCode: SecStaticCode?
        if SecCodeCopySelf([], &code) == errSecSuccess, let code, SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode {
            var raw: CFDictionary?
            if SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &raw) == errSecSuccess,
               let details = raw as? [String: Any] {
                cdhash = (details[kSecCodeInfoUnique as String] as? Data)?.map { String(format: "%02x", $0) }.joined()
                teamId = details[kSecCodeInfoTeamIdentifier as String] as? String
                let flags = (details[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
                if cdhash != nil { signature = flags & 0x2 != 0 ? "ad_hoc" : "identity" }   // 0x2 = kSecCodeSignatureAdhoc
            }
            var designated: SecRequirement?, text: CFString?
            if SecCodeCopyDesignatedRequirement(staticCode, [], &designated) == errSecSuccess, let designated,
               SecRequirementCopyString(designated, [], &text) == errSecSuccess { requirement = text as String? }
        }
        return BuildIdentity(
            version: info["CFBundleShortVersionString"] as? String ?? "unknown",
            revision: info["GCSourceRevision"] as? String ?? "unknown",
            dirty: (info["GCSourceDirty"] as? String).flatMap { $0 == "true" ? true : $0 == "false" ? false : nil },
            builtAt: info["GCBuildDate"] as? String,
            signingRequested: info["GCSigningRequested"] as? String,
            signature: signature, teamId: teamId, cdhash: cdhash, designatedRequirement: requirement,
            bundlePath: Bundle.main.bundlePath, bundleIdentifier: Bundle.main.bundleIdentifier)
    }

    var compact: String {
        let rev = revision == "unknown" ? "unknown revision" : String(revision.prefix(7)) + (dirty == true ? "+dirty" : "")
        return "\(rev) · \(signature.replacingOccurrences(of: "_", with: "-")) · cdhash \(cdhash.map { String($0.prefix(10)) } ?? "none")"
    }
}

/// Session-only, opt-in local diagnostics connection served by the running app itself, so live
/// results reflect this binary's own Accessibility grant. Read-only: it never clicks, activates
/// other apps, moves the pointer, captures the screen or changes settings.
@MainActor final class DiagnosticsBridge: ObservableObject {
    @Published private(set) var enabled = false
    @Published private(set) var detail = "Off. Nothing is listening."
    let identity = BuildIdentity.current()
    let socketPath = DiagnosticsPaths.defaultSocket
    private var server: DiagnosticsServer?
    private unowned let model: Model
    /// Shared with the Model, which reports user work and selection changes to it.
    private var coordinator: DiagnosticsCoordinator { model.diagnostics }

    init(model: Model) { self.model = model }

    func setEnabled(_ on: Bool) {
        if on == enabled { return }
        if on {
            let session = coordinator.enable()
            let server = DiagnosticsServer(path: socketPath) { [weak self] data in
                await self?.handle(data) ?? DiagnosticsProtocol.error(.disabled, session: nil)
            }
            do {
                try server.start()
                self.server = server; enabled = true
                detail = "On for this session (\(session)). Read-only status and counts-only scans at \(socketPath). Turn off to close it immediately."
            } catch {
                coordinator.disable(); detail = "Could not open the diagnostics connection (\(error)). It stays off."
            }
        } else {
            server?.stop(); server = nil; coordinator.disable(); enabled = false
            detail = "Off. Nothing is listening."
        }
    }

    // MARK: Requests

    private struct Session: Encodable { let id: String?; let enabledAt: Date?; let requests: Int }
    private struct Selected: Encodable { let bundleId: String?; let pid: Int32; let running: Bool; let selectionGeneration: Int; let requestPresent: Bool }
    private struct Engines: Encodable { let overlayPanelsVisible: Bool; let speechEnabled: Bool; let speakingNow: Bool; let utterancesStarted: Int }
    private struct Status: Encodable {
        let ok = true; let schema = DiagnosticsProtocol.version; let command = "status"
        let session: Session; let build: BuildIdentity
        let accessibilityTrusted: Bool
        let selected: Selected
        let lastScan: ScanReport?
        let guidance: GuidanceHealth
        let engines: Engines
        let notes = [
            "accessibility_trusted is AXIsProcessTrusted() for this exact binary (see build.cdhash). If System Settings shows an enabled GuideCursor entry while this is false, that entry is not being applied to this binary; which build or signature it was granted to cannot be determined from here.",
            "engines.* and guidance.* are engine state, not proof that the user saw or heard guidance."
        ]
    }
    private struct ScanResponse: Encodable {
        let ok = true; let schema = DiagnosticsProtocol.version; let command: String; let session: String?
        let accessibilityTrusted: Bool; let report: ScanReport
        let expectedOwnControlsFound: Int?; let expectedOwnControlsTotal: Int?
    }
    private struct FixtureResponse: Encodable {
        let ok = true; let schema = DiagnosticsProtocol.version; let command = "fixture"; let session: String?
        let fixtures: DiagnosticFixtures.Report
    }

    func handle(_ data: Data) async -> Data {
        guard let session = coordinator.session else { return DiagnosticsProtocol.error(.disabled, session: nil) }
        let request: DiagnosticsRequest
        switch DiagnosticsProtocol.parse(data) {
        case .success(let parsed): request = parsed
        case .failure(let error): return DiagnosticsProtocol.error(error, session: session)
        }
        let admission: Admission
        switch coordinator.admit(request, hasSelection: model.selectedApp != nil,
                                 selectionGeneration: model.selectionGeneration, guiding: model.guiding) {
        case .success(let admitted): admission = admitted
        case .failure(let refused): return DiagnosticsProtocol.error(refused, session: session)
        }
        switch request.command {
        case .status:
            return DiagnosticsProtocol.encode(status())
        case .fixture:
            return DiagnosticsProtocol.encode(FixtureResponse(session: session, fixtures: DiagnosticFixtures.run()))
        case .scan, .selfCheck:
            guard let work = request.command == .scan ? model.diagnosticScanWork() : model.diagnosticSelfCheckWork() else {
                coordinator.abandon(admission)
                return DiagnosticsProtocol.error(.noSelection, session: session)
            }
            // Session, user-work and selection checks happen when the AX work ends; a stale result is dropped.
            switch await coordinator.runLive(admission, waitLimit: 8, work: work) {
            case .failure(let error):
                return DiagnosticsProtocol.error(error, session: error == .disabled ? nil : session)
            case .success(let outcome):
                return DiagnosticsProtocol.encode(ScanResponse(command: request.command.rawValue, session: session,
                                                               accessibilityTrusted: AXIsProcessTrusted(), report: outcome.report,
                                                               expectedOwnControlsFound: outcome.expectedOwnControlsFound,
                                                               expectedOwnControlsTotal: outcome.expectedOwnControlsTotal))
            }
        }
    }

    private func status() -> Status {
        let app = model.selectedApp
        return Status(
            session: Session(id: coordinator.session, enabledAt: coordinator.enabledAt, requests: coordinator.requests),
            build: identity, accessibilityTrusted: AXIsProcessTrusted(),
            selected: Selected(bundleId: app?.bundleIdentifier, pid: model.selectedPID, running: app.map { !$0.isTerminated } ?? false,
                               selectionGeneration: model.selectionGeneration,
                               requestPresent: !model.request.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty),
            lastScan: model.lastScanReport, guidance: model.health,
            engines: Engines(overlayPanelsVisible: model.overlayVisible, speechEnabled: model.speech,
                             speakingNow: model.speakingNow, utterancesStarted: model.utterancesStarted))
    }
}
