### Pages

A Page is one Markdown file inside a [[PageTypes|Page Type]]. Pages are the only entity that holds free prose content — Items are also `.md` (sharing the same `AtomicYAMLMarkdown` codec), but an Item's body is a short capped description, not a prose document. A Page **belongs to one Page Type** (the Type whose folder it physically lives in). Pages conform to their Page Type's property schema.

The parallel Items-side entity is the Item — a property-bearing `.md` record whose body is a short capped description (it shares Pages' `AtomicYAMLMarkdown` codec; the body is the description, not free prose). See [[Items]] for details.

---

#### On disk

- A single `.md` file inside a Page Type folder (a root folder carrying `_pagetype.json`).

- **Page Type membership is determined by location.** A Page inside a Page Type folder (folder containing `_pagetype.json`) is a Page in that Page Type. Pages can live directly in a Page Type folder or in a Page Collection sub-folder (carrying `_pagecollection.json`) inside the Page Type.

- Move a Page between Page Types → properties not in the destination Page Type's schema are stripped (Notion-style; confirm prompt warns the user). Move it within the same Page Type (between Page Collection sub-folders) → no strip; schema is shared.

- YAML frontmatter for identity (`id`), icon, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the Page Type's schema. **No `page_type` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → [[Prospects]].)
- **Title is NOT the same thing as ID.** The Page's `id` (ULID in frontmatter) is its stable identity; the filename is its renameable display title. Cross-references (wikilinks, context-link tier values) resolve via `id`, never by filename. Two Pages in the same Page Type / Page Collection cannot share a title — a colliding create or rename is rejected (canonical rule → [[Domain-Model]] § "Entity identity vs title").

- Properties on a Page must conform to the Page Type's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → [[Prospects]].)

- Markdown body for prose.

- **Adopted `.md` files load leniently.** Markdown files without Pommora frontmatter open via `PageFile.loadLenient(from:nexusRoot:)`. Missing `id` is synthesized as `"adopted-" + sha256(relativePath).prefix(16)` (stable across launches, path-relative to the Nexus root); missing `created_at` falls back to the file's `creationDate`; tier and properties default to empty. The loader **never mutates** the on-disk file — frontmatter is written only when the user edits and saves through the editor, so opening a folder that's also an Obsidian vault leaves notes byte-identical until touched. Both sidebar discovery and the editor use the lenient path, so anything that surfaces also opens.

---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Contexts (Spaces / Topics / Projects) only — the composed-blocks surfaces, not Pages.

Pages support everything in standard Markdown — paragraphs, headings (H1–H6; H5/H6 render at body size), bulleted / numbered / task lists, fenced + inline code, images, GFM tables, blockquotes, horizontal rules. Standard Markdown round-trips natively to any external tool.

**Headings are foldable** by default; fold state persists per-Page in frontmatter as `folded_headings: [...]` (ordinal-disambiguated keys; orphan entries reconciled on save). The Markdown body itself stays untouched. Implementation + visual spec → [[PageEditor]]; architecture rationale → `// Guidelines//Markdown.md` §9.11.

**Task lists** are GFM (`- [ ]` / `- [x]`) on disk. Pommora's `-[]` / `-[x]` shorthand is an input convenience that **canonicalizes to GFM on the space that starts the content** — so checkboxes stay portable (render in Obsidian/GitHub/pandoc too). Render + canonicalization + click-to-toggle spec → [[PageEditor]].

**Blockquote, horizontal rule, code-block** rendering is in [[PageEditor]]. The on-disk form is standard CommonMark in every case (the `>` marker hides in-editor but stays on disk; HR is `---` on its own line; Pommora rejects the Setext H2 interpretation — `---` is always HR).

**Tables** parse as GFM (`| col | col |`) today with basic styling only. Apple-Notes-style inline-grid tables are a future deliverable; full spec → [[PageEditor]] § "Tables — to be implemented".

On top of standard Markdown, Pages support **two Pommora-specific rendering directives** (both deferred — see [[PageEditor]] § "Deferred"). Each is fenced notation around a normal-Markdown section; external tools that don't understand the directive see the fence as inert text and the content as standard Markdown:

- **`@Columns`** — marks a section to render in N horizontal columns (equidistant width by child count). The directive only changes visual layout.

- **`:::callout`** — wraps content the editor renders as a minimally-rounded outlined box (distinct from blockquotes — callouts are outlined; blockquotes are filled-with-left-bar).

**Blockquotes vs callouts** are distinct constructs: a blockquote (`>`) renders as a filled card with a left accent bar; a callout (`:::callout`) renders as an outlined box. Wrap multiples of either in an `@Columns` directive for side-by-side variants. Render detail → [[PageEditor]].

Inline embedded views (live editable embeds of other entities) are a **Contexts / Homepage** feature, not a Pages feature — composed-blocks surfaces have blocks; Pages don't. (`@View`, an in-line database-view embed, is a [[Prospects|Prospect]].)

---

#### Editor surface

The editor's **WYSIWYG prose** experience — what the user sees and types — is a **dynamic-syntax** render: markers shrink near-invisible when the caret leaves an AST node, reveal when the caret enters (Bear / iA Writer pattern). Raw Markdown source is only visible in an external tool (`vim`, Obsidian source mode). Full surface, save pipeline, library, and hot-swap layer → [[PageEditor]]. Architecture, anti-patterns, and Nathan-locked editor decisions → `// Guidelines//Markdown.md`.

The `.md` file format is the architectural firewall — Pages on disk are identical under any future editor swap. Frontmatter never reaches the editor canvas; the property surface is separate from the page body (see § "Properties surface" below).

**Page icon (header).** When the per-Nexus `showPageIcon` setting is on (default OFF), a Page's `icon` renders inline beside the title — with a hover "Add Icon" affordance when unset — and a custom icon also shows in the sidebar row and NavDropdown (overriding the per-kind default). Full behavior → [[PageEditor]].

---

#### Properties surface

Currently, a Page's properties surface as the **property panel** in the editor's pop-out **inspector** (`FrontmatterInspector`, a SwiftUI `.inspector` at the window's trailing edge — not inside the page body), rendering every schema property as a fillable row. This **will move to a dedicated properties dropdown** (`PropertiesPulldown`) to free the inspector for the planned LLM / CLI interface. Auto-managed `id` + `created_at` sit in a divider-separated section; `modified_at` shows as **Last Edited Time** for sortability. Title is not included (filename plays that role). Canonical architecture: [[Properties]] § "Where Properties Live".

---

#### Opening behavior

**Default — detail pane (single Page at a time).** Clicking a Page row in the sidebar opens the Page in the existing detail pane, replacing the Page Collection / Page Type / Context detail view for that selection. Only one Page is open at a time in the main window; switching to a different Page closes the previous one (its body is already auto-saved by the editor's debounce loop).

**From the NavDropdown — single-click select / double-click open.** Clicking a Page row in the dropdown's Pinned or Recents list updates the dropdown's selection (no action); double-clicking opens the Page in the main detail pane via a direct `SidebarSelection` closure (no preview gate, no standalone window). Full mechanics live in `NavDropdown.md`. An open-in-preview affordance is gated behind the cross-feature **PreviewWindow primitive** (`Guidelines/CRUD-Patterns.md → Preview-window prerequisite`): the primitive ships per kind before any "open in preview" UI for that kind is wired.

**Standalone-window path: deferred.** There is no standalone-window scene for Pages. Standalone Page previews / multi-instance windows ship later via the PreviewWindow primitive (queued).

Items use a different model — they open in the **floating Item Window**, a draggable, dismissible window scene built on the shared PreviewWindow primitive (the first consumer of that primitive; Pages reuse it for the deferred preview path above). See [[Items]].

---

#### Hierarchy

Pages are flat within a Page Collection. No forced sub-page nesting. A Page Collection's folder typically holds its member `.md` files directly (no nested sub-folders inside a Page Collection). Pages can also live directly in a Page Type's folder root (outside any Page Collection sub-folder). Sub-pages (nested Page hierarchy inside a Page Collection) is a v2 candidate (see [[Prospects]]).

---

#### Sidebar visibility

Pages are the only operational entity with sidebar leaf visibility — they appear as `doc.text` leaf rows under their parent Page Type (root) or Page Collection. **Items, Agenda Tasks, and Agenda Events do NOT appear in the sidebar** (Items live in detail-pane Tables under their Item Type; Agenda Tasks + Events surface via the Calendar pin entry): the sidebar tree is the structural / Page-shaped view; the detail pane is the full data view that includes Items. A Page row is a leaf — v1 has no sub-pages. Disclosure structure → [[PageTypes]] § "Sidebar treatment".

Right-click on a Page row in the sidebar gives Rename / Delete; right-click in a Page Type or Page Collection detail view gives Rename / Pin (or Unpin) / Delete. A right-click "Open in New Window" / `⌥⌘O` affordance is queued behind the PreviewWindow primitive — not yet wired. For full sidebar layout + creation affordances → [[Sidebar]].

---

#### Wikilinks

Canonical spec → [[Wiki-Link]]; the on-disk form is ratified by blessed decision D1 (`// Planning//2026-06-02-MarkdownPM-Decisions.md`). The wikilink system itself lands as a separate post-rebuild session (roadmap → v0.4.0).

- **Disk format: plain `[[Page Name]]`** (Obsidian-compatible) — Pommora never writes a piped `[[Title|<id>]]` form to disk. Rename-safe ID resolution comes from a derived `wikilinks: [<id>, ...]` frontmatter mirror, auto-maintained on save (v0.4.0) — not an inline pipe.
- **Untargeted `[[Page Name]]`** (typed outside autocomplete, or pasted from another tool) resolves by current basename match. If multiple Pages share that name, the editor underlines it as ambiguous and the picker prompts for disambiguation at insertion.
- Wikilinks render as styled colored inline text (Obsidian-style hyperlink), not as Notion-style chips/pills.

**Wikilinks vs context-link properties.** These are two distinct linking mechanisms, in two different places:

| | Where it lives | How it renders |
|---|---|---|
| **Wikilink** | inline in the Markdown **body** (plain `[[Page Name]]`) | styled colored inline text, in the prose flow |
| **Context-link property** | a **frontmatter** property value — the pre-configured `tier1` / `tier2` / `tier3` arrays (tagged target IDs) | the target's **icon + title in styled colored text**, in the property surface — never a chip/pill |

A wikilink is body content the editor renders in place; a context-link property is a pre-configured tier property whose value is shown in the inspector, resolved from the target's current icon + title. Both resolve their target by ID and stay rename-safe, but they never share a surface — wikilinks never appear in the property surface, context-link values never appear inline in the body.
