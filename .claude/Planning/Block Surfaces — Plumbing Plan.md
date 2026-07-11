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

### Task 1 — Block Document + Persistence

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

### Task 2 — Markdown Block Tiles

**Files:** Create `src/renderer/src/Blocks/MarkdownBlock.tsx` (the G-2 family starts here); modify `main/blocks.ts` + `index.ts` + preload (create/remove/read/write ops), `HomepageView` wiring (renderTile switches on resolved payload).

**Interfaces (produces):** `blocks.createMarkdown(host)` → `{ ok, id }` — main `mkdir`s `blockHostDir` first (recursive; the dir is main-derived and safe by construction, so it bypasses `resolveUnderRoot` exactly as `createContext` uses `contextTierDir`), mints the ULID, writes the empty `.md`, appends the `blocks[]` entry; the renderer then splices the layout and saves. An entry with no leaf is legal and invisible; **a leaf whose id resolves to no entry renders the inert placeholder** (the E-1/E-2 path — it occupies its space until removed). `blocks.removeTile(host, tileId)`: the renderer splices the leaf out and saves the layout **first**, then the op drops the entry and trashes a markdown tile's `.md` via **`trashWithTimestamp`** (the primitive already handles files — E-5's "new op" is this IPC op). `blocks.readMarkdown` / `blocks.writeMarkdown` are **dedicated pure-body ops under `serializeOnFile`** — the page ops do accept `.nexus/…` paths, but `page:updateBody` stamps a `modified_at` frontmatter envelope onto what must stay a frontmatter-free file (D-11), so reuse is off the table.

**Steps:** IPC ops + tests (create mints + file exists; remove trashes file + drops entry; foreign entries untouched) → `MarkdownBlock` static render (existing `react-markdown` read path) with click-to-edit mounting MarkdownPM, single live editor, exit on click-out/Esc (E-4; CM6 remount gotcha: extension changes need ⌘R) → new-tile flow: a plain "add" affordance in the host (chrome lands in Task 6; G-7 default = markdown) → gates, CDP pass on a throwaway tile, commit.

### Task 3 — Shared Page-Embed Framework (G-11)

**Files:** Create `src/renderer/src/Embeds/PageEmbed.tsx` (+ helpers); create `Blocks/PageEmbedBlock.tsx`; extend `shared/blocks.ts` page-entry chrome fields (`banner?: boolean; title?: boolean; locked?: boolean; display_title?: string`).

**One seam, two consumers:** `PageEmbed` renders a Page inside any foreign surface — SurfacePM tiles now, MarkdownPM `![[Embed]]` later — so its props speak in page identity + chrome flags, never in tile vocabulary. Scrollable; edit-in-place via the same single-live-editor pattern; kind-specific hover-lock (B-5: locked page = no edit, no click-in); banner toggleable, in-line title per G-4/G-6. Dead page ref → inert placeholder (E-2). Re-ground `page:open`/`PageDetail` + MarkdownPM's mount contract at task start.

### Task 4 — View Embeds: Linked, Then Custom

**4a Linked (D-12/C-1):** `Blocks/ViewEmbedBlock.tsx` resolves `source_id` against the tree; **per-instance view resolution** — the payload's `view_id` picks from `source.views`, `activeViews` is never touched; view-config edits persist via the existing `views.save(sourcePath, kind, view)`; data edits/drags already write through TableView's source-bound paths (correct behavior per C-1). The seam is **deeper than one hook**: the active-view slot is read by six surfaces — `useActiveView` in `TableView:151`, `ViewDropdown:44`, `PropertiesPane:166`, `HiddenPane:194`, plus **direct** `activeViews[node.id]` reads in `ViewPane.tsx:68` and `SettingsPane.tsx:74` — so the embed's resolution (view + id + persistence sink) threads through a provider/context scoped to the embed subtree, or the embed simply never mounts the slot-reading chrome. Re-ground all six at task start. Chrome: no banner ever (G-4), zoomed out via the existing `--zoom` knob (G-10), display-title override (G-6).

**4b Custom (D-5a–d):** payload-owned `SavedView`-shaped config; **nexus-wide row source** — a new batch IPC generalizing `loadValues` to the whole nexus (`listMarkdownFiles(root, { skipTopLevel: ['.nexus', '.trash'] })` joined to tree pages), columns/filters against the full registry (D-5b), cached per-host-open, most-recent-wins (D-5c); forest structural grouping = by-Collection top bands (D-5d). The arc's mountain — if a session runs short, 4a is a clean stop.

### Task 5 — Link-Graph Host Passes (D-8)

**Files:** Modify `src/main/index/build.ts` (~:316 — connections build only from walked pages) and `src/main/crud/cascade.ts` (`SKIP_TOP_LEVEL` at :20 skips `.nexus` wholesale).

Both gain a **host-folder pass** over `blockHostDir` files (just `.nexus/homepage` until real hosts land), and the two halves have different shapes:

- **Indexer:** `connectionEdges(sourceId, body, index)` already takes a caller-supplied source id — key block sources by the tile ULID from `blocks[]`. But the upsert stamps `source_kind: 'page'` / `surface: 'page_body'` today — parameterize it (or add a block variant) to stamp `source_kind: 'markdown_block'` + `surface: 'block_body'`, the discriminator D-8's search/graph-view exclusion depends on.
- **Rename:** a **dedicated block-body rewrite pass**, NOT an extension of `renameCascade`'s page loop — that loop's `!frontmatter.id → skip` guard (`cascade.ts:38`) is load-bearing for pages and block files are id-less by design (D-11), so routing them through it silently no-ops. The block pass gates on nothing but the host-dir membership, rewrites under `serializeOnFile` (the same lock the live block editor takes).

Tests use a **frontmatter-free** block fixture (an id-bearing one would falsely pass the rename half): block `.md` linking `[[X]]` → rename X → body rewritten; connections row exists with the block source kind.

### Task 6 — Chrome Mechanics (G-8, No Figma Gate)

**MarkdownPM handle method:** ground the editor's drag-handle implementation (`renderer/src/MarkdownPM/` — decorations/input) at task start; the `spm-handle` adopts its visual treatment + grammar: drag = move (exists), **click / right-click = the block menus** (Turn Into per G-7 — converting away from markdown trashes the `.md` recoverably, into markdown mints one; Delete; kind-specific entries). **Insert menu (G-9):** right-click on surface background → native menu (the `contextMenu.ts` pattern): Page (search picker) · View (source drill: Collections → Sets chevron → views, + Custom footer) · Block. **Locks:** `blocks_locked` (G-3) → SurfaceView gains a `static` prop (gestures disabled); per-tile `locked` consumed by the Blocks components (B-5); G-5's container view-lock (ViewPane `MenuBottomRow`) is standalone — build it here or split out if the task runs heavy.

### Verification Discipline

Per task: gates → build-breaking-agent review (findings verified first-hand) → fold → commit. CDP self-verify against the dev app (`-- --remote-debugging-port=9222`, playwright-core `connectOverCDP`; scratchpad has drive scripts). Post-functional UIX review closes the arc. Re-assess this plan between green tasks — later tasks re-ground their cited files before code.
