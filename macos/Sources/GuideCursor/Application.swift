import AppKit
import SwiftUI

struct Content: View {
    @ObservedObject var model: Model
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("GuideCursor").font(.largeTitle.bold())
            Text("Use the same computer. Get the guidance you need.").foregroundColor(.secondary)
            HStack {
                Label(model.trusted ? "Accessibility enabled" : "Accessibility permission needed", systemImage: model.trusted ? "checkmark.shield" : "hand.raised")
                Spacer()
                Button("Enable access") { model.permission() }.disabled(model.trusted)
            }
            Divider()
            HStack {
                Picker("Application", selection: $model.selectedPID) {
                    Text("Choose an app").tag(Int32(0))
                    ForEach(model.apps, id: \.processIdentifier) { app in Text(app.localizedName ?? "App").tag(app.processIdentifier) }
                }.disabled(model.busy || model.guiding).onChange(of: model.selectedPID) { _ in model.stop(message: "Application changed. Find controls in this app.") }
                Button("Refresh") { model.refreshApps() }.disabled(model.busy || model.guiding)
            }
            TextField("What do you need? For example: find the search button", text: $model.request)
                .textFieldStyle(.roundedBorder).onSubmit { model.find() }
                .accessibilityLabel("Task or control to find")
            Toggle("Use a local Ollama model", isOn: $model.useAI).disabled(model.busy)
            if model.useAI {
                TextField("Installed model name", text: $model.modelName).textFieldStyle(.roundedBorder)
                Text("Sends your request and control labels to Ollama on this Mac. Use a locally running model with cloud features disabled. No screenshots are captured.").font(.caption).foregroundColor(.secondary)
            } else {
                Text("Label search matches control names. AI task interpretation requires a local model.").font(.caption).foregroundColor(.secondary)
            }
            Toggle("Speak movement directions", isOn: $model.speech).onChange(of: model.speech) { enabled in if !enabled { model.silence() } }
            DisclosureGroup("macOS magnification") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("In System Settings → Accessibility → Zoom, enable ‘Use keyboard shortcuts to zoom’. For magnification near the cursor, select the picture-in-picture Zoom style.").font(.callout)
                    Toggle("I have enabled the Option–Command–8 Zoom shortcut", isOn: $model.zoomShortcutConfirmed)
                    Button("Toggle macOS Zoom") { model.toggleZoom() }.disabled(!model.trusted || !model.zoomShortcutConfirmed)
                    Text("This sends the system shortcut. Your macOS Zoom settings determine the magnification style.").font(.caption).foregroundColor(.secondary)
                }.padding(.top, 8)
            }
            HStack {
                Button(model.busy ? "Finding…" : "Find controls") { model.find() }.keyboardShortcut(.return).disabled(model.busy || !model.trusted)
                Button("Stop") { model.stop() }.keyboardShortcut(.escape)
            }
            Text(model.status).font(.callout).fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(model.candidates) { control in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(control.label).fontWeight(.semibold)
                                Text("\(control.role.replacingOccurrences(of: "AX", with: "")) · \(control.region)").font(.caption).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("Guide me") { model.guide(control) }.accessibilityLabel("Guide me to \(control.label), \(control.region)")
                        }.padding(10).background(Color.primary.opacity(0.05)).cornerRadius(8)
                    }
                }
            }
            Text("Desktop prototype · You control every click. Optional Zoom uses your macOS settings. Snapping and screen-image recognition are not implemented in this milestone.").font(.caption).foregroundColor(.secondary)
        }.padding(24).frame(minWidth: 600, minHeight: 650)
    }
}
@MainActor final class Delegate: NSObject, NSApplicationDelegate {
    var model: Model!
    var window: NSWindow!
    var item: NSStatusItem!
    func applicationDidFinishLaunching(_ notification: Notification) {
        model = Model()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 650, height: 760), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "GuideCursor"; window.contentView = NSHostingView(rootView: Content(model: model)); window.center()
        window.isReleasedWhenClosed = false
        let statusMenu = NSMenu(title: "GuideCursor")
        statusMenu.addItem(withTitle: "Show GuideCursor", action: #selector(show), keyEquivalent: "") .target = self
        statusMenu.addItem(withTitle: "Stop guidance", action: #selector(stop), keyEquivalent: "") .target = self
        statusMenu.addItem(withTitle: "Toggle macOS Zoom", action: #selector(zoom), keyEquivalent: "") .target = self
        statusMenu.addItem(.separator())
        statusMenu.addItem(withTitle: "Quit GuideCursor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "GC"; item.menu = statusMenu
        let appMenu = NSMenu()
        let guideMenu = NSMenu(title: "GuideCursor")
        guideMenu.addItem(withTitle: "Show GuideCursor", action: #selector(show), keyEquivalent: "") .target = self
        guideMenu.addItem(withTitle: "Stop guidance", action: #selector(stop), keyEquivalent: ".") .target = self
        guideMenu.addItem(withTitle: "Toggle macOS Zoom", action: #selector(zoom), keyEquivalent: "") .target = self
        guideMenu.addItem(.separator())
        guideMenu.addItem(withTitle: "Quit GuideCursor", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let root = NSMenuItem(title: "GuideCursor", action: nil, keyEquivalent: "")
        root.submenu = guideMenu; appMenu.addItem(root)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit; appMenu.addItem(editItem)
        NSApp.mainMenu = appMenu
        show()
    }
    @objc func show() { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true) }
    @objc func stop() { model.stop() }
    @objc func zoom() { model.toggleZoom() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
}
@main struct GuideCursorApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = Delegate()
        app.setActivationPolicy(.regular)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}
