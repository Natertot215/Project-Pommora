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

Pages on disk are a continuous Markdown stream. Wikilinks render as styled colored inline text (Obsidian-style); a slash menu or toolbar inserts the two Pommora directives (`@Columns`, `:::callout`); heading-fold (toggling content under a heading) is built-in UI behavior on every heading, not a directive.

The editor has two options:

- **Option 1 — Native Swift markdown editor.** Two sub-approaches aiming at the same UX: fork **Clearly** ([Shpigford/clearly](https://github.com/Shpigford/clearly) — native AppKit/SwiftUI markdown editor with a `MarkdownSyntaxHighlighter` in its `ClearlyCore` Swift Package, fold-state plumbing, and an editor shell; FSL-1.1-MIT, converts to MIT Feb 2028), or build an original native editor on `NSTextView` / AppKit text-engine primitives. The target shape is source-with-decorations on a native text engine — the document IS the Markdown string, styling layered as text attributes, Obsidian-style Live Preview (markers hidden when cursor leaves a construct, revealed when it enters) driven by attribute manipulation on selection change. Comes with native text behavior (smart quotes, system dictionary, AppKit caret and selection) for free. GFM table inline rendering would require custom layout fragments; TextKit 2 has community reports of rough edges around advanced layout work — to factor in if Option 1 is pursued.

- **Option 2 — WKWebView hosting a JS markdown editor.** Likely direction. Host **Tiptap**, **Milkdown**, or **BlockNote** in a WKWebView. All three have solid markdown translation — they read from and write to on-disk Markdown cleanly, keeping files canonical. The JS editor handles the editor surface; the SwiftUI shell wraps it with a native toolbar, menus, keyboard shortcuts, three-pane layout, sidebar, and inspector — everything outside the editor canvas stays native. The editor canvas is styled to match the design system (SF Pro via `font-family: -apple-system`, Pommora's design tokens as CSS custom properties). Scroll physics and caret animation are WebKit's rather than AppKit's — the main UX seam. WWDC25 shipped a first-class `WebView` in SwiftUI (iOS 26.0+ / macOS 26.0+), eliminating the `NSViewRepresentable` wrapper for those targets; older OS targets keep using `WKWebView` via `NSViewRepresentable`. MarkEdit (App Store) is the production reference for this architecture.

  Expected implementation shape: the editor's JS bundle (CodeMirror 6 / Tiptap / Milkdown / BlockNote) ships **inside** the Pommora `.app` — fully self-contained, no external network fetches at runtime. A custom URL scheme handler (`WKURLSchemeHandler` registered for e.g. `editor://`) is the typical way to serve it, since WKWebView treats `file://` as a null origin and blocks `<script type="module">` (long-standing WebKit limitation, see bug #154916). The cross-origin caveat on custom schemes doesn't bite when the bundle is shipped in-app. `WKScriptMessageHandler` carries editor events into Swift; Swift writes Markdown to disk and updates SQLite. Only Markdown crosses the bridge on save. iOS/iPad parity comes along — WKWebView is cross-Apple-platform.

  Editor candidates — pick at commit time, evaluate in practice before committing:
  - **Tiptap (MIT)** — headless ProseMirror framework; most configurable; every package Pommora needs ships MIT.
  - **Milkdown (MIT)** — markdown-first by design; round-trip integrity built into the framework; plugin ecosystem covers slash menu, history, clipboard, math, upload.
  - **BlockNote (MPL-2.0)** — batteries-included; built on Tiptap; fastest to a working editor. Avoid `@blocknote/xl-multi-column` (GPL-3.0 or commercial) — build the columns block in core instead.
  - **MarkdownEditor ([Pallepadehat/MarkdownEditor](https://github.com/Pallepadehat/MarkdownEditor), MIT)** — pre-packaged Swift Package wrapping CodeMirror 6 in WKWebView with a clean SwiftUI API (`EditorWebView(text: $markdown)`). Ships with Obsidian-style syntax hiding built in (`hideSyntax: true` default), GFM tables via the `GFM` lezer extension, SF fonts as default, light/dark theme, and a command palette triggered by `/`. Missing for Pommora: `:::callout`, `:::columns`, wikilinks (all addable as CM6 extensions in TypeScript). Personal project, one contributor, v1.0.1 — fork rather than depend. CM6 is the engine under the hood; this package provides the UI on top.

##### Markdown serialization caveats

- **Block directives use DocC `@Name(args){...}` syntax** in Apple's swift-markdown (per its `BlockDirectives.md` documentation), enabled via `ParseOptions.parseBlockDirectives`. It does not parse Pandoc / Obsidian / Docusaurus `:::name` fenced divs. Pommora's Markdown uses `:::columns` and `:::callout`, so a `:::` ↔ `@` preprocessor or a fork of swift-markdown would be needed on the parse side.
- **`MarkupFormatter` isn't a fit for the save path.** It reformats the AST — list markers, fence choice, whitespace, table alignment all get normalized to its options rather than preserved as written. Useful as a normalization or pretty-print pass, not as a byte-preserving writer. Use swift-markdown as a parse / query / AST layer; route writes through a separate path.
- **A hand-rolled Markdown writer is the expected save path.** Apple's ecosystem doesn't ship a round-trip serializer (Notes / Bear use proprietary stores). The writer walks Pommora's domain model directly (not the swift-markdown AST) and emits bytes deterministically. Not technically hard; just unowned territory.

##### Documented primitives

- `TextEditor(text: Binding<AttributedString>, selection:)` is a documented initializer (iOS 26+ / macOS 26+) supporting character-level styling (font, color, underline, kerning, links). Formatting constraints expressible via `AttributedTextFormattingDefinition`.
- `apple/swift-markdown` parses Markdown into a typed AST (cmark-gfm under the hood). Usable as a parse / query layer.
- The wikilinks-as-styled-spans shape is straightforward in principle: pattern-detect `[[...]]` in `AttributedString`, stamp custom attributes, attach a `pommora://page/<id>` link. The pattern follows WWDC25 Session 280's rich-text guidance; behavior in Pommora's editor will need real-world verification.
- `AttributedString(markdown:)` is one-way out of the box — there's no built-in `.markdown` accessor going back. Custom attributes (e.g., wikilink IDs) can be made encode/decode-stable via `AttributeScope` + `CodableAttributedStringKey` + `MarkdownDecodableAttributedStringKey`. The markdown init also normalizes whitespace, drops unknown directives, and flattens some table/list nuance — another reason the canonical save path can't round-trip through it.

> If pivoting to React, see `// ReactInfo// Editor.md` for the React-side approach (BlockNote/Tiptap directly, no WebView wrapper).

---

#### Hierarchy

Pages are flat within a Pages collection. No forced sub-page nesting. A Pages collection's folder typically holds its member `.md` files directly (no nested sub-folders inside a Collection). Loose Pages can live anywhere outside Collection folders, in any user-defined folder structure (vault root, cosmetic folders). Sub-pages (nested Page hierarchy inside a Collection) is a v2 candidate (see `Prospects.md`).

---

#### Wikilinks

- `[[Page Name]]` resolves by basename match (Obsidian-style).
- If two Pages share a basename, disambiguation uses path: `[[Notes// Roadmap]]` vs `[[Personal// Roadmap]]`.
- Renaming a Page that has ambiguous siblings updates only the references that resolve to it.
- Wikilinks render as **styled colored inline text** (Obsidian-style hyperlink), not as Notion-style chips/pills.

Full rename + wikilink-rewrite algorithm lives in `PommoraPRD.md` ("File Renames and Wikilink Updates").
