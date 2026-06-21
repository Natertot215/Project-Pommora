### Pages

A Page is one Markdown file inside a [[PageTypes|Page Type]] — the only operational entity that holds free prose content. A Page **belongs to one Page Type** (the Type whose folder it physically lives in). Pages conform to their Page Type's property schema.

---

#### On disk

- A single `.md` file inside a Page Type folder (a root folder carrying `_pagetype.json`).

- **Page Type membership is determined by location.** A Page inside a Page Type folder (folder containing `_pagetype.json`) is a Page in that Page Type. Pages can live directly in a Page Type folder, in a Page Collection sub-folder (carrying `_pagecollection.json`), or in a Page Set sub-folder (carrying `_pageset.json`) inside a Collection.

- Move a Page between Page Types → properties not in the destination Page Type's schema are stripped (Notion-style; confirm prompt warns the user). Move it anywhere within the same Page Type (between Sets, Collection roots, and the Type root) → no strip; schema is shared and Sets carry none of their own.

- YAML frontmatter for identity (`id`), icon, **per-tier multi-relations** (`tier1` / `tier2` / `tier3` pointing to Contexts), and property values from the Page Type's schema. **No `page_type` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → [[Prospects]].)
- **Title is NOT the same thing as ID.** The Page's `id` (ULID in frontmatter) is its stable identity; the filename is its renameable display title. Cross-references (connections, context-link tier values) resolve via `id`, never by filename. Page titles are globally unique nexus-wide — a colliding create or rename is rejected (canonical rule → [[Domain-Model]] "Entity identity vs title").

- Properties on a Page must conform to the Page Type's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → [[Prospects]].)

- Markdown body for prose.

- **Adopted `.md` files load leniently.** Markdown files without Pommora frontmatter still open. A missing `id` is synthesized from a hash of the file's nexus-relative path (stable across launches); a missing creation date falls back to the file's own; tier and properties default to empty. The loader **never mutates** the on-disk file — frontmatter is written only when the user edits and saves through the editor, so opening a folder that's also an Obsidian vault leaves notes byte-identical until touched. Both sidebar discovery and the editor use the lenient path, so anything that surfaces also opens.



---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Contexts (Areas / Topics / Projects) only — the composed-blocks surfaces, not Pages.

Pages support everything in standard Markdown — paragraphs, headings (H1–H6; H5/H6 render at body size), bulleted / numbered / task lists, fenced + inline code, images, GFM tables, blockquotes, horizontal rules. Standard Markdown round-trips natively to any external tool.

**Headings are foldable** by default; fold state persists per-Page in frontmatter as `folded_headings: [...]` (ordinal-disambiguated keys; orphan entries reconciled on save). The Markdown body itself stays untouched. Implementation + visual spec → [[PageEditor]]; architecture rationale → `// rules//MarkdownPM.md` §9.11.

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

The editor's **WYSIWYG prose** experience — what the user sees and types — is a **dynamic-syntax** render: markers shrink near-invisible when the caret leaves an AST node, reveal when the caret enters (Bear / iA Writer pattern). Raw Markdown source is only visible in an external tool (`vim`, Obsidian source mode). Full surface, save pipeline, library, and hot-swap layer → [[PageEditor]]. Architecture, anti-patterns, and Nathan-locked editor decisions → `// rules//MarkdownPM.md`.

The `.md` file format is the architectural firewall — Pages on disk are identical under any future editor swap. Frontmatter never reaches the editor canvas; the property surface is separate from the page body (see § "Properties surface" below).

**Page icon (header).** When the per-Nexus `showPageIcon` setting is on (default OFF), a Page's `icon` renders inline beside the title — with a hover "Add Icon" affordance when unset — and a custom icon also shows in the sidebar row and Navigation (overriding the per-kind default). Full behavior → [[PageEditor]].

---

#### Properties surface

A Page's properties surface as the **property panel** in the editor's pop-out **inspector** at the window's trailing edge — not inside the page body — rendering every schema property as a fillable row. This **moves to a dedicated properties dropdown** to free the inspector for the LLM / CLI interface. The inspector has no meta section (Title / ID / Created / Icon) — the filename is the title, the page ID renders as a bottom-pinned pane footer, and an **Add Property** affordance beneath the rows commits through the shared property-creation path. Canonical architecture: [[Properties]] "Where Properties Live".

---

#### Opening behavior

**Routing is per-vault.** Each vault declares an open mode on its `_pagetype.json` sidecar (`compact` | `window`; absent = `window`), set by the vault's footer toggle (→ [[PageTypes]] "Open-in mode"). One shared open-path resolves every page-tap — sidebar single-click, detail-table double-click, and the Component Library all route through it — and decides whether the tap lands in the main detail pane or an in-window preview card. Pages inside a Page Set route identically; a save never re-points a page's set.

**`window` (default) — detail pane (single Page at a time).** Clicking a Page row in the sidebar opens the Page in the existing detail pane, replacing the Page Collection / Page Type / Context detail view for that selection. Only one Page is open at a time in the main window; switching to a different Page closes the previous one (its body is already auto-saved by the editor's debounce loop).

**`compact` — preview card.** The Page opens in a **preview card**: one reusable, resizable panel that retargets when you peek another Page. The panel is **child-attached to the main window** and **never acts as a main app window** — clicking it from another app refocuses Pommora, but it never demotes or dims the main window, so preview and main read as a single focus unit. It rides main-window moves, hides with the main window, and closes with it and on Nexus switch; it never floats over other apps and has no Dock, Window-menu, or fullscreen presence. Chrome is minimal: a renameable proxy title (double-click to edit; filename = title), a proxy icon, a footer breadcrumb + lock, and two capsule buttons (close, inspector). The body is the shared editor, read-only on open.

- **Drag from anywhere non-interactive** — the header gaps, footer, inspector empty areas, and the locked body all move the window; the title field, capsule buttons, and editable body do not.
- **Opens locked** (read-only) with the inspector open. The footer lock toggles editing; unlocking reveals an **Open** button that promotes the Page to the main detail pane (a title double-click renames, it does not promote).
- **Inspector** — the shared property inspector mounted compact, natively resizable (→ [[Properties]] "Where Properties Live").
- **Edit conflicts are structurally unreachable** — a Page currently shown in the main detail pane never opens as a preview (the tap is suppressed).

**From the Navigation — single-click select / double-click open.** Clicking a Page row in the dropdown's Pinned or Recents list updates the dropdown's selection (no action); double-clicking opens the Page in the main detail pane. Full mechanics → [[Navigation]].

---

#### Hierarchy

Pages live at three depths inside a Page Type: the Type root, a Page Collection root, or a Page Set inside a Collection (the optional third container level — see [[Sets]]). The hierarchy stops there — depth-3+ folders are sidecar-less and their pages roll up into the nearest Set. No forced sub-page nesting; sub-pages (nested Page hierarchy) are a v2 candidate (see [[Prospects]]).

---

#### Sidebar visibility

Pages are the only operational entity with sidebar leaf visibility — they appear as `doc.text` leaf rows under their parent Page Type (root), Page Collection, or Page Set. **Tasks and Events do NOT appear in the sidebar** — they surface via the Calendar pin entry. A Page row is a leaf — v1 has no sub-pages. Disclosure structure → [[PageTypes]] § "Sidebar treatment".

Right-click on a Page row in the sidebar gives Rename / Delete; right-click in a Page Type or Page Collection detail view gives Rename / Pin (or Unpin) / Delete. For full sidebar layout + creation affordances → [[Sidebar]].

---

#### Connections

A Page's body can hold inline `[[Page Name]]` connections — Obsidian-compatible wikilinks that render as styled colored inline text in the prose flow (never a chip). Canonical spec → [[Connections]]; the frontmatter `tier1` / `tier2` / `tier3` context-link counterpart → [[Properties]].
