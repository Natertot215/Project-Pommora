### Pommora — Roadmap

Phased plan; no dates. Order is the only commitment.

> **Stack status:** Under active evaluation (React+Electron vs SwiftUI). Both paths produce identical on-disk Markdown and identical SQLite indexes — only the editor surface and desktop shell differ. Version descriptions below are capability-level and survive either stack. The v0.0 spec is the only document that hard-commits to a stack; it gets rewritten when the call lands.

#### Vision

A Markdown-canonical, SQLite-indexed personal management platform that combines Obsidian's local-first openness with Notion's database and view capabilities. Built around three entity types — Pages (Markdown documents), Collections (folder-as-database), Spaces (composed dashboard surfaces). Mac-first, always open-source.

#### Phases

Each version adds one capability cluster on top of the previous. Slicing is incremental and demoable — every version produces a verifiable outcome you can run.

##### v0.0 — Shell opens
Toolchain proof. App launches into a styled three-pane shell (sidebar / main / inspector) consuming design tokens. No interactivity, no data. Spec: `// Planning//v0.0.md` (currently React+Electron-locked; will be rewritten if SwiftUI is chosen).

##### v0.1 — Vault reads
Sidebar tree mirrors folder structure of `~// PommoraVault//`. Clicking a `.md` file shows its raw markdown in the main pane. No parsing, no editor.

##### v0.2 — Index + watcher
SQLite index + frontmatter parser + file watcher. Pages indexed at launch; sidebar displays titles from frontmatter (not filenames); changes on disk update the sidebar live.

##### v0.3 — Editor: prose + standard Markdown
Page editor renders prose with all standard Markdown block types — paragraphs, headings, lists, code blocks, images, tables, callouts. Edits persist back to the file. No embed blocks yet.

##### v0.4 — Editor: multi-column block
The `@Columns` block-level fenced directive wired up — multi-column container inside the editor. Slash menu or toolbar inserts it; serializer round-trips it through the file. (The earlier-proposed `@View` in-line view embed is deferred to v2+ and would only be feasible under the React stack.)

##### v0.5 — Links
Wikilink rendering (styled colored inline text, Obsidian-style) + resolution + backlinks panel + automatic file rename with cross-vault wikilink rewrite. The link layer is fully functional.

##### v0.6 — Properties: simple types
Property panel reads each Page's Collection schema (from the `_collection.json` sidecar inside the Page's folder). Text, number, checkbox, and URL property values editable directly from the panel.

##### v0.7 — Properties: rich types
Date, datetime, select, status, multi-select, relation. Full v1 property catalog usable.

##### v0.8 — Collections: filters + table + list
Collection construct first-class: a folder + a `_collection.json` schema sidecar inside it (Make.md folder-notes pattern). Pages inside the folder are members of the Collection. Sidebar shifts to logical model: Collections appear as collapsible groups (collapsed by default); Pages outside any Collection folder surface as Loose Pages. Filter / sort / group / shown-properties controls. Table view (sortable, inline-editable) + list view. Saved view configurations stored inside `_collection.json`.

##### v0.9 — Collections: cards + gallery + board
Three remaining view types. Board view uses drag-and-drop to update source frontmatter.

##### v0.10 — Spaces: composition foundation
Spaces are a first-class entity — Notion-page-style block-composition surfaces. Canvas-based composer with drag/drop and slash-menu insertion. Text blocks: paragraph, headings, lists, callout, code, image. Plus the linked-pages widget block (renders Pages whose `spaces` property points to this Space). Block tree persists to `.space.json` files in `_pommora// spaces//`.

##### v0.11 — Spaces: rich blocks + search
Multi-column layout inside Spaces (`columns` block). Embedded Collection view widget (renders any saved Collection view inline). Link list widget (manually curated). Global FTS5 search over Page bodies and frontmatter.

##### v0.12 — In-app customization
Settings panel exposes design tokens for user override — colors and typography. The user can change accent colors, surface tones, font family, and type scale from inside the app; changes apply live and persist. Token override layer sits on top of the Figma-derived defaults; the underlying token names stay stack-portable.

##### v1.0 — Stabilization
No new features. Polish, performance, bug-fix across everything from v0.0 through v0.12.

##### Post-v1
No specific phase commitments yet. Potential features and brainstormed ideas for after v1.0 — editor enhancements, additional view types (timeline, formulas, rollups), block features (synced blocks, per-block comments, block-level history), design polish (light/dark themes, design auditor), sync (Supabase), mobile and web, plugin system, etc. — are catalogued in `// Features//Prospects.md`. Items move from Prospects into a numbered version here when they become committed work.

#### Current Focus

**v0.0** — see `// Planning//v0.0.md`. Per-version planning docs are authored as we approach each version, not pre-stubbed. Implementation order has not been reviewed or approved by Nathan; this order will likely change. 
