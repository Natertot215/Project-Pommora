### Pages

A Page is one Markdown file in the vault. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Collection or stands alone** (no Collection at all). Pages are never shared between multiple Collections.

---

#### On disk

- A single `.md` file in the vault.

- **Collection membership is determined by location.** A Page inside a folder that contains a `_collection.json` is a member of that Collection. A Page anywhere else is a loose Page.

- Move a Page between folders → its Collection assignment changes accordingly. Move it out of any Collection folder → it becomes loose.

- YAML frontmatter for identity (`id`), icon, `spaces` (multi-relation to Spaces), and property values from the Collection's schema. **No `collection` field needed** — membership is by location. **No `title` field either** — the Page's title is its filename (minus `.md`); renaming the title in the UI renames the file on disk. (Independent UI titles → `Prospects.md`.)

- Properties on a Page must conform to the Collection's schema. **Ad-hoc properties (page-local fields not in the schema) are out of v1 scope** — the only "outside the schema" things are sidebar ordering / sorting, which are UI state, not file content. (Ad-hoc properties → `Prospects.md`.)

- Markdown body for prose.

---

#### Block-level features in v1

Three block-level features are in scope inside the Page body:

- **`@Columns`** — multi-column container. Equidistant width division by child count; no per-column width configuration in v1. Three children = three equal-width columns; four = four equal; etc. Adjustable widths deferred to a later version.

- **Callouts** — visual container with an optional color attribute. Single design pattern (one border style); no icons, no semantic types like "warning" or "info". Default border color inherits from text color; explicit color comes from a catalog. Inner content is editable markdown. Composes with `@Columns` for Notion-style side-by-side callouts.

- **Toggles** — collapsible content blocks (Notion-style). Clickable triangle expands/collapses inner content. Useful for FAQs, condensed reference sections, optional detail. Inner content is editable markdown. **For React** — implemented natively as a custom BlockNote block. **For Swift** — added in Phase A as part of the H4–H6 + toggles fork of the native `TextEditor`.

The earlier-proposed `@View` (in-line database view embed) is **deferred** to v2+; full prospect → `Prospects.md`.

---

#### Editor surface

Pages are edited in a **prose-first text editor** (Bear / iA Writer style) — not block-per-paragraph (Notion style). The user types Markdown text; wikilinks render as styled colored inline text (Obsidian-style); slash menu or toolbar inserts directives and block-level features.

**For React**

BlockNote (open-source MPL-2.0 core) configured for prose-first behavior. Drag handles per paragraph disabled; the prose feel comes from the absence of block UI on every line. Custom block specs for `:::columns`, `:::callout`, toggles via `createReactBlockSpec`. Custom markdown serializer per block type to enforce the canonical-files round-trip (BlockNote's built-in markdown is lossy by design; the custom serializer is the canonical-format guarantee). Wikilinks via custom inline marks paired with `@flowershow/remark-wiki-link` for the parse direction. Pivot doors held open if BlockNote disappoints in real use: Tiptap, Milkdown, Yoopta, CodeMirror 6 (markdown-canonical Plan B). Detail → `// ReactInfo.md`.

**For Swift**

Two-phase strategy. Phase A is the v1 editor; Phase B is a committed core feature for the Swift path, scheduled post-v1.

**Phase A — v1 editor (basic native + quick fork):**

- Native `TextEditor<AttributedString>` (iOS 26 / macOS 26+) as the prose surface.

- Heading detection and formatting (H1–H3 standard); fork quickly to add **H4–H6** and **toggles**.

- Bold / italic / underline / inline code via `AttributedString` attributes + toolbar + standard keyboard shortcuts.

- Wikilinks: pattern-detect `[[...]]`, custom attributes, styled colored text, tap-to-navigate (WWDC25 Session 280 pattern).

- Callouts and columns: segment splits — callout = styled container wrapping a sub-`TextEditor`; columns = `HStack` of sub-`TextEditor`s, equidistant.

- Slash menu: position-anchored popover; inserts directives and blocks at the cursor.

- Divider / Horizontal seperator via (---). It would add an in-page divider to the markdown. 

- Free from the system: undo/redo, copy/paste, spell check, autocorrect, dictation, accessibility, native cursor behavior.

**Phase B — post-v1 core feature (full custom editor):**

A committed core feature for the Swift path — not optional, not Prospects, but scheduled after v1 ships.

- Hover-on-selection bubble toolbar (Medium / Notion-style — select text, popover with formatting actions appears).

- Richer block manipulation, drag handles where they help, inline action affordances.

- Still built on native text-engine primitives where possible; falls back to NSTextView / TextKit 2 only where SwiftUI's `TextEditor` genuinely can't deliver.

The segment-based render (Phase A) has a known load-bearing risk: no shipped Mac markdown app uses the segment pattern, and cross-segment cursor flow is unsolved. Phase B is the eventual investment that addresses this; alternatively, Phase B may pivot to STTextView (TextKit 2) for the page surface and re-architect as decorations-on-a-single-buffer (closer to how Bear / iA Writer / Craft do it). Detail → `// SwiftInfo.md`.

Both stacks produce the same on-disk Markdown.

---

#### Hierarchy

Pages are flat within a Collection. No forced sub-page nesting. A Collection's folder typically holds its member Pages directly (no nested sub-folders inside a Collection). Loose Pages can live anywhere outside Collection folders, in any user-defined folder structure.

---

#### Wikilinks

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs `[[Personal// Roadmap]]`.
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills — across both stacks.

Full rename + wikilink-rewrite algorithm lives in `PommoraPRD.md` ("File Renames and Wikilink Updates").
