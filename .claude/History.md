### Pommora — History

Locked decisions, ordered by area. Brief by design — implementation detail lives in `PommoraPRD.md` and the feature docs.

#### Decisions

##### Stack
- **Initial direction:** React + Electron + Tailwind + TypeScript + BlockNote + better-sqlite3 + Material Symbols, with SwiftUI as a deferred v2 path.
- **Currently under re-evaluation.** Both React+Electron and SwiftUI remain viable; only the editor surface and desktop shell are stack-specific (rest is portable).
- **2026 SwiftUI research:** WWDC25's native `AttributedString` binding to `TextEditor` removed the long-standing rich-text-editing blocker. `apple/swift-markdown`, GRDB.swift (FTS5 + `ValueObservation`), SF Symbols all production-ready. Wikilinks-as-styled-spans dissolves the chip/pill inline attachment gap.
- **2026 dual-stack research:** distribution is a wash (electron-updater ≈ Sparkle 2.x; both ship cleanly to MAS). React edges on dev loop (electron-vite HMR); SwiftUI edges on first-party tooling. Mac OS integration leans materially toward SwiftUI (QuickLook, CoreSpotlight, Share Extensions, Finder file-promise drag-out, sidebar vibrancy, accessibility). Detail in `Resources.md` and `SwiftInfo.md`.
- **Editor (React path) — two co-primary candidates: BlockNote (MPL-2.0) and Tiptap (MIT).** BlockNote is batteries-included; Tiptap is the headless ProseMirror-React framework BlockNote is built on (more configurable, more wiring). Both are fully open-source and free; every Tiptap package Pommora would use (`@tiptap/core`, `@tiptap/react`, `@tiptap/extension-drag-handle-react`, `@tiptap/markdown`, etc.) ships under MIT from the regular `@tiptap/*` npm scope. Either delivers the full editor surface — pick at React commit time. Pivot doors held: Milkdown (markdown-first), Yoopta (Slate-based), CodeMirror 6 (buffer-based, Plan B).
- **SwiftUI editor strategy (if chosen): two options.** Option 1 — native Swift markdown editor: fork Clearly (FSL-1.1-MIT, converts to MIT Feb 2028) or build original on NSTextView/AppKit; delivers source-with-decorations + Obsidian-style Live Preview (markers hidden when cursor leaves a construct, revealed when it enters). Option 2 (likely direction) — WKWebView hosting Tiptap, Milkdown, or BlockNote; all three have solid Markdown translation; native SwiftUI shell wraps the editor canvas; editor styled to match the design system via CSS. Detail in `SwiftInfo.md`.
- `better-sqlite3` over `node:sqlite` for the React path.

##### Architecture (three load-bearing constraints)
1. **Stack portability of functionalities** — file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design tokens, UX patterns survive a stack rebuild. The codebase doesn't. **No enforced layer separation** (the earlier Core/Adapter/UI rule was dropped); portability comes from documented decisions.
2. **Cross-vault queryability + cloud sync compatibility** — Collections aren't isolated; they're queryable and linkable from anywhere. The on-disk model maps cleanly to a cloud DB (single shared `pages` / `items` tables keyed by `collection_id`; `_collection.json` → `collections` row; each Space → `spaces` row). Sync arrives later as additive translation, not redesign. Cloud sync is real long-term intent.
3. **Persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Pommora = local + structured.

##### Domain Model
- Three top-level entities: **Pages** (`.md`), **Collections** (folder + `_collection.json`), **Spaces** (`.space.json`). Plus **Items** (`.json`, Collection-bound).
- **Collections are typed at creation** (`kind: "pages" | "items"`, persistent). Pages collections hold `.md` members; Items collections hold `.json` members. No mixed kinds. Personal use never mixes — the kind decision belongs at the Collection level, not per-entry.
- **Membership is by file location.** A `.md` inside a Pages collection folder is a member; a `.json` inside an Items collection folder is a member. No `collection` frontmatter field.
- **Loose Pages and loose Items both exist** — files outside any Collection folder. They carry identity and built-in fields but no schema-conforming properties. Reachable via search or wikilinks. Not a sidebar group. (Pinning to Saved is post-v1.)
- **Folder semantics**: a folder with `_collection.json` is a Collection; without one, it's cosmetic filesystem organization.
- **Spaces are referential, not containers** — they embed Pages / Items / Collection views via widgets and directives, not by holding them.
- **Filename = title canonical for all purposes** — Pages, Items, Collections (folder name), Spaces all derive their title from the filesystem name. No `title` field anywhere. No `name` field on Items. Independent UI titles are a Prospect.
- **No ad-hoc properties for members in v1** — must conform to the Collection's schema. Loose entities have no schema.
- **Page-to-Space and Item-to-Space linking**: `spaces` multi-relation, by Space ID.
- **No in-place Item ↔ Page promotion in v1.** Design insight preserved in `Prospects.md` — promotion is a format conversion (shared property catalog), not a data migration; demotion strips the Markdown body.
- **Sub-pages (nested Page hierarchy) is a v2 candidate.** Pages stay flat within Collections in v1.
- **No default seeded Collections.** First launch seeds only the `Homepage` Space.

##### Storage Layout
- **Vault location is user-pickable on first launch** (default suggestion `~// PommoraVault//`). The user can place the vault in iCloud Drive / Dropbox / any synced folder for free device-to-device sync in v1.
- **App-internal config folder: `.pommora//`** (leading dot, hidden by default — matches `.obsidian` convention; renamed from the earlier underscore-prefix `_pommora//`). Lives inside the vault. Holds `pommora.db` (SQLite index — regeneratable) and `spaces//` (`.space.json` files). (Earlier-planned `saved.json` for pinning is post-v1 — pinning is out of v1 scope.)
- **Vault-local trash: `.trash//`** at the vault root (sibling of `.pommora//`). Deleted entities move here, preserving original relative path. Restoration is a straight file move back. Auto-purge / age-based clearing is post-v1; v1 ships with manual clear only.
- **`.space.json` files** carry the full block tree. `_collection.json` is the Collection's schema sidecar (Make.md folder-notes pattern).
- **Files canonical, SQLite as index.** Markdown for Pages; JSON for everything else. SQLite is regeneratable from files.
- **Cloud-sync mapping** in PRD: a single shared `pages` table with `collection_id` + `properties` JSONB column; parallel `items` table with the same shape; one `collections` row per `_collection.json`; one `spaces` row per `.space.json`.

##### Property Model
- **No free-form text property.** Title is the filename; "text-shaped" values use Select / Multi-select with creatable options (Notion behavior).
- **No dedicated `Status` type.** Status-like behavior = a Select named "Status" with user-defined options.
- **v1 catalog (8 types):** number, checkbox, date, datetime, select, multi-select, relation, URL.
- **Per-Collection schemas** — each `_collection.json` holds its own property schema and saved views. No shared schemas file.
- **Property values** — Pages in YAML frontmatter; Items in the `.json` file's `properties` key. Same catalog, two storage substrates.
- **Color palette for Select / Multi-select** = fixed 9-color Notion palette (`gray`, `brown`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `red`). Custom hex picker is a Prospect.
- **Property panel shows every schema property always** (Notion-style), even unset. Hide-empty is a Prospect.
- **Option order within Select / Multi-select properties defines sort behavior** — drag-to-reorder options; ascending sort returns first-listed first. Replaces alphabetical sort.
- **View-level column ordering is visual, per-view** (drag column headers; stored in the view spec). Schema-level property declaration order is append-on-add in v1.
- **Inline cell editing in Table view** confirmed.
- **Relations are stored by ID** (rename-safe) and **displayed as the target's current title** (resolves ID → title at render time; renames update display automatically).
- **Move-strip rule (Notion-style):** moving a member across Collections (or in/out of loose state) strips properties not in the destination schema. No `_orphaned` quarantine, no backup. **User gets a simple confirmation warning** listing which properties will be stripped before the move proceeds. Same rule applies to property deletion.
- **Auto-managed fields**: `id` (ULID), `created_at`, `modified_at` on every member and every loose entity.

##### Editor
- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips/pills — both stacks.
- **Pages are Markdown documents, not block surfaces** — one continuous Markdown stream. "Block-level features" as a project term belongs to Spaces only.
- **Two Pommora-specific Markdown directives on Pages**: `@Columns` (`:::columns`) renders a section in N horizontal columns; `:::callout` renders an outlined-box callout (distinct from blockquotes). Both directives resolve cleanly when read by external Markdown tools.
- **Standard Markdown features**: paragraphs, headings H1–H5 (in v0's type scale; no H6 token; **headings are foldable by default** — built-in UI, not a directive), lists, code blocks + inline code, images, GFM tables, blockquotes, horizontal rules. Tables are GFM. Dividers are `---`. Side-by-side callouts or blockquotes via `@Columns` wrapping.
- **Blockquotes vs callouts are distinct constructs.** Blockquotes use standard `>` syntax and render as a filled box with a left-side emphasis bar. Callouts use the `:::callout` directive and render as a minimally-rounded outlined box. Both adhere to dedicated token families: `blockquote// fg` / `bg` / `accent` (left bar) and `callout// fg` / `bg` / `border`, all tied to the color system.
- **Code rendering tokens.** Code blocks and inline code render in mono font (SF Mono) at 1.0 em with dedicated tokens: `code// fg` (default `#FF2525`) and `code// bg` (default `#323233`). Tied to color primitives; tunable through the color system independently of text and accent.
- **Columns are equidistant in v1** — width division by child count. Adjustable widths deferred.
- **`@View` (in-line database view embed in a Page) is deferred to v2+** and React-conditional — `@View` inside the prose flow is the harder direction on a native editor, so the v2+ revisit is React-conditional. Embedded Collection views remain available *inside Spaces* (widget blocks) for v1.
- **Wikilink syntax variants in scope, incremental**: `[[Page Name]]` ships in v0.5; aliases (`[[name|alias]]`), heading anchors (`[[name#heading]]`), and asset embeds (`![[asset]]`) land as follow-ups.
- **Editor serialization architecture (React path) is load-bearing.** Three components, identical pattern on either co-primary editor (only the API names change):
  - **Markdown on disk** (`.md`) — canonical content format; required by agent legibility and external-tool compatibility. **BlockNote:** `blocksToMarkdownLossy` / `tryParseMarkdownToBlocks`. **Tiptap:** `@tiptap/markdown`.
  - **JSON in-editor** — working format + perfect-fidelity export for cursor state, undo / redo, Pommora-to-Pommora interchange. **BlockNote:** `editor.document`. **Tiptap:** `editor.getJSON()`.
  - **Custom per-block / per-node serializers** — bridge the two for the two Pommora directives. **BlockNote pattern:** [Issue #221](https://github.com/TypeCellOS/BlockNote/issues/221) → [PR #426](https://github.com/TypeCellOS/BlockNote/pull/426). **Tiptap pattern:** `renderHTML` per node + the first-party `@tiptap/markdown` extension's `MarkdownManager` (`editor.markdown.parse` / `serialize` / `getMarkdown` / `setContent` with `contentType: 'markdown'`) — round-trip is first-class, no extensibility hooks or parallel `prosemirror-markdown` integration required.
  Both formats are necessary. The `Lossy` suffix on BlockNote's API is generic-case naming — a non-issue here, closed by the small per-block / per-node serializers for the two directives. Generalized in `Architecture.md` as a cross-stack principle (every editor has on-disk and in-memory formats; explicit serializers bridge them).
- **SwiftUI editor feasibility confirmed, two options.** Option 1 (native): source-with-decorations on NSTextView/AppKit — text storage IS the markdown source, styling layered as attributes, marker hiding/reveal selection-driven; Clearly is the fork-able baseline. Option 2 (likely direction if SwiftUI chosen): WKWebView hosting Tiptap, Milkdown, BlockNote, or MarkdownEditor — all have solid Markdown translation; native SwiftUI shell wraps the editor canvas. If Option 2, the stack decision collapses to shell quality and build effort for everything outside the editor. **MarkdownEditor** ([Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor)) is the key evaluated reference: a Swift Package wrapping CodeMirror 6 in WKWebView with Obsidian-style syntax hiding, GFM tables, and SF fonts built in; MIT; personal project — fork rather than depend. **MarkEdit** (App Store) is the public production reference for the architecture. Pommora-specific extensions to add: `:::callout`, `:::columns`, wikilinks (all addable as CM6 extensions). The `file://` ES-module block in WKWebView is resolved by a `WKURLSchemeHandler` registered for a custom scheme (`editor://`) — Apple-documented pattern; doesn't apply when the editor bundle ships inside the `.app` with no external fetches.

##### Sidebar + Shell
- **Three top-level collapsible headings, default-collapsed, user-reorderable**: Spaces (leaf labels), Saved (non-operational placeholder in v1 — pinning is post-v1), Collections (kind-agnostic; each Collection is a folder-style disclosure).
- **No Loose sidebar group.** Loose entities reach via search, wikilinks, or pinning.
- **No raw filesystem view in v1.**
- **"Collapsed-by-default disclosure"** is the general UI pattern for any hierarchical or grouped content.
- **Three-pane shell**: sidebar (default 240px) / main (flex) / inspector (default 280px). Both side panes drag-resizable from v0.0; widths persist across launches.
- **Main pane is multi-tabbed** (Obsidian / Notion pattern). Tab row at the top of the main pane; each tab is one open view — a Page, a Collection (with active saved view), or a Space. Tab chrome ships in v0.0 (visual, non-functional); tab navigation wired in v0.1 when files open. `+` / `×` / `Cmd+T` / `Cmd+W` / `Cmd+1..9` / `Ctrl+Tab` standard shortcuts. Open tabs + active tab persist across launches. Items don't get their own tabs in v1 — they open in an **Item window**: a popover-style floating surface anchored to the trigger (Calendar-event-detail pattern), holding title + property inputs + a 250-char plain-text description. Tabs are reserved for full-pane views (Pages, Collections, Spaces); the inspector is for Page property panels only. Detail → `PommoraPRD.md` ("Top-Bar Tabs").
- **Property panel default location is the right inspector pane.** Below-heading and page-bottom placements are Prospects.
- **Inspector pane has two planned views.** Default view in v1 is the property panel for the active Page. An **AI chat interface** is a planned future addition (post-v1) — a frontend to Nathan's existing local CLI (not an API integration; the same pattern he already uses on Obsidian). See `// Features//Prospects.md`.

##### Views
- **Five view types in v1**: table, board, list, cards, gallery.
- **Inline cell editing** in Table view; **board view ships as visual kanban layout** in v0.9 (cards grouped by a property's options; edit a card to "move" it); **drag-to-rewrite-frontmatter kanban** is a planned post-v1.0 follow-up.
- **Two contexts for views**: inside a Collection (saved views in `_collection.json`); embedded as a Space widget (filter / sort / group / shown-properties override locally).

##### Scope and Posture
- **Mac for v1**; Linux / Windows not on v1 path but not forever-closed. **iOS / iPad is real long-term intent** — affects the stack call materially (SwiftUI ships to iPad essentially free; React needs a parallel build).
- **Plugin system out of scope**, now and indefinitely. Personal tool, not a platform.
- **Versioning / file history delegated to OS tools** (Time Machine, git, filesystem snapshots). Pommora handles in-session undo only.
- **Single-user.** Multi-user collaboration is out of scope.

##### First-Launch Experience
- **Empty sidebars + seeded `Homepage` Space.** No tutorial, no walkthrough wizard. First Pages / Collections are user-created.

##### Design System
- **Two-tier source of truth.** Figma owns design tokens — semantic role-based names (`surface// primary// bg`) exporting to CSS custom properties (React) and SwiftUI Color extensions (Swift). The component library owns components — built from those tokens; once in the library, consumed as-is during feature work (no per-screen tweaks). React library lives on Pommora's own localhost (no Storybook intermediary).
- **Build order**: Figma design-system phase (pre-v0.0; stack-agnostic at the variable level) → stack decision → v0.0 shell consumes the design system. Design system precedes the stack call.
- **One initial scheme** in v0.x — no built-in light / dark; in-app customization for colors and typography lands in Framework v0.12.
- **Dual-axis tier model** — surface tier × element tier (independent axes), each with primary / secondary / tertiary.
- **Visual direction:** Notion-comfortable density; pastel-leaning color treatment (muted / desaturated); flat dark chrome (no shadows except on overlays); mixed-scale rounding (pill for tags / chips, tight for buttons / toggles / labels, surface for cards / panels / modals — Notion / Claude-style).
- **Typography pairing:** SF Pro (sans) + SF Mono (mono), system-native. Heading scale is em-relative (H1–H5; no H6 in v0) so changing body rescales every heading.
- **Accent:** Single-hue purple, 2×2 matrix — `accent// primary// active`, `primary// muted`, `secondary// active`, `secondary// muted`. All 4 stops share the same hue; descending in saturation + lightness. Pastel-muted.
- **Baseline tokens committed** — see `// Planning//Figma Prompt.md`. All hex / sizing values are baselines for Figma round 1.
- **Material Symbols (outlined as default)** on React; **SF Symbols** on Swift. Icon role table seeded in `// Planning//Figma Prompt.md` (canonical seed for `.pommora// symbols.json`); covers shell, common actions, entity kinds, sidebar sections, editor formatting, property types, views, and view controls.
- **Symbol indirection (React only).** Components reference semantic symbol roles (`settings`, `add`, etc.), not direct Material / SF names. The mapping lives in `.pommora// symbols.json` (seeded on first launch from the role table in the Figma Prompt) so the icon library can be swapped via a planned setting without rewriting components. Detail → `// Guidelines//Symbols-guide.md`.
- **In-app token override (React-conditional).** Variables export to CSS custom properties; settings panel writes user-scoped overrides to a separate CSS layer cascading on top of defaults — single property mutation at runtime, no rebuild. Token names remain stack-portable so a future SwiftUI rebuild inherits the same override pattern via `@AppStorage` + the SwiftUI environment. Framework v0.12 covers color + typography only; spacing / radius / shadow stay on baseline.
- **Disclosure pattern + DisclosureLine.** Pommora has multiple disclosure types (tree / folder, heading, toggle block, sidebar section header), all built on a single `Disclosure` primitive with an `indent line` variant. `true` for tree / folder disclosures — renders a `DisclosureLine` hairline guide tracing depth (Obsidian / VSCode pattern). `false` for heading disclosures and toggle blocks — no line. DisclosureLine is a sub-element of Disclosure, never placed independently.

#### Features Implemented

None yet. v0.0 in spec stage; `// Planning//v0.0.md` is React+Electron-locked and gets rewritten if SwiftUI is chosen.
