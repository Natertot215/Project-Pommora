### Framework — Roadmap

Pommora's path to v1.0.0. The React + Electron build rebuilt the Swift paradigm from the ground up, reached parity, then passed it — **Page Previews + the Subfield unification closed the rebuild, and the build stands at v0.5.0**. Each minor version ships green and standalone — shipped detail → `History.md`, session state → `Handoff.md`. Numbers are soft — order and grouping firm up as each cluster lands. Scope is the **core 7** (data · properties · connections · markdown · navigation · table · gallery) plus the deferred frontier (the non-Table view renderers, block-surface completion, Agenda surfacing, settings UI, global search, LLM-chat inspector, OS integrations).

### Versioning

`major.minor.patch` semver. **Minor (`v0.X.0`)** = a completed feature cluster. **Patch (`v0.X.y`)** = a touch-up or additive extension on a shipped feature. **Major (`vX.0.0`)** is reserved for `v1.0.0` (stabilization) and onward. **v0.5.0 is the rebuild-complete baseline** — the arc up to it is recorded by date below (full detail in `History.md`), and the upcoming line is version-targeted but not date-bound; order and grouping firm up as each cluster lands.

### The Rebuild Arc (to v0.5.0)

Brief milestones — the full record with locked decisions lives in `History.md`.

#### Genesis → Walking Skeleton (06-14 → 06-16)

Spun up from the rebuild exploration with scope locked to the **core 7** and the on-disk format modernized TS-native (built against a throwaway nexus at `~/test`). The first slice was a read-only walking skeleton — one nexus walk (`readNexus`) over IPC into a Zustand store, rendering a recursive glass sidebar. Settled as one repo on one `main`, the code under `Pommora/`, byte-compatible on disk with the Swift build.

#### Headless Data Layer + Desktop Write Path (06-15 → 06-16)

The whole write side built tests-first, no UI: CRUD for every entity, the property schema engine, the `[[connection]]` + tier-relation engine, the regeneratable SQLite accelerator, and Agenda — plus the navigation + view-pipeline spine (filter → group → sort) behind placeholder renderers. Then a real Mac app: native pickers + menu bar, the single path-guarded `mutate` IPC, New Page ⌘N end-to-end, a live full-refresh index.

#### Glass, Drag, and the Design System (06-17 → 06-19)

The shipped glass material (a CSS frost, chosen over refractive libraries in a comparison lab) plus native window chrome; the in-house **PommoraDND** drag engine, proven in a standalone lab with `@dnd-kit` retired; a hash-routed design-system showcase over opacity-derived color and tint primitives; and the first real surfaces — the sidebar insertion-line drag and container views (Collection tables, Context + Homepage) behind banners.

#### The MarkdownPM Editor (06-20 → 06-25)

The dynamic-syntax editor on a CodeMirror 6 substrate — markers show raw on the caret line and render styled when the caret leaves, the behavior layer framework-free and unit-tested. Plus the page banner + shared icon/title header, heading folding, a native context menu, and full interactive GFM table editing.

#### Chrome, Footer, and Inspector (06-25 → 06-26)

The Subfield footer (depth-aware breadcrumb + per-view stats); the glass split into two materials (Apple "Liquid Glass" for controls, the frost elsewhere); the Inspector pane with the toolbar trio's frame-synced "swallow"; plus the drawn caret and the list drag/flavor work.

#### Tables, Views + Properties V2 (06-27 → 07-04)

The Collection table's full interaction layer — the per-type cell gesture matrix, per-view column styles, the Apple overflow model, and band drag (group reorder + Set reparent as real folder moves). Over it, the portable **SavedView** engine (filter → group → sort, multi-key, recursive) and the view-settings dropdown's first panes. **PropertiesV2** flattened definitions into one nexus-wide registry Collections assign — cross-Collection queries + strip-free moves. Then every page write serialized onto **one per-file lock** (the F1 cascade-vs-cell race closed).

#### The View-Settings Suite + Property Editors (07-06 → 07-09)

The watcher walk went **mtime-gated** (parse only what moved). Multi-View scaffolding landed the view-type roster + the toolbar switcher + the two-door ViewSettings editor; the **Group / Sort / Filter** authoring panes filled the blank leaves over the pipeline; and the **Date · Number · Checkbox · Icon** property editors plus the full-Lucide **Icon Picker** shipped. The sidebar became a **ribbon + mode-switched column** (Collections · Contexts · Agenda surfaces), with ⌘E toggling it via a data-driven `commands` registry.

#### SurfacePM — Block Surfaces (07-10 → 07-13)

Pommora's composable dashboard layer: a **BlockHost** renders a mosaic of draggable, resizable tiles over the in-house **SurfacePM** tessellation engine, with the Homepage as the removable dev host. Three tile types (markdown block · page embed · view embed), repair-not-reject at every level, per-block Scale, and the embed-IS-the-CM6-view seam — live on the Homepage host, with view embeds / geometry locks / the link-graph host still to complete.

#### Auto-Scroll + the Navigation Surface (07-14)

Every drag's edge-scroll collapsed onto **one shared primitive** (`autoscroll.ts`) across seven surfaces. Then the **Navigation** surface: a per-nexus nav-state layer (recents MRU + pins, favorites, all live-resolved against the tree) feeding a store + client-side fuzzy search, presented through the always-centered NavPane command surface.

#### Multi-Tab Nexus (07-15 → 07-16)

Warm, state-preserving **Toolbar Tabs** superseded single-pane-replace: a persisted, cross-device-synced working set — pinned (the `.nexus/pins/` set, left-docked) plus unpinned scratch tabs — each keeping its own scroll + undo + Back/Forward, one view mounted at a time (a serialized warm cache rehydrated instantly on switch). The empty state became **NavView** (full-window gallery + search); the nav surfaces renamed for the model — **NavWindow** (floating overlay), **NavPane** (toolbar dropdown), **NavView** (new-tab page).

#### Page Previews (07-16 → 07-17)

The floating, fully-editable **preview mini-app** — wiki-clicks open dedup-focused tabs beside the origin, tab-neutral to the app's tabs. Two flavors (page + NavWindow) share one chrome, one tab-motion layer, one side-pane shell, one warm seam, and one debounced-sidecar machine; per-origin tab sets persist and sync (`page-previews.json`); container + connection opens route by `open_in` and the nexus-wide `connectionsOpenInPreview` key.

#### Unified Subfield + Scan-Promote (07-17)

Collapsed the floating ↔ full-pane split so the Subfield footer and scan-promote semantics are **shared, not re-implemented per surface** — the Subfield takes one optional `scope` prop (the floating preview describes its own page from a local body it owns). NavView gained the List/Gallery toggle, a reorderable list showing the pinned group, and two persisted view-mode slices; the map-flavor scan promotes the NavWindow into NavView. **This closed the React rebuild — the build is v0.5.0.**

### II. Upcoming (v0.5.0 → v1.0.0)


#### v0.6.0 — The View Renderers

The non-Table renderers — **Gallery · Cards · List · Calendar · Timeline** — over the shipped filter → group → sort pipeline and the view-type scaffolding already in place (only Table renders today). The chip mechanics ride along where reused.

#### v0.7.0 — Agenda + Calendar

Tasks and Events surfacing through a Calendar entry (the data layer is done) with compact per-entity panels, plus an EventKit bridge (opt-in, bidirectional mirroring) as a follow-on.

#### v0.8.0 — Settings + Quick Capture + LLM Inspector + Search

The Settings editing UI (accent picker, label rename forms, tier-config consolidation), Quick Capture (a global entry surface creating Pages / Tasks / Events), the Claude-chat inspector (a local-CLI frontend), and global `⌘K` search over an FTS index.

#### v0.9.0 — SurfacePM Completion + Contexts

SurfacePM's remaining passes (view embeds — Linked → Custom + the nexus-wide row source, geometry locks, the link-graph host), the contexts resolution + its sidebar surfaces, the Context Linked-From surface, and the Homepage's final shape.

#### v1.0.0 — Stabilization

No new features — polish, performance, and a release pass (signing, notarization, auto-update).

### Post-v1

No phase commitments. The catalog lives in `PommoraPRD.md` (the Prospects section) — additional view types, synced page-body blocks, a graph view, sync, mobile, and a plugin system among them.
