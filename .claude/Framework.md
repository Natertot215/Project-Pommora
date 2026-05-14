### Pommora — Roadmap

Phased plan; no dates. Order is the only commitment.

> **Stack: SwiftUI.** Capability-level version descriptions below survive an editor-implementation pivot inside the SwiftUI path (Option 1 native vs Option 2 WKWebView).

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform that combines Obsidian's local-first openness with Notion's database and view capabilities. Built around three entity types — Pages (Markdown documents), Collections (typed folder-as-database: Pages collections or Items collections), Spaces (composed dashboard surfaces) — plus Items (row-shaped entries inside Items collections). Mac-first for v1, always open-source.

#### Phases

Each version adds one capability cluster on top of the previous. Slicing is incremental and demoable — every version produces a verifiable outcome you can run.

##### v0.0 — Shell opens
Toolchain proof. App launches on macOS 26+ (Tahoe) into a styled three-pane shell — sidebar (default 240) / main (flex) / inspector (default 280) — built on SwiftUI's `NavigationSplitView`. Both side panes drag-resizable from launch; widths persist across launches. Top-bar tab chrome renders in the main pane (single placeholder tab, non-functional; `+` and `×` buttons render but don't open / close anything). Sidebar and inspector are empty styled surfaces — no data wiring, no vault picker, no editor. Default window 1200×800; minimum 960×560.

**Pre-v0.0 prerequisite:** Asset Catalog `AccentColor.colorset` exists (Xcode default is fine — brand-accent value is deferred). `Color+Pommora.swift` and `Font+Pommora.swift` can be empty stubs in v0.0 — populated as their consuming features land (code colors v0.3+, callout/blockquote v0.3–v0.4).

The React+Electron-locked v0.0 spec is preserved at `// ReactInfo//v0.0.md` for contingency.

##### v0.1 — Vault reads + tabs functional
Sidebar tree mirrors folder structure of `~// PommoraVault//`. Clicking a `.md` file in the sidebar opens it as a tab in the top-bar tab row; the main pane shows the file's raw markdown. Multiple tabs can be open simultaneously; clicking a tab switches the main pane; closing a tab removes it. New tab via `+` or `Cmd+T` opens an empty state. Open tabs and active tab persist across launches. No parsing, no editor yet.

##### v0.2 — Index + watcher
SQLite index + frontmatter parser + file watcher. Pages indexed at launch; sidebar displays titles derived from filenames; changes on disk update the sidebar live.

##### v0.3 — Editor: prose + standard Markdown
Page editor renders prose with all standard Markdown — paragraphs, headings (H1–H5 in v0's type scale; no H6 token), bulleted / numbered lists, code blocks, images, GFM tables, blockquotes (rendered as filled box with left-side emphasis bar; on-disk standard `>` syntax), horizontal rules (`---`). Edits persist back to the file via standard Markdown round-trip. No Pommora-specific rendering directives yet.

##### v0.4 — Editor: `@Columns` + `:::callout`
The two Pommora-specific rendering directives wired up. `@Columns` is a fenced directive (`:::columns ... :::`) marking a section of the Page to render in N horizontal columns — the Markdown inside is unchanged, the directive only affects layout. `:::callout` is a fenced directive that wraps content as a minimally-rounded outlined box (distinct from blockquotes, which are standard `>` syntax rendered with a filled background + left-side emphasis bar). Slash menu or toolbar inserts both; custom serializer round-trips them through the file. These are the only Markdown features that need custom serialization on top of standard MD; everything else round-trips natively. (The earlier-proposed `@View` in-line view embed is deferred to v2+ and is feasible on Option 2; harder on Option 1. Heading-fold ships as built-in UI behavior, not a directive.)

##### v0.5 — Links
Wikilink rendering (styled colored inline text, Obsidian-style) + resolution + automatic file rename with cross-vault wikilink rewrite. The link layer is fully functional.

##### v0.6 — Properties: simple types
Property panel reads each Page's Collection schema (from the `_collection.json` sidecar inside the Page's folder). Text, number, checkbox, and URL property values editable directly from the panel.

##### v0.7 — Properties: rich types
Date, datetime, select, multi-select, relation. Full v1 property catalog usable. (No dedicated Status type — Status-like properties are Selects named "Status.")

##### v0.8 — Collections: filters + table + list
Collection construct first-class: a folder + a `_collection.json` schema sidecar inside it (Make.md folder-notes pattern). **Collections are typed at creation** (`"kind": "pages"` or `"kind": "items"`); Pages collections hold `.md` member files, Items collections hold `.json` member files. Sidebar shifts to its v1 logical model with three top-level collapsible headings (Spaces / Saved / Collections), all default-collapsed. Each Collection inside the Collections heading is a folder-style disclosure expanding to its members. Saved is a non-operational placeholder heading in v1 (pinning is post-v1). Loose Pages and loose Items exist on disk but aren't a sidebar group — reachable via search or wikilinks. Filter / sort / group / shown-properties controls. Table view (sortable, inline-editable) + list view. Saved view configurations stored inside `_collection.json`.

##### v0.9 — Collections: cards + gallery + board
Three remaining view types. Board view ships as a **visual kanban layout** — cards grouped by a property's options (status, type, etc.); editing a card's property via the card UI moves it visually between columns. **Drag-to-rewrite-frontmatter** (dragging a card across kanban columns to mutate the source's property value directly) is post-v1.0 — it needs the property edit / atomic write / watcher loop hardened first.

##### v0.10 — Spaces: composition foundation
Spaces are a first-class entity — Notion-page-style block-composition surfaces. Canvas-based composer with drag/drop and slash-menu insertion. Text blocks: paragraph, headings, lists, callout, code, image. Plus the linked-pages widget block (renders Pages whose `spaces` property points to this Space). Block tree persists to `.space.json` files in `.pommora// spaces//`.

##### v0.11 — Spaces: rich blocks + search
Multi-column layout inside Spaces (`columns` block). Embedded Collection view widget (renders any saved Collection view inline). Link list widget (manually curated). Global FTS5 search over Page bodies and frontmatter.

##### v0.12 — In-app customization
Settings panel exposes two user-overridable values: the accent color and the font size. SwiftUI handles everything else natively (semantic colors auto-adapt for dark mode, Dynamic Type for typography scale, Materials for vibrancy) — no additional override surface needed. Changes apply live and persist; the override layer sits on top of the Asset Catalog accent and the default font scale.

##### v1.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0 through v0.12.

##### Post-v1
No specific phase commitments yet. Potential features and brainstormed ideas for after v1.0 — editor enhancements, additional view types (timeline, formulas, rollups), block features (synced blocks, per-block comments, block-level history), design polish (light/dark themes, design auditor), sync (Supabase), mobile and web, plugin system, etc. — are catalogued in `// Features//Prospects.md`. Items move from Prospects into a numbered version here when they become committed work.

#### Current Focus

**v0.0** — buildable from this Framework entry + PRD + UIX-Guide; pre-build step is `AccentColor.colorset` in `Assets.xcassets`. Per-version planning docs are authored as we approach each version, not pre-stubbed. Implementation order has not been reviewed or approved by Nathan; this order will likely change.
