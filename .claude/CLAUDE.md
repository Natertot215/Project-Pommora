## Pommora — React (Project Instructions)

### Overview

A React + TypeScript + Electron rebuild of Pommora ("a simpler Notion that's also a more capable Obsidian"), **behavior-identical to the PRD** — SwiftUI is left behind. The product spec, domain model, and on-disk paradigm are the same as the Swift app; only the "how" changes.

- **Product truth** lives in the Swift project: `// Projects // Project Pommora // .claude // PommoraPRD.md` (+ its `Features/*`). Don't re-document the domain model here — reference it.
- **This project is the rebuild.** Its docs cover the React/TS/Electron *how* and the build's state.

### Stack (locked)

electron-vite · Electron 42 · React 19 · TypeScript 6 · Vite 7 + `@vitejs/plugin-react` 5 (pinned — newer plugin-react requires Vite 8, which electron-vite doesn't support yet) · Zustand · TanStack Table/Virtual · `react-markdown` + `remark-gfm` · `eemeli/yaml` · `@phosphor-icons/react` · Vitest. Editor (deferred): **CodeMirror 6**.

### HARD RULES

- **Main owns the filesystem.** All fs/Node lives in `src/main`, exposed to the renderer only through a **narrow typed IPC** bridge in `src/preload` (contextBridge). The renderer never touches `fs`/Node.
- **`src/shared/types.ts` is the cross-process contract.** No fs, no React there. Both sides import it.
- **IPC never throws across the boundary** — handlers return a `{ ok: true, … } | { ok: false, error }` envelope.
- **Files are canonical.** The on-disk model is the portable contract (modernized TS-native serialization). No SQLite for the read path — a single fs walk is the source (SQLite returns later only as a regeneratable accelerator for queries).
- **Read and write are cleanly separable.** The read path is read-only by construction; mutations are additive, never woven into reads.
- **Condensed control flow / DRY / simplicity-first** — model finite states as unions + switch; hoist shared logic; don't add unrequested complexity.

### Locked decisions

- **CommonJS main/preload** (package is NOT `type: module`) — Electron's `require('electron')` fails on ESM named imports; CJS also lets the preload stay sandboxed.
- **`sandbox: true` + `contextIsolation: true` + `nodeIntegration: false`.**
- **Single-window now, multi-window-ready seams** — data is main-owned + Query/store-cached per renderer; the live-refresh bus is a swappable transport; windows identified by serializable refs. No global singleton holding shared mutable client state.
- **Modernized TS-native on-disk format** (tagged PropertyValue, zod-validated) — built/tested against a dedicated **test nexus at `~/test`** (override via `TEST_NEXUS_PATH`).
- **Glass:** Apple-Regular CSS (edge-defined: specular rim + dark containment edge, no body brightness/white fill). `liquid-dom` (WebGPU) evaluated and **shelved** (experimental HTML-in-Canvas flag + invasive scene-graph). See `Guidelines/`.

### Run gotcha (read before launching)

The GUI only launches with `ELECTRON_RUN_AS_NODE` **unset** (this env has it set to 1, which makes Electron run as plain Node → `require('electron')` returns a path string and the app crashes). Launch:
`env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` (after `npm run build`). Full notes in `Guidelines/Build-Gotchas.md`.

### Document map

- `Handoff.md` — current state + next session (read first).
- `History.md` — what's been built + decisions/commits (brief).
- `Framework.md` — phased roadmap + status.
- `Features/Architecture.md` — the data/read/IPC architecture.
- `Guidelines/` — build gotchas + decisions not to repeat.
- `Planning/` — active plans (Phase specs).
