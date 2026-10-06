# GuideCursor

GuideCursor is the shared repository for Team 15's VU Digital Business & Information Systems project.

**Current positioning:** AI-guided pointer support for people with a visual impairment working on macOS.

The October 2026 pitch narrows the earlier concept substantially. The first MVP focuses on one user group (low vision to blindness), one platform (macOS) and one end-to-end journey (attaching a file to an email in Mail, including the file picker).

## Product principle

GuideCursor helps a user get from a goal to the right control while keeping every action human.

- The user activates GuideCursor by keyboard shortcut and states a goal by voice or keyboard.
- macOS Accessibility data provides real controls and their roles, labels, state and position.
- On-device screen recognition can add lower-confidence candidates when controls are unlabelled.
- The AI model chooses only from the observed candidate list.
- GuideCursor verifies the chosen control in the live window before guidance starts.
- Low-vision users receive a high-contrast outline, pointer-to-target arrow and optional Zoom.
- Blind users receive the target name plus short directional/distance sounds.
- GuideCursor never clicks, types, chooses a file or confirms an action for the user.

Hearing support, motor support, Windows and broad application coverage are deliberately outside the first MVP.

## MVP scope

### Core journey
1. Find **Attach** in Apple Mail.
2. Re-read the file-selection window.
3. Clarify which CV/file the user means if several match.
4. Guide to the chosen file.
5. Verify and guide to **Open**.

### Stretch tests
Only after the core journey is reliable:
- Downloading a file from Safari.
- Finding a menu command.

## Native macOS prototype

Development is active in Draft PR #1: **Add first native macOS GuideCursor prototype**.

The branch currently includes a native Swift app, macOS Accessibility control discovery, real-cursor guidance, spoken output, optional Ollama target suggestions, on-device OCR groundwork, diagnostics and build/signing tooling.

The main remaining gate is live installed-Mac verification of the full Mail → file picker → Open journey. The prototype should not be described as a production release yet.

## Processing model

The pitch paper proposes **local processing by default**. A local model served through Ollama is compared against an opt-in cloud model on target accuracy and response time.

- Screenshots stay on-device.
- Opt-in cloud inference receives only the text candidate list, never screenshots.
- The default architecture should be chosen from test evidence rather than assumed model capability.

## Business / adoption model

GuideCursor is no longer positioned as a consumer freemium SaaS product.

The proposed route is:
- Annual licence per user.
- Paid by an employer or potentially through a UWV work provision.
- Adoption through assistive-technology suppliers and trainers.
- Intended-user recruitment/co-design through organisations such as Visio, Bartiméus and Oogvereniging.
- Commercial price to be validated during a follow-up pilot.

## Website

The website has been updated to reflect the October 2026 pitch:
- Narrow visual-impairment / macOS positioning.
- Low-vision and blind guidance concept.
- Verified-target architecture.
- One Mail journey + two stretch tests.
- Local-first / opt-in cloud processing.
- Co-design and testing plan.
- Workplace funding and adoption model.
- Native prototype status rather than fake installers.
- Security, privacy, accessibility and help pages aligned to the narrowed MVP.

## Local development

```bash
git clone https://github.com/Teesxm/guidecursor.git
cd guidecursor
npm install
npm run dev
```

## Production build

```bash
npm run build
```

## Group workflow

Keep `main` presentation-ready.

1. Pull the latest `main`.
2. Create a branch, for example `alberto/mvp-development`.
3. Make and test changes locally.
4. Push the branch.
5. Open a pull request into `main`.
6. Review before merging when possible.
