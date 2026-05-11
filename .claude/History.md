### Pommora — History

#### Decisions

##### Stack
- **Initial direction:** React + Electron + Tailwind + TypeScript + BlockNote + better-sqlite3 + Material Symbols, with SwiftUI as a deferred v2 path
- **Currently:** under re-evaluation. Both React+Electron and SwiftUI remain viable. The architecture's conceptual-portability framing (file formats, schemas, semantic operations, design tokens, UX patterns survive a stack rebuild) preserves either-direction translation; only the editor surface and desktop shell are inherently stack-specific
- **2026 SwiftUI research (logged for reference):** WWDC25 added native `AttributedString` binding to `TextEditor`, removing the long-standing rich-text-editing blocker for SwiftUI. `apple/swift-markdown` (block directives), GRDB.swift (FTS5 + `ValueObservation`), and SF Symbols all production-ready. The one remaining gap (chip/pill inline attachments) is moot because wikilinks render as styled colored spans, not chips
- **2026 dual-stack tools/considerations research (logged for reference):** distribution and auto-update story is equivalent between stacks (electron-updater ≈ Sparkle 2.x; both ship cleanly to MAS via security-scoped bookmarks). React edges on dev loop (electron-vite HMR); SwiftUI edges on first-party tooling. Mac OS native integrations lean materially toward SwiftUI: QuickLook (.md preview via Finder spacebar), CoreSpotlight, Share Extensions, Finder file-promise drag-out, sidebar vibrancy, and accessibility all show meaningful gaps in pure Electron (some require shipping a separate Swift bundle to deliver at all). Equal: app menu, deep links, basic notifications, dark-mode toggling. Detail in `// Resources.md` and `// SwiftInfo.md`
- **Editor (React path) — picked BlockNote (open-source MPL-2.0 core).** Considered alternatives during this session: Tiptap (eliminated free Cloud plan in 2026; commercial-trajectory risk for an "always open-source" project), Milkdown (markdown-first by design, MIT, ProseMirror foundation), Yoopta (Slate-based, MIT, 20+ built-in plugins including a callout). All three remain on the table as **pivot doors** if BlockNote disappoints in real use
- `better-sqlite3` chosen over `node:sqlite` for the React path

##### Architecture
- **Conceptual portability of functionalities** — Pommora's *functionalities* (file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design tokens, UX patterns) are designed to survive a stack rebuild. If one stack ships and Pommora is later rebuilt in the other, that rebuild is guided translation work, not redesign. **The earlier three-layer enforcement model (Core/Adapter/UI with "Core has zero UI imports" rule) was dropped as over-engineered for indie development** — portability now comes from documented decisions, not enforced code structure
- **Cross-vault queryability + cloud sync compatibility is the second load-bearing constraint** — Collections aren't isolated to their folder; they're queryable and linkable from anywhere in the vault. The on-disk model must translate cleanly to a cloud database (Collection → table, Pages → rows, schema → columns, Space → row with JSON block tree) so a future sync layer (e.g. Supabase) is additive, not a redesign
- **Reference convention:** frontmatter relations use IDs (rename-safe); body wikilinks use names (rewritten on rename)

##### Domain Model (current)
- Three top-level entity types: **Pages**, **Collections**, **Spaces**. Definitions in `// Features//Domain-Model.md`
- **Pages** = Markdown files. Prose-first editor (Bear / iA Writer style, not Notion-style block-per-paragraph). One embed type in body for v1: `@Columns`. Each Page is a member of the Collection whose folder it lives in, OR a loose Page if it lives outside any Collection folder. Pages are never shared between multiple Collections
- **Collections** = a folder + a `_collection.json` schema sidecar inside the folder (Make.md folder-notes pattern applied to databases). Hold property schemas and saved view configurations (table / board / list / cards / gallery). **No text-editor surface** — purely database viewers. Member Pages are the `.md` files alongside the sidecar
- **Spaces** = Notion-page-style block-composition surfaces. Stored as `.space.json` files (not Markdown) in `_pommora// spaces//`, holding the full block tree. Text blocks (paragraph, headings, lists, callout, code, columns, image) and widget blocks (linked-pages, embedded-collection-view, link-list) intermixed in one canvas. The only surface in Pommora with Notion-style block manipulation. Independent of Collections
- **Folder semantics:** a folder containing a `_collection.json` is a Collection (semantic). A folder without one is cosmetic filesystem organization (no semantic meaning). Pages inside cosmetic folders are loose Pages
- **Page-to-Space linking:** `spaces` multi-relation property in Page frontmatter (locked)
- **Page-to-Collection membership:** by file location (locked). No `collection` frontmatter field
- **Cross-Collection linking:** normal — relation properties on Pages or Spaces can reference any other entity in the vault, regardless of folder location
- **No default "Inbox" Collection** — loose Pages take the place of an Inbox
- **Filename = title.** No `title` field in Page frontmatter, in `_collection.json`, or in `.space.json`. Renaming any of these in the UI renames the underlying file/folder. Independent UI titles are a wishlist item
- **No ad-hoc properties for v1.** Page properties must conform to the Collection's schema. The only "outside the schema" things are sidebar ordering / sorting (UI state, not file content)
- **No free-form text property type.** Title is the filename (handled by the file system, not a property); all other properties are typed (number, date, checkbox, select, multi-select, relation, URL). "Text-shaped" property values use Select / Multi-select with creatable options — typing a new label adds it to the catalog (Notion behavior)
- **Spaces are page-like canvases with drag-and-drop blocks** — Notion-style structured layout (1D vertical flow with one nestable `columns` container), not free X/Y positioning

##### Data
- **Files canonical, SQLite as index.** Markdown for Pages on disk; JSON for Collection schemas and Spaces; SQLite for fast queries
- **Per-Collection schemas** — each Collection's `_collection.json` sidecar (inside the Collection's folder) holds its own property schema and saved views. The earlier shared `_pommora// schemas.json` proposal is dropped
- **Property values in frontmatter** — directly editable in any text editor
- **Local-end translation principle:** files store the spec, not the rendered data — view directives reference what they render but don't inline it
- **Spaces serialization:** `.space.json` files in `_pommora// spaces//` (locked, not Markdown — full block tree)
- **Collection serialization:** `_collection.json` sidecar inside each Collection's folder (locked, Make.md folder-notes pattern)
- **Cloud sync mapping clarified.** The earlier PRD wording "each Collection → one cloud table" was misleading — would produce dynamically-created Postgres tables in production. Corrected mapping: a single shared `pages` table where each row carries `collection_id` and a `properties` JSONB column (matching local SQLite shape, and matching the Notion / Airtable / AFFiNE convention). Each `_collection.json` schema → a row in a `collections` table; each Space → a row in a `spaces` table with the block tree as a JSON column

##### Editor
- **Wikilinks render as styled colored inline text** (Obsidian-style hyperlink), NOT Notion-style chips/pills — across both stacks. This decision dissolves the SwiftUI editor blocker around inline view attachments
- **Pages use a prose-first editor**, not block-per-paragraph. Slash menu / toolbar inserts block-level features; no draggable block handles on every paragraph
- **In v1, block-level features inside a Page are `@Columns`, callouts, and toggles.** The earlier-proposed `@View` directive (in-line database view inside a Page) is deferred to v2+. Embedded Collection views remain available *inside Spaces* (as widgets) for v1.

  **For React** — `@View` would become a custom block component on top of BlockNote core (well-trodden) when revisited.

  **For Swift** — `@View` is not feasible inside the native `TextEditor`; would require an `NSTextView` / TextKit 2 surface. The v2+ revisit is React-conditional for this reason.
- **Columns are equidistant in v1.** Width division is determined by child count — three children = three equal columns. No per-column width configuration, no inline width attributes, no sidecar layout file. Adjustable widths deferred to a later version.
- **Callouts are visual containers with optional color** — single design pattern (one border style), no icons, no semantic types (no "warning" / "info" / "error" variants). Default border color inherits from text color; explicit color comes from a catalog. Inner content is editable markdown. Composes with `@Columns` for Notion-style side-by-side callouts.
- **Toggles are collapsible content blocks** (Notion-style) — clickable triangle expands/collapses inner content. Useful for FAQs, condensed reference sections, optional detail. Inner content is editable markdown.
- **If SwiftUI is the chosen stack, the editor strategy is two-phase.** Phase A is v1 scope: native `TextEditor<AttributedString>` (iOS 26 / macOS 26+) with a quick fork to add H4-H6 and toggles support; sufficient for ship. Phase B is a **committed post-v1 core feature** (not optional, not Prospects, but scheduled after v1): full custom editor with hover-on-selection bubble toolbar (Medium / Notion-style — select text, popover with formatting actions appears). Both phases use a segment-based render pattern for callouts and columns (page = `[Segment]`; prose segments use `TextEditor`; column/callout segments use specialized container views). Native text engine = system spell check, undo/redo, dictation, accessibility all free. Detail in `// Pages.md` and `// SwiftInfo.md`.
- **BlockNote markdown is lossy by design** (confirmed in official docs): nested non-list blocks flatten on export, custom blocks need custom serializers, inline marks beyond built-ins drop silently. Custom serialization is achievable via per-block `toExternalHTML`/markdown handlers (Issue #221 / PR #426) but covering every block type *is* the canonical-format guarantee — not a small layer. CodeMirror 6 (markdown literally *is* the document; perfect round-trip by definition) remains the markdown-canonical Plan B at 2-3× implementation cost
- **SwiftUI editor segment-render is the load-bearing risk on the SwiftUI path** (logged for reference): no shipped Mac markdown app uses the segment-based render pattern; Bear / iA Writer / Craft all use single-text-view-with-decorations precisely to avoid the cross-segment cursor problem. Mitigations if SwiftUI is picked: treat per-segment selection as a Notion-like feature, or drop down to STTextView (TextKit 2) if cross-segment selection becomes a hard requirement. Detail in `// SwiftInfo.md`

##### Sidebar Pattern
- **Top-level groups:** Spaces, Collections, Loose Pages
- **Collections are collapsible disclosure groups** — default state collapsed. Expanding reveals member Pages
- **No raw filesystem view** in v1 (no Files toggle). Sidebar surfaces only the logical model
- **"Collapsed-by-default disclosure" is the general default UI pattern** for any hierarchical or grouped content elsewhere in the app

##### Design System
- **Figma is the source of truth** for visual design
- **Dual-export naming discipline:** Figma Variables use semantic role-based names that export to both CSS custom properties (React) and SwiftUI Color extensions (SwiftUI)
- **One initial scheme** in v0.x — no built-in light/dark; customization deferred to v2
- **Dual-axis tier model:** surface tier × element tier (independent axes)
- **Material Symbols** (React path) or **SF Symbols** (SwiftUI path)

#### Features Implemented

None yet. v0.0 in spec stage; the spec itself is React+Electron-locked and gets rewritten if the SwiftUI path is chosen.
