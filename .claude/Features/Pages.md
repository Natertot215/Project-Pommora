### Pages

A Page is one Markdown file in the nexus. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Vault** (the Vault whose folder it physically lives in). Pages conform to their Vault's property schema (Vault-wide in v1; see `Vaults.md`). Vaults are kind-agnostic — Pages and Items can coexist in the same Vault. Pages are never shared between multiple Vaults.

---

#### On disk

- A single `.md` file in the nexus.

- **Vault membership is determined by location.** A Page inside a Vault folder (folder containing `_vault.json`) is a Page in that Vault. Pages can live directly in a Vault folder or in a Collection sub-folder inside the Vault.

- Move a Page between Vaults → properties not in the destination Vault's schema are stripped (Notion-style; confirm prompt warns the user). Move it within the same Vault (between Collection sub-folders) → no strip; schema is shared.

- YAML frontmatter for identity (`id`), icon, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the Vault's schema. **No `vault` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → `Prospects.md`.)

- Properties on a Page must conform to the Vault's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → `Prospects.md`.)

- Markdown body for prose.

---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Contexts (Spaces / Topics / Sub-topics) only — the composed-blocks surfaces, not Pages.

Pages support everything in standard Markdown:

- Paragraphs, **headings** (H1–H5 in v0's type scale; no H6 token). **Headings are foldable by default** — clicking the chevron on any heading collapses the content below until the next equal-or-higher heading. This is built-in UI behavior, not a Markdown directive; no on-disk syntax change.
- Bulleted / numbered lists
- **Code blocks** (fenced) and **inline code** — render in mono font (SF Mono) at 1.0 em (same size as body) with their own color tokens: `code// fg` (text color; default `#FF2525`) and `code// bg` (background; default `#323233`). Both are independent tokens tied to the color primitives so the code palette can be tuned through the color system without touching text or accent.
- Images
- **Tables** — standard GFM `| col | col |` syntax
- **Blockquotes** — standard `>` syntax. Rendered Apple-style: filled rounded box with a left-side bar (the Calendar.app event-card pattern — vertical bar at the leading edge, no outline border, medium corner radius). Default tint is grey (not accent) for v1. Distinct from callouts (see below). On disk they're standard blockquotes.
- **Horizontal rules** — standard `---` or `***`

Standard Markdown round-trips natively to any tool that reads the file.

On top of standard Markdown, Pages support **two Pommora-specific rendering directives**:

- **`@Columns`** — multi-column rendering directive. The directive marks a section of the Page to render in N horizontal columns (equidistant width by child count; three children = three equal-width columns). The Markdown content inside is just normal Markdown — the directive only changes how the editor lays it out visually. On disk the file is one continuous Markdown document with `:::columns` (or similar) fenced notation around the columned section. External tools that don't understand the directive see the notation as inert text and the content as standard Markdown. Same principle Notion uses in its Markdown export — the directive resolves cleanly to readable Markdown when stripped.

- **`:::callout`** — outlined-box callout. The directive wraps content the editor renders as a minimally-rounded bordered box (distinct from blockquotes — callouts are outlined; blockquotes are filled-with-left-bar). Default text color is the primary text token, but the callout's border (and optional bg) bind to independent `callout//` tokens so the visual treatment can be tuned without touching text or accent. External Markdown tools see the directive as inert text and render the content as standard Markdown.

**Blockquotes vs callouts:**

| | Markdown syntax | Visual treatment |
|---|---|---|
| **Blockquote** | standard `>` | filled rounded box + left-side bar (grey default; Apple Calendar event-card pattern) |
| **Callout** | `:::callout` directive | outlined box, minimal rounding, transparent / subtle bg |

Side-by-side variants of either: wrap multiple blockquotes (or callouts) inside an `@Columns` directive.

The earlier-proposed `@View` (in-line database view embed) is **deferred** to v2+; full prospect → `Prospects.md`. Inline embedded views (live editable embeds of other entities) are a **Contexts / Homepage** feature, not a Pages feature — composed-blocks surfaces have blocks; Pages don't.

---

#### Editor surface

Pages on disk are a continuous Markdown stream; in the editor, that stream renders as **WYSIWYG prose** — no markdown syntax markers visible. Typing `**bold**` immediately becomes **bold**; typing `# H1 ` immediately becomes a heading; etc. The raw Markdown source is only visible if you open the file in an external editor (`vim`, `cat`, Obsidian source mode).

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

**Editor implementation — three options inventoried at `// Planning//Page-Editor-Plan.md`** (end-of-5-18 research). The plan is the canonical decision document for which engine/stack to use; Nathan picks at v0.2.7 implementation start. The three options at a glance:

1. **Native Swift** — `swift-markdown` + TextKit 2 + `NSTextView`. Optionally wrap `nodes-app/swift-markdown-engine` (Apache 2.0, 455★) which ships wikilinks-with-ID-round-trip matching Pommora's spec.
2. **JS editor library + macOS shell we build** — Tiptap / Milkdown / BlockNote inside a WKWebView shell we author.
3. **Fork `Pallepadehat/MarkdownEditor`** — CodeMirror 6 + WKWebView wrapped as a Swift Package; ours after fork.

**`.md` file format is the architectural firewall** — Pages on disk are identical across all three options, so the engine choice is reversible without user data migration. `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` is the Swift-side write path used by all three; mirrors the existing `updateItem` shape.

**Pommora-specific surface behavior** (regardless of which engine implements it):

- Markdown round-trip on disk — body is what's saved; frontmatter handled separately in Swift.
- Live Preview marker hiding (Obsidian/Bear pattern) OR pure WYSIWYG (Notion/Tiptap pattern) — both acceptable to Nathan; the page should look like a page, not a file, in the default view.
- Apple-native styling in the canvas — system font stack (`-apple-system, BlinkMacSystemFont, "SF Mono", Menlo`), system caret, accent-derived selection color; brand values from `Color+Pommora.swift` bridged to the editor (CSS custom properties for WKWebView paths, direct attributes for native).
- Standalone window via `WindowGroup(for: PageRef.self)` + `⌥⌘O` works the same regardless of engine.
- Frontmatter never reaches the editor canvas; property panel is a separate SwiftUI surface (v0.3.0 Properties).

Per-option setup details, swap costs (in Claude sessions), and reference implementations live in `// Planning//Page-Editor-Plan.md`. A fresh implementation chat should read both this Pages.md spec and Page-Editor-Plan.md as the complete implementation brief.

> If pivoting to React, see `// ReactInfo//Editor.md` for the React-side approach (Tiptap directly, no WKWebView wrapper).

---

#### Opening behavior

**v0.3 default — detail pane (single Page at a time).** Clicking a Page row in the sidebar opens the Page in the existing detail pane, replacing the `CollectionDetailView` / `VaultDetailView` / `ContextDetailPlaceholder` for that selection. Only one Page is open at a time in the current window; switching to a different Page closes the previous one (its body is already auto-saved by the editor's debounce loop). This is the v0.3 mode — Tabs haven't shipped yet.

**v0.4+ default — new tab in the current window.** Once Tabs land at v0.4, clicking a Page row opens it as a new tab in the current Pommora window. If the Page is already open in a tab, focus existing rather than duplicate. The tab strip hosts Pages alongside Vault and Collection detail views and supports `+` / `×` / `⌘T` / `⌘W` / drag-to-reorder, with persistence to `.nexus/state.json`.

**Optional — new window (available from v0.3 onward).** Right-click a Page row → "Open in New Window", or `⌥⌘O` with a Page row selected (or with a Page focused, which opens the current Page in a new window), or drag a Page row out of the sidebar onto another part of the screen. The standalone window opens via SwiftUI's value-typed `WindowGroup(for: PageRef.self)` scene + `@Environment(\.openWindow)` action, where `PageRef` carries `{ pageID, vaultID, collectionID? }` and resolves through the existing managers. Standalone windows have their own minimal toolbar (no sidebar, no tab strip) and respect macOS native window tabbing — users who want to combine standalone Pages into a tab group use the OS-provided `⌥⌘T` Merge All Windows.

Why this sequencing: v0.3 ships the editor in isolation to prove the WYSIWYG canvas works end-to-end before adding multi-instance complexity. v0.4 then has a clean job — take the working editor and host N of them in tabs — without simultaneously debugging the editor itself. The standalone-window path is available the whole time because it's a separate `WindowGroup` scene, not dependent on the tab strip.

Items use a different model — they open in the **Item Window popover** (Calendar-event-detail pattern), never in a tab or standalone window. See `Items.md`.

---

#### Hierarchy

Pages are flat within a Collection. No forced sub-page nesting. A Collection's folder typically holds its member `.md` files directly (no nested sub-folders inside a Collection). Pages can also live directly in a Vault's folder root (outside any Collection sub-folder). Sub-pages (nested Page hierarchy inside a Collection) is a v2 candidate (see `Prospects.md`).

---

#### Sidebar visibility

Pages appear **in the sidebar** as leaf rows under their parent Vault (root) or Collection, rendered with the `doc.text` icon. This is the only Content type with sidebar visibility — **Items, Agenda items, and Events do NOT appear in the sidebar** (they live exclusively in detail-pane Tables). The rationale: the sidebar tree is the structural / Page-shaped view; the detail pane is the full data view that includes Items.

- Vault row → discloses Pages directly in the vault root + Collection sub-folders
- Collection row → discloses its Pages
- Page row → leaf (no further disclosure; v1 has no sub-pages)
- **Click on a Page row is a no-op until v0.3** when the WYSIWYG editor lands; the row is structurally visible / selectable but doesn't open anything yet
- From v0.3 onward, click opens the Page in the detail pane (single Page at a time); from v0.4 onward, click opens the Page as a tab in the current window (see "Opening behavior" above)

Right-click on a Page row gives Rename / Delete until v0.3; from v0.3 onward it also adds **Open in New Window** (`⌥⌘O`). From v0.4 onward, the right-click menu also adds **Open in New Tab** alongside the now-default tab-opening click behavior. For full sidebar layout + creation affordances → `Sidebar.md`.

---

#### Wikilinks

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs `[[Personal// Roadmap]]`.
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills.

Full rename + wikilink-rewrite algorithm lives in `PommoraPRD.md` ("File Renames and Wikilink Updates").
