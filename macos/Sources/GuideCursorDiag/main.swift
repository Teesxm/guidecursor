import Foundation
import GuideCursorCore

// Client for GuideCursor's opt-in development diagnostics connection. It has no permissions of its
// own: every live result comes from the running GuideCursor app and its own Accessibility grant.
//
//   swift run --package-path macos GuideCursorDiag status
//   swift run --package-path macos GuideCursorDiag scan [--selection N | --no-selection-check]
//       By default the client first asks for status and sends the selection generation it observed, so the
//       app refuses the scan (stale_selection) if the selected app or request changed in between.
//   swift run --package-path macos GuideCursorDiag self-check
//   swift run --package-path macos GuideCursorDiag fixture
//   options: --socket PATH (default: the per-user path the app uses), --compact
//
// Exit codes: 0 ok, 2 the app refused or reported an error, 3 no diagnostics connection, 64 usage.

var arguments = Array(CommandLine.arguments.dropFirst())
func option(_ name: String) -> String? {
    guard let i = arguments.firstIndex(of: name), arguments.indices.contains(i + 1) else { return nil }
    defer { arguments.removeSubrange(i...(i + 1)) }
    return arguments[i + 1]
}
let socket = option("--socket") ?? DiagnosticsPaths.defaultSocket
func usage() -> Never {
    FileHandle.standardError.write(Data("usage: GuideCursorDiag status|scan [--selection N | --no-selection-check]|self-check|fixture [--socket PATH] [--compact]\n".utf8))
    exit(64)
}
let selectionText = option("--selection")
let explicitSelection: Int?
if let selectionText {
    guard let value = Int(selectionText), value >= 0 else { usage() }   // never silently drop an invalid check
    explicitSelection = value
} else { explicitSelection = nil }
let skipSelectionCheck = arguments.contains("--no-selection-check"); arguments.removeAll { $0 == "--no-selection-check" }
let compact = arguments.contains("--compact"); arguments.removeAll { $0 == "--compact" }
let commands = ["status": "status", "scan": "scan", "self-check": "self_check", "fixture": "fixture"]
guard arguments.count == 1, let command = commands[arguments[0]] else { usage() }
if command != "scan" && (explicitSelection != nil || skipSelectionCheck) { usage() }
if explicitSelection != nil && skipSelectionCheck { usage() }
func send(_ fields: [String: Any]) throws -> Data {
    try DiagnosticsClient.send(try JSONSerialization.data(withJSONObject: fields), path: socket)
}
var request: [String: Any] = ["v": DiagnosticsProtocol.version, "cmd": command]
do {
    if command == "scan" && !skipSelectionCheck {
        if let explicitSelection {
            request["selection"] = explicitSelection
        } else {
            // Tie the scan to the selection observed just now.
            let status = try JSONSerialization.jsonObject(with: try send(["v": DiagnosticsProtocol.version, "cmd": "status"])) as? [String: Any]
            guard let selected = status?["selected"] as? [String: Any], let generation = selected["selection_generation"] as? Int else {
                FileHandle.standardError.write(Data("Could not read the selection from status; retry, or pass --no-selection-check.\n".utf8)); exit(2)
            }
            request["selection"] = generation
        }
    }
    let response = try send(request)
    guard let object = try? JSONSerialization.jsonObject(with: response) as? [String: Any] else {
        FileHandle.standardError.write(Data("GuideCursor closed the connection without a reply (diagnostics may have been turned off).\n".utf8)); exit(3)
    }
    let output = try JSONSerialization.data(withJSONObject: object, options: compact ? [.sortedKeys] : [.prettyPrinted, .sortedKeys])
    print(String(decoding: output, as: UTF8.self))
    exit(object["ok"] as? Bool == true ? 0 : 2)
} catch {
    FileHandle.standardError.write(Data("No diagnostics connection at \(socket). Open GuideCursor, expand Developer diagnostics and turn on the session connection. (\(error))\n".utf8))
    exit(3)
}
