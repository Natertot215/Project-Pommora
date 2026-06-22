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

- **Tables rendering — ASAP.** GFM pipe-tables as styled, caret-aware text (pipes + `|---|` separator hidden off-caret, revealed on entry; inline plain-text editing) — no grid engine. The interactive grid (cell editors, drag-reorder) stays deferred.
- **Stats footer — ASAP.** Hover-revealed bar: `Vault › Collection › Page` breadcrumb + line / word / char counts (`editor/textStats.ts` stub exists, unwired).
- **Callouts** (`::` → portable `> [!type]`, behind a swappable codec — a deliberate extension beyond Swift) · **image + latex** render seams (detected + styled today, rendered later) · **zoom slider** placement in the UI.
