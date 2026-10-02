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
