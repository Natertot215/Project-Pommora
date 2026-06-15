## History — Pommora React

Decisions + what shipped. Brief, not a work log.

### Project genesis (2026-06-14)

Spun up from the Swift project's React-rebuild exploration. Scope locked to the "core 7" (data · properties · connections · markdown · navigation · table · gallery); on-disk format modernized TS-native; built/tested against a test nexus at `~/test`. Two research workflows (Swift→React portability assessment + library/toolkit dual-look) back the roadmap.

### Phase 1 — Window + glass sidebar skeleton ✅

Read-only walking skeleton: `readNexus` (sidecar + structure-classification paths, lenient frontmatter, roll-up, stable adopted ids, ordering) → IPC `nexus:open` → Zustand store → recursive glass sidebar reading `~/test`. 15 vitest tests; typecheck + build green. Adversarially reviewed (read engine verified against the real `~/test`).

Key commits: `823ee65` skeleton · `50e37c5` CommonJS main/preload + sandbox + README · `ee616a0`…`de79a93` glass iterations.

### Locked decisions

- **CommonJS main/preload** (not `type: module`) — ESM `require('electron')` named imports fail at runtime; CJS also keeps the preload sandboxable.
- **`sandbox: true` + `contextIsolation: true` + `nodeIntegration: false`.**
- **No SQLite on the read path** — a single fs walk is the source (proven against the Swift sidebar's own behavior); SQLite returns later only as a regeneratable query accelerator.
- **Title-fallback ordering for adopted entities** (hash ids aren't meaningful order); ULID-id fallback for sidecar entities.
- **Vite 7 + plugin-react 5 pin** (newer plugin-react needs Vite 8, unsupported by electron-vite 5).
- **Glass:** Apple-Regular CSS, edge-defined (no body brightness/white fill). `liquid-dom` (WebGPU) evaluated and shelved (experimental flag + invasive).

### Phase 2 — Navigation spine + view pipeline ✅ (renderers stubbed)

The build workflow shipped the **tested logic spine**, deliberately leaving the visual renderers as honest placeholders:

- **`page:open` IPC** (`src/main/index.ts`) — path-traversal-guarded (rejects non-string/empty/absolute/`..`-climbing via `resolve`/`relative`/`sep`); never throws across the boundary.
- **`readPage`** (`src/main/readPage.ts`) — on-demand single-page read: lenient frontmatter split + body extraction, stable `adopted-<sha256>` id.
- **Pure view pipeline** (`src/renderer/src/views/pipeline.ts`) — side-effect-free `filter (AND) → group → sort` over `ViewRow[]`; empties sort last; `ViewRow.frontmatter` is optional so frontmatter-keyed columns light up later with no pipeline change.
- **Selection → detail routing** (`DetailPane.tsx` + store `pageStatus`/`pageDetail`) — real wiring; the vault (Table/Gallery) and page-render branches are **placeholders** ("coming next").

Read-only; write/CRUD/editor/properties/connections deferred. **Not yet built:** the Table (TanStack) + Gallery renderers and the react-markdown page render (deps installed, unused). 20 vitest tests; typecheck + build green.

Landing commit: _(this commit)_
