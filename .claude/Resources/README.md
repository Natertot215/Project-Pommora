## Resources — Build Reference

Forward-looking reference for the React + Electron build: the vetted library menu and architecture notes for work **not yet built**. Replaces the retired `.claude/ReactInfo/` (written when React was a contingency path, before the build began).

**Read this as a menu, not a commitment.** Choices here are candidates until the build makes them; always reconcile against `React/package.json` before trusting a version or a "decided" claim. Shipped architecture lives in `Features/`; active phase specs in `Planning/`; product truth in the root `PommoraPRD.md`.

### Files

- `Libraries.md` — the vetted library catalog (each tagged Decided / Candidate / Not-yet-needed)
- `Editor.md` — the Pages editor + the deferred block editor; serialization, directives, wikilinks
- `Mac-Integration.md` — Electron macOS integration ceilings (first-party / companion-bundle / hard-ceiling)
- `Distribution.md` — packaging, signing, notarization, auto-update, MAS sandbox
