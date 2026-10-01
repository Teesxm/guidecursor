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
- `Sources/GuideCursorCore/ControlIndex.swift`: app-independent accessibility-tree index. It attaches visible text nested inside a row/cell/button to that interactive ancestor. This is a cross-app rule, not a Finder-specific selector.
- `Tests/GuideCursorCoreTests/main.swift`: executable check harness; full XCTest is unavailable in this Mac's Command Line Tools.
- `scripts/build.sh`: builds and bundles an ad-hoc signed `.app`.
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
