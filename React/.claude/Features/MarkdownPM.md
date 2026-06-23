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
- **Connections** (`[[Title]]`) — title-only, rendered as **styled colored inline text (never a chip)**, three states (resolved / phantom / ambiguous) wired to the live `@shared/connections` layer; click navigates; live restyle when connections change. Plus the `[[` **autocomplete panel** (glass popup above the caret, prefix-matched, keyboard-driven).
- **External links** (`[text](url)`) — title-only at rest (URL hidden). **Valid vs invalid** by a static URL check shared with the opener (`@shared/links`, so colour can't disagree with what opens): valid → link colour + underline; invalid → dimmed `label-control` with its `[brackets]` shown. The revealed `(url)` carries the tell — valid = italic + underline, invalid = dimmed. Pointer cursor + navigation (`shell.openExternal`) on valid titles only.

### Tables

GFM pipe-tables rendered as a **live grid you edit like Notion** that serializes to clean, portable GFM — built inside CodeMirror 6 with no second editor engine.

- **Decoration, not a widget.** The table's lines stay in the document; structural pipes and the delimiter row are hidden, each row becomes a grid line, each cell a mark-decorated span. Because the text never leaves the document, cell editing is native CM6 — caret, undo, IME, spellcheck, and the editor's own inline rendering all work for free; only the table *structure* is render-side chrome. Chosen deliberately over a ProseMirror engine (Tiptap / BlockNote / prosemirror-tables): once the on-disk format is portable GFM, GFM itself caps the feature set (rectangular cells, per-column alignment, inline-only content), so a heavy engine buys interaction polish at the cost of a second engine and lossy round-trips — a decoration layer reaches the whole GFM ceiling with far less surface.
- **On-disk: the dash-count width convention.** Column width is encoded in the source as the *number of dashes per delimiter cell* (the Pandoc convention — `---|-` ⇒ 75% / 25%), rendered as CSS ratios; no sidecar, no frontmatter. Width is dash-count only; alignment is the delimiter colons (`:--` / `:-:` / `--:`, standard GFM) — the two are orthogonal, so re-aligning a column never changes its width. A fresh table seeds a moderate dash total so the one-dash resize quantum reads as smooth (1-dash floor). Best-effort cosmetic: Pandoc honors it, GitHub / Obsidian render the table normally and ignore it, an external reformatter may normalize it away — widths are never data, so losing them never loses content. **This supersedes the Swift build's "widths → frontmatter" (`rules/MarkdownPM.md` §9.2) and the parked "widths → `.nexus/` sidecar" note**: TextKit can't render custom inline widths without forfeiting TextKit 2, which forced Swift to frontmatter; CSS can, so React encodes width in portable source (recorded in `History.md` as the shared convention). The mdast node discards delimiter widths, so the codec counts dashes off the raw delimiter line and reads structure / alignment / cell-offsets from micromark.
- **Render mechanism.** CM6 renders each document line as a separate block-level `.cm-line`; columns align across rows only if every row resolves to identical per-column widths — which the dash-count makes exact. Each row is laid out as a grid line; each cell's content sits in an explicit span weighted by its dash-count with a **zero basis**, so content size never leaks into width and long content wraps *inside* the cell (the row just grows taller — CM6 measures wrapped height natively, no plumbing). The caret behaves because there are no anonymous grid items: every character lives in an explicit element (cell spans for content, atomic replaces for the hidden pipes). **Self-healing** — a region grids iff it parses as a single `table` node, re-evaluated per change; a half-typed or broken table falls back to raw text with the caret preserved.
- **The cell model — no visible syntax.** The user never sees a pipe table. Structure (pipes + delimiter row) is *always* hidden, even with the caret in a cell; cells are full live-preview inline editors (caret-reveal of inline marks exactly like the main editor; block constructs stay literal, matching GFM's inline-only cells). In-cell pipes are a dichotomy with micromark's cell boundaries as sole authority: a **structural** `|` is hidden + atomic; an **escaped** `\|` renders the glyph (typing `|` in a cell inserts `\|`, idempotent). There is no third "raw pipe in inline code" case — a bare `|` terminates the cell in GFM and breaks the parse.
- **Structure is uncorruptable from the keyboard.** A single `EditorState.transactionFilter` (the *structure guard*) cancels any keyboard transaction that would change a table's shape signature — columns × rows × structural-pipe count — while cell *content*, including emptying a cell to `||`, edits freely. This one rule replaces per-key backspace / delete / selection suppression and covers every edit path (typing, ranged delete, paste, IME) at once; explicit structural ops bypass it via a `StructuralEdit` annotation. The keyboard is navigation-only: structural pipes + the delimiter line register as `atomicRanges` so arrow motion skips them, and Tab / Shift-Tab / Enter move cell-to-cell and exit past the table edge (appending a trailing newline when the table sits at the document edge) — no keystroke ever creates structure.
- **Structure + resize — design ratified; headless ops built, grip/drag UI pending.** Structural change is menu-driven, never a syntax path: a hover-revealed grip (one per row / column) whose right-click opens an Insert / Delete / Align / Delete-table menu, kept separate from the cell's formatting menu; creation is an "Insert Table" entry in the Block submenu → a 3×3 grid below the caret line. Resize drags a column boundary, transferring whole dashes between the two adjacent columns (total held constant, so non-adjacent columns keep their exact ratio), tracking the cursor fluidly and snapping on release, clamped at the 1-dash floor. Row / column **reorder** is a post-v1 seam — `moveRow` / `moveColumn` ship in the headless core; the drag wires onto the same grips later via PommoraDND.
- **Rulings.** Whitespace-only and empty cells render as real min-height cells; a header-only table (no body rows) is valid; deleting the last column deletes the table, and the header can't be deleted as a row; paste over a selected table replaces it as raw text then re-grids (no structural merge); a table is never auto-tidied — a foreign table opened and left untouched saves byte-identical. No horizontal scroll — many columns narrow and wrap.
- **Module shape.** `MarkdownPM/Tables/`: a framework-free headless core (`model` · `codec` · `operations` · `regions`) importing neither CodeMirror nor React and unit-tested standalone, plus thin adapters (`decorations` for the grid + atomic ranges, `input` for navigation + the structure guard + pipe-escape, `resize` for the boundary drag) behind an `index.ts` seam that exports one CM6 extension — removing that registration degrades tables to plain text without touching anything else.

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
