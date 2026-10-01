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
