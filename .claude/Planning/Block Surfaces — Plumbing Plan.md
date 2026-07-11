## Block Surfaces — Plumbing Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans, inline, on branch `surfacepm` — adversarial review via `build-breaking-agent` after EACH task, findings verified first-hand before folding. The spec is `7-10 - Block Surfaces — Decision Log.md` (review-certified); every decision tag cited here (D-3, E-5, …) resolves there.

**Goal:** Wire the shipped SurfacePM engine to real content — persisted block documents, markdown/page/view tiles, the shared embed framework, link-graph coverage, and chrome — everything non-design-dependent.

**Architecture:** The engine stays a controlled component (`layout` in, `onLayoutChange` out). A new `blocks` IPC namespace persists the block document behind the **BlockHost seam** with `homepage.json` as the removable dev host (G-12). Tile payloads are a zod tagged union in shared; the renderer resolves payloads to a `Blocks/` component family. Main owns every file touch.

**Tech Stack:** existing — Electron IPC envelopes, zod, MarkdownPM, TableView, Vitest.

### Global Constraints

- Gates per task: `env -u ELECTRON_RUN_AS_NODE npm run typecheck` + `npx vitest run <scoped suites>` from `Pommora/`, then commit **explicit paths**.
- IPC never throws — `{ ok } | { ok: false, error }` envelopes; renderer paths are nexus-relative POSIX.
- Foreign keys survive every sidecar write (`mutateJson` read-merge-write); unknown tile entries render inert, never stripped (E-1); dead references render inert placeholders (E-2).
- Layout writes are debounced on gesture end; block content loads are targeted per-host, never woven into the tree walk (E-3).
- Tokens only; no keyboard shortcuts beyond Esc; main-process changes need a dev restart; CDP verification drives throwaway content only — though `homepage.json` writes are real by design (G-12).

### Task 1 — Block Document + Persistence (SHIPPED)

**Files:** Create `src/shared/blocks.ts` + `blocks.test.ts`; create `src/main/blocks.ts` + `blocks.test.ts`; modify `src/shared/types.ts` (nothing — doc types live in `blocks.ts` like `mutate.ts` does), `src/main/paths.ts` (host-folder path helper), `src/main/index.ts` (handlers), `src/preload/index.ts`, `src/renderer/src/SurfacePM/core/codec.ts` (import raw layout schemas from shared), `src/renderer/src/Detail/HomepageView.tsx` (real surface over the doc).

**Interfaces (produces):**

```ts
// shared/blocks.ts
export type BlockHostRef = { kind: 'homepage' }            // extensible union — THE BlockHost seam (D-2)
export interface MarkdownBlockEntry { id: string; type: 'markdown' }           // file = <id>.md in the host folder (D-11)
export interface PageBlockEntry { id: string; type: 'page'; page_id: string }  // + chrome fields land in Task 3
export interface ViewBlockEntry { id: string; type: 'view'; view_id?: string; source_id?: string; config?: unknown } // Task 4 fills this in
export type BlockEntry = MarkdownBlockEntry | PageBlockEntry | ViewBlockEntry
export interface BlockDoc { layout: unknown; blocks: unknown[]; locked?: boolean }  // blocks stay raw-preserving (E-1)
export function knownBlock(raw: unknown): BlockEntry | null                    // per-entry parse; null = foreign, render inert
export type BlocksGetResult = { ok: true; doc: BlockDoc } | { ok: false; error: string }
```

The raw layout zod schemas (`RawTile`/`RawRow`/`RawColumn` + the bands object) **move from `SurfacePM/core/codec.ts` into `shared/blocks.ts`**; the codec imports them (one schema source, repair logic stays in the engine). On disk the doc is two keys on the host sidecar/config — `blocks` (the Swift-reserved array, now modeled) and `layout` — plus `blocks_locked` for G-3.

**Steps:**

- [ ] `shared/blocks.ts` with the schemas above; tests: known/unknown entry parse, layout schema round-trip (reuse codec fixtures).
- [ ] `main/blocks.ts`: `readBlockDoc(root, host)` (reads `homepage.json`, returns `{ layout, blocks, locked }` raw) and `writeBlockDoc(root, host, patch)` via `mutateJson` on `nexusConfig(root, NEXUS_CONFIG_FILES.homepage)` — only `layout`/`blocks`/`blocks_locked` keys touched, banner + foreign keys survive. **Every homepage.json writer serializes on the config path** (`serializeOnFile`, the page-branch precedent at `mutate.ts:266`): `writeBlockDoc` AND `setBanner`'s homepage/sidecar branch, which today runs bare `mutateJson` — a banner write racing a debounced layout write is a whole-file lost update. Test: foreign-key survival + interleaved banner/layout writes both land.
- [ ] `paths.ts`: `blockHostDir(root, host)` → `.nexus/homepage` (the homepage host's `.md` folder — Task 2 consumes it). Add block host dirs to the watcher's ignore set (`watcher.ts` — the E-3 knob: a debounced block-body write must not trigger a full re-walk; `homepage.json` itself stays watched, the tree reads its banner).
- [ ] Handlers `blocks:get` / `blocks:save` in `main/index.ts` + preload `blocks.get(host)` / `blocks.save(host, patch)` following the `subfield` pattern.
- [ ] Renderer: `useBlockDoc(host)` hook — loads on mount, decodes layout through the repairing codec, exposes `saveLayout` debounced (gesture-end writes, E-3). `HomepageView` swaps `SurfaceLab` for `SurfaceView` over the doc (Lab stays reachable from the showcase leaf).
- [ ] Gates; live check: drag/resize on the Homepage, relaunch dev, layout survived. Commit.

### Task 2 — Markdown Block Tiles (SHIPPED)

**Files:** Create `src/renderer/src/Blocks/MarkdownBlock.tsx` (the G-2 family starts here); modify `main/blocks.ts` + `index.ts` + preload (create/remove/read/write ops), `HomepageView` wiring (renderTile switches on resolved payload).

**Interfaces (produces):** `blocks.createMarkdown(host)` → `{ ok, id }` — main `mkdir`s `blockHostDir` first (recursive; the dir is main-derived and safe by construction, so it bypasses `resolveUnderRoot` exactly as `createContext` uses `contextTierDir`), mints the ULID, writes the empty `.md`, appends the `blocks[]` entry; the renderer then splices the layout and saves. An entry with no leaf is legal and invisible; **a leaf whose id resolves to no entry renders the inert placeholder** (the E-1/E-2 path — it occupies its space until removed). `blocks.removeTile(host, tileId)`: the renderer splices the leaf out and saves the layout **first**, then the op drops the entry and trashes a markdown tile's `.md` via **`trashWithTimestamp`** (the primitive already handles files — E-5's "new op" is this IPC op). `blocks.readMarkdown` / `blocks.writeMarkdown` are **dedicated pure-body ops under `serializeOnFile`** — the page ops do accept `.nexus/…` paths, but `page:updateBody` stamps a `modified_at` frontmatter envelope onto what must stay a frontmatter-free file (D-11), so reuse is off the table.

**Steps:** IPC ops + tests (create mints + file exists; remove trashes file + drops entry; foreign entries untouched) → `MarkdownBlock` static render (existing `react-markdown` read path) with click-to-edit mounting MarkdownPM, single live editor, exit on click-out/Esc (E-4; CM6 remount gotcha: extension changes need ⌘R) → new-tile flow: a plain "add" affordance in the host (chrome lands in Task 6; G-7 default = markdown) → gates, CDP pass on a throwaway tile, commit.

### Task 3 — Shared Page-Embed Framework (SHIPPED — revised live: the CM6 portal, E-4; header parked pending the ⋮ pass)

**Files:** Create `src/renderer/src/Embeds/PageEmbed.tsx` (+ helpers); create `Blocks/PageEmbedBlock.tsx`; extend `shared/blocks.ts` page-entry chrome fields (`banner?: boolean; title?: boolean; locked?: boolean; display_title?: string`).

**One seam, two consumers:** `PageEmbed` renders a Page inside any foreign surface — SurfacePM tiles now, MarkdownPM `![[Embed]]` later — so its props speak in page identity + chrome flags, never in tile vocabulary. Scrollable; edit-in-place via the same single-live-editor pattern; kind-specific hover-lock (B-5: locked page = no edit, no click-in); banner toggleable, in-line title per G-4/G-6. Dead page ref → inert placeholder (E-2). Re-ground `page:open`/`PageDetail` + MarkdownPM's mount contract at task start.

### Task 4 — View Embeds (one kind, two seeds — D-5/D-12)

An embed's config is **copied at pick time, never synced**: Linked seeds from an existing saved view, Custom (+ Custom) from a blank default; from then on both are identical block-owned config against a single source. Order of work:

1. **Entry contract** (`shared/blocks.ts`): the view entry finalizes as `{ id, type: 'view', views: [{ source_id, config }], active?, style?, display_title? }` — **list-shaped from day one** so the tabbed future (Still Open #3) never migrates the on-disk format; plumbing ships single-entry lists. `source_id` is never optional (D-5a); `config` is `SavedView`-shaped, raw-preserved, snapshotted from the picked view or the blank default. Lock fields ride inert until Task 6.
2. **The embed view scope** — the C-1 seam: an `Embeds/ViewEmbedScope` React context carrying `{ view, persistView }`. `useActiveView` gains a context-first read (one edit covers its four consumers: `TableView:151`, `ViewDropdown:44`, `PropertiesPane:166`, `HiddenPane:194`); the two DIRECT slot reads (`ViewPane.tsx:68`, `SettingsPane.tsx:74`) get the same context check. `[re-ground the six call sites at task start — the one mandatory grounding gap]` Outside a scope everything behaves exactly as today.
3. **`Blocks/ViewEmbedBlock.tsx`**: resolves `source_id` against the tree (Collection or depth-1 Set; dead ref → inert, E-2 — a deleted source *view* can't orphan the tile, the config is copied), renders the **H-5 slim header** (display title per G-6, config affordance in the hover chrome opening ViewSettings INSIDE the scope), then TableView under the provider at the fixed embed zoom (G-10; the `--zoom` knob — resize is viewport-only, H-10). Never a banner (G-4).
4. **Persistence** (D-12): `persistView` has ONE route — the payload `config` via the `saveBlocks` updater; `views.save`/`saveViewAdopting` are never called from an embed. Data edits + drags already write through TableView's source-bound paths — untouched.
5. **Creation**: enable Type ▸ View → the source drill picker (the `blockPagePicker` returning-menu pattern as interim scaffolding until G-16's PickerMenu component: Collections → Sets chevron → that container's views, **+ Custom** footer inside each drill per G-9/D-5a) → a `blocks:convertToView` op (raw-entry spread carrying the config snapshot; trashes a markdown tile's `.md` under the file lock — the convertToPage recipe).

**Checkpoint:** two embeds seeded from ONE saved view diverging freely; a config edit inside an embed does NOT touch the Collection's saved view (and a source-view edit doesn't reshape the embed); the main pane's own view slot untouched throughout; a + Custom embed survives relaunch from the payload; + New Page from an embed lands in the source container.

### Task 5 — Link-Graph Host Passes (D-8)

Order of work:

1. **`main/blocks.ts`: `listBlockBodies(root)`** — enumerate every host dir's `<ulid>.md` with its tile id (just `.nexus/homepage` until real hosts land; the helper is the single place that learns new host dirs).
2. **Indexer pass** (`index/build.ts` ~:316): feed each block body through `connectionEdges(tileUlid, body, linkIndex)` — the source id is caller-supplied already — and parameterize the upsert to stamp `source_kind: 'markdown_block'` + `surface: 'block_body'` (the discriminator D-8's search/graph exclusion depends on; today it hardcodes page/page_body).
3. **`blockRenameCascade(root, oldTitle, newTitle)`** — a DEDICATED pass over block bodies, NOT an extension of `renameCascade` (its `!frontmatter.id → skip` guard at `cascade.ts:38` is load-bearing for pages; block files are id-less by design, D-11). Rewrites under `serializeOnFile` — the same lock the live block editor and the trash paths take. Called from mutate's page-rename case beside `renameCascade`, same revert-on-failure envelope.
4. **Tests with a frontmatter-free fixture** (an id-bearing one would falsely pass): block `.md` linking `[[X]]` → rename X → body rewritten; connections row exists with the block source kind; a block body that ALSO fails the rewrite reverts with the page rename.

**Checkpoint:** type `[[Some Page]]` in a block → it indexes as a block-sourced connection; rename that page → the block body heals.

### Task 6 — Chrome Completion

Shipped early during live direction (already merged): the notched grip handle + its menu (Type ▸ / Style ▸ / Remove-confirmed), Borderless, background right-click create with wedge fill, Turn Into → Page with the drill picker, proximity reveal, caret-priority scroll. Remaining:

1. **The block menu component** (G-16 — Task 6's opener; everything below rides it): a `PickerMenu` shell notch-anchored to the drag handle (its collision flip gives down/side/up placement) hosting the menu family's pane frames — `PaneSlider` between panes, `MenuPaneTopRow` ‹ back, the pinned-edge scroll frame. Link Page = the search pane (row: icon + title in label/`control` over the tight `Collection › Set` breadcrumb in label-secondary/`footnote.emphasized`; recents descending until search — the page-open MRU record is new plumbing, shared with the Navigation arc). Link View = the Task 4 source drill. Replaces the native `blockHandleMenu` + `blockPagePicker`.
2. **The Insert menu** (G-9): the background right-click upgrades from create-markdown-directly to the full menu — **Page** (the search pane) · **View** (the source drill) · **Block** (the current default create) — the same G-16 component; the wedge/append target resolution is already built and stays.
3. **Turn Into completion + Duplicate**: → Markdown (mints a fresh `.md`, G-7; embed conversions never touch the source) and → View (Task 4's op); the Type family becomes context-aware (current type checked/disabled). **Duplicate** (G-16, confirmed v1): copies the tile — markdown mints a copy of its `.md`, embeds copy the payload — landing directly below via the attach logic.
4. **Locks**: `blocks_locked` (G-3) → a SurfaceView `static` prop gating all gestures + the wired SettingsPane lock footing; per-tile `locked` consumed kind-specifically (B-5: page = no edit/no click-in, open action stays per H-3; view = config frozen, interaction live); **G-5's container view-lock** (ViewPane `MenuBottomRow`, dims SettingsPane/ViewPanes container-wide, sidecar-synced, view CRUD included) — standalone; split to its own task if 6 runs heavy.
5. **Page-embed header returns** via the ⋮ hover menu: banner/title toggles + `display_title` (fields already wired; H-2's open scroll clause may land here too once Nathan adjudicates).

**Checkpoint:** every creation and conversion path reachable from the surface itself; a locked host is fully static; a locked page embed reads but never edits.

### Verification Discipline

Per task: gates → build-breaking-agent review (findings verified first-hand) → fold → commit. CDP self-verify against the dev app (`-- --remote-debugging-port=9222`, playwright-core `connectOverCDP`; scratchpad has drive scripts). Post-functional UIX review closes the arc. Re-assess this plan between green tasks — later tasks re-ground their cited files before code.
