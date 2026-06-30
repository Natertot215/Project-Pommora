## MarkdownPM

Pommora's in-house Markdown editor: a dynamic-syntax editor on a web-native (CodeMirror 6) substrate. 
### Architecture — Three Strata, One Owned

| Stratum | React uses | Ownership |
|---|---|---|
| Text substrate (caret, IME, undo, viewport) | CodeMirror 6, behind the `editor/` seam | dependency |
| Behavior layer (syntax, styling, detection, transforms) | hand-written | **ours** |
| Parser / AST (GFM tree + per-node offsets) | micromark / mdast, behind `parser.ts` | dependency |

The behavior layer is pure logic over `(doc string, selection, tokens, decorations)` — it never imports CodeMirror or micromark; two adapters (`editor/`, `parser.ts`) bridge it. CM6 decorations (mark / widget / replace) apply the styling. Swapping either dependency touches only its seam.

### The Dynamic-Syntax Pattern

A construct's Markdown markers are **revealed** (literal editable text) when the caret is inside its token and **hidden / decorated** when it leaves; chrome (HR rule, blockquote card, code background, bullet / checkbox glyph) is a render-side decoration that never exists on disk. Two render lockings: **caret-aware reveal/hide** (inline marks, headings, HR) and **always-show overlay** (bullet, checkbox, blockquote). One detection function per construct feeds both the hide logic and the chrome — no "marker hidden but no chrome" half-states.

### Source-of-Truth Contract

- **Disk == `EditorState.doc` string, always** — no reconstruction layer; survives an editor swap.
- **Display ≠ source** — the same bytes render differently; the editor never auto-tidies source (mutations are user-initiated only).
- **Binds to the body only** — frontmatter is stripped on load, held on the model, re-serialized from the typed object on save (foreign keys / comments preserved). YAML is never visible or destroyable in the editor.
- **Display-only UI state lives in dedicated `.nexus/` files, never frontmatter** — e.g. heading folds in `.nexus/folds.json`, keyed by page id, per-machine.

### Constructs

- **Inline marks** — bold / italic / bold-italic, strikethrough, inline code, links, connections; caret-aware marker reveal; heading-aware sizing; suppressed inside code + literal targets.
- **Headings** — H1–H6 on the em scale (H1–H4 in the menu; all six render); `#` reveals on caret. **Foldable** via a gutter chevron reusing the sidebar's disclosure language (chevron on hover when open, persistent when folded); state in `.nexus/folds.json`.
- **Lists** — bullet (`-` → `•`), `+`, arrow `→` (typed `->`), ordered, and GFM task checkboxes — all sharing one indent/spacing zone and the full behavior set (continuation, indent, drag). On disk all are portable CommonMark except the arrow line (`→ text`, a Pommora render directive legible anywhere but only rendered as a list inside Pommora). **Drag-to-reorder by the glyph**: grab a list glyph to move the item with its nested sub-block; dropping beside a shallower item re-nests, ordered runs renumber — one source-line transaction, one undo. Pure logic in a unit-tested `editor/listDragModel.ts` under the `editor/listDrag.ts` gesture.
- **Code** — inline + fenced share one `code` identity (mono, code color, code fill); fenced gets a copy button; syntax highlighting is a no-op seam.
- **Blockquote** — always-show rounded card + accent bar. Block constructs nest inside it (and inside callouts): the `>` prefix is stripped and the inner line renders as its own construct — `> - item` is a real bullet, `> # h` a heading, `> ---` an inner rule. Same renderer at the top level or behind a prefix (no exclusivity).
- **Callout** — a `> [!callout]` blockquote rendered as a **bordered, gutter-width box**, distinct from the quote card; typed with the `||` shorthand, coexists with plain quotes (the tag discriminates). **Detection is per-HEAD** — every `[!type]` line starts its own box, so adjacent / pasted / nested heads never merge with a leaked tag; an invalid tag falls back to a plain quote. Block constructs (lists, headings, separators, fenced code, nested quotes) render **inside** the box, their indent measured from one shared `--li-origin`. The hidden `> [!type] ` head is an **atomic range** (the caret can't enter, so typing / delete can't demote it to a quote), and a **transaction guard** keeps any delete from eroding a body line's `>` prefix out of the box; Shift+Enter stays in. On disk it's a plain, portable blockquote. *Known gap: a table inside a callout renders as raw text (region detection isn't prefix-aware — deferred); the box stays intact around it.*
- **Thematic break** (`---`) — caret-aware full-width rule; no setext interpretation, ever.
- **Connections** (`[[Title]]`) — title-only, rendered as **styled colored inline text (never a chip)**, three states (resolved / phantom / ambiguous) wired to the live `@shared/connections` layer; click navigates; live restyle when connections change. Plus the `[[` **autocomplete panel** (glass popup at the caret, prefix-matched, keyboard-driven), one `useConnectionAutocomplete` hook shared by the page editor and table cells.
- **External links** (`[text](url)`) — title-only at rest. Valid vs invalid by a static URL check shared with the opener (`@shared/links`, so color can't disagree with what opens): valid → link color + underline; invalid → dimmed with `[brackets]` shown. Pointer cursor + navigation (`shell.openExternal`) on valid titles only.
- **Caret + hover cursor** — a **drawn caret** (a CM `layer` over `caret-color: transparent`, native selection untouched) with a smooth symmetric fade instead of Chromium's hard blink, plus a custom I-beam hover cursor; knobs in `Styles.css`. `editor/caret.ts`.

### Tables

GFM pipe-tables render as an editable HTML table — a CodeMirror **block-replace widget** over the canonical GFM source, which stays in `EditorState.doc`. Chosen over a ProseMirror table because portable GFM itself caps the feature set (rectangular cells, per-column alignment, inline-only content) — a widget over the source reaches that ceiling with far less surface and lossless round-trips. A React port of [`ckant/codemirror-markdown-tables`](https://github.com/ckant/codemirror-markdown-tables) (MIT); Pommora-only additions are the dash-count width columns + width-resize, the structure + merge guards, page-scoped in-cell undo, and the OS-native grip menu.

- **Live cell editors** — every cell is a nested CodeMirror editor reusing the main editor's inline rendering (caret / IME / marks work in-cell, no read↔edit switch); **Cmd-Z forwards to the page history**. A cell edit writes a minimal pipe-to-pipe diff, tagged as a self-edit so the widget *remaps* (focused cell stays mounted) instead of rebuilding.
- **Cell ⇄ source encoding** — a cell is single-line GFM: literal `|` / `\` are backslash-escaped, an in-cell line break (Shift+Enter) serializes as `<br>` — so no keystroke or paste can split a row. `cellToSource` / `cellToDisplay` are the inverse pair.
- **Structure is uncorruptible from the keyboard** — the widget replaces the source so the caret never reaches the pipes; `atomicRanges` skip each table (a boundary delete removes the whole block, undoable). **Two tables can't be fused** — an insert is blank-line-fenced, and deleting the lone blank line between two tables is refused by a transaction filter. *(Known minor: deleting a trailing table with no final newline leaves one orphan blank line.)*
- **Connections in cells** — `[[…]]` render + autocomplete inside a cell (Tab / Enter accepts). An aliased `[[Title|alias]]` collides with cell-pipe escaping, so autocomplete only inserts alias-free `[[Title]]` (open paradigm call).
- **On-disk: dash-count width** — column width is the dash count per delimiter cell (Pandoc convention, `---|-` ⇒ 75 / 25), rendered as `<colgroup>` ratios with `table-layout: fixed`; orthogonal to alignment (re-aligning never resizes). Best-effort cosmetic (Pandoc honors, GitHub / Obsidian ignore, a reformatter may normalize away) — widths are never data, so losing them never loses content. Rides the portable source because CSS renders custom widths natively.
- **Self-healing** — a region is a widget iff it parses as a single GFM table, re-evaluated per change; a half-typed / broken table falls back to raw text with the caret preserved. Empty cells are real min-height cells; a header-only table is valid; deleting the last column deletes the table; a foreign table round-trips byte-identical; no horizontal scroll (many columns narrow and wrap).
- **Structural edits via grips** — hovering reveals a quiet grip, one at a time (top per-column, left per-row). Dragging reorders live (a no-op move snaps back); right-click pops the OS-native menu (align / insert / clear / delete · Delete Table on the header grip), and the header-row grip's **left-press drags the whole table** (see Block Drag); dragging a column boundary resizes by moving whole dashes between the two neighbors (total conserved, 1-dash floor, the moving columns are the only feedback). Creation is the Block menu's Insert Table.
- **Module shape** — `MarkdownPM/Tables/`: a framework-free headless core (`model` / `codec` / `regions` / `operations`, unit-tested standalone) under thin adapters (`widget.tsx` the block-replace decoration, `TableView` / `CellEditor`, `sync.ts` the minimal-diff commit); `index.ts` exports one CM6 extension — unregister it and tables degrade to plain text.

### Block Drag

Every block carries a gutter **drag handle** that relocates the whole block to the nearest block boundary. The rail grip (paragraph / code / list) is a content-anchored `::before` revealed only on gutter hover; the heading chevron, the callout's gutter grip, and the table's heading-row action grip double as drag handles for their own blocks — one shared `createBlockDragGesture`, hit-tested by a gutter x-coordinate (a non-CM-line handle like the table widget calls the same `startBlockDrag` directly). The block to move is resolved by `blockAt`; the drop is one source-line move (`blockMoveChanges`), blank-separated at BOTH new seams so a relocation never fuses adjacent blocks (a glue-adjacent paragraph won't become a lazy list continuation). The fixed accent insertion line snaps list-drag-style to the nearer block's **outer** box edge (the DOM line box, so it lands outside a callout/quote/code border, not inside) and flips at the block's midpoint, with edge auto-scroll, scroll re-measure, and Escape/blur abort. A folded heading **auto-unfolds at drag-start** — a fold can't survive the relocating single-replace edit (CM's `mapPos` collapses interior positions to a span endpoint). Interior drop-slots (dropping INTO a box) are deferred to V2 nesting.

### Typing Transforms (Input-Time Only)

Each fires as one atomic transaction with a re-entry guard; all are **prefix-aware** (a list behind a `>` behaves like one at the top level); paste preserves literal text.

- **List continuation / indent** — Enter continues a list, Tab indents (capped at the nesting limit); checkbox canonicalizes (`-[]` → `- [ ]`).
- **Callout shorthand** — `||` → `> [!callout] `.
- **Auto-pair + paired-delete** — brackets `(` `[`, and the single emphasis/code + quote markers `* _ \` " '`. The latter pair **only when not right after a word char** (so contractions, units `5"`, `2 * 3`, and snake_case stay literal) and **type over** their own closer on the way out; `**` / `__` / `` `` `` still promote to the doubled form. Backspace inside an empty pair removes both halves; `{` is excluded. All of it runs in table cells too.
- **Enter / Shift+Enter close an open construct** — Enter inside a pair / quote / emphasis / connection steps the caret past the closer (no newline); Shift+Enter closes it **first**, then breaks the line, so a newline never lands inside the pair.
- **Dash / arrow auto-format** — `--` → `—`, `->` → `→`.
- **Smart whole-marker backspace** — deletes the whole marker on a marker line; callout-aware (never strips a lone `>`).

### Context Menu + Shortcuts

Right-click pops the **OS-native** menu, built in the Electron main process (`Menu.buildFromTemplate`, `frame`-wired so system items — Look Up, Services, spelling, Writing Tools — surface), with Pommora submenus (Format / Heading / Lists / Block) whose active state is computed from the live `EditorState`, not a static snapshot. Shortcuts: ⌘B / I / E / K, ⌘⇧X (strike), ⌘⇧K (connection).

### Service Seams (Host-Injected)

Wikilink resolver — **wired** to `@shared/connections`: resolution, styling, click-routing, and rename-cascade all ride the connections layer. Image provider, latex renderer, syntax highlighter — no-op defaults today; real implementations slot in behind the same seams later.

### Module Shape

`MarkdownPM/` — one folder per concern: `parser/` · `detect/` · `tokens/` · `decorations/` · `input/` · `callouts/` · `widgets/` · `editor/` (CM6 wiring) · `services.ts` · `Styles.css`. `Styles.css` is the single appearance file; every value resolves from the root design-system tokens via the `--var` bridge (the lone exception is link / connection coloring, which renders off-page too and lives in the global style layer). The behavior layer — everything but `widgets/`, `editor/`, and `Styles.css` — is framework-free and unit-tested against a dedicated corpus.

### Non-Obvious

- **Emphasis markers are located by geometry, not width-subtraction** — per side, take the *tighter* of the content bounds and place the `*`/`_` run exactly that many chars adjacent; naive `start + width` mislocates whenever an inner span abuts the delimiter run (`**a *b* c**`). The one genuinely subtle AST algorithm; re-validate against the parser's offset semantics if the parser is swapped.
- **Block constructs confirm by parsing a single line in isolation** — which is why a bare `---` is *always* a thematic break. Setext H2 was removed; a setext-underline guard must never be reintroduced.
- **`WidgetType.ignoreEvent` defaults to TRUE** — a CM6 widget swallows every event from its own DOM, so an interactive glyph widget (bullet, checkbox) needs an explicit `ignoreEvent → false` or a pointerdown never reaches its handler (the bug that made bullet-drag silently dead).
- **Connection detection reuses `@shared/connections`, not its own regex** — so the editor can't drift from the scanner / resolver / rename-cascade, and a connection restyles live the instant its target is created or renamed (no doc reparse).
- **All offsets are character offsets (UTF-16), never bytes** — micromark/mdast reports char offsets, dissolving the cmark byte-offset column-bug class; still guard astral-plane characters at parser boundaries.
- **Box constructs float with an outer gap, never a line margin** — CM6 line margins break caret/arrow mapping (only padding is measured), so each box construct (blockquote, code block, callout) paints its fill as an inset `::after` and the first/last line pads by an outer-gap knob (`--bq-gap` / `--cb-gap` / `--callout-gap`), leaving empty space *outside* the fill so the box reads as separated from its neighbours even with no blank line between them. A code block nested inside a box pins its gap to 0 (the surrounding box already owns the outer spacing).

### Known Issues

- **A bullet whose content is one long unbroken word drops the word below the marker** — the line-breaker takes the soft break between marker and content rather than force-breaking the word. `+` and arrow items share it; hiding the source space (the ordered/checkbox fix) doesn't survive a CM6 replace decoration, so only the glyph's `line-height` cap shipped.

### Deferred

- **Image + latex** render seams (detected + styled today, rendered later) · **zoom slider** UI placement · **heading-fold inside a callout** (headings render in a callout, but the fold chevron isn't prefix-aware yet) · **table inside a callout** (renders as raw text; needs prefix-aware region detection).
- **Border-anchored "+" insert** (hover a column/row edge to insert) — deferred while tables are full-width; the grip's right-click Insert covers the need.
