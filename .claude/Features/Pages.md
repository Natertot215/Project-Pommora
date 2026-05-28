### Pages

A Page is one Markdown file inside a [[PageTypes|Page Type]]. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Page Type** (the Type whose folder it physically lives in). Pages conform to their Page Type's property schema.

The parallel Items-side entity is the Item — a row-shaped JSON record without body. See [[Items]] for details.

---

#### On disk

- A single `.md` file inside a Page Type folder (a root folder carrying `_pagetype.json`).

- **Page Type membership is determined by location.** A Page inside a Page Type folder (folder containing `_pagetype.json`) is a Page in that Page Type. Pages can live directly in a Page Type folder or in a Page Collection sub-folder (carrying `_pagecollection.json`) inside the Page Type.

- Move a Page between Page Types → properties not in the destination Page Type's schema are stripped (Notion-style; confirm prompt warns the user). Move it within the same Page Type (between Page Collection sub-folders) → no strip; schema is shared.

- YAML frontmatter for identity (`id`), icon, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the Page Type's schema. **No `page_type` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → [[Prospects]].)
- **Title is NOT the same thing as ID.** The Page's `id` (ULID in frontmatter) is its stable identity; the filename is its renameable display title. Cross-references (wikilinks, relation values, tier links) resolve via `id`, never by filename. Duplicate titles within the same Page Type / Page Collection are allowed — each Page has a unique ULID. Filesystem auto-disambiguates colliding filenames with `(2)` suffix; the displayed title stays the user-typed value.

- Properties on a Page must conform to the Page Type's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → [[Prospects]].)

- Markdown body for prose.

- **Adopted `.md` files load leniently (shipped v0.2.7.4).** Markdown files that surface during folder adoption — i.e. existing notes without Pommora frontmatter — open via `PageFile.loadLenient(from:nexusRoot:)`. Missing `id` is synthesized as `"adopted-" + sha256(relativePath).prefix(16)` (stable across launches, derived from the file's path relative to the Nexus root). Missing `created_at` falls back to the file's `creationDate`; tier and properties default to empty. The on-disk file is **not mutated** by the lenient loader — frontmatter is only written when the user actually edits and saves the Page through the editor. This guarantees opening a folder that's also an Obsidian vault leaves your notes byte-identical until you touch them. Both the sidebar's discovery (`PageContentManager.loadAll(for:)`) and the editor (`PageEditorHost`) use the lenient path — anything that surfaces also opens.

---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Contexts (Spaces / Topics / Projects) only — the composed-blocks surfaces, not Pages.

Pages support everything in standard Markdown — paragraphs, headings (H1–H5; H5/H6 render at body size), bulleted / numbered / task lists, fenced + inline code, images, GFM tables, blockquotes, horizontal rules. Standard Markdown round-trips natively to any external tool.

**Headings are foldable** by default; fold state persists per-Page in frontmatter as `folded_headings: [...]` (ordinal-disambiguated keys; orphan entries reconciled on save). The Markdown body itself stays untouched. Implementation + visual spec → [[PageEditor]]; architecture rationale → `// Guidelines//Markdown.md` §9.11.

**Task lists** accept GFM (`- [ ]` / `- [x]`) and Pommora's `-[]` / `-[x]` shorthand. Render + click-to-toggle spec → [[PageEditor]].

**Blockquote, horizontal rule, code-block** rendering is in [[PageEditor]]. The on-disk form is standard CommonMark in every case (the `>` marker hides in-editor but stays on disk; HR is `---` on its own line; Pommora rejects the Setext H2 interpretation — `---` is always HR).

**Tables** parse as GFM (`| col | col |`) today with basic styling only. True Apple-Notes-style inline-grid tables — drag-resize columns, double-click popover cell editor, structural context menu — are a **major future deliverable**; full spec → [[PageEditor]] § "Tables — to be implemented".

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

The editor's **WYSIWYG prose** experience — what the user sees and types — is a **dynamic-syntax** render: markers shrink near-invisible when the caret leaves an AST node, reveal when the caret enters (Bear / iA Writer pattern). Raw Markdown source is only visible in an external tool (`vim`, Obsidian source mode). Full surface, save pipeline, library, and hot-swap layer → [[PageEditor]]. Architecture, anti-patterns, and Nathan-locked editor decisions → `// Guidelines//Markdown.md`.

The `.md` file format is the architectural firewall — Pages on disk are identical under any future editor swap. Frontmatter never reaches the editor canvas; property surface is separate from the page body (see § "Properties Pulldown" below).

---

#### Properties Pulldown

For Pages in the main window, properties live in a NavDropdown-style **pulldown** at the top of the page content. **Lazy rendering** — only populated properties render; empty schema entries are invisible. "+ Add property" picker over the parent Page Type's schema populates new properties on this Page. Auto-managed `id` + `created_at` sit at the bottom in a divider-separated section; `modified_at` appears in the main list as **Last Edited Time** for sortability. Title is NOT included (filename plays that role). For Pages opened in a Page Preview window, the property panel inside the inspector uses **eager rendering** — all schema properties visible, void-or-fill from there. Pulldown stays lazy; only the Inspector is eager. Canonical architecture: [[Properties]] § "Where Properties Live" + § "Render modes".

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

- **Disk format: `[[Page Name|01HXYZ...]]`** — the title is the human-readable label, the ULID after the pipe is the unambiguous reference.
- Resolution is ID-keyed. The displayed title updates automatically when the target is renamed — resolution happens at render time via the ULID, never via the stored label.
- Renames never break wikilinks. No cross-file body-scan rewrite is needed on rename.
- **Untargeted `[[Page Name]]`** (typed without going through autocomplete, or pasted from another tool) resolves by current basename match. If multiple Pages share that name, the editor underlines it as ambiguous and the autocomplete picker prompts for disambiguation at insertion.
- Wikilinks render as styled colored inline text (Obsidian-style hyperlink), not as Notion-style chips/pills.
- Obsidian-compat degrades gracefully — Obsidian sees `[[Page Name|01HXYZ...]]` and renders the title as the alias; just loses Pommora's rename-safety guarantees outside Pommora.
