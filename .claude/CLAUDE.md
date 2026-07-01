## Project Pommora

Pommora is a personal management app based on Nathan’s frustration with modern productivity apps that excel in one aspect but are absolutely terrible in others — Pommora is Nathan’s “Fine, I’ll do it myself — Thanos.” Pommora’s main leverage is taking the extremely flexible, properties-based categorization of Notion and the inherently agentic-legible, local-first approach used by Obsidian, aiming to create a true local-first, all-in-one productivity and organizational platform. Pommora’s structure is based on relating **Content** ←> **Content** through *Connections*, with their attributes given through their **Collection’s** schema-based **Properties,** and linking them all together through relationships to **Contexts.** 

**Contexts:** The organization layer — three free-standing tiers that Content relates *to*. None contains or parents another; an entity tags whichever tiers fit.

- **Areas:** broad life domains — Personal, Academics, Work.
- **Topics:** the subject areas within them — Productivity, Side Projects, Reading List.
- **Projects:** specific efforts — CS 161, Pommora, "Atomic Habits."

**Content:** The operational layer — what you actually make, linked to each other through **Connections** for content ←> content relations, and with **Front-matter** for content ←> tier relations.

- **Collections & Sets:** a **Collection** is a folder that carries a shared property schema and saved views; it nests Sets to any depth as organizing subfolders that inherit that schema.
- **Pages:** Markdown documents inside a Collection or Set, conforming to its Collection’s schema — the only Content that holds free prose. Pages use MarkdownPM for its editor surface, which includes in-line connections to other pages. 
- **Agenda:** the calendar layer — **Tasks** (reminder-shaped) and **Events** (calendar-shaped), each with a built-in Status.
- **Properties:** the typed attributes a Collection's schema defines, and its members fill in — Select, Status, Date, and the rest; the schema lives on the Collection, the values on each entity.
- **Connections:** inline `[[Title]]` colored-text links in a Page's body, stored in **SQLite**, connecting to another Page — the Content ←> Content matrix.

**Files are canonical.** Pages are `.md` (YAML frontmatter + body); Contexts, Agenda, and all config are JSON sidecars; an entity's kind comes from its folder's sidecar, not the extension. Foreign keys are preserved on every write, and the SQLite index is a regeneratable accelerator off the read path. Agent-legibility of a user's Nexes, and future cloud-sync capability are core constructs for all development.
**FULL SPEC** → `PommoraPRD.md` + `Features/` domain-specific documentation.

**Swift Origins:** Pommora was first built as a native SwiftUI app — that build was active for around one month and designed and versioned the entire paradigm; React was initially scoped as an alternative contingency. The decision to switch to React mostly came down to frustrations and limitations with SwiftUI, and to Claude's inherent massive capability disparity between Swift-based coding and TypeScript. 

### Stack

Pommora is an **Electron** desktop app — a **React + TypeScript** renderer over a Node main process that owns the filesystem. electron-vite · Electron 42 · React 19 · TypeScript 6 · Vite 7 + `@vitejs/plugin-react` 5 (compat pin — newer plugin-react needs Vite 8, which electron-vite doesn't support yet) · Zustand · TanStack Table/Virtual · `react-markdown` + `remark-gfm` · `eemeli/yaml` · `lucide-react` · Vitest. Editor: **MarkdownPM** — a CodeMirror 6 build behind a swappable editor seam. The codebase lives at `React/` on the monorepo's main branch.

**No dependency lock-in.** Every library sits behind a thin seam (SQLite behind `db.ts`, YAML behind `pageFile.ts`, IDs behind `ids.ts`, glass behind `Surface`) so it's swappable without touching callers. Version numbers are compatibility pins, not endorsements.

**Design source:** the Figma library (https://www.figma.com/file/fYZ5oiK7stC3diRhaBHl1r) is canonical for design values — mirror changes into the tokens. The live showcase deploys from `React/` to https://pommora-design-system.vercel.app.

### Formatting

Biome (`biome format`) auto-runs on every TS/CSS/JSON write via a PostToolUse hook — don't hand-align code, normalize quotes/semicolons/commas, or sort imports; write it correctly and let Biome handle style, and never run Biome yourself. If an Edit fails on a whitespace mismatch, Biome reformatted the file — re-read and retry; it's not a bug. Type-checking is separate and stays: `npm run typecheck` (two `tsc` passes) is the *only* type-safety gate, since the Vite/esbuild build strips types without checking them.

### Hard Rules

- **Main owns the filesystem.** All fs/Node lives in `src/main`, exposed to the renderer only through a **narrow typed IPC** bridge in `src/preload` (contextBridge). The renderer never touches `fs`/Node.
- **`src/shared/types.ts` is the cross-process contract.** No fs, no React there. Both sides import it.
- **IPC never throws across the boundary** — handlers return a `{ ok: true, … } | { ok: false, error }` envelope.
- **Filesystem is canonical.** The on-disk model is the portable contract (TS-native serialization). No SQLite on the read path *currently* — a single fs walk is the source (SQLite returns later as a regeneratable query accelerator).
- **Read and write are cleanly separable.** The read path is read-only by construction; mutations are additive, never woven into reads.
- **Condensed control flow / DRY / simplicity-first** — model finite states as unions + switch; hoist shared logic; don't add unrequested complexity.
- **Colors are authored as hex** — `#RRGGBB`, or `#RRGGBBAA` (8-digit) for alpha — never `rgb()` / `rgba()`. The token layer (`design-system/tokens/`) is the source; platform-returned values (e.g. `getComputedStyle`) are the only exception. Detail: `design-system/tokens/README.md`.
- **Docs name; code holds exacts.** These docs describe the *system* and reference the product spec (`PommoraPRD.md` + `Features/`) — they never restate exact code values. Name the token and its treatment ("the red solid at a low opacity"), never the literal `#hex` / `%` / line-for-line code stays in the code itself. 
- **`Handoff.md` is a lean snapshot maintained via `/handoff`.** Sections: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. 
### Locked Decisions

- **CommonJS main/preload** (package is NOT `type: module`) — Electron's `require('electron')` fails on ESM named imports; CJS also lets the preload stay sandboxed. **`sandbox: true` + `contextIsolation: true` + `nodeIntegration: false`.**
- **Single-window now, multi-window-ready seams** — data is main-owned + Query/store-cached per renderer; the live-refresh bus is a swappable transport; windows identified by serializable refs. No global singleton holding shared mutable client state.
- **TS-native on-disk format** (tagged PropertyValue, zod-validated) — built and tested against a dedicated **test nexus at `~/test`** (override via `TEST_NEXUS_PATH`).
- **Glass:** two materials. **Window** + **Surface** use a CSS frost (blur + brightness); **Controls** use Apple "Liquid Glass" (`@samasante/liquid-glass`, `feDisplacementMap` edge-refraction).  Recipe + rationale → `Features/Design.md`.

### Run Gotcha (Read Before Launching)

The GUI only launches with `ELECTRON_RUN_AS_NODE` **unset** (this env has it set to 1, which makes Electron run as plain Node → `require('electron')` returns a path string and the app crashes). Launch: `env -u ELECTRON_RUN_AS_NODE npm run dev` (HMR), or `… ./node_modules/.bin/electron .` after `npm run build`. `TEST_NEXUS_PATH` only steers tests, never the running app. Full notes in `Guidelines/Build-Gotchas.md`.

**Worktree Electron binary:** a worktree's `node_modules` is typically installed for the Vitest/Node gate only and **omits the Electron binary**, so the first `dev`/launch dies with `Error: Electron uninstall`. Fix: run `./node_modules/.bin/electron --version` once (downloads the binary), then relaunch.

### Important Information 

- Design tokens **must** be pulled from their sources in `design-system` — never hand-roll tokens without explicit direction.
- **Connections** are in-line `[[Title]]`, resolved via SQLite, and **aren’t** displayed in any container views *(tables, galleries, lists…)*. **Contexts** are properties resolved via front-matter; content ←> content relational properties **don’t** exist. 
- If Nathan mistakenly says "label-quaternary" or "label-quinary," he actually means fills → `design-system/tokens.` 

### Working Discipline

- **Ask before designing.** Stop to disclose assumptions and clarify direction before any design or interaction-based decision — don't guess at how something looks or behaves. *Void when Nathan's unreachable:* proceed on the best record of his design wishes and the existing design logic, but disclose every such decision and assumption as you make it.

### Document Map

Specs live in `Features/`; root docs (PRD · Handoff · History · Framework) sit at the `.claude` root.

```
Product spec — what Pommora is + how its data is shaped
  PommoraPRD.md   vision · domain model · storage philosophy · v1 scope
  Structure.md    domain-model map (two layers, identity, linking) + Homepage/Settings singletons
  Contexts · Collections · Views · PageSets · Pages · Properties ·
  Agenda · Connections · Navigation · Sidebar · Inspector · QuickCapture    per-entity + per-surface specs

Implementation — how this build works
  Architecture.md   data / read / IPC architecture
  MarkdownPM.md     CodeMirror 6 page editor      TableView.md    the table view renderer
  Design · Typography · Interaction · Icons    design system · type scale · motion · icon set
  PommoraDND.md     in-house drag engine          Subfield.md     the footer

Process + reference
  Handoff.md (read first) · History.md · Framework.md
  Guidelines/  build gotchas + don't-repeats     Resources/  libraries · distribution · macOS
  Planning/  active plans                         Deployment.md  Vercel showcase deploy
```

The paused Swift build's docs are archived under `Swift/` — its own `CLAUDE.md`, PRD, Features, Guidelines, and Planning. See **Swift Origins** above for why the line moved.
