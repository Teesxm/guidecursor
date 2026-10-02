# GuideCursor for macOS — first desktop milestone

This is the native desktop component of GuideCursor. The existing website stays at the repository root. Requires macOS 13 or later and Apple's Command Line Tools (`xcode-select --install` if absent).

## Build and run

From the repository root:

```sh
./macos/scripts/build.sh && open ~/Library/Caches/nl.guidecursor.prototype/build/GuideCursor.app
```

The script compiles in the repository, but assembles, signs and zips the app in a temporary folder, verifies the signature of the bundle and of a freshly extracted ZIP copy, then installs both to `~/Library/Caches/nl.guidecursor.prototype/build/` (override with `GUIDECURSOR_OUT`, which must be outside Documents/Desktop/iCloud). It refuses to replace a copy that is running from that folder and never touches `~/Applications`. Do not copy the app back into Documents: the file provider adds Finder metadata within seconds, and strict signature checks then fail. Share `GuideCursor-macOS-prototype.zip` instead. The ZIP bytes differ between runs because of timestamps.

In the app, select **Enable access**, then enable GuideCursor under **System Settings → Privacy & Security → Accessibility**. The user must grant this permission. If macOS does not list it, add the built app (path above) with the + button. Local ad-hoc builds may require renewing permission after rebuilding. Accessibility guidance needs no Screen Recording, microphone or camera permission. This build never requests Screen Recording.

1. Open an ordinary app window such as Finder.
2. Choose that application in GuideCursor.
3. Enter a control label such as “search” and select **Find controls**.
4. Review the returned candidates and choose **Guide me** for the intended one.
5. The chosen app comes forward. A click-through outline marks the actual control; a companion follows your cursor with movement directions. Speech can be disabled.
6. Move and click yourself. If a click near the target is detected, guidance stops and asks you to inspect the result. It does not claim the action succeeded. Search again for the next step or new window.
7. Stop at any time from GuideCursor's window (Escape) or its **GC** menu-bar menu. Quit with Command-Q while GuideCursor is active.

If nothing is found, the status line names the first cause to fix: missing or outdated Accessibility permission, the app has quit, no open window, the app did not respond in time, the window exposes no named controls, the request has no searchable words, or no named control matched. If the scan stopped early (element, time or depth limit, or failed reads) that is stated, because the control may exist but was not read; when nothing named was read from a partial scan, GuideCursor says the window could not be fully read rather than that the app exposes no controls. A **Scan details** line shows counts only (elements read, named/unnamed controls by role, duration, stop reasons) and can be copied for troubleshooting; it never includes labels or other screen text. Nothing is logged to disk.

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
- Bounded background accessibility-tree traversal with labelled control candidates, including text nested in standard rows and cells.
- Label search and optional local Ollama target-selection adapter.
- Click-through target highlight and pointer-following companion across displays.
- Real-time geometric directions using live target positions and system speech.
- Explicit user target confirmation, stop controls, and invalid-target handling.

## Limits and next milestones

This is a desktop foundation, not the completed course MVP. No automatic multi-step planning, screen-image recognition, voice input, pointer snapping, motor stabilization or live captions yet. Hearing remains TBD in the project draft. The first scope is visual guidance in a few selected desktop apps.

Control discovery uses shared macOS accessibility roles and hierarchy, with no app-specific rules. It should transfer to other apps that expose their controls through the accessibility API, but coverage is not universal. Some applications omit accessibility labels or expose only part of their interface; recognising controls in a screen image is future work (see below). Duplicate labels require user selection. The app does not yet detect all occlusion, same-window content changes, or whether a click successfully completed an action. Movement guidance is not validated for blind users; conduct supervised testing before claiming accessibility outcomes. Relative-window regions distinguish duplicate labels but need validation with intended users.

Next: verify the native overlay and control discovery with permission on this Mac; test a local model; verify the optional macOS Zoom shortcut; complete and validate one multi-step desktop journey with synthetic data. Keep the working website as a presentation asset.

## Verification

```sh
swift run --package-path macos GuideCursorCoreChecks
./macos/scripts/build.sh
```

Core checks cover pointer directions, multi-display coordinate conversion, target regions, no-match and shared-stem matching (“download” finds “Downloads”), rejecting invented model IDs, generic accessibility-tree cases for nested row text and labelled buttons, diagnosis ordering, incomplete-scan messages, and the rule that diagnostics contain no screen text. Permission-dependent integration, speech quality and different applications require live testing. A successful build does not establish those behaviors.

API references: [Apple accessibility attributes](https://developer.apple.com/documentation/applicationservices/1462085-axuielementcopyattributevalue), [NSPanel](https://developer.apple.com/documentation/appkit/nspanel), [click-through windows](https://developer.apple.com/documentation/appkit/nswindow/ignoresmouseevents), [Ollama chat API](https://docs.ollama.com/api/chat).

### One-session live check (requires a person with Accessibility permission granted)

Quit any running GuideCursor first. Build with `./macos/scripts/build.sh`, open the built app (path above), and renew its Accessibility entry if macOS shows it as off (ad-hoc rebuilds can invalidate the old entry). Then, using synthetic/public content:

1. Finder window showing the sidebar → request `downloads`, then `download`. Expect a Row candidate “Downloads”; choose **Guide me**, move the pointer to it and click yourself. Copy the Scan details.
2. Minimise all Finder windows (or close them) → `downloads`. Expect the “no open window” message, not “No match”.
3. Finder window → `find the button`. Expect “no searchable words”.
4. Finder window → `zzzz`. Expect “No match among N named controls”.
5. One other app (e.g. Safari or Mail) → the visible name of a toolbar button. Copy the Scan details.

Report for each: status text, Scan details line, and whether the outline/companion/speech appeared at the right place.

## Screen-image fallback (groundwork only — not available to users)

GuideCursor does not capture the screen and never asks for Screen Recording permission in this build. The permission will be requested only once a real visual-guidance path exists.

The code contains groundwork for that path, unused by the app's interface:

- **When to offer an image.** A decision based on accessibility evidence: only after a complete scan with no named controls, or no match while some controls are unnamed. Never after a partial or failed scan.
- **Offer bound to its scan.** The app keeps such an offer privately and drops it when the app, request or scan changes. Any future capture must first re-read the selected process, request text, focused window element and frame, and refuse if they differ.
- **Capture service.** ScreenCaptureKit (macOS 14+) captures only the matched window, without the cursor, at most 2048 px, in memory only.
  - GuideCursor stops *waiting* after 5 s, but ScreenCaptureKit cannot abort a screenshot already in progress. One may finish later; that late image is released on arrival without being used.
- **Offline evaluation tools.** Image-to-screen mapping, validation of proposed boxes (always marked unverified), a synthetic screen renderer with ground truth, and scoring.

None of this establishes model accuracy or that live capture works; both are unverified.

## Offline text location on generated screens (step 2 evaluation — not in the app)

`VisionTextAnalyzer` uses Apple's built-in Vision text recognition (revision 3, no model download) to find visible words in an in-memory image. It returns pixel boxes, checked by the same validation path as any visual proposal. The app does not call it, does not capture the screen and does not show OCR boxes. Run the benchmark on generated screens only:

```sh
swift run -c release --package-path macos GuideCursorVisionBench 5            # add --lines to print OCR lines, --png DIR to save the generated screens
swift run --package-path macos GuideCursorOCRChecks                          # opt-in real-OCR assertions (not in CI; results can vary by macOS version)
```

Measured on an Apple M4 (16 GB, macOS 26.6.2) on 6 generated screens and 51 requests. The set includes duplicate labels, a dark non-Retina screen with 11–12 pt text, a dense file list, and a screen where only opposite actions are visible ("Don't Save", "Don't Delete", "Save as PDF"). Three requests must return nothing ("Save", "Delete", "Folder"):

| Level | Requests exactly right | Recall | Precision | Text-box IoU | Median per window image | First call in a new process |
|---|---|---|---|---|---|---|
| accurate | 49 / 51 | 0.959 | 1.000 | 0.844 | 47–66 ms (7 runs) | 137–474 ms |
| fast | 39 / 51 | 0.755 | 1.000 | 0.810 | 5–7 ms | 6–22 ms (Vision already loaded) |

**Limits.**
- A text box is not a clickable control. It marks where words are drawn. The real hit area may be larger (a row or button), smaller, or absent (plain text).
- **Visual text must have the same name as the request.** Every request word has to be in the label, and every label word in the request; only plural differences ("Download"/"Downloads") are allowed. "Save" therefore never matches "Don't Save" or "Save as PDF", "Delete" never matches "Don't Delete" or "Deleted", and "Folder" never matches "New Folder". Missing a match is the intended safe outcome. Accessibility label search keeps its broader ranking.
- Vision sometimes misreads at full confidence: it read "Don't Save" as "Dont savi" and "Cancel" as "sance" on clean buttons.
- The fast level failed on small, dark, non-Retina text (1 of 9 labels).
- These are synthetic results only. They say nothing about accuracy on real apps, other languages, icons without text, or low contrast.
