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

Landing commit: `80e210e`.

### Data Layer (headless) — Phases 0–3 ✅

The complete write/mutation side, built tests-only (no UI wired). Design + decisions in `Planning/Data-Layer-Design.md`; grounded in a 20-agent dual-research pass with load-bearing claims verified against real Swift. **130 vitest tests; typecheck + build green at each commit.**

- **Phase 0 — contracts + atomic I/O** (`d523dcc`): `shared/result.ts`; `shared/propertyValue.ts` (the value codec in the locked Swift precedence, table-driven round-trip); `main/ids.ts` (the single ID owner — ulidx monotonic + `adoptedId`; DRY: removed the dup from readNexus/readPage); `main/io/atomicWrite.ts` (write-file-atomic, sorted/stable JSON, mutateJson, trash).
- **Phase 1 — page file engine** (`c0ba4df`): `main/io/pageFile.ts` — the envelope + foreign-preserving write via the yaml Document API (foreign keys **and comments** survive; the additive win over Swift).
- **Phase 2 — sidecars** (`8f71db9`): `shared/schemas.ts` (zod v4; schema = codec = type; `z.looseObject` retains foreign keys — closes Swift's JSON-sidecar data-loss gap; DRY shared builders collapse Swift's triplicated context managers); `main/kind.ts` (path-based kind authority, stateless probe); `main/sidecarIO.ts`.
- **Phase 3 — CRUD** (`18cda71`, `d55dc5a`): `crud/folderEntity.ts` (ONE create/rename/delete/updateSidecar for all six folder entities) + `crud/page.ts` (create/rename/delete/updateBody/move). filename = title; fresh ULID on create; delete → in-nexus `.trash`; partial updates govern only their keys; all return `Result`, never throw.

**Decisions locked:** byte-compatible on-disk format (native read/write, no codec) · `better-sqlite3` behind `db.ts` (Phase 6) · adoption mirrors Swift (minimal, `~/test` only) · "history" = Recents in state.json (no versioning) · `blocks: []` stays empty (catch up to Swift, don't go ahead). **Deviation theme:** every shipped enhancement is Swift framework-complexity deleted, with a capability (foreign-data preservation, crash-free kind-resolution) falling out for free.

**Remaining:** Phase 3 reorder + `mutate:*` IPC wiring (handlers headless-testable; renderer stays stub) · readNexus DRY refactor (deferred polish) · Phase 4 properties · Phase 5 connections · Phase 6 SQLite index.
