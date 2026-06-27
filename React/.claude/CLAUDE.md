## Pommora — React (Project Instructions)

### Overview

A React + TypeScript + Electron rebuild of Pommora ("a simpler Notion that's also a more capable Obsidian"), **behavior-identical to the PRD** — SwiftUI is left behind. The product spec, domain model, and on-disk paradigm are the same as the Swift app; only the "how" changes.

- **Product truth** lives in the Swift project: `// Projects // Project Pommora // .claude // PommoraPRD.md` (+ its `Features/*`). Don't re-document the domain model here — reference it.
- **This is a sub-project of Project Pommora** — the React + Electron rebuild, living at `React/` on the monorepo `main` (one repo, one `main`). It's the *same app* as the Swift build, just built differently. These docs (`React/.claude/`) cover the React/TS/Electron *how* and the build's state; shared product truth lives at the repo root. The former standalone `Pommora - React` checkout is **retired** — all React work happens here.
- **Live design-system showcase:** https://pommora-design-system.vercel.app — Vercel, deploys from the `React/` folder of the `Project-Pommora` monorepo on `main`.
- **Figma library (source of design):** https://www.figma.com/file/fYZ5oiK7stC3diRhaBHl1r — canonical design values; mirror changes here into the tokens.

### Stack (current — swappable, not locked)

electron-vite · Electron 42 · React 19 · TypeScript 6 · Vite 7 + `@vitejs/plugin-react` 5 (compat pin — newer plugin-react requires Vite 8, which electron-vite doesn't support yet) · Zustand · TanStack Table/Virtual · `react-markdown` + `remark-gfm` · `eemeli/yaml` · `lucide-react` · Vitest. Editor: **MarkdownPM** — a CodeMirror 6 port, behind a swappable editor seam.

**No dependency lock-in.** Every library sits behind a thin seam (SQLite behind `db.ts`, YAML behind `pageFile.ts`, IDs behind `ids.ts`, glass behind `Surface`) so it's swappable without touching callers. Version numbers are compatibility pins, not endorsements; nothing above is a permanent commitment.

### Formatting

Biome (`biome format`) auto-runs on every TS/CSS/JSON write via a PostToolUse hook — don't hand-align code, normalize quotes/semicolons/commas, or sort imports; write it correct and let Biome handle style, and never run Biome yourself. If an Edit fails on a whitespace mismatch, Biome reformatted the file — re-read and retry, it's not a bug. Type-checking is separate and stays: `npm run typecheck` (two `tsc` passes) is the *only* type-safety gate, since the Vite/esbuild build strips types without checking them.

### HARD RULES

- **Main owns the filesystem.** All fs/Node lives in `src/main`, exposed to the renderer only through a **narrow typed IPC** bridge in `src/preload` (contextBridge). The renderer never touches `fs`/Node.
- **`src/shared/types.ts` is the cross-process contract.** No fs, no React there. Both sides import it.
- **IPC never throws across the boundary** — handlers return a `{ ok: true, … } | { ok: false, error }` envelope.
- **Files are canonical.** The on-disk model is the portable contract (modernized TS-native serialization). No SQLite for the read path — a single fs walk is the source (SQLite returns later only as a regeneratable accelerator for queries).
- **Read and write are cleanly separable.** The read path is read-only by construction; mutations are additive, never woven into reads.
- **Condensed control flow / DRY / simplicity-first** — model finite states as unions + switch; hoist shared logic; don't add unrequested complexity.
- **Colors are authored as hex** — `#RRGGBB`, or `#RRGGBBAA` (8-digit) for alpha — never `rgb()` / `rgba()`. The token layer (`design-system/tokens/`) is the source; platform-returned values (e.g. `getComputedStyle`) are the only exception. Detail: `design-system/tokens/README.md`.
- **Docs name; code holds exacts.** These docs describe the *system* and reference product truth (root `PommoraPRD.md` + `Features/`) — they never restate exact code values. Name the token and its treatment ("the red solid at a low opacity"), never the literal `#hex` / `%` / line-for-line code; exacts live in `design-system/tokens/` + Figma.

### Locked decisions

- **CommonJS main/preload** (package is NOT `type: module`) — Electron's `require('electron')` fails on ESM named imports; CJS also lets the preload stay sandboxed.
- **`sandbox: true` + `contextIsolation: true` + `nodeIntegration: false`.**
- **Single-window now, multi-window-ready seams** — data is main-owned + Query/store-cached per renderer; the live-refresh bus is a swappable transport; windows identified by serializable refs. No global singleton holding shared mutable client state.
- **Modernized TS-native on-disk format** (tagged PropertyValue, zod-validated) — built/tested against a dedicated **test nexus at `~/test`** (override via `TEST_NEXUS_PATH`).
- **Glass:** two materials. **Window** + **Surface** use a CSS frost (blur + brightness); **Controls** use Apple "Liquid Glass" (`@samasante/liquid-glass`, `feDisplacementMap` edge-refraction). `liquid-dom` (WebGPU) was evaluated and shelved. Recipe + rationale → `Features/Design.md`.

### Run gotcha (read before launching)

The GUI only launches with `ELECTRON_RUN_AS_NODE` **unset** (this env has it set to 1, which makes Electron run as plain Node → `require('electron')` returns a path string and the app crashes). Launch: `env -u ELECTRON_RUN_AS_NODE npm run dev` (HMR), or `… ./node_modules/.bin/electron .` after `npm run build`. The running app opens its last nexus (`pommora.json` `lastNexusPath`) or ⌘O to pick one — `TEST_NEXUS_PATH` only steers tests, never the running app. Full notes in `Guidelines/Build-Gotchas.md`.

**Worktree Electron binary:** a worktree's `node_modules` is typically installed for the Vitest/Node gate only and **omits the Electron binary**, so the first `dev`/launch dies with `Error: Electron uninstall`. Fix: run `./node_modules/.bin/electron --version` once (downloads the binary), then relaunch.

### Document map

- `Handoff.md` — current state + next session (read first).
- `History.md` — what shipped + locked decisions, newest first (brief).
- `Framework.md` — the continuous roadmap (shipped spine + what's next; no phases — the rebuild goes as it goes).
- `Prospects.md` — ideas considered and deliberately parked (off the roadmap, not yet planned).
- `Features/Architecture.md` — the data/read/IPC architecture.
- `Features/MarkdownPM.md` — the page editor's feature map (exhaustive build spec in `Planning/MarkdownPM.md`).
- `Guidelines/` — build gotchas + decisions not to repeat.
- `Planning/` — active plans (Phase specs).
- `Deployment.md` — Vercel showcase deploy (where to point + settings).
