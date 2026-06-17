## History — Pommora React

Decisions + what shipped. Brief, not a work log.

### Project genesis (2026-06-14)

Spun up from the Swift project's React-rebuild exploration. Scope locked to the "core 7" (data · properties · connections · markdown · navigation · table · gallery); on-disk format modernized TS-native; built/tested against a test nexus at `~/test`. Two research workflows (Swift→React portability assessment + library/toolkit dual-look) back the roadmap.

### Phase 1 — Window + glass sidebar skeleton ✅

Read-only walking skeleton: `readNexus` (sidecar + structure-classification paths, lenient frontmatter, roll-up, stable adopted ids, ordering) → IPC `nexus:open` → Zustand store → recursive glass sidebar reading `~/test`. 15 vitest tests; typecheck + build green. Adversarially reviewed (read engine verified against the real `~/test`).

Key commits: `823ee65` skeleton · `50e37c5` CommonJS main/preload + sandbox + README · `ee616a0`…`de79a93` glass iterations.

### Locked decisions

- **One repo, one `main` (2026-06-16).** React is a sub-project of Project Pommora under `React/` — the *same app* as the Swift build, built differently. The earlier standalone `Pommora - React` checkout (React-at-root, subtree-merged into the monorepo) was **retired**: its full Phase 0–3 write path + tokenized design system resynced into `React/` and committed on `main`, byte-identical, with manual `main` tweaks preserved. No more two-repo / subtree sync.
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

### Data Layer (headless) — Phases 0–7 ✅ + Foundation Review (review-certified)

The complete write/mutation side, built tests-only (no UI wired), now fully caught up to Swift. Design + decisions in `Planning/Data-Layer-Design.md`; per-phase retrospective + flag adjudication in `Planning/Data-Layer-Build-Log.md`; grounded in a 20-agent dual-research pass with load-bearing claims verified against real Swift. **220 vitest tests; typecheck + build green at each commit.**

- **Phase 0 — contracts + atomic I/O** (`d523dcc`): `shared/result.ts`; `shared/propertyValue.ts` (the value codec in the locked Swift precedence, table-driven round-trip); `main/ids.ts` (the single ID owner — ulidx monotonic + `adoptedId`; DRY: removed the dup from readNexus/readPage); `main/io/atomicWrite.ts` (write-file-atomic, sorted/stable JSON, mutateJson, trash).
- **Phase 1 — page file engine** (`c0ba4df`): `main/io/pageFile.ts` — the envelope + foreign-preserving write via the yaml Document API (foreign keys **and comments** survive; the additive win over Swift).
- **Phase 2 — sidecars** (`8f71db9`): `shared/schemas.ts` (zod v4; schema = codec = type; `z.looseObject` retains foreign keys — closes Swift's JSON-sidecar data-loss gap; DRY shared builders collapse Swift's triplicated context managers); `main/kind.ts` (path-based kind authority, stateless probe); `main/sidecarIO.ts`.
- **Phase 3 — CRUD** (`18cda71`, `d55dc5a`, `6ae13c7`): `crud/folderEntity.ts` (ONE create/rename/delete/updateSidecar for all six folder entities) + `crud/page.ts` (create/rename/delete/updateBody/move) + `crud/reorder.ts`. filename = title; fresh ULID on create; delete → in-nexus `.trash`; partial updates govern only their keys; all return `Result`, never throw.
- **Phase 4 — properties** (`ab43e49`…`b3193e6`): value write + schema CRUD on the type sidecar (add/rename/reorder/delete/changeType) with atomic member strips via `io/schemaTransaction.ts` (two-phase commit) + tier synthesis (`properties/tiers.ts`).
- **Phase 5 — connections & tier relations** (`de0a878`…`5c63484`): pure-Map `[[link]]` engine (scan/rewrite/resolve/edges) + `crud/cascade.ts` (renameCascade + unlinkTier) + `setPageTier`. Resolution has NO SQLite dependency — the index is a pure accelerator.
- **Phase 6 — SQLite index** (`f54f869`…`7a85c4a`): `better-sqlite3` behind `db.ts`; 11-table schema (DDL structurally identical to Swift's, `SCHEMA_VERSION=14`) + version handshake (stamp-after-build) + per-entity upserts + cold build.
- **Phase 7 — Agenda** (`0f87383`…`5caf60b`): Tasks + Events item CRUD + index pop + config-schema CRUD by generalizing `crud/schema.ts` over a `SchemaTarget` (one five-op core serves pages + agenda).
- **Foundation review** (`d712999`…`e8f8364`): 7-agent adversarial review + hard DRY pass, every finding verified against source. Fixed criticals — SchemaTransaction rollback hole + dangerous `.bak-` sweep; index tier `target_kind` = `area`/`topic`/`project` (not `context_tier`); lenient colors; typed `ErrorCode`; `.md`/`.task.json` name guard; self-link skip — and collapsed duplicated helpers to single owners (`isPlainObject`, `applyPropertyValue`, `readJsonObject`, `pathExists`, `coerce.ts`, tier field/id). Flag adjudication (Fixed/Kept/Deferred) in the build log. **Swift→React data-layer LOC: 8,552 → 2,383 (~72%, shared-functionality-only).**

**Decisions locked:** byte-compatible on-disk format (native read/write, no codec) · `better-sqlite3` behind `db.ts` (Phase 6) · adoption mirrors Swift (minimal, `~/test` only) · "history" = Recents in state.json (no versioning) · `blocks: []` stays empty (catch up to Swift, don't go ahead). **Deviation theme:** every shipped enhancement is Swift framework-complexity deleted, with a capability (foreign-data preservation, crash-free kind-resolution) falling out for free.

**Remaining (all UI-gated, no data-layer logic left):** `mutate:*`/`index:*` IPC + preload bridge · incremental index upserts on mutation (+ electron-rebuild/asarUnpack) · cascade orchestration · the real UI from the Figma library. Two deferred-with-reason items (build sidecar re-read → side-channel read; connection engine onto the read walk) — see `Handoff.md` + build log § Foundation Review. The "readNexus → schemas" refactor is **refuted** (would re-couple lenient read to the write contract).

### Desktop & Filesystem Integration — Phases 0–3 ✅ (write path live)

Made the React app a real Mac app over a real on-disk nexus. Plan + deviations: `Planning/Desktop-Filesystem-Integration.md`.

- **Phase 0–1** (`05f9d78`…`6bd302e`): app config + session (no hardcoded path; restore-or-empty, never a launch modal); native folder picker + recents + `app.addRecentDocument`; drag-a-folder-to-open. **Phase 2** (`94fa54b`): native macOS menu bar.
- **Phase 3 — the write path** (`f913c7e`…`c972385`): `pathSafety.resolveUnderRoot` (realpath, the single guard, backported into `page:open`); container `path` on every node DTO (`PathNode`); one `mutate` IPC (create page/container/context + root-create · rename · delete · movePage; relative paths only). Cascade policy owned at the mutate layer — page rename → `renameCascade` with **revert-on-failure**; context delete → `unlinkTier` before the folder. Delete branches on `trashMode` (in-nexus `.trash` vs `shell.trashItem`). Native right-click context menus (New / Delete-confirm / Reveal) on every Sidebar row; **New Page ⌘N** end-to-end; create-name disambiguation centralized in main. Live SQLite index via **full-refresh** after each mutation. 4-agent adversarial review folded (never-throws IPC, Reveal path-guard, reserved-path guard, NUL-name, selection reconcile). **282 vitest tests; green.**

**Decisions locked:** renderer sends RELATIVE paths only, resolved under root via realpath · cascade policy lives at the mutate layer, not call sites · **index = full-refresh, not incremental** (reuses `buildIndex`, zero row-logic duplication; the once-built `deleteEntity` removed as unwired; incremental is a v1.1 perf optimization) · `db.ts` **lazy-requires** better-sqlite3 so a native-ABI mismatch degrades to a cold index, never crashes (the index is off the read path) · `node_modules` stays Node-ABI for the test gate; electron-builder rebuilds for Electron at package time. **Deferred (the remaining Phase 3 UI):** inline **rename** (op + menu exist, inline-edit UI doesn't) + top-level create affordances (New Vault / Area·Topic·Project). Packaged-index may be cold (electron-builder `buildFromSource=false` inconsistent) — invisible until a query consumer (Views) lands.
