### Framework — Roadmap

Pommora's path to v1.0.0, rebuilt in React + Electron from Swift. Each minor version ships green and standalone — shipped detail → `History.md`, session state → `Handoff.md`. Scope is the **core 7** (data · properties · connections · markdown · navigation · table · gallery) plus the deferred frontier (block editor, Agenda surfacing, Board/List/Cards renderers, settings UI, global search, LLM-chat inspector, OS integrations).

### Versioning

`major.minor.patch` semver. **Minor (`v0.X.0`)** = a completed feature cluster. **Patch (`v0.X.y`)** = a touch-up or additive extension on a shipped feature. **Major (`vX.0.0`)** is reserved for `v1.0.0` (stabilization) and onward. The build so far is recorded by date in `History.md`; the upcoming line is version-targeted but not date-bound — order and grouping firm up as each cluster lands.

#### Genesis → Walking Skeleton (06-14 → 06-16)

Spun up from the rebuild exploration with scope locked to the **core 7** and the on-disk format modernized TS-native, built and tested against a throwaway nexus at `~/test`. The first slice was a read-only walking skeleton — one nexus walk (`readNexus`) over IPC into a Zustand store, rendering a recursive glass sidebar. Settled as one repo on one `main`, React living under `React/`.

#### Headless Data Layer + Desktop Write Path (06-15 → 06-16)

The entire write/mutation side built tests-first, no UI: CRUD for every entity, the property schema engine, the `[[connection]]` + tier-relation engine, the regeneratable SQLite accelerator, and Agenda — plus the navigation + view-pipeline logic spine (filter → group → sort) behind placeholder renderers. Roughly 72% less code than the original's data layer, with comment-preserving writes and index-independent link resolution falling out for free. Then it became a real Mac app: native folder pickers + menu bar, the single path-guarded `mutate` IPC, New Page ⌘N end-to-end, and a live full-refresh index.

#### Glass, Drag, and the Design System (06-17 → 06-19)

The shipped glass material — a CSS frost that adds its own light, chosen over refractive libraries in a comparison lab — plus native window chrome. The in-house **PommoraDND** drag engine, built and proven in a standalone Interaction Lab with `@dnd-kit` retired. A hash-routed design-system showcase over opacity-derived color and tint primitives. And the first real surfaces: the "sidebar" insertion-line drag adopted app-wide, and container views (Vault / Collection tables, Context + Homepage) behind banners.

#### The MarkdownPM Editor (06-20 → 06-25)

The dynamic-syntax editor on a CodeMirror 6 substrate — Markdown markers show as raw source on the caret line and render styled when the caret leaves, the behavior layer framework-free and unit-tested. Joined by the page banner (`cover` frontmatter) plus a shared icon/title header, heading folding, and a native context menu — then full interactive GFM table editing (a widget over canonical pipe-table source, every cell a live nested editor, reorder and resize through hover grips).

#### Chrome, Footer, and Inspector (06-25 → 06-26)

The Subfield footer (a depth-aware breadcrumb plus per-view stats). The glass split into two materials — Apple "Liquid Glass" for controls, the frost for everything else. The Inspector pane with the toolbar trio's "swallow" animation on one frame-synced progress. Plus the drawn caret, list drag-to-reorder by the glyph, and the arrow/plus list flavors.

#### Views + View Settings (06-27 → 06-29)

Callouts (`> [!callout]` boxes that render nested syntax inside). The Collection Table-Views pipeline — a portable `SavedView` engine (filter → group → sort) with multi-key sort and recursive filters, deliberately ahead of the original. The view-settings dropdown and its first panes (Properties schema CRUD), in progress. The motion + shadow token pass — the Bloom open/retract — alongside the Figma Switch. And **PropertiesV2**: definitions flattened to one nexus-wide registry that Collections assign, unlocking cross-Collection queries + strip-free moves (the data-layer paradigm; the assign-surface UI rides with View Settings).

#### Tables Interactive (06-30 → 07-02)

The table's full interaction layer. First the per-type cell gesture matrix — the title navigates, every value cell owns its click through the shared picker/editor surfaces — with per-view column styles, the Apple overflow model (fixed tracks, whole-view h-scroll past the pane, the conditional inspector), and the DRY overflow-scroll mechanism. Then **band drag**: group bands reorder per-view by their glyph (manual-only, view-owned order) and Set bands reparent across the tree as real folder moves; Esc aborts every drag surface.

### II. Upcoming (Toward v1.0.0)

#### v0.5.0 — Views Complete + Properties UI

The Gallery / Board / List / Cards renderers, the toolbar Views switcher, and the full View Settings panes (Filter / Group / Sort / Layout / Visibility) over the shipped pipeline; the chip mechanics (the DRY'd slide + the hover (×) remove); the **assign surface** (the Properties pane grown to the nexus-wide model — assign-existing, Remove vs global Delete); and the page property panel (the data layer is done, registry-backed).

#### v0.6.0 — Agenda + Calendar

Tasks and Events surfacing through a Calendar entry (the data layer is done) with compact per-entity panels, plus an EventKit bridge (opt-in, bidirectional mirroring) as a follow-on.

#### v0.7.0 — Settings + Quick Capture + LLM Inspector + Search

The Settings editing UI (accent picker, label rename forms, tier-config consolidation), Quick Capture (a global entry surface creating Pages / Tasks / Events), the Claude-chat inspector (a local-CLI frontend), and global `⌘K` search over an FTS index.

#### v0.8.0 — Block Surfaces (SurfacePM)

The host-agnostic tile-grid system: **SurfacePM** (an in-house reconstruction of react-grid-layout — its vendored MIT core math over PommoraDND-style sensors and own components), the BlockHost document model, and the three v1 tile types — markdown block · page embed · view embed (**Linked** referencing a saved view, **Custom** with embed-owned nexus-wide config). Full review-certified spec → `Planning/7-10 - Block Surfaces — Decision Log.md`; handle/hover chrome gated on Figma designs. The contexts resolution, its sidebar surfaces, the Context Linked-From surface, and the Homepage's shape are their own later passes.

#### v1.0.0 — Stabilization

No new features — polish, performance, and a release pass (signing, notarization, auto-update).

### Post-v1

No phase commitments. The catalog lives in `PommoraPRD.md` (the Prospects section) — additional view types, synced page-body blocks, a graph view, sync, mobile, and a plugin system among them.
