### Pommora — History

Locked decisions, ordered by area. Brief by design — implementation detail lives in `PommoraPRD.md` and the feature docs.

#### Decisions

##### Stack — SwiftUI

Pommora's stack is SwiftUI. The earlier dual-stack evaluation (React+Electron vs SwiftUI) closed on SwiftUI for Mac cohesion, Apple ecosystem alignment, and iOS/iPad future intent. React+Electron is preserved as the contingency path; translation methodology and per-topic React detail live in `// ReactInfo//`.

- **Editor strategy: two SwiftUI options.** Option 1 — native Swift markdown editor: fork Clearly (FSL-1.1-MIT, converts to MIT Feb 2028) or build original on NSTextView/AppKit; source-with-decorations + Obsidian-style Live Preview. Option 2 (likely direction) — WKWebView hosting Tiptap, Milkdown, BlockNote, or MarkdownEditor; all have solid Markdown translation; native SwiftUI shell wraps the editor canvas. Detail in `// Features//Pages.md` editor section.
- **Mac OS integration is first-party** on SwiftUI — QuickLook, CoreSpotlight, Share Extensions, Finder file-promise drag-out, sidebar vibrancy, accessibility. Detail in `PommoraPRD.md` "Mac OS Integration" section.
- **Distribution** uses Sparkle 2.x for non-MAS auto-update; TestFlight for Mac; security-scoped bookmarks for MAS sandbox. Detail in `PommoraPRD.md` "Distribution" section.
- **React-side editor research preserved** at `// ReactInfo//Editor.md` — BlockNote (MPL-2.0) and Tiptap (MIT) as co-primary candidates, `@tiptap/markdown` first-party round-trip, etc. Same JS-editor candidates also serve as the Option 2 in-WebView editor on Swift.

##### SwiftUI research findings (preserved)

- `TextEditor(text: Binding<AttributedString>, selection:)` is documented for iOS 26+ / macOS 26+ (Tahoe).
- `apple/swift-markdown` is suitable as a parse / AST / query layer. `MarkupFormatter` reformats rather than round-trips and isn't a fit for the save path; a hand-rolled writer is the expected approach.
- Native `.draggable` + `.dropDestination` + `Transferable` are Apple's documented drag-and-drop API for new SwiftUI code.
- The wikilinks-as-styled-spans pattern follows WWDC25 Session 280's rich-text guidance; in-Pommora behavior verified in build.
- `AttributedString(markdown:)` is one-way (no `.markdown` accessor going back) — the save path needs its own writer.
- swift-markdown block directives use DocC `@Name(args){...}` syntax (NOT Pandoc / Obsidian `:::` fenced divs), enabled via `ParseOptions.parseBlockDirectives`. A `:::` ↔ `@` preprocessor or a fork of swift-markdown is needed for Pommora's directives on the parse side.
- Candidate component libraries surfaced during research: `stevengharris/SplitView`, `visfitness/reorderable`, `SwiftUIX/SwiftUIX`. Selection happens at build time.
- Reference: WWDC25 Session 280 ("Cook up a rich text experience in SwiftUI with AttributedString").
- Reference: Apple "Building rich SwiftUI text experiences".

##### Architecture (three load-bearing constraints)
1. **Stack portability of functionalities** — file formats, SQLite schema, domain model, property catalog, directive syntax, wikilink behavior, view directives, design values, UX patterns survive a stack rebuild. The codebase doesn't. **No enforced layer separation** (the earlier Core/Adapter/UI rule was dropped); portability comes from documented decisions.
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
- **Wikilinks render as styled colored inline text** (Obsidian-style), not Notion-style chips/pills.
- **Pages are Markdown documents, not block surfaces** — one continuous Markdown stream. "Block-level features" as a project term belongs to Spaces only.
- **Two Pommora-specific Markdown directives on Pages**: `@Columns` (`:::columns`) renders a section in N horizontal columns; `:::callout` renders an outlined-box callout (distinct from blockquotes). Both directives resolve cleanly when read by external Markdown tools.
- **Standard Markdown features**: paragraphs, headings H1–H5 (in v0's type scale; no H6 token; **headings are foldable by default** — built-in UI, not a directive), lists, code blocks + inline code, images, GFM tables, blockquotes, horizontal rules. Tables are GFM. Dividers are `---`. Side-by-side callouts or blockquotes via `@Columns` wrapping.
- **Blockquotes vs callouts are distinct constructs.** Blockquotes use standard `>` syntax and render as a filled box with a left-side emphasis bar. Callouts use the `:::callout` directive and render as a minimally-rounded outlined box. Each binds to its own brand-value family — `blockquote// fg` / `bg` / `accent` (left bar) and `callout// fg` / `bg` / `border` — alongside SwiftUI semantic colors.
- **Code rendering.** Code blocks and inline code render in SF Mono at 1.0 em. Foreground and background bind to Pommora-brand values (`code// fg`, `code// bg`) so the code palette can be tuned independently of text and accent.
- **Columns are equidistant in v1** — width division by child count. Adjustable widths deferred.
- **`@View` (in-line database view embed in a Page) is deferred to v2+.** Easier on Option 2 (WKWebView + JS editor — same node-component approach BlockNote and Tiptap support directly); harder on Option 1 (native editor) due to layout-attachment complexity. Embedded Collection views remain available *inside Spaces* (widget blocks) for v1.
- **Wikilink syntax variants in scope, incremental**: `[[Page Name]]` ships in v0.5; aliases (`[[name|alias]]`), heading anchors (`[[name#heading]]`), and asset embeds (`![[asset]]`) land as follow-ups.
- **Editor serialization architecture is load-bearing.** Three components, applies on either editor option:
  - **Canonical on-disk format** — Markdown (`.md`) for Pages, JSON for Spaces / Items / Collections. Required by agent legibility and external-tool compatibility.
  - **Rich in-editor working format** — whatever the editor framework prefers internally (styled-attribute model on Option 1's native text editor; the JS editor's block tree on Option 2 in WKWebView). Carries cursor state, undo/redo, in-app interchange.
  - **Explicit serializers** bridge the two for the Pommora-specific directives (`:::columns`, `:::callout`, wikilinks). Hand-rolled writer on Option 1; per-node/per-block serializers on Option 2's JS editor.

  This principle is stated stack-agnostically in `// Features//Architecture.md`. The React-side detail (BlockNote `blocksToMarkdownLossy` / `tryParseMarkdownToBlocks`, Tiptap `editor.getJSON()` + `@tiptap/markdown`, custom node serializer patterns) lives in `// ReactInfo//Editor.md`.
- **SwiftUI editor options.** Option 1 (native): source-with-decorations on NSTextView/AppKit — text storage IS the Markdown source, styling layered as attributes, marker hiding/reveal selection-driven. Clearly is the fork-able baseline. Option 2 (likely direction): WKWebView hosting Tiptap, Milkdown, BlockNote, or MarkdownEditor. [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) is the public production reference for the architecture; [Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor) is a Swift Package wrapping CodeMirror 6 in WKWebView with Obsidian-style syntax hiding, GFM tables, and SF fonts built in (MIT; personal project, single contributor — fork rather than depend). Pommora-specific extensions to add: `:::callout`, `:::columns`, wikilinks (addable as CM6 extensions). The `file://` ES-module block in WKWebView is resolved by a `WKURLSchemeHandler` registered for a custom scheme (Apple-documented pattern); the cross-origin caveat doesn't bite when the editor bundle ships inside the `.app`.

##### Sidebar + Shell
- **Three top-level collapsible headings, default-collapsed, user-reorderable**: Spaces (leaf labels), Saved (non-operational placeholder in v1 — pinning is post-v1), Collections (kind-agnostic; each Collection is a folder-style disclosure).
- **No Loose sidebar group.** Loose entities reach via search, wikilinks, or pinning.
- **No raw filesystem view in v1.**
- **"Collapsed-by-default disclosure"** is the general UI pattern for any hierarchical or grouped content.
- **Three-pane shell**: sidebar (default 240px) / main (flex) / pop-out inspector (default 280px). Built on SwiftUI's two-column `NavigationSplitView(sidebar:detail:)` with the inspector pane attached via the `.inspector(isPresented:)` modifier (macOS 14+) on the detail column. Apple's idiomatic pattern for main-pane + supplementary side panel (Mail / Notes / Pages); chosen over the three-column `NavigationSplitView` variant because the detail column was designed for selected-item drill-down, not for a contextual supplementary panel. Sidebar width via `.navigationSplitViewColumnWidth(min:ideal:max:)`; inspector width via `.inspectorColumnWidth(min:ideal:max:)`. `InspectorCommands()` registered in the App's `.commands` provides the View-menu toggle + default keyboard shortcut; a toolbar icon (`sidebar.right` SF Symbol at `.primaryAction` on the detail column) gives the visible toggle affordance. **Inspector hidden by default in v0.0** (the property panel content lands in v0.6; the default-shown decision is revisited then). Sidebar drag-resizable from v0.0; inspector drag-resizable when shown; widths persist across launches.
- **Main pane is multi-tabbed** (Obsidian / Notion pattern). Tab row at the top of the main pane; each tab is one open view — a Page, a Collection (with active saved view), or a Space. **Tab chrome and tab navigation both ship in v0.1** when files open (v0.0 has no tab chrome — chrome-without-functionality was removed from v0.0 as dead weight). `+` / `×` / `Cmd+T` / `Cmd+W` / `Cmd+1..9` / `Ctrl+Tab` standard shortcuts. Open tabs + active tab persist across launches. Items don't get their own tabs in v1 — they open in an **Item window**: a popover-style floating surface anchored to the trigger (Calendar-event-detail pattern), holding title + property inputs + a 250-char plain-text description. Tabs are reserved for full-pane views (Pages, Collections, Spaces); the inspector is for Page property panels only. Detail → `PommoraPRD.md` ("Top-Bar Tabs").
- **Property panel default location is the right inspector pane.** Below-heading and page-bottom placements are Prospects.
- **Inspector pane has two planned views.** Default view in v1 is the property panel for the active Page. An **AI chat interface** is a planned future addition (post-v1) — a frontend to Nathan's existing local CLI (not an API integration; the same pattern he already uses on Obsidian). See `// Features//Prospects.md`.

##### Views
- **Five view types in v1**: table, board, list, cards, gallery.
- **Inline cell editing** in Table view; **board view ships as visual kanban layout** in v0.9 (cards grouped by a property's options; edit a card to "move" it); **drag-to-rewrite-frontmatter kanban** is a planned post-v1.0 follow-up.
- **Two contexts for views**: inside a Collection (saved views in `_collection.json`); embedded as a Space widget (filter / sort / group / shown-properties override locally).

##### Scope and Posture
- **Mac for v1**; Linux / Windows aren't on the v1 path and become contingency-only on SwiftUI. **iOS / iPad is real long-term intent** — SwiftUI ships there essentially for free; one of the values that drove the SwiftUI lock.
- **Plugin system out of scope**, now and indefinitely. Personal tool, not a platform.
- **Versioning / file history delegated to OS tools** (Time Machine, git, filesystem snapshots). Pommora handles in-session undo only.
- **Single-user.** Multi-user collaboration is out of scope.

##### First-Launch Experience
- **Empty sidebars + seeded `Homepage` Space.** No tutorial, no walkthrough wizard. First Pages / Collections are user-created.

##### Design System
- **Swift-native baseline.** Pommora uses SwiftUI semantic colors + Pommora-brand `Color` / `Font` extensions for values not covered by native semantics; the component library at `// UI-UX//Components//` consumes them (no per-screen tweaks). For Swift, only a small subset matters (accent, code, callout, blockquote) — SwiftUI semantic colors carry the rest. The full ~118-token Figma-built taxonomy with semantic role-based naming is React-flavored and preserved at `// ReactInfo//Styling-Tokens.md`.
- **One initial scheme** in v0.x — no built-in light / dark; in-app customization is limited to accent color + font size (Framework v0.12). SwiftUI semantic colors, Materials, and Dynamic Type cover the rest natively.
- **Visual direction:** Notion-comfortable density; pastel-leaning color treatment (muted / desaturated); flat dark chrome (no shadows except on overlays); mixed-scale rounding (pill for tags / chips, tight for buttons / toggles / labels, surface for cards / panels / modals — Notion / Claude-style).
- **Typography pairing:** SF Pro (sans) + SF Mono (mono), system-native via SwiftUI Font scale. Heading scale is em-relative (H1–H5; no H6 in v0) so changing body rescales every heading.
- **Accent:** Single-hue, 2×2 matrix — primary/active, primary/muted, secondary/active, secondary/muted. All 4 stops share the same hue; descending in saturation + lightness. App accent color lives in `Assets.xcassets/AccentColor.colorset`; the other stops live as `Color+Pommora.swift` extensions. Specific hue is deferred — Xcode default stands in until the design lock.
- **SF Symbols on Swift** via `Image(systemName:)` — no indirection layer. (Material Symbols + role-indirection via `.pommora//symbols.json` is the React-side approach, preserved at `// ReactInfo//Symbols-guide.md`.)
- **In-app customization** (Framework v0.12) covers two values: accent color and font size. SwiftUI handles dark mode, semantic colors, Materials, and Dynamic Type natively — no additional override surface needed. Spacing / radius / shadow stay on baseline.
- **Disclosure pattern + DisclosureLine.** Pommora has multiple disclosure types (tree / folder, heading, toggle block, sidebar section header), all built on a single `Disclosure` primitive with an `indent line` variant. `true` for tree / folder disclosures — renders a `DisclosureLine` hairline guide tracing depth (Obsidian / VSCode pattern). `false` for heading disclosures and toggle blocks — no line. DisclosureLine is a sub-element of Disclosure, never placed independently.

#### Features Implemented

**v0.0 — Shell opens.** Barebones three-pane shell: two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)` on the detail column. Sidebar (240 default, drag-resizable) + main pane (empty `Color.clear`) + pop-out inspector (280 default, hidden by default, toggled via View menu / `InspectorCommands` keyboard shortcut). All three panes are completely empty — no labels, no content. Window 1200×800 default, 960×560 min, `.contentMinSize` resizability. Window title suppressed via `.windowToolbarStyle(.unified(showsTitle: false))` (traffic lights render; no "Pommora" title text). Deployment target macOS 26.5. Build verified via `xcodebuild`. Files: [PommoraApp.swift](Pommora/Pommora/PommoraApp.swift), [ContentView.swift](Pommora/Pommora/ContentView.swift).

The React+Electron-locked v0.0 spec is preserved at `// ReactInfo// v0.0.md` for contingency.
