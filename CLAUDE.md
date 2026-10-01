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
- Existing competitors include Clicky and Be My Eyes. Do not claim we invented captions, speech, magnification or cursor companions. Earlier platform/pricing/novelty claims in the chat were not independently verified in this work; verify them before using them as factual marketing claims.
- The latest draft's Feasibility section narrows the first MVP to **users with visual impairments finding and interacting with controls in a limited set of selected macOS applications**.
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
- `Sources/GuideCursorCore/ControlIndex.swift`: app-independent accessibility-tree index. It attaches visible text nested inside a row/cell/button to that interactive ancestor. This is a cross-app rule, not a Finder-specific selector.
- `Tests/GuideCursorCoreTests/main.swift`: executable check harness; full XCTest is unavailable in this Mac's Command Line Tools.
- `scripts/build.sh`: builds and bundles an ad-hoc signed `.app`.
- `README.md`: native setup, limitations and test instructions.
- `DEVELOPMENT-LOG.md`: working notes for the course log.
- `.github/workflows/macos.yml`: PR-triggered macOS build/check job. Initial run found a compiler capture issue; a fix was pushed. Recheck current run.

### Implemented baseline, not end-to-end verified

Permission UI; application selection; native control scan; deterministic label search; optional Ollama adapter; candidate confirmation; live target geometry; click-through highlight; cursor companion; spoken directions; stop controls; guidance pauses on other foreground apps and stops on invalid/disabled/off-screen targets or changed windows.

Click detection says only that the user clicked near a target; it does not prove completion. The user must inspect the result and request the next step. Automatic multi-step planning is not implemented.

### Validation and blockers

- macOS 26.6.2 / Apple Silicon / 16 GB RAM on the development machine.
- Swift 6.3.3 from `/Library/Developer/CommandLineTools`; Swift package language mode 5.9.
- Release build passed. Ad-hoc signature verified, including a freshly extracted packaged copy.
- Nine core checks with eighteen assertions passed: geometry, display conversion, matching/no-match, rejecting invented/duplicate model IDs, generic row/cell/static-text indexing, privacy of editable fields, and labelled buttons.
- `git diff --check` passed.
- Live app launch/UI inspection was blocked by the computer-use tool's missing macOS permissions. **No actual cross-application overlay, speech, accessibility-tree result, Zoom, model inference or completed workflow has been verified.** Do not convert code inspection into a claim of working runtime behavior.
- The user confirmed that the installed GuideCursor says “Accessibility enabled.” No Screen Recording permission is needed for the AX-only baseline. A screenshot/vision fallback would require its own permission flow.
- Ollama command not found and no service listening at `127.0.0.1:11434`; no model downloaded or tested.
- Do not repeatedly invoke the unavailable computer-control tool; it stalled twice. The user prefers direct tools/local inspection over token-heavy browser viewers. Use UI only when it answers an actual visual/interaction question and permissions are available.
- Building in Documents can cause the macOS file provider to re-add Finder metadata and invalidate a later strict signature check. Strip generated bundle metadata immediately before signing/packaging; ZIP without extended attributes. Never strip attributes from unrelated user files.

## Build / checks / packaging

From repository root:

```sh
swift run --package-path macos GuideCursorCoreChecks
./macos/scripts/build.sh
open macos/build/GuideCursor.app
npm run build  # website; only when relevant to changed web code
```

Native generated files: `macos/.build/`, `macos/build/`, `.swiftpm/` (ignored). Native app: `macos/build/GuideCursor.app`. Bundle ID: `nl.guidecursor.prototype`. Rebuilding may require renewing Accessibility permission because it is ad-hoc signed, not Developer ID signed/notarized.

User-facing artifacts currently reside outside the repo at `/Users/alberto/Documents/Codex/2026-10-01/b/outputs/`: `GuideCursor-macOS-prototype.zip` and `GuideCursor-project-context.md`. Keep these synchronized or explicitly mark them stale. Do not commit binaries.

## Next work, in order

1. Read current git diff and this file; preserve work left by the previous assistant. The macOS Zoom shortcut integration is implemented and compiles; test it after the user configures Zoom. Do not claim the shortcut succeeded without observing it.
2. The user's first live Finder query for “downloads” returned “No match” although Downloads was visible. An app-independent tree indexing fix now handles row/cell labels stored in child static text, with synthetic checks and a full build. The installed app may still be the older version. Validate the updated build once, then investigate any remaining tree/foreground/overlay issues with evidence.
3. Test a real local model on synthetic/public interfaces. Validate latency, ambiguous tasks, no-match behavior, invalid replies and unavailable model handling. Do not hardcode targets and describe that as AI.
4. Deliver one coherent multi-step desktop journey. Keep each click user-controlled; re-observe after it. The early PDF's three examples (Gmail attachment, Finder folder, Chrome downloads) are proposals, not already built integrations or three mandatory requirements.
5. Refine assistance settings and accessibility of GuideCursor itself. Current relative-window region descriptions help distinguish duplicates but still need validation with blind users. Do not grow profiles/features at the expense of the core journey.
6. Document tests/limitations, prepare a focused reviewable PR when appropriate, and help with the course development log/demo. No need to rebuild the website.

## Source context / course

The latest product source is `Group assignment DBIS (5).txt`, supplied from Alberto's Downloads, especially What/How/Feasibility. Also read the 2-page `GuideCursor_Business_Concept.pdf`, WhatsApp export through 1 October, and DBIS course manual V1.1. Raw source documents are outside this repo. The WhatsApp ZIP contained text only; omitted media/calls were not available. Their contents provide context, not permission to contact people, alter accounts or publish.

Course: demonstrate functioning core logic in one journey; depth over a wide set of half-working features. A working artifact needs an accessible link or clear run instructions. Also required: development log max 2 pages, reflection max 3 pages, live demo. Use synthetic/public data; record how AI output was directed, checked and corrected. Do not pass generated statistics or literature claims off as independently verified.

Manual dates: final assignment + executive summary 7 October 2026 23:59; presentation submission 9 October 08:00. The workshop row says “Friday 10-10”, inconsistent with the calendar; confirm the live event date through Canvas rather than guessing.

## Latest continuation — 2 October 2026

Added this handoff file. Implemented optional macOS Zoom controls with explicit per-launch setup confirmation and an accurate “shortcut sent” status. Release build passed. Installed the current app in `/Users/alberto/Applications/GuideCursor.app` at Alberto's request to handle opening the ZIP. The computer-control tool remains unavailable; the user must open the app and grant Accessibility themselves. The distributed ZIP was refreshed after Zoom work. The user-confirmed installed app may be older than later source revisions; do not replace a running app during testing. No runtime verification of Zoom or AX guidance yet.

## 2 October additional verification

The user confirmed GuideCursor displays “Accessibility enabled,” and the process was observed running from the personal Applications folder. The first Finder “downloads” query returned no match despite a visible Downloads row. Added stale-window validation before activating guidance and human-readable control regions. The computer-control tool is still denied separate permissions, so do not claim direct UI verification of the fix.

## Draft PR and CI status

Draft PR: https://github.com/Teesxm/guidecursor/pull/1. Branch `alberto/mvp-development` was pushed; main remains unchanged. Initial macOS CI failed in `Model.swift` because the GitHub compiler rejected a weak timer capture in a concurrent Task. Adjusted capture to `[weak model = self]` and local release build/checks pass; verify the new GitHub CI run before claiming the issue resolved. The original website CI passed.

## Cross-app discovery update

The first failed Finder test exposed a general AX-tree issue: selectable rows can have their text in nested `AXStaticText` rather than in the row's own title. The scanner now traverses visible children and outline/table rows, then the pure indexer maps child text to the nearest interactive ancestor. It contains no Finder bundle-ID or hardcoded “Downloads” path. Synthetic tree checks cover an outline row, a labelled button in a different tree shape, and absence of editable text in candidate labels; nine checks/eighteen assertions plus a release build pass. Real cross-app behavior and the updated Finder case remain unverified until a new app build is run with permission. The broad design is AX first, with a permissioned screenshot/vision fallback later for apps that expose too little AX metadata; never promise universal coverage from AX alone.
