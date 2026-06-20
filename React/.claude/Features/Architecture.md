## Architecture — Data, Read Engine & IPC

### Two-process shape

- **Main** (`src/main`) owns all filesystem access. It walks a nexus and serves typed data over IPC. No UI.
- **Preload** (`src/preload`) is the only bridge: a `contextBridge`-exposed `window.nexus` with a narrow set of read methods. Sandboxed; no Node leaks to the renderer.
- **Renderer** (`src/renderer/src`) is pure presentation: a Zustand store over the IPC data + React components.
- **Shared** (`src/shared/types.ts`) is the cross-process contract — `NexusTree`, `PageDetail`, `SelectionState`, the `{ ok, … } | { ok, error }` envelope. No fs, no React.

One eager walk → one IPC → one immutable tree → one store. No parallel caches, no lazy per-row loads, **no SQLite** on the read path (a flat-scale nexus walk is cheap; SQLite returns later only as a regeneratable query accelerator).

### The read engine — `readNexus(rootPath) → NexusTree`

A single recursive, **read-only** walk (`src/main/readNexus.ts`). Supports two modes:

- **Sidecar-driven** — when `.nexus/nexus.json` exists: identity + config from `.nexus/`, folders gated by their sidecars (`_pagetype.json` / `_pagecollection.json` / `_pageset.json`, contexts under `.nexus/{areas,topics,projects}`).
- **Structure-classification** — raw/un-adopted folders (the test-nexus case): no sidecars, so classify by structure (root folder → Vault, subfolder → Collection, deeper → Set, `.md` → Page) with synthesized stable ids hashed from the relative path.

Supporting pure modules: `paths.ts` (layout), `exclusion.ts` (skip dot/underscore/node_modules + user-excluded folders, NFC + case-fold segment-prefix), `order.ts` (persisted order then title/id fallback; **title fallback for adopted entities** whose ids are non-meaningful hashes).

Load-bearing behaviors: lenient frontmatter (no fence → all body; unterminated → graceful empty); the **roll-up rule** (loose `.md` in non-container subfolders rolls up; Collection/Set folders load as nodes) with a 3-level depth cap (pageType → collection → set); agenda singletons (`Tasks`/`Events`/`Agenda`) discovered but **not surfaced** (a `_pagetype.json` outranks the conventional name); `path` (nexus-relative POSIX) on every `PageNode` so pages can be opened.

### The `NexusTree` contract

Pre-ordered, serializable, consumed by the renderer without re-sorting: `nexus` (identity — name · description · avatar photo) · `homepage` (the singleton's banner) · `saved[]` (3 fixed) · `contexts {projects, topics, areas}` (render order P→T→A) · `vaults[]` (PageType → Collection → Set → Page, typed arrays so Collections-before-Pages / Sets-before-Pages is structural) · `userSections[]` · `labels` · `accent`. Full shape in `src/shared/types.ts`.

### What ports cleanly from Swift

The on-disk format, domain model, property catalog, and CRUD semantics are stack-independent by design (PRD constraint #1) — they arrive as data + pure logic, not transliterated Swift. The entire macOS-sandbox layer (security-scoped bookmarks, the XCTest modal guard, NSOpenPanel retry) simply doesn't exist here. See the Swift project's `Features/Architecture.md` + `PommoraPRD.md` for the canonical on-disk spec.

### Assets — the `nexus-asset://` protocol

Binary assets (banner / avatar images) live under `.nexus/assets/<entity-id>/` and are served to the renderer over a registered, read-only **`nexus-asset://`** scheme — path-traversal-guarded and confined to `.nexus/assets/`. Image bytes therefore never ride the reloaded `NexusTree`; the read walk carries only the relative path and the renderer composes the URL. Writes go through one generic `setBanner` mutate op per owner kind (vault / collection / context sidecars, or the homepage singleton). A **fresh filename per write** keeps each image's URL unique so the browser can't serve a stale cached version. (Swift serves the same assets via Nuke/`LazyImage`; this is the web-platform equivalent.)

### Renderer view layer

The renderer mirrors Swift's folder shape. `Detail/` holds the router (`DetailPane`), the shared surface (`DetailScaffold` ≈ Swift `ViewSurface`), selection→entity resolution (`Scope` ≈ `DetailScope`), and a view file per container kind: `ContainerView` (shared by Vault + Collection — they share view principles, with `source.kind` as the divergence seam), `HomepageView`, `ContextView`, `PageView`. `Detail/Table/` (table + view pipeline), `Detail/Banner/`, `Sidebar/`, and `Components/` (shared primitives) complete it. Genuinely-shared mechanism (scaffold, banner, table, glass material) stays single-sourced; each view owns its composition + co-located styles.
