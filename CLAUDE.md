# GuideCursor — coding handoff

Last updated: 2 October 2026. Read this before changing code. Update the implementation/validation sections as work progresses. This file is for any coding assistant continuing Alberto's work.

## Product and intended outcome

GuideCursor is an AI-supported **macOS desktop accessibility app**, part of a VU Digital Business and Information Systems group assignment. Its purpose is to help people interact with ordinary applications through the same interface and workflow as other users.

A small semi-transparent companion follows the real system cursor. The user expresses a goal, GuideCursor identifies relevant controls and provides adapted visual/spoken guidance and optional precision support. The person chooses what to do, moves the cursor, clicks, selects files and decides whether to continue. The product strengthens human action instead of autonomously operating the computer.

**The existing website is a concept/demo and presentation asset. It is not the intended macOS MVP.** Alberto explicitly corrected this distinction twice. Do not substitute a better website, a browser-only demo or a fake desktop for the native app. Develop the macOS component alongside the existing website.

Tagline: “Use the same computer. Get the guidance you need.” Calm, precise, non-patronizing language; indigo, mint and charcoal; high contrast and legible controls.

## Agreed scope and differentiation

- Terence emphasizes accessibility profiles, continuous cursor guidance, larger effective targets, optional magnetic assistance, and retaining normal app workflows.
- Alberto emphasizes integrating existing macOS accessibility capabilities, such as Zoom, so users can invoke the right assistance naturally and in context.
- The intended value is their combination: task/screen understanding + cursor guidance + appropriate accessibility tools within ordinary desktop apps.
- Existing competitors include Clicky and Be My Eyes. Do not claim we invented captions, speech, magnification or cursor companions. Official competitor pages were reviewed on 2 October: HeyClicky describes screen awareness and screen annotations (https://www.heyclicky.com/about); Be My Eyes Desktop describes AI screen/image assistance on Mac and Windows (https://www.bemyeyes.com/be-my-eyes-for-desktop/). Their internal implementation was not audited. Do not infer product uniqueness or guaranteed coverage from marketing pages.
- The latest draft narrows MVP validation to users with visual impairments and a few selected macOS workflows. Alberto subsequently clarified that the **architecture must serve many apps through shared macOS discovery and a visual fallback**. The selected apps are test cases, not separate hardcoded integrations; universal coverage is not established.
- Low-vision proposals: visible pointer, target highlights, cursor-area magnification, contrast and spoken labels.
- Blindness proposals: control descriptions, continuous directions and optional near-target snapping. Usability must be tested; do not claim clinical/accessibility effectiveness from a build or demo.
- Motor assistance remains in the broader product: stabilization, enlarged effective targets, optional snapping. Dwell-to-click and double-click prevention were brainstormed, not mandatory initial requirements.
- **Hearing support is explicitly TBD.** The website includes a hearing simulation, but that does not establish a first-release commitment.
- Task guidance must react to the actual current window. Example: locate Attach, wait for the user's click, then recognize the file picker and guide the next user-selected step. Do not assume an action succeeded or blindly replay coordinates.
- macOS first. Windows is a later ambition, not a current deliverable.

## Model and integration decisions

Use macOS accessibility information first, with screenshot/vision fallback as a later capability. Native speech and Zoom are proposed integrations. Voice input is also proposed but not required to prove the initial desktop interaction.

Local AI through Ollama is preferred if speed/accuracy are adequate. The 25 September discussion and latest draft explicitly leave the actual choice subject to testing. Cloud is an optional future fallback requiring explicit permission for sharing screen context; no cloud integration is authorized by merely reading an old chat. ElevenLabs was mentioned as an option, not selected. Text-to-speech is not the same thing as VoiceOver; speech output is visual-impairment support, not hearing support.

Currently label search is deterministic, not AI. Keep that distinction visible. Never silently simulate AI success when the model fails.

## Repository and collaboration

- Shared repository: https://github.com/Teesxm/guidecursor
- Current local checkout: `/Users/alberto/Documents/Codex/2026-10-01/b/guidecursor`
- Alberto's local branch: `alberto/mvp-development`
- Original baseline: `767864a510ac41cd3a07eeece4cd7fc25434f2f3`.
- GitHub connector account: `tenochespinosa-stack`. Rechecked after invitation acceptance: repository `push=true`, collaborator permission `write`.
- Command-line Git push succeeded on Alberto's branch. `gh` is not on PATH, so use the GitHub web/API to inspect PR checks if needed.
- Draft PR: https://github.com/Teesxm/guidecursor/pull/1. No merge or deployment has happened.
- Keep `main` presentation-ready. Develop on the feature branch, test, then use a reviewable PR for collaboration. Do not overwrite teammates' changes or force-push shared history.
- README says the existing Vercel project originally used `Teesxm/dbisassignment`; production linkage to the new repo is unverified. Do not change deployment as a side effect of desktop development.
- Do not put private WhatsApp exports, personal documents or credentials in this public repository.

## Current code

Root: Vite static HTML/CSS/JavaScript website, with retained React/TypeScript files. Website demo uses predefined targets, real browser pointer tracking/speech, enlarged click areas and scripted hearing captions. Downloads and checkout are simulations. Root website build passed before native work; website code has not been changed, apart from README links.

`macos/`: native Swift package, AppKit + SwiftUI, macOS 13 minimum, no external package dependencies.

- `Sources/GuideCursor/Application.swift`: app lifecycle, main window, app picker, task field, candidate selection, menu-bar Stop/Quit.
- `Model.swift`: observable state, bounded background scans, explicit target confirmation, generation tokens to reject stale work, live target validation, geometric guidance/speech, click-near-target handling.
- `Accessibility.swift`: accessibility permission-independent helpers, focused window/sheet lookup, bounded traversal (time/nodes/depth), including visible children and outline/table rows. Reads labels/roles/geometry and static text, never editable field values. Labels and static text can still contain personal information.
- `Magnification.swift`: explicit user-confirmed Option–Command–8 system Zoom shortcut; requires prior macOS Zoom keyboard setup and Accessibility permission. Does not claim the effect succeeded.
- `Overlay.swift`: floating, click-through target outline and companion near the real pointer; does not warp the pointer or click.
- `Ollama.swift`: optional loopback `/api/chat` adapter; sends task and at most 150 controls, validates returned IDs against the scan, requires the person to select a candidate. No screenshots. An independently configured Ollama service could use cloud models; configure local-only before testing sensitive context.
- `Sources/GuideCursorCore/Guidance.swift`: coordinate conversion, directions, simple label scoring, model ID validation.
- `Sources/GuideCursorCore/Diagnostics.swift`: pure, tested scan diagnosis (permission / app quit / no window / not responding / no named controls / unsearchable request / no match / model chose none) plus incomplete-scan notes and a counts-only summary that never contains screen text.
- `Sources/GuideCursorCore/TreeScan.swift`: pure traversal and window-fallback policy behind a `TreeReader` interface: error classification (absent vs failed), consistent window validation, bounded array reads, a deadline checked before each reader call (not a strict wall-clock cap; see the visibility-fix note), and supported AXVisibleRows treated as authoritative for rows in that table subtree. `Accessibility.swift` supplies the live AXUIElement reader; checks use an in-memory tree.
- `Sources/GuideCursorCore/ScreenFallback.swift`: when to offer a screen image (from the AX diagnosis), image→screen geometry, AX↔capture window matching, output sizing, validation of visual proposals (always unverified), `VisualAnalyzer` interface. `VisualEvaluation.swift`: IoU/precision/recall, centre-hit scoring and an in-memory synthetic screen renderer (buttons/plain text, light/dark, text ground truth). `TextRecognition.swift`: Vision OCR adapter (`VisionTextAnalyzer`), coordinate flip, gap-based segments, strict same-name matching (`Guidance.sameName`). `Sources/GuideCursorVisionBench`: offline benchmark executable on generated screens.
- `Sources/GuideCursor/ScreenCapture.swift`: not called by the UI yet. Screen Recording preflight/request helpers and a scan-bound ScreenCaptureKit capture of the one scanned window (macOS 14+), memory only, with a bounded wait (the screenshot itself cannot be aborted).
- `Sources/GuideCursorCore/ControlIndex.swift`: app-independent accessibility-tree index. It attaches visible text nested inside a row/cell/button to that interactive ancestor. This is a cross-app rule, not a Finder-specific selector.
- `Tests/GuideCursorCoreTests/main.swift`: executable check harness; full XCTest is unavailable in this Mac's Command Line Tools.
- `scripts/build.sh`: compiles, then assembles/ad-hoc signs/zips in a temporary folder, verifies the bundle and a fresh ZIP extraction, and installs both to `~/Library/Caches/nl.guidecursor.prototype/build/` (outside synced Documents).
- `README.md`: native setup, limitations and test instructions.
- `DEVELOPMENT-LOG.md`: working notes for the course log.
- `.github/workflows/macos.yml`: PR-triggered macOS build/check job. Both native and website CI passed for implementation commit `5e6bcd0`; see verification links below.

### Implemented baseline, not end-to-end verified

Permission UI; application selection; native control scan; deterministic label search; optional Ollama adapter; candidate confirmation; live target geometry; click-through highlight; cursor companion; spoken directions; stop controls; guidance pauses on other foreground apps and stops on invalid/disabled/off-screen targets or changed windows.

Click detection says only that the user clicked near a target; it does not prove completion. The user must inspect the result and request the next step. Automatic multi-step planning is not implemented.

### Validation and blockers

- macOS 26.6.2 / Apple Silicon / 16 GB RAM on the development machine.
- Swift 6.3.3 from `/Library/Developer/CommandLineTools`; Swift package language mode 5.9.
- Release build passed. Ad-hoc signature verified, including a freshly extracted packaged copy.
- 25 core checks with 81 assertions pass (after the visibility fix), including hidden-row exclusion with supported visible rows, non-row table children surviving, and fake-tree regressions for AXRows-only tables, supported visible rows, bounded huge row lists, failed child reads, complete empty scans, window fallback/errors, the budget check before each reader call and lost permission. Also covered: geometry, display conversion, matching/no-match/shared stems, rejecting invented/duplicate model IDs, generic row/cell/static-text indexing, privacy of editable fields, labelled buttons, diagnosis ordering, incomplete-scan messages, and diagnostics containing no screen text.
- `git diff --check` passed.
- Live app launch/UI inspection was blocked by the computer-use tool's missing macOS permissions. **No actual cross-application overlay, speech, accessibility-tree result, Zoom, model inference or completed workflow has been verified.** Do not convert code inspection into a claim of working runtime behavior.
- The user confirmed that the installed GuideCursor says “Accessibility enabled.” No Screen Recording permission is needed for the AX-only baseline. A screenshot/vision fallback would require its own permission flow.
- Ollama command not found and no service listening at `127.0.0.1:11434`; no model downloaded or tested.
- Do not repeatedly invoke the unavailable computer-control tool; it stalled twice. The user prefers direct tools/local inspection over token-heavy browser viewers. Use UI only when it answers an actual visual/interaction question and permissions are available.
- Building in Documents lets the macOS file provider re-add Finder metadata; reproduced on 2 October: a verified bundle copied into Documents failed strict verification within 20 s. `build.sh` therefore signs and verifies outside Documents. Never copy the app back into Documents; share the ZIP. Never strip attributes from unrelated user files.

## Build / checks / packaging

From repository root:

```sh
swift run --package-path macos GuideCursorCoreChecks
./macos/scripts/build.sh
open ~/Library/Caches/nl.guidecursor.prototype/build/GuideCursor.app
npm run build  # website; only when relevant to changed web code
```

Native generated files: `macos/.build/`, `.swiftpm/` (ignored), and `~/Library/Caches/nl.guidecursor.prototype/build/` (app + ZIP). `macos/build/` is no longer written. Bundle ID: `nl.guidecursor.prototype`. Rebuilding may require renewing Accessibility permission because it is ad-hoc signed, not Developer ID signed/notarized.

User-facing artifacts currently reside outside the repo at `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/`: `GuideCursor-macOS-prototype.zip` and `GuideCursor-project-context.md`. Keep these synchronized or explicitly mark them stale. Do not commit binaries.

## Agreed five-step delivery plan

1. **Reliable foundation.** Read the existing code and preserve current changes. Validate the updated generic control discovery, target selection and continuous guidance. Add concise diagnostics that distinguish missing permission, missing window, no exposed controls, no matching label and a truncated scan, without collecting screen content by default. The first Finder “downloads” test failed on the old installed build; the generic fix has only synthetic validation so far. Prefer tests the coding agent can run; batch any unavoidable human verification into one short session.
2. **Screen understanding fallback.** Design and implement screenshot/vision recognition for controls missing from AX. Keep it app-independent, scoped to the chosen app/window, permissioned and explicit about confidence. First inspect available model/runtime support and test synthetic or public images. Do not silently upload screens or treat model coordinates as verified controls. Local Ollama is preferred but not yet available/tested. Record model accuracy and latency before choosing a provider.
3. **Tasks connected to guidance.** Interpret a goal, suggest an observed target, guide the user's movement, then reassess after the user's click. Handle changed windows and ambiguity; do not infer successful completion from a click alone. Deliver one coherent journey before expanding feature count.
4. **Complete journeys across apps.** Use Finder, a browser and an email workflow to exercise the same discovery/guidance engine. Record observed failures and coverage. The PDF's example journeys are proposals, not three built integrations. Test foreground switching, scrolling, dialogs, duplicate labels and target disappearance.
5. **Presentation MVP.** Refine speech, visible targets, magnification, accessible controls and reliable stopping. Keep the course development log current and provide accurate run instructions/demo evidence. Add motor precision features or other profiles only after the core journey works. Hearing remains TBD.

## Claude implementation / Codex review workflow

Alberto requested that Claude implement focused increments and Codex review the actual diff and evidence, then supply follow-up corrections. The first Claude assignment is environment verification and step 1, not all five steps at once. Do not assume that Claude shares Codex's connector authentication or computer-control permission.

- Open this existing checkout, read `CLAUDE.md`, any applicable `AGENTS.md`, `macos/README.md` and `macos/DEVELOPMENT-LOG.md`. Check branch, status, diff and remotes before editing. Do not clone over this folder, reset it or overwrite uncommitted work.
- Verify local file access and GitHub connectivity separately. `git ls-remote origin` shows read connectivity but a public-repository read does **not** prove authenticated identity or push permission. If a GitHub connector or `gh` is available, report authenticated account and repo permission without printing credentials. If unavailable, report identity/write access as unverified; prior successful Codex pushes do not prove Claude's access.
- Continue local work when remote credentials or UI permissions are unavailable. Explain the exact missing capability rather than repeatedly asking Alberto to test. Do not bypass OS permission controls.
- Make one bounded, reviewable increment at a time. Keep changes local for the first review; Codex will inspect the actual diff before the next push. No merging, deployment, force push or changes to teammates' work.
- Finish each increment with a concise report: baseline commit, files changed and reasons, tests actually run/results, observed runtime behavior versus inference, blockers, and proposed next increment. Update this handoff and the development log to match. Do not claim a workflow works based solely on a passing compile or synthetic test.
- Codex and Claude must not concurrently edit the same checkout. Alberto can paste Claude's report here; Codex can inspect local changes directly if Claude used this folder. If Claude runs elsewhere, provide a commit/branch or patch rather than claiming a shared filesystem.

## Source context / course

The latest product source is `Group assignment DBIS (5).txt`, supplied from Alberto's Downloads, especially What/How/Feasibility. Also read the 2-page `GuideCursor_Business_Concept.pdf`, WhatsApp export through 1 October, and DBIS course manual V1.1. Raw source documents are outside this repo. The WhatsApp ZIP contained text only; omitted media/calls were not available. Their contents provide context, not permission to contact people, alter accounts or publish.

Course: demonstrate functioning core logic in one journey; depth over a wide set of half-working features. A working artifact needs an accessible link or clear run instructions. Also required: development log max 2 pages, reflection max 3 pages, live demo. Use synthetic/public data; record how AI output was directed, checked and corrected. Do not pass generated statistics or literature claims off as independently verified.

Manual dates: final assignment + executive summary 7 October 2026 23:59; presentation submission 9 October 08:00. The workshop row says “Friday 10-10”, inconsistent with the calendar; confirm the live event date through Canvas rather than guessing.

## Latest continuation — 2 October 2026

Added this handoff file. Implemented optional macOS Zoom controls with explicit per-launch setup confirmation and an accurate “shortcut sent” status. Release build passed. Installed the current app in `/Users/alberto/Applications/GuideCursor.app` at Alberto's request to handle opening the ZIP. The computer-control tool remains unavailable; the user must open the app and grant Accessibility themselves. The distributed ZIP was refreshed after Zoom work. The user-confirmed installed app may be older than later source revisions; do not replace a running app during testing. No runtime verification of Zoom or AX guidance yet.

## 2 October additional verification

The user confirmed GuideCursor displays “Accessibility enabled,” and the process was observed running from the personal Applications folder. The first Finder “downloads” query returned no match despite a visible Downloads row. Added stale-window validation before activating guidance and human-readable control regions. The computer-control tool is still denied separate permissions, so do not claim direct UI verification of the fix.

## Draft PR and CI status

Draft PR: https://github.com/Teesxm/guidecursor/pull/1. Branch `alberto/mvp-development` was pushed; main remains unchanged. Initial macOS CI failed in `Model.swift` because the GitHub compiler rejected a weak timer capture in a concurrent Task. Adjusted capture to `[weak model = self]`; the subsequent CI run passed. Both checks also passed for `5e6bcd0`: native https://github.com/Teesxm/guidecursor/actions/runs/36942347940 and website https://github.com/Teesxm/guidecursor/actions/runs/36942347938. This confirms build/check results, not permission-dependent desktop behavior.

## Cross-app discovery update

The first failed Finder test exposed a general AX-tree issue: selectable rows can have their text in nested `AXStaticText` rather than in the row's own title. The scanner now traverses visible children and outline/table rows, then the pure indexer maps child text to the nearest interactive ancestor. It contains no Finder bundle-ID or hardcoded “Downloads” path. Synthetic tree checks cover an outline row, a labelled button in a different tree shape, and absence of editable text in candidate labels; nine checks/eighteen assertions plus a release build pass. Real cross-app behavior and the updated Finder case remain unverified until a new app build is run with permission. The broad design is AX first, with a permissioned screenshot/vision fallback later for apps that expose too little AX metadata; never promise universal coverage from AX alone.

## Latest delivered state for the next agent

Implementation baseline: `5e6bcd0` (generic nested accessibility labels); earlier `8c540a4` fixed the CI timer capture and `9786da0` added the native baseline. Both CI jobs passed. The refreshed output ZIP was signed in a temporary directory outside Documents to avoid file-provider metadata, then extracted and signature-verified. ZIP SHA-256: `99f8d497bb0e5226cea381ecbabf677c3e33356cc69dc18b6e8b522301982795`. It contains the new scanner. The running app at `/Users/alberto/Applications/GuideCursor.app` was still the old build at the last check; do not assume source, ZIP and installed process have the same version. Safely quit before replacing a running installation, and account for renewed Accessibility permission with ad-hoc signatures. No updated live Finder result has been observed.

## Step 1 increment — Claude, 2 October (local, uncommitted, awaiting Codex review)

Baseline `266c554` (implementation baseline `5e6bcd0`). Environment: local checkout readable/writable; GitHub API via the keychain git credential reports `tenochespinosa-stack` with `push: true` (token not displayed; no `gh`, no GitHub connector); PR #1 open/draft at `266c554` with both CI checks green. The agent's process is **not** Accessibility-trusted and has no screen-capture or native UI control, so no live scan was performed.

Changes: error-code-based window lookup with focused → main → standard-window fallback; global 0.3 s AX timeout; distinct element/time/depth/failed-read stop reasons; visible-rows-first traversal of outlines/tables; shared-stem label matching; filler-only request detection; user-facing diagnosis messages; counts-only copyable Scan details. No app-specific rules, no logging, no new permissions, no model or provider changes. Nothing committed, pushed or installed; `~/Applications/GuideCursor.app` untouched. `outputs/GuideCursor-macOS-prototype.zip` is now stale relative to source.

Still unverified: every live AX behavior, including the Finder Downloads row, the new window fallback, the 0.3 s timeout against slow apps (Electron/Chromium apps may need a retry on first access), overlay and speech. A one-session live check is in `macos/README.md`. Next recommended work: run that check, fix what it reveals, then start step 2 (screen-recognition fallback design) only after the AX path is observed working.

## Codex review of Claude's first increment — pending corrections

Claude left local, uncommitted diagnostics/scanner changes based on `266c554`. Codex independently reran the suite: 13 checks / 42 assertions pass. Release compilation passed, but rerunning `./macos/scripts/build.sh` failed at signing with forbidden Finder/resource-fork metadata; the build/package is not currently reproducible. No live UI behavior has been verified and no review changes were pushed.

Corrections requested before accepting this increment: restore a bounded AXRows fallback when visible-row metadata is unsupported; preserve operational errors from child/label/geometry reads and avoid claiming no exposed controls after failed scans; propagate errors through main/window-list fallback and consistently handle minimised windows while bounding reads; stage signing/packaging outside Documents and verify a fresh extracted artifact. The user-facing follow-up prompt is `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/Claude-review-corrections.md`. Keep this work local for the next Codex review. The current output ZIP predates Claude's diagnostics changes.

## Step 1 review corrections — Claude, 2 October (local, uncommitted, awaiting Codex review)

All four Codex findings addressed; see the development log for detail. Traversal and window policy now live in `GuideCursorCore/TreeScan.swift` and are tested with an in-memory reader: 21 checks / 72 assertions pass, and four deliberate mutations (no AXRows fallback, no minimised check, no deadline check, unbounded child probe) each fail a check. Release build has no warnings. `build.sh` ran twice successfully. Each run verified the staged bundle, a fresh ZIP extraction and the installed copy in `~/Library/Caches/nl.guidecursor.prototype/build/` (latest ZIP SHA-256 `7f9176f308a2364717e4e80b4a2c9612e3216f67a3e5703a5de5a1e0c472f1c2`; bytes change per run). `guide()` now validates on the background queue.

Unresolved / unverified: the agent process still lacks Accessibility permission, so live AX error mapping (including the count-refused fallback), the Finder Downloads case, overlay, speech and cross-app behavior are unobserved. Possible false "failed reads" from apps that return generic errors for unsupported attributes would show up as incomplete-scan notes; check the Scan details during the live session. Non-row children of a table are only queued when its child list has ≤ 64 entries. `outputs/GuideCursor-macOS-prototype.zip` and `~/Applications/GuideCursor.app` were not touched and are stale relative to source.

## Codex second review — verified packaging, remaining visibility correction

Codex independently reran the current 21 checks / 72 assertions, native build/package script and diff check; all passed. Signing in temporary storage and verifying a fresh ZIP extraction now work. The current cache output ZIP is updated, but the user-facing outputs ZIP and installed Applications copy were not refreshed by this review. These are local verification results, not new CI results.

One remaining correctness bug was reproduced with the real core scanner and FakeTree: supported `AXVisibleRows = []` plus a short `AXChildren` list containing a hidden row still indexes that row; with one visible and one hidden row in `AXChildren`, both are indexed. The short-child-list path reintroduces non-visible rows. Requested a focused filter that preserves non-row controls, bounded fallback for unsupported visibility, and regression coverage. Also requested accurate timeout documentation because some LiveReader methods wrap multiple native calls and window geometry is read after the scanner budget. Follow-up prompt: `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/Claude-review-final-visibility-fix.md`. Changes remain uncommitted pending correction and review. Live UI behavior remains unverified.

## Visibility fix after Codex second review — Claude, 2 October (local, uncommitted)

Fixed the hidden-row bug. When a table/outline supports AXVisibleRows, that set is now the row context for its whole subtree: any `AXRow` reached another way (short AXChildren list, a column, a group) that is not in the set is skipped after its role read. Non-row children (header, columns, buttons, scroll bars) are still queued. A nested table sets its own context, or none if it lacks visibility support, so the bounded AXRows fallback is unchanged. Queued children are deduplicated. Failed visibility reads still fall back to AXRows and count as failed reads. No app-specific rules.

Checks: 25 / 81 pass, including Codex's exact cases A (supported empty visible rows → no row candidate) and B (visible row 3, hidden row 5 → only “Visible row”), non-row controls beside an empty visible-row list (including a hidden row reached through a column), the unsupported and failed-visibility fallback, and a nested table without visibility support. Mutations that remove the skip, treat unsupported visibility as empty, or let a nested table inherit the outer context each fail a check. Release build has no warnings; `build.sh` packaged and verified the fresh extraction (ZIP SHA-256 `77c8a1689e49a8540010fb2eb6747b7212989ea1e98f2924f839b97866ef4430`); `git diff --check` passes.

Timing, corrected: The 3 s scan budget is checked before every reader call, including window lookup, and the window's geometry is now taken from the scan itself (node 0) rather than read afterwards. A reader call that starts just before the deadline still completes, and on the live reader one call can be two native requests (frame: position + size; array: count + copy), each nominally limited by the 0.3 s messaging timeout. The expected worst case is therefore about 3.6 s plus local processing, but that bound depends on macOS honouring the timeout and has not been measured against real apps; the fake-clock check only proves the budget is consulted before each reader call.

Still unverified live: Finder, overlay, speech, real AXVisibleRows behavior per app, and the timing above. Installed app and `outputs/` ZIP untouched.

## Codex acceptance of Claude's first implementation increment

Codex reviewed the final scanner, diagnostics, guidance and build changes and reproduced the previously failing hidden-row cases as passing regressions. It independently reran 25 core checks / 81 assertions, `./macos/scripts/build.sh` (including signing, ZIP extraction and verification) and `git diff --check`; all passed. The new architecture uses a testable, bounded AX tree scanner; the changed build now stages signing outside synced Documents. See the current branch/PR CI for the final pushed commit. The new ZIP was copied to the Codex outputs folder after local verification. The old copy in `/Users/alberto/Applications/GuideCursor.app` remains an older running/installable version unless explicitly replaced.

This acceptance establishes code, test and packaging quality for the first increment. It does not establish that the real Finder sidebar, overlay or spoken guidance work on the user's Mac. The next practical gate is one consolidated live check using the new binary with Accessibility permission, recording status and counts-only Scan details. Meanwhile the next Claude task may design a generic screen-vision fallback against synthetic/public screens without requesting permissions or uploading private content. Do not present a design or synthetic model result as live cross-app coverage.

## Step 2, first slice — Claude, 2 October (corrected after Codex review; local, uncommitted)

Baseline `3876bf2` (accepted step 1, pushed to PR #1). This is groundwork for the screen fallback only. **Users cannot capture anything:** the main window is identical to `3876bf2`, and the app never requests Screen Recording.

What exists in code, unused by the UI:
- `ScreenFallback.decide`: offer an image only after a complete AX scan with no named controls, or no match while unnamed interactive controls exist.
- `CaptureOffer`: an offer bound to the process, request and window frame of its scan. The Model keeps it privately and clears it on stop, app change, request edit, or a scan that finishes after the request changed.
- `ScreenCapture.captureWindow(offer:observation:)`: refuses unless a fresh observation (PID, request, CFEqual focused window, frame within 1 pt) matches. It uses ScreenCaptureKit (macOS 14+), one matched window, memory only.
- `BoundedWait`: returns at the deadline even if the operation ignores cancellation, but **does not abort the screenshot**. A late image is released on arrival. Do not claim capture "stops" at 5 s.
- Geometry, matching, proposal validation and synthetic evaluation tools, as before.

Required before exposing capture again: a real user-facing visual-guidance path (an analyser plus unverified-target presentation), the fresh observation read on the AX queue immediately before capture, and a permission request only from that path.

Checks: 34 / 144 pass with no warnings. Mutations restoring the task-group wait, ignoring request edits or ignoring window identity each fail. Release build, packaging (to the agent's scratch folder; the shared cache still holds the accepted build) and `git diff --check` pass. Runtime capture, permission flow, timing and coordinate agreement are unverified: this session lacks Screen Recording and Accessibility permission.

Next: measure candidate on-device vision models with `VisualEvaluation` on synthetic/public screens (accuracy and latency) before building the visual-guidance path.
## Codex review of step 2 first slice — pending product and timeout corrections

Codex independently reran Claude's 32 checks / 129 assertions, built the release app and verified a fresh ZIP extraction in a separate temporary output folder; `git diff --check` passed. The capture service, permission preflight, generic fallback decision and synthetic evaluation core remain local and uncommitted. No real capture or guidance was observed.

Before accepting this increment, Codex asked Claude to remove the user-facing capture-only action: it requests Screen Recording but does not yet provide screen recognition or guidance. Codex also demonstrated that a throwing task group racing a non-cooperative async operation against a deadline returns only when the slow operation finishes (a 0.1-second deadline took about 2.1 seconds), so the current five-second capture guarantee is unsound. A future capture must also reject stale scan context if the request or selected window changes. Follow-up prompt: `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/Claude-capture-review-corrections.md`. The accepted ZIP in outputs and cached build remain at `3876bf2` and do not include this increment.

## Codex acceptance of step 2 capture groundwork

Codex reviewed Claude's corrected local changes and independently reran 34 core checks / 144 assertions, a release build with fresh ZIP extraction and strict signature verification, and `git diff --check`; all passed. The ordinary UI has no Screen Recording request or capture-only button. The generic fallback policy, in-memory capture service, scan-bound offer, bounded wait and synthetic vision evaluation tools are groundwork for a future visual guidance path. The bounded wait stops awaiting at its deadline; an underlying ScreenCaptureKit call may finish later, and its result is dropped. This is a caller wait limit, not a guaranteed abort of macOS capture. No real screenshot capture, model inference, UI mapping or visual target has been observed or shown to a user. See the current branch/PR checks for pushed CI evidence; do not call this screen recognition.

## Step 2, offline text location — Claude, 2 October (local, uncommitted, awaiting Codex review)

Baseline `cd53962`. Apple Vision text recognition (built in, revision 3, no download) is wrapped as `VisionTextAnalyzer` and evaluated **only on generated screens**. App sources are unchanged since `cd53962`, so there's no UI, no capture and no Screen Recording request. The app binary now links Vision through the core library but never calls it.

Measured on an Apple M4 / 16 GB / macOS 26.6.2, 5 generated screens, 43 requests: accurate 41/43 exactly right, precision 1.000, median 47–63 ms per window image, first call 137–474 ms. Fast 33/43, about 5–7 ms, and it failed on small dark 1× text. Vision misread "Don't Save" and "Cancel" at confidence 1.0. Visual matches then required every request word. That was insufficient; it is superseded by the same-name rule below. Accessibility search scoring is unchanged.

Checks: 39 / 173, including real-OCR checks. Four mutations (coordinate flip, gap split, coverage rule, duplicate resolution) each fail a check. Release build has no warnings; packaging to scratch and `git diff --check` pass.

Risks:
- CI now runs real OCR in the core checks on its macOS 14 runner; untested there.
- Synthetic Helvetica screens overstate real-app accuracy.
- Word boxes are not click targets.
- Confidence is not trustworthy.

Next: evaluate on public screenshots with hand-labelled ground truth, and design presentation of an unverified visual target (dashed outline plus a "check before clicking" wording) before any UI wiring.

## Codex review of on-device OCR increment — pending safety correction

Codex independently reran Claude's 39 checks / 173 assertions, offline Vision benchmark and release build/package verification; all passed locally. The accurate OCR benchmark found 41/43 synthetic labels and fast found 33/43 on this Apple M4. These are generated Helvetica screens, not real app coverage. No OCR UI or live capture has been connected.

Before acceptance, Codex reproduced a matcher safety gap: when the only recognized label is “Don't Save,” a request for “Save” returns it as a candidate. The benchmark had exact “Save” buttons alongside it, hiding this case. OCR visual matching needs a generic conservative full-label rule and opposite-action regression cases. Required real-OCR checks may also vary by macOS version; keep the evaluation while ensuring the PR's macOS 14 gate is meaningful and stable. Follow-up prompt: `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/Claude-ocr-review-corrections.md`. Changes remain local and uncommitted.

## Visual matching safety correction — Claude, 2 October (local, uncommitted, awaiting Codex review)

Fixed Codex's reproduced case ("Save" → "Don't Save"). Visual OCR matches now require the **same name**: every request word in the label and every label word in the request, with only plural differences allowed. Labels like "Don't Save", "Save as PDF", "Don't Delete", "Deleted" and "New Folder" never match "Save", "Delete" or "Folder". Accessibility label search is unchanged.

The benchmark now has an opposite-actions-only screen and requests that must return nothing. Results on an Apple M4 / macOS 26.6.2, 51 requests: accurate 49/51 exactly right, precision 1.000, median 47–66 ms; fast 39/51, precision 1.000, about 5–7 ms. Restoring the old looser rule drops precision to 0.870 / 0.740.

Tests are split:
- **Required, deterministic:** `GuideCursorCoreChecks`, 38 / 177. It includes a blank-image real-Vision smoke check.
- **Opt-in:** `swift run --package-path macos GuideCursorOCRChecks`, 3 / 20, real-OCR assertions that can vary by macOS version. Not in CI; CI has not run this increment.

Still offline: no capture, no UI, no Screen Recording request, no guidance to OCR boxes.

## Codex acceptance of offline Vision OCR increment

Codex reviewed the corrected local matcher and independently reran the deterministic core suite (38 checks / 177 assertions), optional real-OCR integration suite (3 checks / 20 assertions), offline benchmark, release build with verified ZIP extraction, and `git diff --check`; all passed. On this Apple M4 with macOS 26.6.2, the updated six-screen synthetic benchmark reported 49/51 exact requests in accurate mode and 39/51 in fast mode, with zero extra suggestions in its opposite-action cases. Accuracy on real application screenshots is unknown. The conservative visual matcher rejects “Save” when only “Don't Save,” “Save as PDF” or another longer/different action is present. AX label search remains separate. Real OCR assertions that can vary across macOS versions are opt-in rather than part of the required CI gate. See the current branch/PR checks for pushed CI evidence. This increment is offline only: no screen capture, permission request, OCR box or visual guidance is exposed in the app UI.
