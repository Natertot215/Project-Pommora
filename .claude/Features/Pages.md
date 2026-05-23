### Pages

A Page is one Markdown file inside a [[PageTypes|Page Type]]. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Page Type** (the Type whose folder it physically lives in). Pages conform to their Page Type's property schema.

The parallel Items-side entity is the Item — a row-shaped JSON record without body. See [[Items]] for details.

---

#### On disk

- A single `.md` file inside a Page Type folder (under `<nexus>/Pages/<PageType>/`).

- **Page Type membership is determined by location.** A Page inside a Page Type folder (folder containing `_schema.json`) is a Page in that Page Type. Pages can live directly in a Page Type folder or in a Page Collection sub-folder inside the Page Type.

- Move a Page between Page Types → properties not in the destination Page Type's schema are stripped (Notion-style; confirm prompt warns the user). Move it within the same Page Type (between Page Collection sub-folders) → no strip; schema is shared.

- YAML frontmatter for identity (`id`), icon, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the Page Type's schema. **No `page_type` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → [[Prospects]].)

- Properties on a Page must conform to the Page Type's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → [[Prospects]].)

- Markdown body for prose.

- **Adopted `.md` files load leniently (shipped v0.2.7.4).** Markdown files that surface during folder adoption — i.e. existing notes without Pommora frontmatter — open via `PageFile.loadLenient(from:nexusRoot:)`. Missing `id` is synthesized as `"adopted-" + sha256(relativePath).prefix(16)` (stable across launches, derived from the file's path relative to the Nexus root). Missing `created_at` falls back to the file's `creationDate`; tier and properties default to empty. The on-disk file is **not mutated** by the lenient loader — frontmatter is only written when the user actually edits and saves the Page through the editor. This guarantees opening a folder that's also an Obsidian vault leaves your notes byte-identical until you touch them. Both the sidebar's discovery (`ContentManager.loadAll(for:)`) and the editor (`PageEditorHost`) use the lenient path — anything that surfaces also opens.

---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Contexts (Spaces / Topics / Projects) only — the composed-blocks surfaces, not Pages.

Pages support everything in standard Markdown:

- Paragraphs, **headings** (H1–H5 in v0's type scale; no H6 token). **Foldable headings — WIP (not shipped).** Intended UX: hover any heading line to reveal a chevron in the left gutter; click it to collapse the section below that heading (down to the next equal-or-higher heading, or document end) to zero height. Fold state will persist per-Page in frontmatter as `folded_headings: ["## Foo", ...]` (exact heading source line keys; renaming a heading drops its entry). The Markdown body itself stays untouched — external tools see standard headings with no fold notion. Implementation spec + current status → [[PageEditor]]; architecture rationale → `// Guidelines//Markdown.md` §9.11.
- Bulleted / numbered lists
- **Code blocks** (fenced) and **inline code** — render in mono font (SF Mono) at 1.0 em (same size as body) with system-semantic colors as of v0.2.7.4: text color is `NSColor.systemRed.withAlphaComponent(0.85)` (adapts light↔dark via the system accent's red); background is `NSColor.quaternaryLabelColor` (semantic system fill — built-in subtle alpha, adapts light↔dark, sits visibly distinct from the page background without a custom blend). Future per-Nexus theme tokens may expose these as overrides, but the defaults now ride the system palette rather than the earlier hardcoded `#FF2525` / `#323233` values.
- Images
- **Tables** — standard GFM `| col | col |` syntax
- **Blockquotes** — standard `>` syntax (shipped v0.2.7.5). Rendered Notion/Obsidian-style: filled rounded card with a continuous vertical accent bar to its left (separated by a small gap). The `>` syntax marker is hidden in-editor (font 0.1 + clear color) but stays on disk for portability; activation requires `> ` (marker + space). Multi-paragraph quotes (consecutive `> ` lines) render as one visually-contiguous block via per-fragment position enum (`.only` / `.first` / `.middle` / `.last`) for selective corner rounding. Plain Enter continues the quote with `> ` prefix; Shift+Enter exits. Default tint is `NSColor.tertiarySystemFill` (system semantic, light/dark adaptive); accent bar is `NSColor.secondaryLabelColor`. Distinct from callouts (see below). On disk they're standard CommonMark blockquotes.
- **Horizontal rules** — standard `---` or `***`

Standard Markdown round-trips natively to any tool that reads the file.

On top of standard Markdown, Pages support **two Pommora-specific rendering directives**:

- **`@Columns`** — multi-column rendering directive. The directive marks a section of the Page to render in N horizontal columns (equidistant width by child count; three children = three equal-width columns). The Markdown content inside is just normal Markdown — the directive only changes how the editor lays it out visually. On disk the file is one continuous Markdown document with `:::columns` (or similar) fenced notation around the columned section. External tools that don't understand the directive see the notation as inert text and the content as standard Markdown. Same principle Notion uses in its Markdown export — the directive resolves cleanly to readable Markdown when stripped.

- **`:::callout`** — outlined-box callout. The directive wraps content the editor renders as a minimally-rounded bordered box (distinct from blockquotes — callouts are outlined; blockquotes are filled-with-left-bar). Default text color is the primary text token, but the callout's border (and optional bg) bind to independent `callout//` tokens so the visual treatment can be tuned without touching text or accent. External Markdown tools see the directive as inert text and render the content as standard Markdown.

**Blockquotes vs callouts:**

| | Markdown syntax | Visual treatment |
|---|---|---|
| **Blockquote** | standard `>` | filled rounded card + continuous left accent bar with small gap (Notion/Obsidian-style); hidden `>` marker; activation = `> `; plain Enter continues, Shift+Enter exits |
| **Callout** | `:::callout` directive | outlined box, minimal rounding, transparent / subtle bg |

Side-by-side variants of either: wrap multiple blockquotes (or callouts) inside an `@Columns` directive.

The earlier-proposed `@View` (in-line database view embed) is **deferred** to v2+; full prospect → [[Prospects]]. Inline embedded views (live editable embeds of other entities) are a **Contexts / Homepage** feature, not a Pages feature — composed-blocks surfaces have blocks; Pages don't.

---

#### Editor surface

> **Full editor implementation spec — see [`PageEditor.md`](PageEditor.md).** Library choice (Apple `swift-markdown` + vendored `swift-markdown-engine`), shipped features as of v0.2.7.0, deferred v0.2.7.x patch scope, save pipeline, and hot-swap surface all live there. The sections below cover the *user-facing* editing model — what the WYSIWYG experience promises — agnostic of the underlying library.

Pages on disk are a continuous Markdown stream; in the editor, that stream renders as **WYSIWYG prose** — markers shrink to near-invisible when the caret leaves an AST node (Bear/Notion/iA Writer pattern). Typing `**bold**` immediately becomes **bold**; typing `# H1 ` immediately becomes a heading; etc. The raw Markdown source is only visible if you open the file in an external editor (`vim`, `cat`, Obsidian source mode).

**Markdown input shortcuts.** Notion / Bear pattern — typing common Markdown syntax triggers immediate formatting via the editor's input-rule system:

- `**word**` → **bold**
- `*word*` → *italic*
- `` `code` `` → `code`
- `~~word~~` → ~~strikethrough~~
- `# `, `## `, `### ` at line start → H1 / H2 / H3
- `- `, `* `, `1. ` at line start → list
- `> ` at line start → blockquote
- ` ``` ` at line start → fenced code block
- `---` on its own line → horizontal rule

Markers are consumed at the moment of typing — they don't remain visible. Cmd-Z undoes the formatting transform as a single unit.

**Wikilink autocomplete.** Typing `[[` opens an autocomplete popover anchored to the cursor showing Page / Item / Context titles filtered by subsequent input. Selecting an entry inserts a styled-inline-text wikilink rendering the target's current title (custom inline node; visually identical to Obsidian-style hyperlinks, no chip background). Esc dismisses; Enter confirms; arrows navigate. The `[[ ]]` brackets are not shown — editing an existing wikilink means clicking it, which opens the picker popover with the current target preselected.

**Floating toolbar on selection.** Bubble-menu pattern — a small floating Material-bg toolbar appears on text selection with bold / italic / code / link / strikethrough buttons; disappears on collapse. Matches the macOS text-selection menu instinct.

**Slash menu (`/`) for directive insertion.** Typing `/` at line start opens a popover listing the two Pommora directives (Callout, Columns) alongside other block insertions (code block, table, heading levels, divider). SF Symbol icons; filterable by typing.

**Editor implementation — shipped at v0.2.7.0 on native TextKit 2.** Pommora uses Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine` (at `External/MarkdownEngine/`, Apache 2.0) + a Pommora-side `AppleASTSupplementalStyler` layered on top. Full implementation spec lives at `PageEditor.md`. The three-options inventory used during v0.2.7 prep (Native Swift / JS-editor in WKWebView / Pallepadehat fork) has been resolved — historical context preserved in git history.

**`.md` file format is the architectural firewall** — Pages on disk would be identical under any future editor swap. The Pages-side content manager's `updatePage(_:in:pageType:)` + `(_:inPageTypeRoot:)` write path is the Swift-side surface (renames land in Phase 2 of ParadigmV2).

**Pommora-specific surface behavior:**

- Markdown round-trip on disk — body is what's saved; frontmatter handled separately in Swift.
- Dynamic syntax — markers shrink to near-invisible when caret leaves an AST node (Bear / iA Writer pattern). Locked architecture rules + anti-patterns + lessons live at [`// Guidelines//Markdown.md`](../Guidelines/Markdown.md); the feature spec for what the editor currently ships lives at [`PageEditor.md`](PageEditor.md).
- Apple-native styling in the canvas — system font stack, system caret, accent-derived selection color; brand values via direct `NSAttributedString` attributes.
- Frontmatter never reaches the editor canvas; property panel is a separate SwiftUI surface (v0.3.0 Properties).
- Standalone-window previews are queued behind the cross-feature **PreviewWindow primitive** (see `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`); `⌥⌘O` is reserved for that ship and not currently bound.

> If pivoting to React, see `// ReactInfo//Editor.md` for the React-side approach (Tiptap directly, no WKWebView wrapper).

---

#### Opening behavior

**Default — detail pane (single Page at a time).** Clicking a Page row in the sidebar opens the Page in the existing detail pane, replacing the Page Collection / Page Type / Context detail view for that selection. Only one Page is open at a time in the main window; switching to a different Page closes the previous one (its body is already auto-saved by the editor's debounce loop). Shipped at v0.2.7.

**From the NavDropdown — single-click select / double-click open** (as shipped at v0.2.7.1). Clicking a Page row in the dropdown's Pinned or Recents list updates the dropdown's selection (no action). Double-clicking opens the Page in the main detail pane via a direct `SidebarSelection` closure (no preview gate, no standalone window). Full mechanics live in `NavDropdown.md`. The preview-then-expand mechanic (an earlier v0.2.7.2 attempt) was reverted in favor of the cross-feature **PreviewWindow primitive** project-wide rule at `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`: the PreviewWindow primitive ships per kind before any "open in preview" UI for that kind is wired. NavDropdown's open-in-preview affordance will light up per kind once the primitive lands.

**Standalone-window path: deferred.** The shipped v0.2.7.1 NavDropdown does NOT include a standalone-window scene for Pages — the `WindowGroup(for: EntityRef.self)` machinery from the failed first attempt was deleted entirely (`EntityRef` + `EntityWindowHost` + 406 lines stripped). Standalone Page previews / multi-instance windows ship later via the PreviewWindow primitive (queued).

Items use a different model — they open in the **Item Window popover** (Calendar-event-detail pattern), never in a standalone window. See [[Items]].

---

#### Hierarchy

Pages are flat within a Page Collection. No forced sub-page nesting. A Page Collection's folder typically holds its member `.md` files directly (no nested sub-folders inside a Page Collection). Pages can also live directly in a Page Type's folder root (outside any Page Collection sub-folder). Sub-pages (nested Page hierarchy inside a Page Collection) is a v2 candidate (see [[Prospects]]).

---

#### Sidebar visibility

Pages appear **in the sidebar** as leaf rows under their parent Page Type (root) or Page Collection, rendered with the `doc.text` icon. Pages are the only operational entity with sidebar leaf visibility — **Items, Agenda Tasks, and Agenda Events do NOT appear in the sidebar** (Items live in detail-pane Tables under their Item Type; Agenda Tasks + Events surface via the Calendar pin entry). The rationale: the sidebar tree is the structural / Page-shaped view; the detail pane is the full data view that includes Items.

- Page Type row → discloses Pages directly in the Page Type root + Page Collection sub-folders
- Page Collection row → discloses its Pages
- Page row → leaf (no further disclosure; v1 has no sub-pages)
- Click on a Page row opens the Page in the detail pane (single Page at a time; shipped v0.2.7.0 + selection wiring from v0.2.1)
- From the NavDropdown (Pinned / Recents), double-click on a Page row opens it in the main detail pane (shipped v0.2.7.1)
- Right-click "Open in New Window" / `⌥⌘O` affordance is queued for the PreviewWindow primitive ship — not yet wired

Right-click on a Page row in the sidebar gives Rename / Delete. Right-click in a Page Type or Page Collection detail view gives Rename / Pin (or Unpin) / Delete (shipped v0.2.7.1 additive scope). For full sidebar layout + creation affordances → [[Sidebar]].

---

#### Wikilinks

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs `[[Personal// Roadmap]]`.
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills.

Full rename + wikilink-rewrite algorithm lives in [[PommoraPRD]] ("File Renames and Wikilink Updates").
