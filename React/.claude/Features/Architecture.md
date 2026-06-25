## Architecture — Data, Read Engine & IPC

### Two-process shape

- **Main** (`src/main`) owns all filesystem access. It walks a nexus and serves typed data over IPC. No UI.
- **Preload** (`src/preload`) is the only bridge: a `contextBridge`-exposed `window.nexus` with a narrow set of read methods. Sandboxed; no Node leaks to the renderer.
- **Renderer** (`src/renderer/src`) is pure presentation: a Zustand store over the IPC data + React components.
- **Shared** (`src/shared/types.ts`) is the cross-process contract — `NexusTree`, `PageDetail`, `SelectionState`, the `{ ok, … } | { ok, error }` envelope. No fs, no React.

One eager walk → one IPC → one immutable tree → one store. No parallel caches, no lazy per-row loads, **no SQLite** on the read path (a flat-scale nexus walk is cheap; SQLite returns later only as a regeneratable query accelerator).

### The read engine — `readNexus(rootPath) → NexusTree`

A single recursive, **read-only** walk (`src/main/readNexus.ts`). Supports two modes:

- **Sidecar-driven** — when `.nexus/nexus.json` exists: identity + config from `.nexus/`, folders gated by their sidecars (`_pagecollection.json` for a Collection, `_pageset.json` for a Set; contexts under `.nexus/{areas,topics,projects}`; agenda by `_taskconfig.json` / `_eventconfig.json`).
- **Structure-classification** — raw/un-adopted folders (the test-nexus case): no sidecars, so classify by position (root folder → Collection, any non-excluded subfolder → recursive Set at any depth, `.md` → Page) with synthesized stable ids hashed from the relative path.

Supporting pure modules: `paths.ts` (layout), `exclusion.ts` (skip dot/underscore/node_modules + user-excluded folders, NFC + case-fold segment-prefix), `order.ts` (persisted order then title/id fallback; **title fallback for adopted entities** whose ids are non-meaningful hashes).

Load-bearing behaviors: lenient frontmatter (no fence → all body; unterminated → graceful empty); **recursive Sets** — a Collection nests Sets to any depth, with no roll-up and no depth cap; agenda singletons discovered but **not surfaced**, identified *solely* by their config sidecar (`_taskconfig.json` / `_eventconfig.json`) — never by folder name (see "Agenda discrimination" below); `path` (nexus-relative POSIX) on every `PageNode` + container so entities can be opened / renamed.

### Agenda discrimination (config-driven, never name-based)

Tasks and Events are Agenda entities — a third kind, distinct from Collections and Contexts. They live as **sibling singleton folders at the nexus root** (no `Agenda/` wrapper) and are identified *only* by their config sidecar (`_taskconfig.json` / `_eventconfig.json`); the folder names are renameable defaults, never reserved. Every collection path — the read walk (`readNexus`), the open-time adopter (`adopt.ts`), and on-creation — skips a folder *iff* it carries an agenda config sidecar. So a user could even name a Page Collection "Tasks" or "Events" and it's correctly a Collection (it carries `_pagecollection.json`, not the agenda config). No name is reserved in either build.

> **Deferred — per-file kind discrimination.** Classification is *folder-level* today (by sidecar). It does not yet discriminate individual *files* within a folder by kind. When Tasks / Events are fully implemented, the adopter MUST gain an explicit per-file discriminator — extension (`.task.json` / `.event.json`), filename prefix, or frontmatter key — so each file's kind (task / event / page) is unambiguous, not inferred from its parent folder. Not built now; the on-disk discriminator choice is open and may change.

### The `NexusTree` contract

Pre-ordered, serializable, consumed by the renderer without re-sorting: `nexus` (identity — name + `profileImage` / `profileSubtitle`, both from `.nexus/settings.json`) · `homepage` (the singleton's banner) · `saved[]` (3 fixed) · `contexts {projects, topics, areas}` (render order P→T→A) · `collections[]` (ungrouped top-level Collections, each nesting recursive Sets then Pages — typed arrays so Sets-before-Pages is structural) · `userSections[]` (grouped Collections) · `labels` · `accent`. Full shape in `src/shared/types.ts`.

### What ports cleanly from Swift

The on-disk format, domain model, property catalog, and CRUD semantics are stack-independent by design (PRD constraint #1) — they arrive as data + pure logic, not transliterated Swift. The entire macOS-sandbox layer (security-scoped bookmarks, the XCTest modal guard, NSOpenPanel retry) simply doesn't exist here. See the Swift project's `Features/Architecture.md` + `PommoraPRD.md` for the canonical on-disk spec.

### Assets — the `nexus-asset://` protocol

Binary assets (banner / avatar images) live under `.nexus/assets/<entity-id>/` and are served to the renderer over a registered, read-only **`nexus-asset://`** scheme — path-traversal-guarded and confined to `.nexus/assets/`. Image bytes therefore never ride the reloaded `NexusTree`; the read walk carries only the relative path and the renderer composes the URL. Writes go through one generic `setBanner` mutate op per owner kind (collection / set / context sidecars, the homepage singleton, or a page's `cover` frontmatter). A **fresh filename per write** keeps each image's URL unique so the browser can't serve a stale cached version. (Swift serves the same assets via Nuke/`LazyImage`; this is the web-platform equivalent.)

### Renderer view layer

The renderer mirrors Swift's folder shape. `Detail/` holds the router (`DetailPane`), the shared surface (`DetailScaffold` ≈ Swift `ViewSurface`), selection→entity resolution (`Scope` ≈ `DetailScope`), and a view file per container kind: `ContainerView` (shared by Collection + Set — same view principles, `source.kind` as the divergence seam), `HomepageView`, `ContextView`, `PageView`. `Detail/Table/` (table + view pipeline), `Detail/Banner/`, `Sidebar/`, and `Components/` (shared primitives) complete it. Genuinely-shared mechanism (scaffold, banner, table, glass material) stays single-sourced; each view owns its composition + co-located styles.
