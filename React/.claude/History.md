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
- **Glass: CSS frost** — a clear backdrop blur with a slight dim, **no fill, no saturate**, plus a **glassy edge** (specular top rim + hairline inner ring + soft lower-rim light). One shared material spread by `GlassSurface`/`GlassControls`. The Apple-style **SVG edge-lens** (true rim refraction) was explored and **shelved** — kept as `materials/edge-lens.tsx` and surfaced in the `glass-editor` tuning tool. `liquid-dom` (WebGPU) shelved earlier.

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

### Glass → CSS frost + window chrome (2026-06-17)

Replaced the glass material and window chrome. Built a comparison lab (a custom edge-bevel SVG lens + 8 npm liquid-glass libraries) and an Apple-recipe research pass (HIG + SwiftUI API + engineering reverse-engineerings: the refractive look is an edge-shaped displacement map, not turbulence; clear center, refractive rim; near-zero tint). Outcome: **CSS frost won** for the shipped material (it adds its own light, so it never collapses to a dark slab over a dark window the way clear refraction does). Pruned the lab + all comparison libraries; kept `materials/edge-lens.tsx` (SVG refraction) as a catalogued material (the standalone CSS glass editor was later folded into the showcase Glass-leaf tuner).

**Window chrome:** native frame kept (standard macOS corner radius + shadow — matching Swift apps) with the title bar hidden and the traffic lights positioned into the sidebar; an opaque window background so the sidebar glass samples the app, not the desktop (native vibrancy explored, then dropped). The glass material lives in `materials/glass-material.ts` (`frostMaterial`); sidebar radius/inset are `--glass-radius` / `--glass-inset` tokens; traffic-light position is in `main/index.ts`.

### PommoraDND — in-house drag engine, Phases 0–2 (2026-06-18)

Decided to **own** drag-and-drop rather than rent dnd-kit — same "own the layer, rent the engine then rebuild it" path as MarkdownPM. Backed by a line-by-line dissection of dnd-kit's ~5.2k dev-source lines (7 read-only agents) and a two-round adversarially-reviewed plan (`Planning/PommoraDND-Research.md`). The engine lives behind the `interactions/drag.tsx` seam; built + verified in the **Interaction Lab** (`interactions.html`), which is the design-system harness, **not** the app. `@dnd-kit` stays in `package.json` until parity, removed at cutover.

- **Phase 0 — unify the seam.** Collapsed the two divergent seam signatures into one canonical API (`SortableZone` / `DragGroup` / `useDragItem`) and ported every surface — including the board, which had been hand-rolling `DndContext` — onto it, **while still dnd-kit-backed**, so the engine swap is a pure internal change. Reviewed behaviour-identical.
- **Phase 1 — single-zone engine** (`engine.tsx`). One Pointer-Events sensor with `setPointerCapture` (no mouse/touch split, no document listeners); rects measured once at drag start (no array churn); closest-centre collision with hysteresis; one rects-reflow displacement covering list/row/wrapping-grid; **decide-then-animate** drop committing on the lifted item's `transitionend`. Drives list / grid / table / tree-within-level.
- **Phase 2 — cross-list board** (`group.tsx`). A `DragGroup` owns the one active drag; the lifted card is hidden in its column and rendered as a `position:fixed` portal overlay; columns shift items by a slot-pitch to show the landing gap; the move commits once via `onCommit(activeId, toZone, toIndex)`. No mid-drag mutation → the duplicate-card race dnd-kit's live cross-container moves required guarding against doesn't exist here.

**Decisions locked:** the seam is the only import surface for drag (engine swappable) · measure-once + commit-on-drop (no FLIP, no mid-drag churn) · single Pointer-Events sensor (Chromium scope) · decide-then-animate via `transitionend`, never a blind timer · the Lab is the verifier, app adoption is separate + later. **Not a 1:1 port** — drops dnd-kit generality we don't need (framework-agnostic core, 3 sensors, 4 collision strategies, modifier pipeline, SSR guards, continuous re-measuring) and adds pointer capture + hysteresis + a frame-accurate commit. Spec → `Features/DragAndDrop.md`; full kept/simplified/dropped ledger → `Planning/PommoraDND-Research.md`.

Then **Phases 4–6** landed in one autonomous pass (each adversarially reviewed + fixed; typecheck + 298 tests green, incl. 12 new pure-function tests for the displacement / auto-scroll / keyboard math):

- **Phase 4 — constraints**: `axis` lock, `bounds` clamp, a `modifiers` escape hatch, `swap` mode (`arraySwap`), and **async `canReorder`** (the lifted item holds in a `pending` state until the verdict resolves). Exercised by a Constraints Lab surface; the faithful list/grid/table/tree stay unchanged.
- **Phase 5 — auto-scroll** (`autoscroll.ts`): rAF loop, nearest scrollable ancestor, ease-in ramp + limit-awareness (vs dnd-kit's `setInterval`+linear); scroll delta compensated into the lifted item + collision. Added a capped-height scrolling Lab surface as the harness.
- **Phase 6 — keyboard + a11y** (`keyboard.ts`, `a11y.ts`): Space/Enter lift, arrow-key move (geometric next-slot getter for list/row/grid), Space/Enter/Tab drop, Esc cancel; assertive ARIA live region with position announcements, hidden instructions via `aria-describedby`, focus restore; focusable handle with a nullable role (table keeps `<tr>` semantics). Pointer + keyboard share one decide-then-animate path (`resolveDrop`).

**Cutover complete (2026-06-18):** Nathan Lab-inspected + approved (gate in the plan doc); `@dnd-kit/*` was **uninstalled** (import-free, gone from `package.json`); a final closeout review came back correctness-clean; and the shared vocabulary (`Box`/`DropState`/`DragItem`/`DragNotify`/`Modifier` types, `toBox`/`px` helpers, tuning constants) was hoisted into `shared.ts` — the one DRY pass, leaving the two engines' distinct in-place-vs-overlay lifecycles separate. All code identifiers are brand-free (`engine.tsx` / `group.tsx` / `Zone` / `useZoneItem` / `useGroupedDragItem` / …); "PommoraDND" lives only in docs (per the no-brand-in-code rule). 298 tests green. **Deferred (decisions):** tree **cross-level** reparenting (within-level works; flatten+project+rebuild approach in the feature spec), **board keyboard** access, and real-app adoption (sidebar tree, view rows — Lab-only today).

### Design system: showcase shell + color primitives (2026-06-18)

The standalone DesignSystem page, Interaction Lab, and CSS glass editor are now one hash-routed showcase (`design-system.html`) with a glass sidebar mirroring the app and leaves driven by a single registry; the glass editor became the Glass leaf's frost tuner (Surface / Control preset slots). Colors gained **system-grey / system-white / system-black** primitives — labels derive from system-white, fills / states / separators from system-grey, each at an opacity via `color-mix` rather than a baked hex. Tints are tokenized the same way — an opacity scale in `tint.ts` (`tint-primary 60 / secondary 40 / tertiary 20 / quaternary 15 / solid 100`) applied to any base via `tintAt(base, step)`; chips re-map onto it (fill = primary, border = secondary, text = label washed with quaternary), with tertiary reserved for tinted segments and solid for tinted buttons. **Locked:** `fill-primary` normalized 22% → 20%; segment (20%) kept a distinct token from fill-primary so they can diverge; spectrum solids and opaque surfaces stay literal values. Flagged: the app's `styles.css` chrome still uses pure `#FFFFFF` rather than system-white.
