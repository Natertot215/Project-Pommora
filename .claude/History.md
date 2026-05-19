### Pommora — History

Locked decisions, ordered by area. Brief by design — implementation detail lives in `PommoraPRD.md` and the feature docs.

#### Session 7 — 2026-05-18 (second long session) — v0.2.7 Phase A-G ship + Milkdown pivot

A single sprawling session covering: SPM dep on Pallepadehat fork → full domain layer + 10 tests → editor wires end-to-end → 5 polish iterations after smoke test → 2 fork-side polish iterations (Phase G #1 + #2) → Nathan-driven decision to swap to Milkdown + Crepe.

**Commits on `main` (8 of them, all on `main`, none pushed):**
- `1df93a6` v0.2.7-a — SPM dep on `Natertot215/PageEditorMD` (branch=main, the Pallepadehat fork)
- `ca33210` v0.2.7-b — Domain layer (PageRef + updatePage + PageEditorViewModel + 10 tests) + icon migration
- `74d1ea9` v0.2.7-c1 — Pommora.entitlements + CODE_SIGN_ENTITLEMENTS (4 keys: app-sandbox / user-selected.read-write / bookmarks.app-scope / network.client)
- `14e1c8a` v0.2.7-c2 — AppGlobals (weak VM registry + lifecycle flush observer) + AppState.pageInspectorOpen + PommoraApp.init bootstrap
- `62f4b7b` v0.2.7-c3 — Editor end-to-end: FrontmatterInspector + PageEditorView + PageEditorHost (page-switch flush via `.task(id:)`) + sidebar wire
- `599ee2f` v0.2.7-c4 — Inspector dedupe + title banner (read-only)
- `454d153` v0.2.7-c5 — Editable title (TextField → renamePage → file rename) + inspector at NavigationSplitView level
- `dcb1ab0` v0.2.7-c5.1 — Inspector toggle INSIDE `.inspector(...)` closure (fixes left-side placement)
- `6882ea9` v0.2.7-c5.2 — Sidebar page-switching regression fix (`@State var viewModel` → `@Bindable` + `.id(vm.page.id)`)
- `2226fbe` v0.2.7-g — Package.resolved bump to fork `4fd91d6` (Phase G #1)
- `1989fac` v0.2.7-g.2 — Package.resolved bump to fork `addaa23` + SwiftUI `.background(Color.clear)` defensive layer

**Fork commits at `Natertot215/PageEditorMD` (Pallepadehat fork, all pushed to origin/main):**
- `4fd91d6` — Phase G #1: drop active-line highlighting + Notes-style fold chevron + markdown-autopair.ts + tighter heading→body spacing + Apple typography overhaul (SF Pro Text body, SF Pro Display headings, SF Mono code, Notes-aligned scale 28/22/17/15/13/13pt) + transparent bg CSS
- `a146a28` — Swift WKWebView triple-clear (drawsBackground KVC + underPageBackgroundColor + NSView layer bg)
- `addaa23` — `!important` on transparent bg rules to win over xcode theme

**Tests:** 186/186 → 198/198 (+12 across Phase B). Lint clean throughout. Build green throughout.

**Smoke-test verdict + Milkdown decision:** Nathan smoke-tested Phase G post-clean-build and decided visual baseline still didn't ship Notion-like polish. Context7 research on Milkdown + Crepe confirmed: Crepe (`@milkdown/crepe`) is the polished out-of-box wrapper with `frame` / `crepe` / `nord` themes (each light + dark); `remark-directive` plugin handles `:::callout` natively; custom inline nodes follow standardized 5-component pattern. Round-trip risk = body stylistic normalization (list marker / fence / heading style), accepted for Pommora's primary single-source-of-truth use case.

**Locked decisions for the swap (Session 8 will implement):**
- **Vendor the wrapper as source files inside Pommora's own tree** (probable `Pommora/Pommora/PageEditor/` + `Pommora/Pommora/PageEditor/web/`), NOT as SPM dep, NOT as fork. Nathan needs to see every line.
- **Use Crepe's `frame` theme (most macOS-native) as default**. Pommora-brand styling layer comes AFTER baseline ships.
- **Defer Pommora extensions:** `:::callout` + `@Columns` → v0.2.9 (remark-directive). `[[wikilinks]]` → v0.2.10 (5-component plugin).
- **Stay WYSIWYG / Live Preview editing model** (Crepe defaults).

**What survives the swap:** PageRef, PageFile, PageMeta, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, Pommora.entitlements, all 198 tests, the title-banner VStack + `.inspector` pattern in PageEditorView.

**What gets stripped:** the 6 pbxproj SPM entries for `MarkdownEditor`, Package.resolved entry for PageEditorMD, `import MarkdownEditor` references, `pommoraEditorConfig`, the Pallepadehat-specific `EditorWebView(...)` call. The fork repo at `Natertot215/PageEditorMD` stays in git history as a parked branch — not deleted, but not consumed.

**Sub-plan for Session 8 plan mode:** `.claude/Planning/v0.2.7-milkdown-swap.md` with three explicit research areas (**Strip / Setup / Construct styling**) + verbatim resume prompt.

**Effort estimate for Session 8:** ~2.5–3 Claude sessions to ship feature-equivalent + better UI baseline.

**Active branch quirk added this session:** branch-pinned SPM forks don't bump via gentle `xcodebuild -resolvePackageDependencies` — need full nuke of `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*` to force a fresh resolve. Documented in the `v0.2.7-g` commit message.

#### Decisions

##### Stack — SwiftUI

Pommora's stack is SwiftUI. The earlier dual-stack evaluation (React+Electron vs SwiftUI) closed on SwiftUI for Mac cohesion, Apple ecosystem alignment, and iOS/iPad future intent. React+Electron is preserved as the contingency path; translation methodology and per-topic React detail live in `// ReactInfo//`.

- **Editor strategy: two SwiftUI options.** Option 1 — native Swift markdown editor: NSTextView via `NSViewRepresentable` + `swift-markdown` + TextKit 2 (Clearly available as a fork-reference, FSL-1.1-MIT → MIT Feb 2028); source-with-decorations + Obsidian-style Live Preview. Option 2 (likely direction) — WKWebView hosting Tiptap, Milkdown, BlockNote, or MarkdownEditor; all have solid Markdown translation; native SwiftUI shell wraps the editor canvas. Detail in `// Features//Pages.md` editor section.
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
2. **Cross-nexus queryability + cloud sync compatibility** — Collections aren't isolated; they're queryable and linkable from anywhere. The on-disk model maps cleanly to a cloud DB (single shared `pages` / `items` tables keyed by `collection_id`; `_collection.json` → `collections` row; each Space → `spaces` row). Sync arrives later as additive translation, not redesign. Cloud sync is real long-term intent.
3. **Persistent immediate legibility for agents** — every entity is a file an external agent can read directly without tool-call round-trips. SQLite is performance scaffolding, not source of truth. Differentiator from Notion-via-MCP (tool-mediated, opaque) and Obsidian (locally legible but unstructured). Pommora = local + structured.

##### Domain Model (revised 2026-05-16 — replaces earlier 3-entity model)

**2-layer PARA-aligned model:**
- **Organization layer — Contexts** (3 tiers): **Spaces** (1, broad life domains) / **Topics** (2, subject areas) / **Sub-topics** (3, specifics within a Topic). All three are composed-blocks surfaces.
- **Operational layer — Vaults + Agenda:** **Vaults** (folder + `_vault.json` with shared schema) contain **Collections** (sub-folders sharing the Vault's schema in v1) which contain **Pages** (`.md`) + **Items** (`.json`). **Agenda** is a sibling of Vaults at `<nexus>/Agenda/` holding `.agenda.json` files with EventKit integration.
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.

**Tier system rules:**
- Tier-parent rule — every `parents[i]` resolves to a Context with `level < this.tier`. Cycles impossible by construction.
- Topics multi-parent across Spaces; Sub-topics single-parent at file (folder location = parent Topic) with additional `linked_relations` as typed multi-valued relation property.
- No same-tier file-structural links (Topic ↛ Topic; Space ↛ Space).
- Tier-skip allowed.
- Per-tier labels user-configurable per-Nexus (Capacities-style singular + plural in `.nexus/tier-config.json`).
- **Three tiers default; tier 3 ("Sub-topics") exposed in v1.** Code/schema supports a fourth tier without changes (gated by `exposed` flag).

**Operational layer rules:**
- Vaults are **kind-agnostic** — Pages and Items coexist under the shared Vault schema. Earlier `kind: "pages" | "items"` Collection typing is gone.
- Collections in v1 are pure sub-folders (no own metadata file, no own schema). Collection-local schema overrides are a post-v1 Prospect.
- **Tasks and calendar events are NOT Items** — they live as **Agenda items** with EventKit integration. Schema is unified (no `kind` discriminator); user-facing type (Task / To-Do / Phase / Event / custom) is a `properties.type` Select.
- Per-tier multi-relations (`tier1` / `tier2` / `tier3`) on Items / Pages / Agenda items replace the earlier `spaces` multi-relation.
- Move-strip rule survives — moving Content between Vaults strips properties not in destination schema with confirm.
- No in-place Item ↔ Page promotion in v1 (Prospect).
- No default seeded Collections; first launch seeds the singleton Homepage entity (not a Space).

**Sidebar shape:**
- Four top-level sections: **Saved / Spaces / Topics / Vaults**. Replaces the earlier three-heading model (Spaces / Saved / Collections).
- Saved holds three fixed entries (Homepage / Calendar / Recents) with renamable labels (`saved-config.json`).
- Agenda items don't appear in the sidebar — accessed via Saved → Calendar.

**Inline editing principle (locked):**
- Every embedded view in a composed-blocks surface (Context, Homepage) is a live, fully-editable view of its source — never a read-only snapshot.
- Edits route through source entity's manager → atomic write → file watcher → SQLite re-index → all embedded views refresh.
- Full inline editing of a referenced Page's body (Notion "synced blocks") is post-v1 (Prospect).

**EventKit integration contract:**
- Agenda items map to `EKEvent` / `EKReminder` based on which time fields are populated.
- Sandbox entitlement `com.apple.security.personal-information.calendars` + Info.plist usage description keys + modern `requestFullAccessTo*` APIs required.
- Sync NOT enabled by default in v1 — opt-in via Settings.

**Full revised spec** lives at `// Planning//Contexts-Vaults-spec.md` (file schemas, validation, CRUD scope, 11-phase implementation plan, SwiftUI research findings, day-1 working plan, doc-rewrite tracking).

##### Storage Layout
- **Nexus location is user-pickable on first launch** (default suggestion `~// PommoraNexus//`). The user can place the nexus in iCloud Drive / Dropbox / any synced folder for free device-to-device sync in v1.
- **App-internal config folder: `.nexus//`** (leading dot, hidden by default — matches `.obsidian` convention; renamed from the earlier underscore-prefix `_pommora//`). Lives inside the nexus. v0.1a holds `nexus.json` (vault-portable identity: ULID + createdAt). v0.2+ adds `state.json` (vault-portable user state: open tabs, sidebar collapsed state) and `spaces//` (`.space.json` files).
- **`nexus.db` lives outside the nexus** at `~//Library//Application Support//com.nathantaichman.Pommora//nexuses//<nexus-id>//nexus.db`. Resolves the iCloud-sync corruption risk that motivated moving SQLite out of the cloud-syncable nexus folder. Per-nexus subdir keyed by ULID survives nexus rename/move; marked `isExcludedFromBackupKey` so iCloud Backup skips the regeneratable index. Per Apple Foundation + GRDB.swift recommendation; SQLite official guidance against placing DBs on network filesystems.
- **App-level state.json** at `~//Library//Application Support//com.nathantaichman.Pommora//state.json` holds machine-specific state (security-scoped bookmark of the last-opened nexus; future recent-nexuses, last-window-frame). No UserDefaults dependency.
- **Three Codable files, three concerns:** identity (`<nexus>/.nexus/nexus.json`, vault-portable, ULID-based), app state (`App Support/.../state.json`, machine-specific, holds bookmarks), nexus user state (`<nexus>/.nexus/state.json`, vault-portable, future v0.2+). The boundary is enforced by *where the file physically lives*, not by code.
- **Nexus-local trash: `.trash//`** at the nexus root (sibling of `.nexus//`). Deleted entities move here, preserving original relative path. Restoration is a straight file move back. Auto-purge / age-based clearing is post-v1; v1 ships with manual clear only.
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
- **SwiftUI editor options.** Option 1 (native): NSTextView via `NSViewRepresentable` + `swift-markdown` (Apple's official AST) + TextKit 2 — text storage IS the Markdown source, styling layered as attributes, marker hiding/reveal selection-driven. Clearly is the fork-able baseline reference. Option 2 (likely direction): WKWebView hosting Tiptap, Milkdown, BlockNote, or MarkdownEditor. [MarkEdit](https://github.com/MarkEdit-app/MarkEdit) is the public production reference for the architecture; [Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor) is a Swift Package wrapping CodeMirror 6 in WKWebView with Obsidian-style syntax hiding, GFM tables, and SF fonts built in (MIT; personal project, single contributor — fork rather than depend). Pommora-specific extensions to add: `:::callout`, `:::columns`, wikilinks (addable as CM6 extensions). The `file://` ES-module block in WKWebView is resolved by a `WKURLSchemeHandler` registered for a custom scheme (Apple-documented pattern); the cross-origin caveat doesn't bite when the editor bundle ships inside the `.app`.

##### Sidebar + Shell
- **Three top-level collapsible headings, default-collapsed, user-reorderable**: Spaces (leaf labels), Saved (non-operational placeholder in v1 — pinning is post-v1), Collections (kind-agnostic; each Collection is a folder-style disclosure).
- **Sidebar selection language locked**: custom `SelectableRow` view with tap-driven `@State var selection: String?` (not `List(selection:)`). `Color.gray.opacity(0.11)` rounded fill via `.listRowBackground`, accent foreground on selected icon + text, `+0.11` brightness boost on the foreground via `.brightness(_:)` to compensate for the fill subtly dimming the accent, `.symbolRenderingMode(.monochrome)` so foregroundStyle applies to symbols. Required because `.tint(_:)` doesn't recolor sidebar List selection on macOS Tahoe — the underlying NSTableView ignores SwiftUI's tint for `.sourceList` highlight. The custom approach is also what lets us combine gray fill *and* accent foreground; the system's default keeps them reciprocal. Trade-off: fill is fixed, doesn't desaturate on window unfocus like Finder/Mail (`NSVisualEffectView` + `.sourceList`). Detail → `// Features//Sidebar.md`.
- **No Loose sidebar group.** Loose entities reach via search, wikilinks, or pinning.
- **No raw filesystem view in v1.**
- **"Collapsed-by-default disclosure"** is the general UI pattern for any hierarchical or grouped content.
- **Three-pane shell** (240 sidebar / flex main / 280 inspector, hidden by default in v0.0): two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)` at the split-view level. Two-column chosen over three-column because the third column is designed for drill-down, not for a contextual side panel. System sidebar toggle (NSSplitView animation, Mail/Notes/Finder pattern); inspector toggle inside the `.inspector { … }` closure so it anchors to the inspector's toolbar segment, wrapped in `withAnimation(.smooth(duration: 0.30))`. Widths persist across launches. Property-panel content lands v0.6; default-shown decision revisited then.
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
- **SF Symbols on Swift** via `Image(systemName:)` — no indirection layer. (Material Symbols + role-indirection via `.nexus//symbols.json` is the React-side approach, preserved at `// ReactInfo//Symbols-guide.md`.)
- **In-app customization** (Framework v0.12) covers two values: accent color and font size. SwiftUI handles dark mode, semantic colors, Materials, and Dynamic Type natively — no additional override surface needed. Spacing / radius / shadow stay on baseline.
- **Disclosure pattern + DisclosureLine.** Pommora has multiple disclosure types (tree / folder, heading, toggle block, sidebar section header), all built on a single `Disclosure` primitive with an `indent line` variant. `true` for tree / folder disclosures — renders a `DisclosureLine` hairline guide tracing depth (Obsidian / VSCode pattern). `false` for heading disclosures and toggle blocks — no line. DisclosureLine is a sub-element of Disclosure, never placed independently.

#### Features Implemented

**v0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`. Sidebar (240 default, drag-resizable) + main pane (`EmptyPane` — `windowBackgroundColor` fill) + pop-out inspector (280 default, hidden by default). Inspector toggle: `sidebar.trailing` SF Symbol at `.primaryAction` inside the `.inspector { … }` closure, wrapped in `withAnimation(.smooth(duration: 0.30))`. Sidebar collapse via system `≡` (`NSSplitView` native animation). View menu's "Show Inspector" via `InspectorCommands()`. Window 1440×810 default, 960×560 min. Title suppressed via `.windowToolbarStyle(.unified(showsTitle: false))`. `NSSearchField` via `NSViewRepresentable`, anchored to `.safeAreaInset(.top, spacing: 8)` — preserved into v0.1a. The placeholder sidebar Sections shipped in v0.0 were replaced by real folder content in v0.1a.

**v0.1a — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, hidden `.nexus/` folder init flow, and a sidebar that mirrors a user-picked nexus folder.

- **Sandbox** enabled via `ENABLE_APP_SANDBOX = YES` + `ENABLE_USER_SELECTED_FILES = readwrite` (Xcode 15+ build settings auto-generate the entitlements plist; no separate `.entitlements` file). Verified via `codesign -d --entitlements -`.
- **Code structure:** single app target, `Nexus/` and `Sidebar/` subfolders auto-included by Xcode 16's `PBXFileSystemSynchronizedRootGroup`. Files: [`Nexus`](Pommora/Pommora/Nexus/Nexus.swift), [`NexusManager`](Pommora/Pommora/Nexus/NexusManager.swift) (@Observable @MainActor), [`NexusBookmark`](Pommora/Pommora/Nexus/NexusBookmark.swift) (security-scoped create/resolve/refresh), [`NexusStore`](Pommora/Pommora/Nexus/NexusStore.swift) (App Support paths), [`NexusIdentity`](Pommora/Pommora/Nexus/NexusIdentity.swift) (Codable `nexus.json`), [`AppState`](Pommora/Pommora/Nexus/AppState.swift) (Codable app-level `state.json`), [`ULID`](Pommora/Pommora/Nexus/ULID.swift) (inline spec-compliant generator, no third-party dependency), [`FolderTree`](Pommora/Pommora/Nexus/FolderTree.swift) (filtered enumeration), plus [`SidebarNode`](Pommora/Pommora/Sidebar/SidebarNode.swift), [`SidebarRow`](Pommora/Pommora/Sidebar/SidebarRow.swift), [`SidebarView`](Pommora/Pommora/Sidebar/SidebarView.swift) (always-rendered `List` with recursive `OutlineGroup`).
- **Init flow:** existing `.nexus/` → load `nexus.json`, skip init. Empty folder → silent init. Non-empty folder → confirm dialog ("Initialize as Pommora Nexus?"). `NSOpenPanel` defaults to `~/PommoraNexus/` if it exists, else `~/`.
- **State separation:** machine-specific bookmark in `~/Library/Application Support/com.nathantaichman.Pommora/state.json`; vault-portable identity in `<nexus>/.nexus/nexus.json`; nexus-portable user state in `<nexus>/.nexus/state.json` (deferred to v0.2+).
- **Per-nexus DB path** reserved at `App Support/.../nexuses/<nexus-id>/nexus.db`; marked `isExcludedFromBackupKey = true`. Database file itself created by GRDB in v0.2.
- **Menu commands:** File → Open Nexus… (⌘O) for switching; Debug → Reset Nexus Bookmark (DEBUG-only) for dev iteration.
- **Tests:** 25 unit tests across `ULIDTests`, `AppStateTests`, `NexusIdentityTests`, `NexusStoreTests`, `FolderTreeTests`. All pass.
- **Stylistic UI copy intentionally absent** in v0.1a per direction — no welcome screens, no error alerts, no empty-state descriptions, no NSOpenPanel customizations beyond defaults. Design pass adds these.

Design + 4 implementation Findings preserved at [.claude/Planning/v0.1-nexus-foundation-design.md](.claude/Planning/v0.1-nexus-foundation-design.md).

**Post-v0.1a sidebar visual scaffolding pass.** Sidebar UI swapped from FolderTree-driven to hardcoded placeholder Sections (3 loose Items + Spaces section × 3 entries + Collections section with 3 collection-folders × 3 placeholders each) to iterate on selection language without real-data noise. New private `SelectableRow` view consolidates icon + text + tap selection + selection chrome. `FolderTree` / `SidebarNode` / `SidebarRow` remain in the target but dormant — re-wire when de-scaffolding. `EmptyPane` removed from `ContentView`; detail closure is bare `Color.clear`. Inspector toggle stays in `.inspector { ... }.toolbar { }` per the v0.0 UIX-Guide direction (the toolbar-move experiment from commit 807057d was reverted in-session). Pommora-specific selection language captured in the Sidebar+Shell decisions above and documented at `// Features//Sidebar.md`.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 1 (2026-05-16).** Tasks 1-44 of 65 from `// Planning//Paradigm-Scaffolding-Tasks.md` shipped on a feature branch, plus 4 cleanup commits — 48 total. Data layer is feature-complete for v0.2: every entity in the locked paradigm (Space / Topic / Sub-topic / Vault / Collection / Item / Page / AgendaItem / AgendaSchema / Recurrence / Homepage / TierConfig / SavedConfig) has Codable, validator, and `@MainActor @Observable` manager. Swift 6 strict concurrency + ExistentialAny upcoming feature both enabled (flipped Task 1). Yams 5.4.0 added via SPM (Task 2). All custom Codable signatures use `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)` and all manager `pendingError` fields use `(any Error)?` per cleanup sweeps. UI tier (sidebar replacement + sheets + detail pane + Item Window + ContentView wiring) is Tasks 45-65, deferred to session 2.

Paradigm-solidifying decisions confirmed during session 1 (registry at `// Guidelines//Paradigm-Decisions.md`):
- **`PropertyValue.relation` encodes as tagged JSON object `{"$rel": "<ULID>"}`** — not bare string. Makes relation edges legible to external agents + graph-view indexer without consulting Vault schema; satisfies load-bearing constraint #3.
- **Collections persist a minimal `_collection.json` sidecar** with `{id, vault_id, modified_at}` — Collection is now Codable (no longer pure folder); parent-Vault relation is explicit on-disk property. Supersedes the original spec's "no metadata file" design.
- **SF Symbol picker = `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's `IconPickerSheet`** — wrapper isolates third-party API; swapping libraries is a single-file rewrite.

A new operating protocol installed in `// Guidelines//Paradigm-Decisions.md`: future paradigm-solidifying choices (on-disk schemas, wire encodings, defaults that lock once data exists, file-layout choices, cross-entity contracts, error semantics, identifier conventions) MUST surface via confirmation BEFORE the code lands, not after-the-fact.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 2 (2026-05-17).** Tasks 45-65 shipped (21 commits this session, **69 total ahead of `main`**). UI tier complete end-to-end: SidebarSheet + SidebarConfirmation enums; SidebarView four-section layout (Saved / Spaces / Topics / Vaults) with SelectionTag; 5 row views (SpaceRow / TopicRow / SubtopicRow / VaultRow / CollectionRow + ParentSpaceTags helper); 10 sheets (NewSpace / NewTopic / NewSubtopic / NewVault / NewCollection / NewPage / NewItem / EditTopicParents / SpaceColorPicker + ColorPickerSheet / IconPickerSheet wrapping SymbolPicker); detail-pane tier (ContentItem + DetailRow + ContextDetailPlaceholder / VaultDetailView + CollectionDetailView with native SwiftUI `Table(_:children:)` / SidebarDetailView dispatcher); ItemWindow tier (MultiSelectChips + FlowLayout / PropertyEditorRow / ItemWindow popover with title + icon + description + property editors + tier1/2/3 read-only); ContentView full 8-manager wiring with real `contextProvider` closures resolved via in-body snapshot-capture trick. **177 unit tests, 0 failures, 0 source warnings, sandbox entitlements verified.** SymbolPicker 1.6.2 added via SPM (pbxproj surgery).

Code review pass (CodeRabbit + reviewer synthesis) at session end — 45 findings, ~10 real. Four-commit cleanup-and-UX-restructure plan staged in `Handoff.md`: (1) dead-code purge (`SheetStubView` + v0.1a FolderTree trio), (2) sidebar UX restructure per Nathan's right-click-context-menu direction + row commit() draft-loss fix, (3) Pages-under-Vaults/Collections sidebar disclosure, (4) atomicity + error-surfacing pattern (6 rename sites, pendingError-on-CRUD, AgendaManager orphan fix, PageFrontmatter required-id, 8 validators trim consistency, ContentView initial-construction race, AtomicYAMLMarkdown force-unwrap, VaultDetailView modifiedAt, ItemWindow applyDraft helper).

Paradigm-solidifying decisions added during session 2 (appended to `// Guidelines//Paradigm-Decisions.md`):
- **Stub-and-progressively-replace execution strategy.** For branch-spanning plans where row/sheet/detail tasks have forward-dependencies on each other, write each task with throwaway in-file stubs for not-yet-shipped types; later tasks replace the stubs in-place. Every commit ships green standalone, every commit is independently verifiable. Supersedes the spec's batch-commit-at-end approach (which produces uncommitted 12-task blobs where any single break contaminates the batch).
- **Sidebar UX direction.** All "+ New" buttons removed from the sidebar; replaced by **right-click context menus, location-scoped to the cursor** (right-clicking on a Vault row → "New Collection / New Page" both bind to THAT Vault; right-clicking on a Collection row → "New Page" binds to THAT Collection; etc.). Saved Section keeps its wrapper for future pinned items but loses the literal "Saved" header text — renders as a heading-less group at the top. **Pages appear in the sidebar** under their parent Vault (root) or Collection with the `doc.text` icon (click no-op until v0.3 editor lands). **Items, Agenda items, Events do NOT appear in the sidebar** — they live exclusively in the detail-pane Tables. Hover-icon "+" affordance on section headings explicitly skipped; quick-capture (Cmd+Shift+N / menu-bar) will absorb most CRUD entry traffic before v1.

The React+Electron-locked v0.0 spec is preserved at `// ReactInfo// v0.0.md` for contingency.

**Paradigm scaffolding — branch `paradigm-scaffolding`, session 3 (2026-05-17/18) — cleanup + UX polish + Commit 4.** All 4 planned cleanup commits shipped + a longer-than-planned sidebar polish iteration sequence. **13 cleanup commits this session, branch landed at 82 commits ahead of `main`.** 182/182 unit tests pass, 0 source warnings, sandbox entitlements verified, app launches cleanly under test harness.

Commits shipped (in order):

1. **`1343e50`** — Dead code purge: `SheetStubView` + v0.1a folder-tree trio (`FolderTree` / `SidebarNode` / `SidebarRow` / `FolderTreeTests`).
2. **`c8dbac6`** — Sidebar UX restructure: right-click context menus replace 5 "+ New" buttons; preserve rename drafts on error; new `SidebarSheet.newPageInVault(vault:)` case for vault-root Page creation; section-area `Color.clear` hit-test rows (later replaced).
3. **`02da8ff`** — Pages-in-Vault-root + show Pages in sidebar under Vaults/Collections: `ContentManager` gained `pagesByVaultRoot` / `itemsByVaultRoot` storage + `pages(in vault:)` / `items(in vault:)` accessors + 4 `(inVaultRoot vault:)` CRUD overloads; new `PageRow` (non-selectable leaf with `doc.text` icon); new `PageParent` enum.
4. **`1a84a5f`** — Sidebar regressions fix: restore full-row click via `Spacer(minLength: 0)` + `.frame(maxWidth: .infinity)` + `.listRowInsets`; restore section disclosure chevrons via `Section(isExpanded:) { } header: { SectionHeader(...) }`; replace empty `Color.clear` hit-test rows with custom `SectionHeader` containing `+` button + context menu.
5. **`64e6cd8`** — Sidebar polish: hover-only `+` button via `.opacity(hovered ? 1 : 0).animation(.easeInOut(duration: 0.12))`; selection chrome on DisclosureGroup-wrapped rows via in-content `.background` (later reverted); `SelectableRow` becomes generic `SelectableRow<Trailing: View>` with trailing slot for TopicRow's `ParentSpaceTags`.
6. **`9971a35`** — Sidebar fixes batch: SF Symbol picker via new `IconPickerField` (wraps `SymbolPicker` directly, bypassing `IconPickerSheet`'s manager-routing) wired into all 4 Create sheets; `SpaceColor.accent` case added; renamingRow in all 6 row files keeps icon visible (only text becomes editable); `.onChange(of: renameFocused)` with `isCommitting` guard auto-cancels rename on click-off without blocking Enter-commit.
7. **`2d707a0`** — Atomicity rollback + pendingError-based error surfacing + 8 small fixes + 4 Commit-3 reviewer carryovers: new `RenameAtomicityError` type; rollback pattern applied at 8 rename sites (7 from spec + the new `renameItem(inVaultRoot:)`); all 8 managers wrap every CRUD method in `do/catch` setting `pendingError`; new `SidebarToast` view observes 5 managers' `pendingError` properties and renders a dismissable banner above the List; replaced silent `try?` calls in SidebarView delete handlers + IconPickerSheet + ColorPickerSheet + PageRow delete; `PageFrontmatter.id` required-decode; `AgendaManager.updateItem` refuses title changes (extracted `renameAgendaItem`); `VaultDetailView` uses `coll.modifiedAt`; `ContentView.onChange(initial: true)`; 8 validators trim consistency; `AtomicYAMLMarkdown` UTF-8 throws; `ItemWindow.applyDraft` helper; `ContentManager` split into `ContentManager.swift` + `ContentManager+CRUD.swift` extension (storage + load in main; 13 CRUD methods in extension); `existingInCollection:` → `existingSiblings:` validator parameter rename; `@discardableResult` symmetry on Collection-scoped create methods; PageRow's unused `confirmingDelete` binding dropped; +5 new tests (`RenameAtomicityTests` + AgendaManager rename tests).
8. **`3657cad`** — Launch crash fix: `ContentView`'s sidebar branch was missing `.environment(contentMgr)` injection. Commit 3 added `@Environment(ContentManager.self)` reads to VaultRow/CollectionRow/PageRow but the parent never injected — Commit 2b's section restructuring shifted diff traversal timing enough to surface it as `EXC_BREAKPOINT in EnvironmentValues.subscript.getter` via `OutlineListCoordinator.recursivelyDiffRows`. Bisected to the launch crash via parallel test runs at 3 SHAs. Fix is one line.
9. **`838b063`** — Accent swatch polish: rainbow swatch via `AngularGradient` for `SpaceColor.accent` (matching macOS Finder Multicolor tag convention) + 5x2 fixed-column grid for the now-10 color options.
10. **`8fe91d7`** — Detail-pane fixes: `SidebarDetailView` gained `.sheet(item: $presentedSheet)` routing so detail-pane "+ New Collection / New Page / New Item" buttons actually present sheets (Nathan's ContentView edit had passed the binding but no `.sheet` was wired); `VaultDetailView` rows now include vault-root Pages + Items as top-level rows (was only showing Collections); `VaultDetailView.task` loads vault-root content too; `SavedSection` dropped `header: { EmptyView() }` (EmptyView header was still reserving height, creating visible top gap under search bar).
11. **`ae8280d`** — Restored `.listRowBackground` for sidebar selection chrome: removed `SelectableRow`'s in-content `.background`; added new `SelectionChrome` view rendering `RoundedRectangle.fill(...).padding(EdgeInsets(top: 2, leading: 11, bottom: 2, trailing: 11))`; each row file applies `.listRowBackground(SelectionChrome(isSelected: ...))` at its body root. Initially attempted asymmetric `.disclosure` style (leading 0 to cover chevron) but reverted to symmetric `.flat` (both 11pt).
12. **`576d933`** — Sidebar geometry consistency: HStack spacing 10 → 8 in SelectableRow + all 6 renamingRow blocks; Image `.font(.system(size: 14, weight: .regular))` forces consistent glyph render size; `.frame(width: 16, height: 16, alignment: .center)` centers glyphs in fixed box so text always starts at the same X regardless of glyph natural width; renamingRow geometry mirrors SelectableRow exactly so rename doesn't visually jump.
13. **`8cc492b`** — Symmetric chrome for disclosure rows: TopicRow / VaultRow / CollectionRow `SelectionChrome` switched from `.disclosure` (leading 0, trailing 11) to default `.flat` (11pt symmetric) so both corners have matching rounded radius. Trade-off documented: chevron may sit just outside chrome's left edge in some sidebar widths; revisit via hand-rolled chevron (Sidebar.md inline-chevron experiment) if visually wrong.
14. **`0bc4c8d`** — Selection polish: Nathan-tweaked chrome opacity (0.11 → 0.10) and text brightness (0.12 → 0.10) for slightly subtler selection treatment.

Plus a parallel SpaceColorPicker tweak (made `color` binding optional + tap-toggle-deselect) shipped via Nathan's separate session — captured in the working-tree handoff state.

**Paradigm-solidifying decisions added during session 3** (appended to `// Guidelines//Paradigm-Decisions.md`):

- **Sidebar selection chrome via `.listRowBackground` at row file level.** Locked after the long polish iteration. `Color.gray.opacity(0.10)` fill, 6pt continuous corner radius, symmetric 11pt horizontal + 2pt vertical inset, text brightness 0.10, icon no brightness, HStack content spacing 8pt, icon column 16x16 centered at 14pt glyph size, row content padding 4pt leading / 0 trailing / 6pt vertical. Chrome applied at each row file's body root (DisclosureGroup itself for wrapped rows; row body for flat rows + Saved items per iteration) so it covers the chevron gutter. SelectableRow keeps no chrome — purely content. `SectionHeader` (private struct in SidebarView) renders a secondary-styled title + hover-only `+` button via `.opacity(hovered ? 1 : 0).allowsHitTesting(hovered).animation(.easeInOut(duration: 0.12))` (opacity not conditional rendering to avoid layout shift); right-click context menu surfaces "New X" regardless of hover.

- **Pages editor stack: Tiptap (ProseMirror) in WKWebView, MarkEdit-pattern native shell, vanilla TypeScript bundle.** Closes the long-running Option 1 (native NSTextView) vs Option 2 (WKWebView + JS editor) question. WYSIWYG editing locked over Live Preview at Nathan's direction — typing `**bold**` becomes **bold** instantly, no markers visible. Markdown round-trip via `@tiptap/markdown` (per-node serializers; near-perfect not byte-perfect). `:::callout` and `:::columns` / `@Columns` directives via custom Tiptap `Node.create`. Roadmap reordered: Pages moves from v0.6/0.7/0.8 to v0.3 (internal phases a/b/c); Tabs become v0.4; Properties v0.5; infrastructure cycles shift to v0.6+. Pages open in detail pane (single Page at a time) in v0.3; tabs ship at v0.4. Standalone-window-via-context-menu / `⌥⌘O` path works in v0.3a via `WindowGroup(for: PageRef.self)`. Full implementation spec at `// Planning//Page-Editor-Plan.md`.

**Pre-merge gates verified at session end:**
- `xcodebuild build` → BUILD SUCCEEDED, 0 source warnings ✅
- `xcodebuild test -only-testing:PommoraTests` → **182/182 pass**, 0 failures, test runner bootstraps cleanly ✅
- Sandbox entitlements (`app-sandbox` + `files.user-selected.read-write`) present in built `.app` ✅
- Visual gold-path: Nathan signed off on full sidebar + detail pane state ✅
- CodeRabbit final review: 3 major findings (all non-blocking test-coverage improvements; defer to v0.3 prep or small post-merge tightening commit)

**Merge strategy locked: full history** (non-fast-forward merge commit preserving all 82 commits). Bisect-value-preserving — already paid off twice this session (locating the launch crash, finding SidebarToast issue).

**Known UX gap flagged at session end (2026-05-17):** Item creation affordance is buried — only `CollectionDetailView`'s footer offers "+ New Item"; not in VaultDetailView footer, not in any sidebar context menu. Fix is small (~3 button additions across detail views + row context menus); deferred to pre-v0.3 polish or rolled into v0.3a prep. Sidebar.md table to be updated to reflect the new affordance once added.

**Nathan-sketched "New Item" window design (v0.5 design intent)** captured at `// Features//Items.md` "Item window — design evolution" section. Modal window with 2-column layout (description body LEFT, property dropdowns stacked RIGHT), Delete (red, edit-only) + Save (blue primary) footer, title bar with icon-picker + view-toggle affordances top-right. Supersedes current v0.2 Spartan ItemWindow popover; lands with v0.5 Properties.

**Parallel-session caveat established as project quirk #15:** Nathan may have a separate session running small UI tweaks while another session is working. Pommora/* working tree is no longer guaranteed clean between subagent dispatches; small Nathan-hand-tweaks may appear (e.g., the `0.12 → 0.10` opacity tweak that arrived mid-session). Subagents should never revert unattributed working-tree changes.

---

#### Session 4 — 2026-05-17 end (audit + semver + v0.2.1 / v0.2.2 / v0.2.3 to main)

Long session covering Framework audit + semver conversion + Pages/Tabs reorder + three patches landed on main.

**v0.2.0 merged to main (e3daedb):** the paradigm-scaffolding 83-commit branch merged via `git merge --no-ff` preserving full history. Pushed to `origin/main`.

**Framework audit + reorders (locked end-of-session):**

1. **Pages + Tabs ship as v0.2.x patches, NOT v0.3.0/v0.4.0 minors.** Restructured: v0.2.7 = Pages editor (prose + standard Markdown), v0.2.8 = Tabs, v0.2.9 = directives + heading fold + slash menu, v0.2.10 = wikilinks + rename cascade. Order between v0.2.7 and v0.2.8 is interchangeable. v0.3.0 becomes Properties — the next substantial capability after Pommora is writable + multi-instance.
2. **Editor library NOT solidified.** Tiptap was previously locked in `// Planning//Page-Editor-Plan.md`; demoted to "leading candidate" end-of-session. Final pick reopens at v0.2.7 implementation start. Architecture (WKWebView + 7-message bridge + MarkEdit pattern) stays stack-agnostic.
3. **Agenda UI ships hand-in-hand with EventKit at v0.6.0** — not split. Earlier in the session an Agenda-UI-at-v0.5-split was considered; reverted end-of-session.
4. **SQLite + Watcher at v0.4.0** (was v0.8.0); **Vault views at v0.5.0** (was v0.10.0); **v0.6.0 consolidates** EventKit + Agenda UI + accessibility + performance + onboarding + Settings + accent customization. v0.11/v0.12 dissolved.
5. **`.trash//` data layer at v0.2.5**, in-app Trash UI window at v0.4.0.
6. **Semver format locked:** `major.minor.patch`. Minor = completed feature; patch = touch-up or addition; major reserved for v1.0.0. Internal phases like `v0.3a/b/c` retired.

**Three patches shipped to main (in order):**

1. **`3bcf328` — v0.2.1: Parallel-session sidebar UX tweaks + page selection wiring.** 16 Swift files (Detail / Sidebar / Sheet polish from the parallel Claude session) including `case page(PageMeta)` selection wired + a `PageDetailView`-style placeholder in `SidebarDetailView` ("Page editor coming v0.6" — stale version string, fix in v0.2.6 spec catch-up).
2. **`2e140ed` — v0.2.2: CodeRabbit tightening.** `ItemWindow.swift` refetch-after-rename recovery (`await contentManager.loadAll(for: coll)` + `dismiss()` on still-missing-after-reload) + 2 `ContentManagerTests` filesystem assertions (`renameItem` verifies old URL gone + new URL exists; `deletes` verifies files gone from disk). Cherry-picked from the `v0.2.2-coderabbit` branch (snapshot ref `e462681`). Executed via subagent-driven-development skill: implementer + spec reviewer + quality reviewer.
3. **`56efd68` — v0.2.3: CI baseline.** `.github/workflows/ci.yml` running `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, triggered by push to ANY branch + PRs targeting `main`. Cherry-picked from `v0.2.3-ci` branch (snapshot ref `b746481`). First push will smoke-test runner availability; fallback is `macos-latest` + explicit Xcode 26 path.

**Combined build state verified end-of-session:** `xcodebuild build` BUILD SUCCEEDED, 0 source warnings; `xcodebuild test -only-testing:PommoraTests` 182/182 pass.

**Mid-session git incident:** while branching for v0.2.x patches, Claude stashed the .claude/* doc accumulation + Swift parallel-session edits before switching branches. Nathan saw docs revert to days-old state when his working view followed Claude to feature branches off main (which had old doc state). Recovered cleanly via `git stash pop`. **Lesson logged:** `.claude/*` IS included in commits going forward (corrected quirk #4 in CLAUDE.md). The prior "don't stage .claude/* unless explicitly asked" rule prevents unilateral doc bundling into Swift commits, but explicit doc commits are expected so branch switches preserve doc visibility.

**xcbeautify deferred from CI:** plan's v0.2.3 YAML included `| xcbeautify --renderer github-actions` pipes for GitHub-native error annotations on PR diffs. Shipped without it as a deliberate scope reduction — raw `xcodebuild` output is sufficient for the baseline. Plan file updated to match. Adding xcbeautify is a future small patch (would also need a `brew install xcbeautify` step).

**Item Window v0.5 redesign now targets v0.3.0:** the redesign was previously slotted alongside Properties at v0.5.0; with Properties moving to v0.3.0 in the reorder, the Item Window redesign comes along.

**Tomorrow's session opens with:** v0.2.4 swift-format baseline, then v0.2.5 `.trash//` data foundation, then v0.2.6 spec catch-up, then v0.2.7 Pages editor (with the editor-library decision reopened first). See `Handoff.md` "Tomorrow's plan."

---

#### Session 5 — 2026-05-18 (v0.2.4 → v0.2.6 shipped via subagent-driven-development)

Execution session: shipped four code patches + one end-of-day doc sweep, ending at v0.2.6 — Pommora now has CI + formatter + `.trash//` data layer + spec docs synced, ready for the editor-library decision and v0.2.7 Pages. All commits land on `main` directly per Nathan's session-local override ("execute; but let's keep it on this branch"); not pushed (Nathan reviews + pushes himself).

**Execution model:** `subagent-driven-development` skill for v0.2.4 and v0.2.5 (full implementer + spec-reviewer + code-quality-reviewer chain). Compressed review for v0.2.5.1 and v0.2.6 (already-reviewed Minor items + mechanical string/doc updates — full ceremony would have been overkill). Builder subagent for xcodebuild verification where reachable; piped-log fallback otherwise.

**Five patches shipped:**

1. **`60e2ef6` — v0.2.4: swift-format baseline.** `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `OrderedImports: true` / `NeverForceUnwrap: false` to honor `try!` use). One-time formatter pass over 97 Swift files (+593/-422; mechanical whitespace + import-ordering only, no semantic changes). CI `swift format lint --strict --recursive` step in `.github/workflows/ci.yml` after "Show toolchain" — fail-fast. Also fixed two pre-existing `OneCasePerLine` violations in `Recurrence.swift` (`Kind` and `Day` enums) since the formatter can't auto-fix that rule — the alternative (disabling the rule) was worse. Code quality reviewer flagged one cosmetic regression: `swift format` mangled ~12 single-line `do { try await … } catch { /* … */ }` patterns in `SidebarView.swift` + `IconPickerSheet.swift` into `} catch\n{ … }` shape (`respectsExistingLineBreaks: true` can't preserve single-line catch bodies that span the `{`). Recommended structural fix (extract `runDelete(_:)` helpers) when SidebarView is next touched — likely during v0.2.7 work; not config-driven.

2. **`9f56fbe` — v0.2.5: `.trash//` data foundation.** 5 new APIs: `NexusPaths.trashDir(in: nexus)` returns `<nexus>/.trash/`; `Filesystem.moveToTrash(_:in:)` (@discardableResult URL throws) preserves the deleted entity's relative path under nexus root, creates intermediate `.trash` dirs, resolves collisions via timestamp suffix; private `Filesystem.suffixedWithTimestamp(_:)` helper; `FilesystemError.sourceNotInNexus(source:, nexus:)` case (new `LocalizedError` enum — no pre-existing type to extend); file-private `String.removingPrefix(_:)` helper. Swapped 10 manager delete call-sites: SpaceManager.delete / TopicManager.deleteTopic + deleteSubtopic / VaultManager.deleteVault + deleteCollection / ContentManager+CRUD.deletePage×2 + deleteItem×2 / AgendaManager.deleteItem. All 10 managers already held a `nexus` reference — no threading required. Pre-existing `pendingError` flow preserved. New `Pommora/PommoraTests/AtomicIO/FilesystemTrashTests.swift` with 4 tests (movesFile / movesFolder / collisionAddsTimestampSuffix / rejectsExternalSource). Extended v0.2.2's `ContentManagerTests.deletes` + `VaultManagerTests.deleteVault`/`deleteCollection` assertions to ALSO check trash-side existence (the cross-patch coordination flagged in the plan). Tests: 182 → 186. PRD-aligned: `.trash//` lives inside the nexus (syncs with iCloud/Dropbox as user data, not regeneratable index), unlike `nexus.db` which lives in Application Support.

3. **`25de7c6` — v0.2.5.1: Trash cleanup.** Three Minor items from the v0.2.5 code quality reviewer: (a) `suffixedWithTimestamp` now appends a 4-char hex discriminator (UUID prefix) after the UTC `YYYYMMDD-HHMMSS` timestamp — guarantees uniqueness for the same-second collision edge case (`@MainActor` serialization makes this impossible today, but future batch-delete scenarios would benefit). Filenames become `Notes.20260518-093215-A3F2.md` — slightly noisier but always unique without loop ceremony. (b) `rejectsExternalSource` test tightened to pattern-match the specific `FilesystemError.sourceNotInNexus` case via the closure form `throws: { error in case ... = error }`, matching existing test convention in `AgendaManagerTests` / `SpaceManagerTests` / `AtomicYAMLMarkdownTests`. (c) UTC documentation folded into the suffix function's docstring (cross-timezone determinism rationale).

4. **`7b17d1d` — v0.2.6: Spec catch-up.** 5 Swift literal `Text(...)` version strings updated to align with the locked Framework reorder:
   - `ItemWindow.swift` `"Property-panel relation editor coming v0.5"` → `"Property panel coming v0.3.0"`
   - `PropertyEditorRow.swift` `"Relation editor coming v0.5"` → `"Relation editor coming v0.3.0"`
   - `ContextDetailPlaceholder.swift` `"Composed view coming v0.9"` → `"Composed view coming v0.7.0"` (+ matching doc comment synced)
   - `SidebarDetailView.swift` `"Saved view coming v0.5"` → `"Saved view coming v0.6.0"`
   - `SidebarDetailView.swift` `"Page editor coming v0.6"` → `"Page editor coming v0.2.7"`
   
   Doc passes: `// Features//Pages.md` softened from "Tiptap LOCKED" framing to "leading candidate; final pick reopens at v0.2.7 prep" with a structured candidate list (Tiptap / Milkdown / BlockNote / CodeMirror 6) and stack-agnostic architecture restated; cross-references Paradigm-Decision #7. `// Features//Sidebar.md` updated the right-click table's Page row entry to reference v0.2.7 and replaced the "discoverability deferred to quick-capture" section with a "hover-icon `+` complement + quick-capture" section acknowledging the hover-only `+` buttons that actually shipped in v0.2.0 — the spec doc was stale on what was already live.

5. **`<pending>` — docs-end-5-18: End-of-session doc sweep.** This `History.md` entry + `Handoff.md` rewrite (end-of-5-18 state replaces end-of-5-17 state) + `Framework.md` "Current Focus" update + v0.2.x "Shipped" section expanded to cover v0.2.4 → v0.2.6 + `CLAUDE.md` Active Version table updated with the 4 new SHAs + quirk #12 added (`swift format` invoked as subcommand). `PommoraPRD.md` and `Paradigm-Decisions.md` required no changes — paradigm-decision #7 (Tiptap demoted) already reflects current state; PRD is intentionally version-agnostic.

**Combined build state verified end-of-session:**
- `xcodebuild build` → BUILD SUCCEEDED, 0 source warnings ✅
- `xcodebuild test -only-testing:PommoraTests` → **186/186 pass**, 0 failures ✅
- `swift format lint --strict --recursive Pommora/Pommora Pommora/PommoraTests Pommora/PommoraUITests` → exit 0 ✅
- Sandbox entitlements present ✅
- Working tree clean post-doc-commit ✅

**No new paradigm-solidifying decisions this session.** Purely execution + spec hygiene. The 10-entry Paradigm-Decisions registry from end-of-5-17 remains current.

**Project quirk added (#12 in `CLAUDE.md`):** `swift format` is invoked as a subcommand (`swift format format`, `swift format lint`) via Xcode 26's bundled toolchain. The direct `swift-format` binary is not on `$PATH` on this machine. CI uses the same subcommand form. Locked at v0.2.4.

**SourceKit staleness re-confirmed (quirk #3):** SourceKit emitted false "Cannot find type X" diagnostics for same-module types and "No such module 'Testing'" after multiple Edit/Write tool runs throughout the session — `Nexus`, `Space`, `NexusPaths`, `Filesystem`, `NexusContext`, `Item`, `Vault`, `PropertyValue`, `ContentManager`, etc. xcodebuild + `xcodebuild test` consistently passed. This is the documented IDE-staleness pattern; squiggles clear after re-indexing. No action needed.

**Next session opens with:** confirm push of v0.2.4 → v0.2.6 to origin (first CI smoke-test on `runs-on: macos-26`; fall back to `macos-latest` + Xcode 26 path if needed) → reopen editor library decision via `superpowers:brainstorming` → **v0.2.7 Pages editor** per `// Planning//Page-Editor-Plan.md`. Use `subagent-driven-development` skill. See `Handoff.md` verbatim resume prompt.

---

#### Session 6 — 2026-05-18 (continued — editor library re-evaluation, no code)

Research session after the v0.2.4 → v0.2.6 patch sequence shipped. Nathan reopened the editor library decision and pushed for an honest evaluation of native AppKit / TextKit 2 against the prior Tiptap-leaning framing. **No code committed**; outcome is a rewritten `// Planning//Page-Editor-Plan.md` (objective options inventory) + a chat-only recommendation.

**Skills used:** `superpowers:brainstorming` (framing), `swiftui-expert-skill` (TextKit 2 / `AttributedString` / macOS-views references), `context7` (`/swiftlang/swift-markdown` API + source-range tracking + GFM tables + visitor patterns). Background Explore agent covered WWDC25 Session 280, Bear 2, Drafts, MarkEdit, the user-shared Reddit thread, plus open-source precedents.

**Linchpin clarifier:** Nathan confirmed Live Preview (Obsidian/Bear pattern — markers fade by cursor proximity) AND pure WYSIWYG are both acceptable — "as long as Markdown syntax isn't always visible and the page looks like a page rather than a file." Removes the constraint that drove Tiptap-over-CodeMirror earlier in the branch.

**Deep-dive on `Pallepadehat/MarkdownEditor`** (cloned + read full source). 3,010 LOC total (~1,300 Swift, ~1,700 TypeScript). MIT, v1.0.1 (Feb 11 2026), 26★, 6 forks. macOS 14+, Swift 5.9+, Xcode 15+. WKWebView + CodeMirror 6 + `@codemirror/lang-markdown` + `@lezer/markdown` GFM. Pre-built `editor.html` ships as SPM Resource via `vite-plugin-singlefile` — no JS toolchain needed in consumer build. Public Swift API: `EditorWebView(text: Binding<String>, configuration: EditorConfiguration, onReady:)` + `EditorBridge` (`@MainActor`) with ~30 methods + `EditorBridgeDelegate` (`@MainActor` protocol) + `EditorConfiguration` (Codable/Equatable/Sendable, includes `hideSyntax` toggle for Obsidian-style Live Preview). Ships in the bundle: `syntax-hiding.ts` (185 LOC, marker fading on inactive lines), `command-palette/` (~500 LOC, `/`-triggered slash menu with sections Formatting/Headings/Lists/Blocks/Media/Diagrams/Math/Insert), `math.ts` (386 LOC, KaTeX), `mermaid.ts` (281 LOC), `images.ts` (208 LOC), `calc.ts` (97 LOC, smart calculator), Xcode-themed light/dark, `@codemirror/search` (Cmd-F panel). Doesn't ship: wikilinks, `:::callout`, `@Columns`, visual table rendering, heading fold (CodeMirror's built-in `foldNodeProp` is available but not enabled), bubble menu on selection, Pommora brand theme. Widget extension pattern is consistent: walk syntax tree via `syntaxTree(state).iterate()` → add `Decoration.mark()`/`Decoration.replace({widget: WidgetType})` to `RangeSetBuilder` → provide as `StateField` via `EditorView.decorations.from(field)` → wrap in `Extension` via `Compartment`. Each Pommora widget would be a new TS file at `CoreEditor/src/widgets/<name>.ts` following the pattern of the four shipped widgets.

**Reference for native path:** [`nodes-app/swift-markdown-engine`](https://github.com/nodes-app/swift-markdown-engine) (Apache 2.0, 455★, v0.4.0 May 2026, pre-1.0). NSTextView + TextKit 2 + SwiftUI bridge. Built by Nodes (Germany) and shipping in their commercial macOS app. Ships: live styling, wiki-style linking with `[[Name|<id>]]` storage/display round-trip (matches Pommora's wikilink spec), LaTeX blocks + inline, code blocks with embedder-supplied syntax highlighting, task checkboxes, Writing Tools integration (macOS 15.1+), spelling & grammar with code/LaTeX/wiki-link suppression, bottom overscroll, drag-select autoscroll. Doesn't ship: tables, multi-column layout, block-level callouts.

**Known native framework gaps surfaced:**
- TextKit 2 has no native `NSTextTable` support; if attributed string contains an actual `NSTextTable` instance, TextKit 2 falls back to TextKit 1 which disables `NSTextAttachmentViewProvider`. Apple Developer Forums thread 776824 documents this. Workaround: render tables via `NSTextAttachment` / `NSTextAttachmentViewProvider` (custom view), never via `NSTextTable` — the fallback isn't triggered by "the document contains table syntax," only by NSTextTable instances in the storage.
- No multi-column inline layout API in TextKit 2. `@Columns` requires custom rendering. STTextView discussions note custom `NSTextContentManager` is "challenging."
- `swift-markdown` lacks first-class custom-directive parsing. Post-parse traversal handles `:::callout` / `@Columns`.
- `swift-markdown` DOES provide source-range tracking (`element.range.lowerBound.line/column/source`) — critical for attribute decoration efficiency.
- MarkEdit's creators (production macOS Markdown editor, 3.3k★) explicitly chose CodeMirror over TextKit 2, citing documentation/community/feature complexity. Direct evidence that production-quality native Markdown editing is non-trivial.

**Three honest options now in `// Planning//Page-Editor-Plan.md`** (rewrote from 939 lines to 169; pure objective inventory, no recommendation in the doc):
1. **Native Swift** — `swift-markdown` + TextKit 2 + `NSTextView`. Optionally wrap `nodes-app/swift-markdown-engine`.
2. **JS editor library + macOS shell we build** — Tiptap (WYSIWYG, ~250KB, MIT) / Milkdown (better Markdown round-trip, ~400KB, MIT) / BlockNote (React + GPL/commercial multi-column) inside a WKWebView shell. Shell itself is ~1–2 Claude sessions of standard WebKit work. No Swift Package wrapper exists for these libraries as of May 2026.
3. **Fork `Pallepadehat/MarkdownEditor`** — CodeMirror 6 + WKWebView. We fork to add Pommora widgets to it (wikilinks, `:::callout`, `@Columns`, tables, bubble menu, brand theme). The fork is ours after fork; upstream is reference only.

**Swap costs documented in Claude sessions** (per StudioMD's new "effort estimates use Claude-time" rule — added this session). All transitions are 1–2 sessions for the shell/wrapper swap + 1 session per Pommora widget needing porting. `.md` file format is the firewall — user data portable across all transitions. Reversibility roughly symmetric.

**Chat-only recommendation (not in the doc):** Try Option 3 first. Three reasons: cheapest experiment (v0.2.7 prose ships in 1 session); surfaces the WKWebView-feel question fast; reversibility is high (Pallepadehat dep is a clean SPM cut). Concrete session-1 deliverable spec captured in `Handoff.md`'s "Next session's plan" section so post-compact implementation can start immediately on Nathan's pick.

**StudioMD updated** with new "Effort estimates use Claude-time" rule (Nexus source → Studio deploy per the Mirror rule). Mandates Claude sessions/hours framing — never weeks/days/months — since Claude is the implementer and calendar time isn't the cost unit. Sibling bullet to "Frame tradeoffs in plain terms" under "Working with Nathan."

**Nexus mirrors** of `Page-Editor-Plan.md` + (this end-of-session) Handoff/Framework/CLAUDE/History/Pages — to `//The Nexus//Topics//Pommora//` for mobile viewing.

**Paradigm-Decisions registry impact:** Decision #7 (Tiptap leading direction) is superseded by the three-option inventory. Sync at v0.2.7 implementation start once Nathan's pick lands — no point updating it speculatively now.

**Next session opens with:** push v0.2.4 → v0.2.6 to origin if Nathan signals → confirm Nathan's pick among the three editor options (recommendation Option 3) → implement v0.2.7 immediately. Opening commit (common to all options): `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` mirroring `updateItem`. Session-1 deliverable spec for Option 3 lives in `Handoff.md`.

---

#### Session 7 — 2026-05-18 (continued — Phase A-G of v0.2.7 + Milkdown decision)

Long execution session. Nathan picked Option 3 (fork Pallepadehat); shipped Phase A through Phase G of v0.2.7 across 11 commits on `main` + 3 commits on the fork at `Natertot215/PageEditorMD`. End-of-session smoke test failed Nathan's visual baseline despite extensive Apple typography overhaul; decision to swap to Milkdown + Crepe (later superseded by Session 8). Doc commit at `152609c`; no swap code.

**Code shipped (11 commits, `1df93a6` → `1989fac`):**

- **Phase A** — SPM dep on Pallepadehat fork
- **Phase B** — Domain layer: `PageRef` (Codable+Hashable ID-based identifier for `WindowGroup(for:)` scene values), `ContentManager.updatePage(_:body:in:vault:)` + vault-root variant (body-only writes, frontmatter preserved verbatim via `PageFile(frontmatter:body:title:).save(to:)` → `AtomicYAMLMarkdown.write` → atomic temp+rename), `PageEditorViewModel` (300ms debounce, `flushNow`/`close`/`explicitSave`/`clearError`, `PageSaver` protocol + `ContentManagerPageSaver`), 10 new tests + Nathan's icon migration bundled
- **Phase C1-C5.2** — Inspector wiring + sandbox entitlements (4 keys including `network.client` for WKWebView), `AppGlobals` (NSHashTable<PageEditorViewModel> registry + lifecycle observers for willResignActive + willTerminate), `AppState.pageInspectorOpen` per-Page persistence (v1→v2 backward-compat decoder), `FrontmatterInspector` (read-only Form), `PageEditorView` + `PageEditorHost` (.task(id:) page-switch flush + .id() re-keying), editable title `TextField` (28pt bold, plain style, commit → `ContentManager.renamePage`), inspector at NavigationSplitView level with toolbar `ToolbarItem(placement: .primaryAction)` INSIDE `.inspector(...)` content closure (fixed left-side placement bug), sidebar page-switching regression fix (`@State var viewModel` → `@Bindable` + `.id(vm.page.id)`)
- **Phase G** — Fork polish: drop active-line, custom fold chevron, `markdown-autopair.ts` for `**`/`__`/`[[`/`` ` ``, Apple typography overhaul (SF Pro Text body + SF Pro Display headings + SF Mono code; 28/22/17/15/13/13pt scale), triple-clear transparent-bg (`drawsBackground=false` KVC + `underPageBackgroundColor=.clear` + NSView layer bg + CSS `!important`), Pommora-side `.background(Color.clear)` defensive layer

**Build state end-of-session:** `xcodebuild build` SUCCEEDED. `xcodebuild test -only-testing:PommoraTests` → **198/198 pass**. `swift format lint --strict --recursive` → exit 0.

**Smoke test verdict (Nathan):** Phase G's overhaul still didn't produce Notion-like polish. Decision to swap editor library to Milkdown + Crepe. Plan written at `// Planning//v0.2.7-milkdown-swap.md`. Compact at session close.

**Project quirk added (#13 in `CLAUDE.md`):** SPM branch-pinned forks need full cache nuke to bump (gentle `xcodebuild -resolvePackageDependencies` respects pins). Nuke `Package.resolved` + `DerivedData/.../SourcePackages` + `~/Library/Caches/org.swift.swiftpm/repositories/<DepName>-*`.

---

#### Session 8 — 2026-05-18 (continued — architecture pivot to Apple swift-markdown + swift-markdown-engine, plan-only)

Plan-only session. Nathan reconsidered the Milkdown direction after demoing `nodes-app/swift-markdown-engine` (Apache 2.0, native TextKit 2, ~7411 LOC). The demo (built + launched manually by Nathan in Terminal — auto-mode classifier blocked the builder agent from /tmp paths) made the native-Mac feel undeniable. Session produced a comprehensive single-session implementation plan at `// Planning//v0.2.7-engine-swap.md` and Nathan accepted it. No code committed. Compact at session close to execute the plan in one go next session.

**Architecture locked:**

- **Parser:** Apple `swift-markdown` (full GFM AST + `BlockDirective` for v0.2.9 directives + source-range tracking). SPM dep on `swiftlang/swift-markdown`.
- **Renderer:** Apple `NSAttributedString` + `NSTextView` + `NSTextLayoutManager`. Writing Tools (15.1+), Look Up / Translate / spell-check, IME, dynamic system colors, drag-select all free.
- **Live-preview chassis:** `swift-markdown-engine` (selectively vendored at `Pommora/Pommora/PageEditor/Engine/`, ~4500 LOC after planned deletions). Two load-bearing engine contributions: **dynamic syntax** (markers shrink when caret leaves AST node — Bear/Notion pattern) + **Markdown-aware typing helpers** (list continuation + block auto-wrap shipped; character-pair auto-pair `**`/`__`/`[[`/`` ` `` with auto-exit-on-space added Pommora-side in Phase 4.5). Engine's `Services/WikiLinkService.swift` two-form `[[Name|<id>]]` ↔ `[[Name]]` storage transform also kept as reference for v0.2.10 wikilink work.
- **Domain wiring:** PageRef, PageFile, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, inspector + sidebar wiring, lifecycle observers, atomic-write contract, frontmatter preservation rule, editable title TextField, all 198 tests — **survive unchanged from Phase A-G**.

**Critical scoping discovery:** engine's `MarkdownToken` type is load-bearing — 11 non-styling files (coordinator extensions, ContextMenu, SpellingPolicy, Input handlers) reach through it. Plan **preserves type-API** of `MarkdownToken`/`MarkdownTokenizer.parseTokens(in:)`/`MarkdownDetection.isInside…` and **rewrites internals** to back onto Apple AST. Only `MarkdownStyler` gets a full body swap (replaced by `PommoraMarkdownStyler`).

**Plan structure (single session, Phases 0-5; Phase 6 docs split defers to v0.2.7.1):**

- **Phase 0** — Documentation repair (~30 min) — verify Handoff/History/Framework/CLAUDE reflect reality post-compact
- **Phase 1** — Strip Pallepadehat fork (~30 min) — 6 pbxproj entries + Package.resolved + `import MarkdownEditor` + `pommoraEditorConfig` + `EditorWebView` call + `network.client` entitlement + `External/PageEditorMD/` clone
- **Phase 2** — Vendor engine + Apple swift-markdown SPM dep (~45 min) — drop `MarkdownEngine.docc/`; copy engine; pin Apple swift-markdown
- **Phase 3** — Replace parser internals + styler (~2 hours, the heart) — reimplement `MarkdownTokenizer.parseTokens(in:)` as Apple-AST walker emitting `MarkdownToken` shims; reimplement `MarkdownDetection` helpers; write `PommoraMarkdownStyler` covering all GFM block types; write `PommoraInlineScanner` for wikilink/image-embed overlay; write `SourceRangeToNSRange` converter + tests
- **Phase 4** — Wire PageEditorView (~20 min) — replace `EditorWebView` with `NativeTextViewWrapper`; swap config; title TextField untouched
- **Phase 4.5** — Auto-pair + auto-exit-on-space (~30 min core + 20 min stretch) — extend `MarkdownInputHandler`
- **Phase 5** — Smoke-test verification (~15 min) — type prose / table / blockquote / hr / strikethrough / wikilink; switch Pages; verify on disk
- **Phase 6** — Docs split → defer to v0.2.7.1

**Locked execution rules:** all commits on `main` directly (override of quirk #13); every dispatched agent uses `claude-opus-4-7` (Opus 4.7); `builder` subagent for `xcodebuild`; FILENAME form for `-only-testing` (quirk #1); `swift format lint --strict` exit 0 before every commit; Nathan pushes manually.

**End-of-session state:** code state unchanged at `152609c`; build green; 198/198 tests pass; lint clean. Planning folder: `v0.2.7-engine-swap.md` active; `v0.2.7-milkdown-swap.md` deleted by Nathan as no-longer-needed; Pallepadehat-era `v0.2.7-editor-polish.md` already marked SUPERSEDED.

**Next session opens with:** post-compact, execute the engine-swap plan Phases 0-5 in one go per the verbatim resume prompt at the top of `Handoff.md`.
