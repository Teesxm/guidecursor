# Development notes — 1 October 2026

Working notes for the team's required development log; not a finished submission.

## Direction and decisions

Alberto clarified that the website is a concept/presentation asset and the MVP must run in the macOS ecosystem. Read the latest group draft and implement a separate native component under `macos/` on `alberto/mvp-development`.

First desktop milestone: choose a real application's control, confirm it, then receive continuous highlighting and speech as the user moves and clicks. Native Swift/AppKit/SwiftUI uses the available Apple Command Line Tools without external package dependencies. AX control discovery precedes a screenshot fallback, limiting initial permissions and complexity.

AI task interpretation is optional via a loopback Ollama adapter. A separately labelled literal control-name search supports native testing before model setup. Do not describe label matching as AI. No Ollama command or running local service was found on the development Mac; model quality is unverified.

## Representative direction

- “Our MVP should exist in the macOS ecosystem.”
- “The user keeps control of their own cursor.”
- Start with visual assistance for a small set of tasks, as the latest draft's feasibility section specifies.

## Corrections and verification

- Initial compilation exposed a missing explicit CoreGraphics import; added it.
- The machine has Command Line Tools but no XCTest module. Changed the small geometry/validation suite into a dependency-free executable check harness, so teammates do not need full Xcode just to run these checks.
- Candidate suggestions must reference actual IDs from the current scan. Invalid and duplicate model IDs are discarded.
- Target switching invalidates pending position reads; stopping also clears previous candidates.
- Accessibility work runs on a serial background queue with node/depth/time limits, keeping slow application responses off the interface thread.
- Position reads are repeated during guidance; switched windows and invalid/disabled targets stop guidance. Screen changes do not cause automatic clicks or assumptions of task success.

## Remaining validation

The app needs the user's macOS Accessibility grant before testing real applications. Build success and geometry checks do not establish overlay behavior, speech usability, model reliability or successful task completion. Test with synthetic/public content and record failures, especially ambiguity, overlays, scrolling, dialogs, multiple monitors and app switching.

## Next decisions

1. Validate one real desktop target and refine the interaction based on use.
2. Set up a suitable local model and measure target-selection accuracy/latency.
3. Add requested macOS magnification with an explicit user control.
4. Implement a complete user-guided multi-step task (including changed windows), with transparent limits.
5. Test with intended users, then prepare a reviewed PR and course demo.

Motor stabilization/snapping, hearing support, voice input and screenshot-based recognition are not delivered in this first milestone.

## Verified result

Release build and ad-hoc signature verification passed. Five core checks with ten assertions passed. `git diff --check` passed. The app was packaged locally. Live UI inspection could not proceed because the computer-control tool lacks macOS permissions; no permission-dependent integration behavior has been verified. Source changes remain local on Alberto's branch; no push or merge was performed. macOS file-provider metadata reappeared on the generated bundle in Documents; stripped it before signing/packaging and excluded extended attributes from the ZIP.

## 2 October continuation

Added comprehensive CLAUDE.md for continuity. Added user-triggered macOS Zoom shortcut after explicit setup confirmation. No macOS settings are altered automatically. The status reports only sending the shortcut, not observed Zoom success. Compiled successfully; real Zoom remains untested. Prepared a personal Applications installation at Alberto's request.

## 2 October target validation

After the user confirmed native Accessibility permission, added a guard against selecting a target from a window that changed while the candidate list was open. Replaced raw target coordinates in candidate rows with relative window regions to distinguish similar controls more clearly. Split the main app menu from the menu-bar status item so each has its own menu. Six core checks (twelve assertions) and release build pass; the Finder target remains awaiting live user feedback.

## CI compiler difference

The first GitHub macOS build used a different Swift compiler and rejected a weak timer capture inside a concurrently executing Task. The local compiler had accepted it. Changed the Task capture list to bind a separate weak model reference. Local release build and six core checks pass; the GitHub rerun is the required verification.

## Cross-app control discovery

The first live Finder test showed a visible Downloads sidebar item but no GuideCursor match. This exposed a general limitation in how controls were indexed: interactive rows can contain their visible names in child static-text elements. Extended the bounded scanner to follow visible children and outline/table rows, then added an app-independent index that associates nested text with the nearest interactive ancestor. There is no Finder-specific selector or hardcoded Downloads behavior. Synthetic accessibility-tree checks now cover an outline row, a button in another tree shape, and the rule that editable field contents are not used as labels. Nine core checks (eighteen assertions), a release build and signature verification pass. The changed binary has not yet been tried against the real Finder window, so this is a reasoned fix rather than confirmed runtime resolution.

The goal is broad coverage through shared macOS accessibility conventions. Apps that do not expose enough usable metadata will still need a future, permissioned screenshot/vision fallback. Competitor material was reviewed for positioning: Clicky offers a screen-aware cursor companion; Be My Eyes Desktop emphasizes AI screen description. GuideCursor's proposed distinction is accessibility-specific, continuous guidance of the user's own pointer and human-controlled clicks across ordinary apps. This positioning does not prove uniqueness or accessibility effectiveness.

## 2 October — reliable-foundation increment (Claude, local, uncommitted for Codex review)

Direction: make control discovery explain itself before adding new capabilities. Previously one message (“No labelled controls found…” or “No match”) covered missing permission, a missing window, an unresponsive app, an unreadable app, an unmatched request and a partly read window, so a failed test could not tell us what to fix.

- Window lookup now uses accessibility error codes to separate missing permission, a quit app, an unresponsive app and an app without a window. It falls back from the focused window to the main window and then a standard non-minimised window, for every app alike.
- A global 0.3 s accessibility request timeout replaces a timeout that only applied to the app element, so one slow element can no longer stall a scan far beyond its 3 s budget.
- Scans report why they stopped early (element, time or depth limit, failed reads); depth truncation was previously silent.
- Outline and table views read their visible rows first instead of every row, so a long file list cannot use up the element budget before the rest of the window is read. This is a code-review finding, not an observed failure.
- Label matching accepts a shared word stem of at least four letters (“download” finds “Downloads”) at a lower score than an exact word. A request made only of filler words is reported as such instead of “No match”.
- A counts-only Scan details line (no labels or screen text) can be copied for troubleshooting. Nothing is written to disk.

Verification: 13 core checks (42 assertions) pass, including diagnosis ordering and a privacy check that synthetic private labels never appear in diagnostics. Release build, ad-hoc signature verification and `git diff --check` pass with no compiler warnings. The agent's process lacks macOS Accessibility permission, so no live scan, overlay or Finder result was observed; the Finder Downloads case remains unverified on a real window.

## 2 October — corrections after Codex review (Claude, local, uncommitted)

Codex reviewed the diff and found four problems; all were confirmed in the code or reproduced.

- **Rows omitted.** The visible-rows-first change dropped AXRows entirely, so tables that expose rows only that way lost them. The scanner now separates "attribute unsupported" from "read failed": supported visible rows are used as reported (even when empty); otherwise a bounded prefix of AXRows is read. Headers, visible children and short non-row child lists (columns, scroll bars) are kept. Array attributes are fetched with a count plus a ranged copy, so long lists are never transferred or queued beyond the element budget; truncation is reported.
- **Failures hidden.** Only role-read errors were counted. Every relevant read (labels, geometry, enabled state, children, rows, header, window candidates, sheets) now keeps its error. A partial scan with nothing named says the window could not be fully read instead of "exposes no controls".
- **Window fallback.** Main-window and window-list reads lost their error codes, and a minimised main window was accepted. Focused, main and listed windows now pass the same validation (role, accepted subrole, not minimised; an unreadable minimised state rejects the candidate and is counted). Permission and app-gone errors stop the lookup; other errors produce "not responding" instead of "no window". The 3 s budget is checked before every reader call, including window lookup (see the timing correction below for the real limit). Starting guidance no longer performs accessibility reads on the main thread.
- **Packaging.** Reproduced: a verified bundle copied into Documents passed strict verification immediately and failed within 20 s after the file provider added Finder metadata. `build.sh` now signs, zips (no resource forks or extended attributes) and verifies a freshly extracted copy in a temporary folder, then installs to `~/Library/Caches/nl.guidecursor.prototype/build/`.

The traversal and window policy moved into `GuideCursorCore` behind a small reader interface, so they are checked against an in-memory tree with injected failures and a simulated clock. 21 core checks (72 assertions) pass. Deliberately breaking the AXRows fallback, the minimised-window check, the deadline check or the child-list bound each makes a check fail. The release build has no warnings; the build script ran twice successfully, and the extracted ZIP verifies. The live reader's error mapping, including a fallback when an app refuses to count an array, has not been exercised against real apps: the agent still lacks Accessibility permission, so Finder, overlay, speech and app compatibility remain unverified.

## 2 October — hidden-row fix after Codex's second review (Claude, local, uncommitted)

Codex re-ran everything (all passing) and reproduced one remaining bug with the real scanner: when a table reported its visible rows, a short child list could reintroduce hidden rows, so GuideCursor could suggest and highlight a row the user cannot see. Supported AXVisibleRows is now authoritative for every AXRow in that table's subtree, including rows reached through columns or groups; non-row controls are kept, nested tables set their own context, children are deduplicated, and unsupported or failed visibility still uses the bounded AXRows fallback. 25 core checks (81 assertions) pass, including Codex's two exact cases; three deliberate mutations of the fix each fail a check. Release build, packaging with fresh-extraction verification and diff check pass.

Timing correction: an earlier entry implied a single-call overrun. The 3 s scan budget is checked before every reader call, including window lookup, and the window's geometry is now taken from the scan itself (node 0) rather than read afterwards. A reader call that starts just before the deadline still completes, and on the live reader one call can be two native requests (frame: position + size; array: count + copy), each nominally limited by the 0.3 s messaging timeout. The expected worst case is therefore about 3.6 s plus local processing, but that bound depends on macOS honouring the timeout and has not been measured against real apps; the fake-clock check only proves the budget is consulted before each reader call.

## 2 October — step 2, first slice: permissioned window capture without recognition (Claude, local, uncommitted)

Direction: begin the screen-understanding fallback without pretending a model exists. Inspected the SDK first: `CGWindowListCreateImage` is obsoleted in the macOS 15 SDK, so capture uses ScreenCaptureKit (`SCScreenshotManager.captureImage`, macOS 14+, behind an availability check because the app targets macOS 13). Querying shareable content can itself prompt, so GuideCursor preflights permission and only requests it from an explicit button.

- **When to offer an image** is decided from the accessibility diagnosis: only after a complete scan that found no named controls, or found no match while unnamed controls exist. A partial or failed scan, an unresponsive app, missing permission or window, an unsearchable request, or a fully named window with no match do not offer it.
- **Capture** takes one image of only the scanned window, matched by process and frame within 4 points; several matches are refused rather than guessed. Cursor excluded, at most 2048 px, 5 s timeout, memory only, discarded immediately. Nothing is saved, logged or uploaded, and no analyser is connected; the UI says so.
- **Pure core for later recognition:** pixel-to-screen mapping that rejects mismatched image shapes and out-of-image boxes; validation of proposed boxes (confidence range, size limits, cap of five, always `verified = false`); a `VisualAnalyzer` interface; a synthetic screen renderer with ground-truth boxes; IoU and label-aware precision/recall for offline evaluation.

Verification: 32 core checks (129 assertions) pass. They include end-to-end fallback decisions from the fake accessibility tree, a pixel read-back check that synthetic ground truth matches what was drawn, and a synthetic analyser run through validation and scoring. Six deliberate mutations (offering images after partial scans, matching other apps' windows, guessing between windows, accepting mismatched image shapes, out-of-image boxes or whole-window boxes) each fail a check. Release build has no warnings; packaging and fresh-extraction verification pass; `git diff --check` passes. The agent session has neither Screen Recording nor Accessibility permission, so no real capture, prompt, window match or coordinate agreement was observed. Whether ScreenCaptureKit window frames use exactly the same coordinates as accessibility frames is an unverified assumption guarded by the 4-point match and shape check. Sheets may not match because their capture window can differ from the accessibility element.

## 2 October — screen-capture corrections after Codex review (Claude, local, uncommitted)

Codex reran everything (passing) and asked for three corrections; all were made.

- **Capture removed from the user interface.** The capture button asked for Screen Recording, took an image and discarded it, without helping anyone find a control. The window section, the permission request and the capture action are gone; the main window is identical to the accepted build. The decision logic, capture service and evaluation tools stay in code for the next step.
- **Timeout claim corrected.** Racing the capture inside a task group did not bound the wait: a task group waits for every child, and cancellation cannot stop a screenshot already in progress. Codex measured 2.1 s for a 0.1 s limit. The new wait resumes the caller exactly once at the deadline. The capture may still finish in the background, and its late image is released on arrival. Re-inserting the task-group version makes the new timing check fail (it waited the stubborn operation's full second).
- **Offer tied to its scan.** An offer now records the process, request and window frame of its scan. It is cleared on stop, app change, any request edit, or a scan that finishes after the request changed. The capture service refuses unless a fresh observation shows the same process, request (ignoring surrounding whitespace), the same window element and a frame within 1 point.

Verification: 34 core checks (144 assertions) pass with no compiler warnings. The checks cover offer invalidation and a deliberately uncancellable operation: the wait returns early, and the late result goes only to the discard path. Mutations that restore the task-group wait, ignore request edits or ignore window identity each fail a check. The release build, packaging with fresh-extraction verification and `git diff --check` pass. This session still lacks Screen Recording and Accessibility permission, so no live capture or timing was observed.

## 2 October — on-device text location, offline evaluation (Claude, local, uncommitted)

Direction: test whether Apple's built-in text recognition can locate visible labels for the screen fallback, measured on generated screens only.

- **SDK check.** `VNRecognizeTextRequest` is available (macOS 10.15+; revision 3 from macOS 13, matching the app's minimum). It ran here at revision 3 with English and five other languages and no download.
- **Probe finding.** Separate controls on one baseline came back as one merged line ("Downloads Attach file"). Per-word boxes from `boundingBox(for:)` are word-accurate at both levels.
- **Adapter.** `VisionTextAnalyzer` runs Vision on a background queue and maps normalised bottom-left boxes to top-left image pixels. It drops blank, non-finite or out-of-image results. Each line is split into segments at gaps larger than 0.8 × word height, and segments go through the existing `VisualProposals` validation.
- **A measured misread exposed a safety problem.** "Don't Save" was read as "Dont savi" at confidence 1.0, and the request then fell back to the plain "Save" buttons, which is the opposite action. Visual matches now need every word of the request, exactly or by stem. Accessibility label search is unchanged.
- **Language correction measured, not assumed.** Turning it on did not change accurate-level results (41/43) and was slower, so it stays off. The benchmark has a flag to repeat the comparison.

Results on an Apple M4, 16 GB, macOS 26.6.2 (build 25G83), 5 generated screens, 43 requests, after the coverage rule:

| Level | Requests exactly right | Recall | Precision | Text-box IoU | Median per window image | First call in a new process |
|---|---|---|---|---|---|---|
| accurate | 41 / 43 | 0.955 | 1.000 | 0.840 | 47–63 ms (5 runs) | 137–474 ms |
| fast | 33 / 43 | 0.773 | 1.000 | 0.814 | 5–7 ms | 6–22 ms (Vision already loaded) |

Accurate misses: "Cancel" and "Don't Save" on the dialog. Both were misread by Vision at confidence 1.0 on a clean rendering, confirmed by viewing the generated PNG. Fast misses: 8 of 9 labels on the dark 1× screen with 11–12 pt text, "Don't Save", and "Résumé.pdf" (read as "Resume.pdf"). The single duplicate-label request ("Save" ×2, next to "Don't Save") returned exactly both Save buttons at both levels.

Checks: 39 core checks (173 assertions). Real OCR checks cover locating labels on a Retina screen, including two buttons sharing a baseline, with mapping to screen points through `CaptureGeometry`; a blank image giving no results; and duplicates staying ambiguous. Pure checks cover the coordinate flip, segment splitting and the misread case. Mutations that remove the vertical flip, the gap split or the coverage rule, or that resolve duplicates by taking the first, each fail a check. Release build has no warnings; packaging with fresh-extraction verification and `git diff --check` pass.

Limits: a word box is not a clickable target. Confidence 1.0 does not mean correct. Synthetic Helvetica screens are easier than real apps (icons, truncation, low contrast, overlapping text, other languages). Nothing is wired into the app.

## 2 October — visual matching safety correction and test split (Claude, local, uncommitted)

Codex reproduced an unsafe case with the matcher: with only "Don't Save" visible, a request for "Save" returned "Don't Save". Requiring every request word to be present still allowed labels with extra words that reverse or change the action. The earlier benchmark hid this because exact "Save" buttons always outscored it.

- **Generic rule (`Guidance.sameName`, visual path only).** Every searchable request word must appear in the label, and every label word (except "the", "a", "an") must appear in the request as typed. Words are equal only if identical or differing by a plural "s"/"es". Missing a match is the intended outcome. Accessibility search keeps its broader scoring, and a check pins that.
- **Benchmark.** Added a screen where only opposite actions are visible ("Don't Save", "Don't Delete", "Cancel", "Save as PDF", "Deleted items"), plus requests that must return nothing ("Save", "Delete", and "Folder" next to "New Folder"). Any suggestion for those lowers precision. Swapping in the old any-shared-word rule drops precision to 0.870 (accurate) and 0.740 (fast).
- **Test split for CI portability.** OS-dependent OCR assertions (exact labels at exact places, duplicates, the opposite-actions screen) moved to the opt-in `GuideCursorOCRChecks`. The required core checks keep deterministic matching and geometry rules plus one real-Vision check that a blank image yields no text. CI has not run any of this yet.

Results on an Apple M4, 16 GB, macOS 26.6.2 (25G83), 6 generated screens, 51 requests:

| Level | Requests exactly right | Recall | Precision | Text-box IoU | Median per window image | First call in a new process |
|---|---|---|---|---|---|---|
| accurate | 49 / 51 | 0.959 | 1.000 | 0.844 | 47–66 ms (7 runs) | 137–474 ms |
| fast | 39 / 51 | 0.755 | 1.000 | 0.810 | 5–7 ms | 6–22 ms (Vision already loaded) |

Accurate misses are unchanged ("Cancel" and "Don't Save" misread on the dialog). Fast also misses both "Don't …" buttons on the new screen, 8 of 9 labels on the dark 1× screen, and "Résumé.pdf". There are no unsafe suggestions at either level.

Checks: required core 38 checks / 177 assertions; opt-in OCR 3 checks / 20 assertions (passed on macOS 26.6.2). Mutations that allow extra label words (Codex's bug), treat any prefix as the same word, or fall back to any shared word each fail a required check. Release build has no warnings; packaging with fresh-extraction verification and `git diff --check` pass. App sources unchanged since `cd53962`.
