import AppKit
import CoreGraphics
import GuideCursorCore
import ScreenCaptureKit

/// One captured window, held in memory only. Never written to disk, logged or sent anywhere.
struct WindowImage {
    let image: CGImage
    let geometry: CaptureGeometry
}

enum CaptureError: Error, Equatable {
    case unsupportedSystem      // ScreenCaptureKit screenshots need macOS 14
    case staleScan              // app, request or window changed since the scan that produced the offer
    case permissionMissing
    case windowNotFound         // moved, resized, minimised or closed since the scan
    case ambiguousWindow(Int)
    case geometryMismatch
    case timedOut
    case failed(String)

    var message: String {
        switch self {
        case .unsupportedSystem: return "Screen images need macOS 14 or later."
        case .staleScan: return "The app, request or window changed since the last scan. Find controls again first."
        case .permissionMissing: return "Screen Recording permission is off. Allow GuideCursor in System Settings → Privacy & Security → Screen & System Audio Recording, then quit and reopen GuideCursor."
        case .windowNotFound: return "The window moved, changed size or was closed after the scan. Find controls again, then retry."
        case .ambiguousWindow(let count): return "\(count) windows match the scanned one, so GuideCursor will not guess. Close or move the extra window and retry."
        case .geometryMismatch: return "The captured image does not match the window's size, so its positions cannot be trusted. Nothing was kept."
        case .timedOut: return "The window image did not arrive in time, so GuideCursor stopped waiting. If it arrives later it is dropped unseen."
        case .failed(let reason): return "The window could not be captured (\(reason))."
        }
    }
}

enum ScreenAccess {
    /// Does not prompt.
    static var granted: Bool { CGPreflightScreenCaptureAccess() }
    /// Shows the system prompt (or adds GuideCursor to the settings list). Call only from an explicit user action.
    /// macOS usually applies a new grant only after GuideCursor is reopened.
    @discardableResult static func request() -> Bool { CGRequestScreenCaptureAccess() }
}

enum ScreenCapture {
    /// Captures only the scanned window, without the cursor, scaled to at most 2048 px on the long edge.
    ///
    /// Precondition for callers: `observation` must be read afresh (on the accessibility queue) right
    /// before calling: selected PID, current request text, whether the focused window is the scanned
    /// AXUIElement (CFEqual) and its current frame. A stale offer is refused before any capture call.
    ///
    /// GuideCursor stops waiting after `waitLimit` seconds, but ScreenCaptureKit offers no way to abort an
    /// in-flight screenshot: it may finish later, and that late image is released on arrival without use.
    static func captureWindow(offer: CaptureOffer, observation: CaptureOffer.Observation, waitLimit: TimeInterval = 5) async throws -> WindowImage {
        guard offer.isCurrent(observation) else { throw CaptureError.staleScan }
        guard #available(macOS 14.0, *) else { throw CaptureError.unsupportedSystem }
        // Preflight first: querying shareable content without permission can itself prompt.
        guard ScreenAccess.granted else { throw CaptureError.permissionMissing }
        let pid = offer.pid, frame = offer.windowFrame
        do {
            return try await BoundedWait.run(seconds: waitLimit) { try await capture(pid: pid, accessibilityFrame: frame) }
        } catch BoundedWaitError.timedOut {
            throw CaptureError.timedOut
        }
    }

    @available(macOS 14.0, *)
    private static func capture(pid: pid_t, accessibilityFrame: CGRect) async throws -> WindowImage {
        let content: SCShareableContent
        do { content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true) }
        catch { throw mapped(error) }
        let candidates = content.windows.compactMap { window -> (CaptureWindow, SCWindow)? in
            guard let owner = window.owningApplication else { return nil }
            return (CaptureWindow(id: window.windowID, pid: owner.processID, frame: window.frame,
                                  layer: window.windowLayer, onScreen: window.isOnScreen), window)
        }
        let window: SCWindow
        switch WindowMatcher.match(pid: pid, accessibilityFrame: accessibilityFrame, in: candidates.map(\.0)) {
        case .notFound: throw CaptureError.windowNotFound
        case .ambiguous(let count): throw CaptureError.ambiguousWindow(count)
        case .match(let hit): window = candidates.first { $0.0 == hit }!.1
        }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let configuration = SCStreamConfiguration()
        let size = WindowMatcher.outputSize(points: filter.contentRect.size, pixelScale: CGFloat(filter.pointPixelScale))
        configuration.width = Int(size.width); configuration.height = Int(size.height)
        configuration.showsCursor = false
        configuration.ignoreShadowsSingleWindow = true
        let image: CGImage
        do { image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) }
        catch { throw mapped(error) }
        guard let geometry = CaptureGeometry(windowFrame: window.frame, imageSize: CGSize(width: image.width, height: image.height)) else {
            throw CaptureError.geometryMismatch
        }
        return WindowImage(image: image, geometry: geometry)
    }

    private static func mapped(_ error: Error) -> CaptureError {
        let nsError = error as NSError
        if nsError.domain == SCStreamErrorDomain && nsError.code == SCStreamError.userDeclined.rawValue { return .permissionMissing }
        return .failed("\(nsError.domain) \(nsError.code)")
    }
}
