## MarkdownPM (React) — Editor

Pommora's in-house Markdown editor: a faithful behavioral port of the Swift `MarkdownPM` package, rebuilt on web-native substrate. **Shipped + committed** — selecting a page renders this. This is the durable feature map; the exhaustive build spec (regexes, exact values, per-construct behavior) lives in `Planning/MarkdownPM.md`, and the Swift behavioral contract is the repo-root `rules/MarkdownPM.md` + `Features/PageEditor.md`.

### Architecture — Three Strata, One Owned

| Stratum | React uses | Ownership |
|---|---|---|
| Text substrate (caret, IME, undo, viewport) | CodeMirror 6, behind the `editor/` seam | dependency |
| Behavior layer (syntax, styling, detection, transforms) | hand-written from the Swift rules | **ours** |
| Parser / AST (GFM tree + per-node offsets) | micromark / mdast, behind `parser.ts` | dependency |

The behavior layer is pure logic over `(doc string, selection, tokens, decorations)` — it never imports CodeMirror or micromark; two adapters (`editor/`, `parser.ts`) bridge it. CM6 decorations (mark / widget / replace) are the analog of the Swift TextKit attribute + layout-fragment styling. Swapping either dependency touches only its seam.

### The Dynamic-Syntax Pattern

A construct's Markdown markers are **revealed** (literal editable text) when the caret is inside its token and **hidden / decorated** when it leaves; chrome (HR rule, blockquote card, code background, bullet / checkbox glyph) is a render-side decoration that never exists on disk. Two render lockings: **caret-aware reveal/hide** (inline marks, headings, HR) and **always-show overlay** (bullet, checkbox, blockquote). A marker hides via a zero-width replace decoration (structural) or a transparent span (width-preserving). One detection function per construct feeds both the hide logic and the chrome — no "marker hidden but no chrome" half-states.

### Source-of-Truth Contract

- **Disk == `EditorState.doc` string, always** — no reconstruction layer; survives an editor swap.
- **Display ≠ source** — the same bytes render differently; the editor never auto-tidies source (mutations are user-initiated only).
- **Binds to the body only** — frontmatter is stripped on load, held on the model, re-serialized from the typed object on save (foreign keys / comments preserved). YAML is never visible or destroyable in the editor.
- **Display-only UI state lives in dedicated `.nexus/` files, never frontmatter** — heading folds in `.nexus/folds.json`, keyed by page id, per-machine. (Deliberate divergence from Swift's frontmatter `folded_headings`, recorded in `History.md`.)

### Constructs (Shipped)

- **Inline marks** — bold / italic / bold-italic, strikethrough, inline code, links, connections; caret-aware marker reveal; heading-aware sizing; suppressed inside code + literal targets.
- **Headings** — H1–H6 on the app's em scale (only H1–H4 offered in the menu; all six render); `#` markers reveal on caret. **Foldable** — gutter chevron reusing the sidebar's exact disclosure language (Lucide `chevron-right` + `.twisty` + the `Reveal` grid animation — CM6's native fold doesn't animate, so the collapse is wrapped to match); chevron on hover when open, persistent when folded; state in `.nexus/folds.json`.
- **Lists** — bullet (`-` → `•` glyph) + ordered + GFM task checkboxes (reusing the chip checkbox; checked = nexus accent; click toggles the source). Portable CommonMark on disk.
- **Code** — inline + fenced share one `code` visual identity (mono, code color, code fill); fenced gets a copy button; syntax highlighting is a no-op seam.
- **Blockquote** — always-show rounded card + accent bar (not caret-aware).
- **Thematic break** (`---`) — caret-aware full-width rule; no setext interpretation, ever.
- **Connections** (`[[Title]]`) — title-only, rendered as **styled colored inline text (never a chip)**, three states (resolved / phantom / ambiguous) wired to the live `@shared/connections` layer; click navigates; live restyle when connections change. Plus the `[[` **autocomplete panel** (glass popup at the caret, prefix-matched, keyboard-driven) — one `useConnectionAutocomplete` hook shared by the page editor and table cells.
- **External links** (`[text](url)`) — title-only at rest (URL hidden). **Valid vs invalid** by a static URL check shared with the opener (`@shared/links`, so colour can't disagree with what opens): valid → link colour + underline; invalid → dimmed `label-control` with its `[brackets]` shown. The revealed `(url)` carries the tell — valid = italic + underline, invalid = dimmed. Pointer cursor + navigation (`shell.openExternal`) on valid titles only.

### Tables

GFM pipe-tables render as an editable HTML table — a CodeMirror **block-replace widget** drawn over the canonical GFM source, which stays in `EditorState.doc`. No second editor engine: chosen over a ProseMirror table (Tiptap / BlockNote / prosemirror-tables) because once the on-disk format is portable GFM, GFM itself caps the feature set (rectangular cells, per-column alignment, inline-only content) — a widget over the source reaches that whole ceiling with far less surface and lossless round-trips.

- **Widget over the source.** A block-replace `Decoration` covers each table region while its GFM lines stay in the document. Every cell is a *live nested CodeMirror editor* reusing the main editor's inline rendering, so caret / IME / undo / spellcheck and the hidden-syntax marks all work inside a cell with no read↔edit visual switch and no focus outline. A cell edit writes a **minimal diff** back to the source — only that cell's pipe-to-pipe span — annotated as a self-edit so the widget *remaps* (keeping the focused cell mounted) instead of rebuilding. The model is reshaped straight from the located region, never a second parse.
- **Cell ⇄ source encoding.** A cell is single-line GFM on disk: a literal `|` or `\` is backslash-escaped, and an in-cell line break (Shift+Enter) serializes as `<br>` — so no keystroke or paste can split a row. `cellToSource` / `cellToDisplay` are the inverse pair (escape on commit; unescape + `<br>`→newline when seeding the cell). A typed literal `<br>` therefore renders as a line break, like GFM everywhere.
- **Structure is uncorruptable from the keyboard** — the source is *replaced* by the widget, so the main caret never reaches the pipes; `atomicRanges` make it skip each table and a boundary delete remove the whole block (undoable). In-cell edits flow through the encoding above, which can't change column or row count. Tab / Shift-Tab / Enter move cell-to-cell and exit past the edges. *(Known minor: deleting a table that's the last thing in the doc, with no trailing newline, leaves one orphan blank line.)*
- **Connections in cells** — `[[…]]` render styled and autocomplete inside a cell (Tab or Enter accepts a candidate). A `|` in an aliased `[[Title|alias]]` collides with cell-pipe escaping, so the alias degrades; autocomplete only ever inserts alias-free `[[Title]]` (open pipe-vs-alias paradigm call).
- **On-disk: the dash-count width convention.** Column width is the *number of dashes per delimiter cell* (the Pandoc convention — `---|-` ⇒ 75% / 25%), rendered as `<colgroup>` ratios with `table-layout: fixed`; no sidecar, no frontmatter. Width (dash count) and alignment (delimiter colons `:--` / `:-:` / `--:`) are orthogonal — re-aligning never resizes. Best-effort cosmetic: Pandoc honors it, GitHub / Obsidian ignore it, a reformatter may normalize it away — widths are never data, so losing them never loses content. **This supersedes Swift's "widths → frontmatter"** (`rules/MarkdownPM.md` §9.2): TextKit can't render custom inline widths without forfeiting TextKit 2; CSS can, so React keeps width in portable source. The mdast node discards dash counts, so the codec reads them off the raw delimiter line.
- **Self-healing + rulings.** A region becomes a widget iff it parses as a single GFM `table`, re-evaluated per change — a half-typed or broken table falls back to raw text with the caret preserved. Whitespace / empty cells render as real min-height cells; a header-only table is valid; deleting the last column deletes the table, and the header isn't a deletable row; pasting over a selected table replaces it as raw text then re-renders; a foreign table left untouched saves byte-identical; no horizontal scroll — many columns narrow and wrap.
- **Structural layer — design ratified, headless ops staged, UI pending.** Structural change is menu-driven, never a syntax path: a hover-revealed grip per row / column → an Insert / Delete / Align / Delete-table menu; creation is an "Insert Table" Block-menu entry → a 3×3 size grid. Resize drags a column boundary, moving whole dashes between the two adjacent columns (total held constant, 1-dash floor). The headless core (insert / delete / align / resize / reorder) is built, unit-tested, and waiting on this UI; row / column reorder wires onto the grips later via PommoraDND.
- **Module shape.** `MarkdownPM/Tables/` — a framework-free headless core (`model` · `codec` · `regions` · `operations`, importing neither CodeMirror nor React, unit-tested standalone) under thin adapters: `widget.tsx` (the block-replace decoration + `atomicRanges`), `TableView` / `CellEditor` (the React table + nested cell editors), `sync.ts` (the minimal-diff commit). `index.ts` exports one CM6 extension — unregister it and tables degrade to plain text without touching anything else.

### Typing Transforms (Input-Time Only)

List continuation (Enter; Shift+Enter exits), Tab indent (capped at the nesting limit), checkbox canonicalization (`-[]` → `- [ ]`), character-pair auto-pair / auto-delete, bracket-skip on Enter, dash / arrow auto-format (`--` → `—`, `->` → `→`), and smart whole-marker backspace across every marker line. Each applies as one atomic transaction with a re-entry guard; paste preserves literal text.

### Context Menu + Shortcuts

Right-click pops the **OS-native** menu, built in the Electron main process (`Menu.buildFromTemplate`, `frame`-wired so system items — Look Up, Services, Share, spelling, Writing Tools — surface), with Pommora submenus (Format / Heading / Lists / Block) whose active state is computed from the live `EditorState`, not a static param snapshot. Shortcuts: ⌘B / I / E / K, ⌘⇧X (strike), ⌘⇧K (connection).

### Service Seams (Host-Injected)

Wikilink resolver — **wired** to `@shared/connections` (not a no-op): resolution, styling, click-routing, and rename-cascade all ride the existing connections layer. Image provider, latex renderer, syntax highlighter — no-op defaults today; real implementations slot in behind the same seams later.

### Module Shape

`MarkdownPM/` — one folder per concern: `parser/` · `detect/` · `tokens/` · `decorations/` · `input/` · `callouts/` · `widgets/` · `editor/` (CM6 wiring) · `services.ts` · `Styles.css`. `Styles.css` is the single appearance file; every value resolves from the root design-system tokens via the `--var` bridge (the one exception is link / connection coloring, which renders off-page too and so lives in the global style layer). The behavior layer — everything but `widgets/`, `editor/`, and `Styles.css` — is framework-free and unit-tested against a corpus mirroring the Swift suites.

### Non-Obvious

- **Emphasis markers are located by geometry, not width-subtraction.** Per side, take the *tighter* of the content bounds and place the `*`/`_` run exactly that many chars adjacent — naive `start + width` mislocates markers whenever an inner span abuts the delimiter run (`**a *b* c**`). The one genuinely subtle AST algorithm; re-validate against the parser's offset semantics if the parser is ever swapped.
- **Block constructs confirm by parsing a single line in isolation** (code-block guard → cheap regex prefilter → parse the lone line). This is why a bare `---` is *always* a thematic break — Setext H2 was removed, and a setext-underline guard must never be reintroduced.
- **List markers never shift the text when revealed** — the `•` / checkbox is an in-slot widget occupying the dash's exact slot, so toggling raw `- ` ↔ glyph moves nothing; other markers hide via a zero-width replace decoration (collapsed, no element). That zero-width replace is also why syntax reveal can't be animated as-is (`Prospects.md`).
- **Connection detection reuses `@shared/connections`, not its own regex** — so the editor can never drift from the scanner / resolver / rename-cascade, and a connection restyles live the instant its target page is created or renamed (phantom → resolved, no doc reparse).
- **All offsets are character offsets (UTF-16), never bytes** — choosing micromark/mdast (which reports char offsets) dissolves the cmark byte-offset column-bug class the Swift build carries; still guard astral-plane characters at parser boundaries.

### Deferred

- **Stats footer — ASAP.** Hover-revealed bar: `Vault › Collection › Page` breadcrumb + line / word / char counts (`editor/textStats.ts` stub exists, unwired).
- **Callouts** (`::` → portable `> [!type]`, behind a swappable codec — a deliberate extension beyond Swift) · **image + latex** render seams (detected + styled today, rendered later) · **zoom slider** placement in the UI.
