# GuideCursor for macOS — first desktop milestone

This is the native desktop component of GuideCursor. The existing website stays at the repository root. Requires macOS 13 or later and Apple's Command Line Tools (`xcode-select --install` if absent).

## Build and run

From the repository root:

```sh
./macos/scripts/build.sh && open macos/build/GuideCursor.app
```

In the app, select **Enable access**, then enable GuideCursor under **System Settings → Privacy & Security → Accessibility**. The user must grant this permission. If macOS does not list it, add `macos/build/GuideCursor.app` with the + button. Local ad-hoc builds may require renewing permission after rebuilding. No screen-recording, microphone or camera permission is needed for this milestone.

1. Open an ordinary app window such as Finder.
2. Choose that application in GuideCursor.
3. Enter a control label such as “search” and select **Find controls**.
4. Review the returned candidates and choose **Guide me** for the intended one.
5. The chosen app comes forward. A click-through outline marks the actual control; a companion follows your cursor with movement directions. Speech can be disabled.
6. Move and click yourself. If a click near the target is detected, guidance stops and asks you to inspect the result. It does not claim the action succeeded. Search again for the next step or new window.
7. Stop at any time from GuideCursor's window (Escape) or its **GC** menu-bar menu. Quit with Command-Q while GuideCursor is active.

Switching applications hides the guidance. A changed window, unavailable control, disabled control or off-screen target stops it. The prototype does not perform clicks or move the system pointer.

## macOS magnification

Expand **macOS magnification** in GuideCursor. In System Settings → Accessibility → Zoom, enable **Use keyboard shortcuts to zoom** and retain Option–Command–8. Choose picture-in-picture in macOS if you want a magnified region near the pointer. Confirm the setup in GuideCursor, then use **Toggle macOS Zoom** in the window or GC menu.

GuideCursor sends the documented shortcut only after your setup confirmation and with Accessibility permission. It does not alter system preferences or infer whether Zoom turned on. The status reports that the shortcut was sent; verify the effect yourself. Custom shortcuts are not yet supported.

Reference: [Apple's Zoom setup instructions](https://support.apple.com/en-gb/guide/mac-help/mchl779716b8/mac).

## Optional local AI

Label search works without a model and is explicitly labelled **no AI**. It matches words in accessibility labels, not general tasks.

For AI-assisted target suggestions, install and run Ollama separately, download a suitable **local** model, disable Ollama cloud features, enable **Use a local Ollama model**, and enter its exact installed name. GuideCursor calls only `http://127.0.0.1:11434/api/chat`; it sends the task and up to 150 control labels/roles. It does not send screenshots, read field values, or retain a transcript. Labels may nevertheless contain document names or other personal information; use synthetic/public content for the course demo.

Model replies may only nominate IDs from that scan. The user confirms the target before guidance. Missing models, malformed replies and connection errors are shown explicitly; they are not silently presented as successful AI results. Model performance has not yet been validated. Local endpoint access alone does not guarantee that the independently configured Ollama service uses no cloud models.

## What this milestone implements

- Native AppKit/SwiftUI macOS app and an installable local `.app` bundle.
- Accessibility permission flow and selection of an existing application's window.
- Bounded background accessibility-tree traversal with labelled control candidates.
- Label search and optional local Ollama target-selection adapter.
- Click-through target highlight and pointer-following companion across displays.
- Real-time geometric directions using live target positions and system speech.
- Explicit user target confirmation, stop controls, and invalid-target handling.

## Limits and next milestones

This is a desktop foundation, not the completed course MVP. No automatic multi-step planning, screenshot fallback, voice input, pointer snapping, motor stabilization or live captions yet. Hearing remains TBD in the project draft. The first scope is visual guidance in a few selected desktop apps.

Some applications omit accessibility labels or expose only part of their interface. Duplicate labels require user selection. The app does not yet detect all occlusion, same-window content changes, or whether a click successfully completed an action. Movement guidance is not validated for blind users; conduct supervised testing before claiming accessibility outcomes. Relative-window regions distinguish duplicate labels but need validation with intended users.

Next: verify the native overlay and control discovery with permission on this Mac; test a local model; verify the optional macOS Zoom shortcut; complete and validate one multi-step desktop journey with synthetic data. Keep the working website as a presentation asset.

## Verification

```sh
swift run --package-path macos GuideCursorCoreChecks
./macos/scripts/build.sh
```

Core checks cover pointer directions, multi-display coordinate conversion, target regions, no-match handling and rejecting invented model IDs. Permission-dependent integration, speech quality and different applications require live testing. A successful build does not establish those behaviors.

API references: [Apple accessibility attributes](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), [click-through windows](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents), [Ollama chat API](https://docs.ollama.com/api/chat).
