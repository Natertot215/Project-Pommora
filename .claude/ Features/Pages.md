### Pages

A Page is one Markdown file in the vault. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Pages collection** (member) **or stands alone** (loose). Member Pages conform to their Collection's schema; loose Pages have no schema and hold only built-in frontmatter fields (`id`, `icon`, `spaces`) plus inline body content. Pages are never shared between multiple Collections.

---

#### On disk

- A single `.md` file in the vault.

- **Collection membership is determined by location.** A Page inside a folder whose `_collection.json` has `"kind": "pages"` is a member of that Pages collection. A Page anywhere else (vault root, cosmetic folders) is a loose Page. A `.md` file inside an Items collection's folder is a vault-integrity warning — it doesn't belong there.

- Move a Page between folders → its Collection assignment changes accordingly. Move it out of any Collection folder → it becomes loose.

- YAML frontmatter for identity (`id`), icon, `spaces` (multi-relation to Spaces), and property values from the Collection's schema. **No `collection` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → `Prospects.md`.)

- Properties on a Page must conform to the Collection's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → `Prospects.md`.)

- Markdown body for prose.

---

#### Markdown features in v1

**Pages are Markdown documents — not block surfaces.** A Page is one continuous Markdown stream from top to bottom. Pommora doesn't impose a block abstraction on Pages; "block-level features" as a project term belongs to Spaces only.

Pages support everything in standard Markdown:

- Paragraphs, **headings** (H1–H5 in v0's type scale; no H6 token). **Headings are foldable by default** — clicking the chevron on any heading collapses the content below until the next equal-or-higher heading. This is built-in UI behavior, not a Markdown directive; no on-disk syntax change.
- Bulleted / numbered lists
- **Code blocks** (fenced) and **inline code** — render in mono font (SF Mono) at 1.0 em (same size as body) with their own color tokens: `code// fg` (text color; default `#FF2525`) and `code// bg` (background; default `#323233`). Both are independent tokens tied to the color primitives so the code palette can be tuned through the color system without touching text or accent.
- Images
- **Tables** — standard GFM `| col | col |` syntax
- **Blockquotes** — standard `>` syntax. Rendered as a filled box with a left-side emphasis bar (distinct from callouts; see below). On disk they're standard blockquotes.
- **Horizontal rules** — standard `---` or `***`

Standard Markdown round-trips natively to any tool that reads the file.

On top of standard Markdown, Pages support **two Pommora-specific rendering directives**:

- **`@Columns`** — multi-column rendering directive. The directive marks a section of the Page to render in N horizontal columns (equidistant width by child count; three children = three equal-width columns). The Markdown content inside is just normal Markdown — the directive only changes how the editor lays it out visually. On disk the file is one continuous Markdown document with `:::columns` (or similar) fenced notation around the columned section. External tools that don't understand the directive see the notation as inert text and the content as standard Markdown. Same principle Notion uses in its Markdown export — the directive resolves cleanly to readable Markdown when stripped.

- **`:::callout`** — outlined-box callout. The directive wraps content the editor renders as a minimally-rounded bordered box (distinct from blockquotes — callouts are outlined; blockquotes are filled-with-left-bar). Default text color is the primary text token, but the callout's border (and optional bg) bind to independent `callout//` tokens so the visual treatment can be tuned without touching text or accent. External Markdown tools see the directive as inert text and render the content as standard Markdown.

**Blockquotes vs callouts:**

| | Markdown syntax | Visual treatment |
|---|---|---|
| **Blockquote** | standard `>` | filled background + left-side emphasis bar |
| **Callout** | `:::callout` directive | outlined box, minimal rounding, transparent / subtle bg |

Side-by-side variants of either: wrap multiple blockquotes (or callouts) inside an `@Columns` directive.

The earlier-proposed `@View` (in-line database view embed) is **deferred** to v2+; full prospect → `Prospects.md`. Tabular data in Spaces uses embedded Collection view widgets (Spaces have actual blocks; Pages don't).

---

#### Editor surface

Pages on disk are a continuous Markdown stream. The editor surface differs by stack — both write the same Markdown. On either, wikilinks render as styled colored inline text (Obsidian-style); a slash menu or toolbar inserts the two Pommora directives (`@Columns`, `:::callout`); heading-fold (toggling content under a heading) is built-in UI behavior on every heading, not a directive.

**Block-level features (Spaces) vs. block-style editor UI (Pages, React):** distinct concepts. Pages stay continuous Markdown on disk regardless of stack. The React Page editor adds Notion-style per-paragraph affordances (`+` insertion + drag-handle reordering markers on the left) as a UX layer on top of that Markdown stream — orthogonal to the content model.

**For React**

Two co-primary editor candidates — BlockNote (MPL-2.0, batteries-included) and Tiptap (MIT, headless framework BlockNote is built on). Either configured as a **Notion-style block editor surface**: per-paragraph `+` (insert) and drag-handle (reorder) markers on the left of every block, slash menu, formatting toolbar. This is the **wanted UX** on React — the block-style affordances are how you insert directives, reorder paragraphs without selecting them, and anchor focus visually while editing. The on-disk format stays Markdown; the block UI is purely an editing affordance, not a content-model change. Pick at React commit time.

The editor uses **two serialization formats deliberately**: Markdown (`.md` on disk) is the canonical content format that agents, external tools, and the vault see; the editor's internal JSON is the working format in memory and the perfect-fidelity export when Markdown can't carry the information (cursor state, undo / redo, Pommora-to-Pommora interchange). Custom per-block / per-node serializers bridge the two for the two Pommora directives (`:::columns`, `:::callout`); standard Markdown round-trips natively. Both formats are first-class — neither replaces the other. **BlockNote API:** `blocksToMarkdownLossy` / `tryParseMarkdownToBlocks` / `editor.document`. **Tiptap API:** `@tiptap/markdown` / `editor.getJSON()`. See `// ReactInfo.md` "Editor serialization architecture" for the full picture.

Pivot doors (Milkdown, CodeMirror 6) trade the Notion-style block UI for a markdown-first / buffer-based surface — the opposite tradeoff from what React wants. They remain in the catalog only because their Markdown ↔ working-state architecture is analogous; pivoting would mean accepting a different editor UX. Wikilinks via custom inline marks paired with `@flowershow/remark-wiki-link` for the parse direction. Detail → `// ReactInfo.md`.

**For Swift**

Two options documented in `// SwiftInfo.md`. Option 1: native Swift editor — fork Clearly or build original on NSTextView/AppKit, delivering source-with-decorations on a native text engine (markers hidden when cursor leaves a construct, revealed when it enters). Option 2 (likely direction if SwiftUI chosen): WKWebView hosting Tiptap, Milkdown, or BlockNote — all three translate cleanly to on-disk Markdown; the native SwiftUI shell wraps the editor canvas; the editor is styled to match the design system via CSS. Wikilinks render as styled colored inline text on either path.

Both stacks produce the same on-disk Markdown.

---

#### Hierarchy

Pages are flat within a Pages collection. No forced sub-page nesting. A Pages collection's folder typically holds its member `.md` files directly (no nested sub-folders inside a Collection). Loose Pages can live anywhere outside Collection folders, in any user-defined folder structure (vault root, cosmetic folders). Sub-pages (nested Page hierarchy inside a Collection) is a v2 candidate (see `Prospects.md`).

---

#### Wikilinks

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs `[[Personal// Roadmap]]`.
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills — across both stacks.

Full rename + wikilink-rewrite algorithm lives in `PommoraPRD.md` ("File Renames and Wikilink Updates").
