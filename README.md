# GuideCursor

GuideCursor is the shared repository for our VU Digital Business & Information Systems group project.

GuideCursor is an assistive desktop concept that helps people use mainstream software through the familiar interface. The product focuses on guidance rather than autonomous task completion: it can help identify controls, provide directional or spoken guidance, surface captions and visual cues, and reduce fine-pointing demands while the user remains in control of the final action.

## Website

The repository contains the current GuideCursor concept website, including:

- Interactive accessibility demo with Vision, Hearing and Motor modes
- Perceive → Understand → Guide → Assist product flow
- Use Cases
- Pricing and simulated checkout
- Simulated macOS and Windows downloads
- Security & Trust
- Accessibility, Privacy, Terms and Cookie Policy
- Searchable Help Center
- Custom GuideCursor 404 page
- Responsive/mobile hardening and reduced-motion support

## Stack

- Vite
- Static HTML/CSS/JavaScript for the product website
- React/TypeScript files retained for prototype work
- Vercel deployment configuration

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

`main` should stay usable and presentation-ready.

For changes:

1. Pull the latest `main`.
2. Create a branch, for example `sarah/hearing-feasibility` or `dean/use-case-copy`.
3. Make and test the change locally.
4. Push the branch to GitHub.
5. Open a pull request into `main`.
6. Have another group member review it before merging when possible.

This keeps everyone from overwriting each other's work and makes it easy to see who changed what.

## Repository status

This repository was initialized from the latest GuideCursor website source that previously lived in `Teesxm/dbisassignment`.

The codebase is now intended to use **Teesxm/guidecursor as the shared source of truth** for future group work.

> Deployment note: the existing Vercel production project was originally connected to the old repository. Its Git source should be reconnected to `Teesxm/guidecursor` so future merges to `main` deploy automatically from this repository.

## Native macOS prototype

The desktop MVP is being developed in [`macos/`](macos/README.md), alongside this concept website. It includes an Accessibility-based control finder, native cursor companion, highlighting and spoken guidance. See its README for setup, current limitations and validation status.

```sh
./macos/scripts/build.sh && open ~/Library/Caches/nl.guidecursor.prototype/build/GuideCursor.app
```
