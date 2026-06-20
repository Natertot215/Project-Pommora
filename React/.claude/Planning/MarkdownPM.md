## MarkdownPM (React) — Editor Build Spec

The exact feature spec for Pommora-React's own Markdown editor: a faithful behavioral port of the Swift `MarkdownPM` package (`External/MarkdownPM/` in the repo root), rebuilt on web-native substrate. This is the **build target**, not yet built. Status: **behavioral rules verbatim-grounded in the Swift source; React integration claims grounded against the codebase (one adversarial round folded). Ready to plan the build.**

The Swift package is the behavioral source of truth. Where this doc cites a value, the Swift code is authoritative; mismatches mean this doc is stale. The construct-level contract behind the Swift build lives at the repo root `.claude/rules/MarkdownPM.md` and `.claude/Features/PageEditor.md` — read those for the *why* behind every locked decision.

Current React state: the read path is done (`page:open` → `readPage` → `{ frontmatter, body }`, frontmatter split by `pageFile.ts`); the page detail renders a **placeholder** (`Detail/PageView.tsx`). This spec is what replaces that placeholder. Prerequisites in §1.1.

---

### 1. Architecture — three strata, one owned

MarkdownPM separates into three layers. Only the middle one is Pommora's to build; the Swift package itself leaned on the platform for the other two, and so do we — each behind a thin seam.

| Stratum                                                                                               | Swift used                         | React uses                                 | Ownership      |
| ----------------------------------------------------------------------------------------------------- | ---------------------------------- | ------------------------------------------ | -------------- |
| **Text substrate** — selection, caret, IME, undo, find, decoration painting, viewport virtualization  | Apple `NSTextView` / TextKit 2     | **CodeMirror 6** (behind an editor seam)   | dependency     |
| **Behavior layer** — dynamic syntax, per-construct styling, detection rules, typing transforms, theme | **Pommora-owned (`MarkdownPM`)**   | **Pommora-owned (`MarkdownPM/`)**          | **ours, 100%** |
| **Parser/AST** — GFM tree with per-node source offsets                                                | Apple `swift-markdown` (cmark-gfm) | **micromark/mdast** (behind a parser seam) | dependency     |

**Locked decisions (this build):**
- **Substrate = CodeMirror 6.** Buffer-based: the Markdown string *is* `EditorState.doc`. CM6 decorations (mark/widget/replace) are the analog of NSTextView attribute styling + custom layout-fragment overlays. CM6 is reached only through one `editor/` seam — no CM6 types leak into the behavior layer.
- **Parser = micromark/mdast** behind a `parser.ts` seam exposing exactly what the behavior layer needs (see §4). Swappable; the behavior layer never imports the parser directly.
- **No other editor dependencies.** Everything in the behavior layer is hand-written from the extracted Swift rules.

**Seam discipline (mirrors the React HARD RULES).** The behavior layer is pure logic over a document string + offsets + an AST. It must not import CodeMirror or micromark directly. Two adapters bridge it:
- `editor/` — translates CM6 transactions/selection/viewport ↔ the behavior layer's `(doc, selection, tokens, decorations)`.
- `parser.ts` — translates the raw Markdown string ↔ the AST shape the detection rules consume.

#### 1.1 Prerequisites + gaps to close first (verified against the codebase)

The read side already exists; these must land before the editor can write or render:

- **Install CM6** — `@codemirror/state` · `@codemirror/view` · `@codemirror/lang-markdown` (none present today). The behavior layer is testable without it; the `editor/` + `widgets/` adapters need it.
- **Parser dependency** — micromark/mdast arrive today only *transitively* via `remark-gfm`. Add `mdast-util-from-markdown` (+ the GFM extension) as **explicit** top-level deps so `parser.ts` controls its own versions; don't rely on the transitive chain.
- **Wire the body-write path.** `updatePageBody` exists (`src/main/crud/page.ts`) but is **not** exposed — the `mutate` IPC contract (`src/shared/mutate.ts`) has only structural ops (create/rename/delete/move/reorder/setBanner/setNexusDescription). Add a body-write path: a dedicated `page:updateBody` IPC handler is cleaner than overloading `mutate` (body writes are debounced and high-frequency, structurally unlike the one-shot structural ops).
- **Add the missing color tokens.** The token layer (`design-system/tokens/color.css.ts`) already has the structural ones the spec maps to — `color.label.primary` (= body text), `color.label.secondary` (= muted), `color.label.tertiary`, `color.fill.tertiary` (= blockquote card), `color.separator.line` (= HR). **Missing and must be added:** `link` (link/wikilink color), `code` (the systemRed-@-0.85 inline/fenced code text), and an explicit `accent` binding (only the `--accent` CSS var from settings exists today). Heading-marker gray can reuse `color.label.tertiary`.

---

### 2. Source-of-truth contract (the non-negotiable)

Identical to the Swift contract — this is what makes the editor swappable and the files agent-legible.

- **Source on disk == `EditorState.doc` string, always.** No reconstruction layer. This survives editor swaps.
- **Display ≠ source.** The same source renders differently (hidden markers, card chrome, glyph overlays) without changing a byte on disk. This is the whole point of the dynamic-syntax pattern (§3).
- **Mutations to source are user-initiated only.** The editor never auto-tidies source in the background. The only editor-initiated source mutations happen at explicit user intent: a keystroke an input handler reacts to (Enter continuing a list), or an edit-commit. No background reformatting.
- **Display-only state lives in frontmatter, never source.** Folded-heading keys, future column widths, etc. go in YAML frontmatter; source stays portable.
- **The editor binds ONLY to the body.** Frontmatter is stripped on load (the data layer already does this — `pageFile.ts`), held on the page model, and re-serialized from the typed object on save. The user cannot destroy frontmatter through the editor, and YAML is never visible in it.

**Offset model.** All offsets are character offsets into the document string. JS strings are UTF-16, as were the Swift `NSRange`s — so offset math ports directly. Guard astral-plane characters (emoji) at any parser boundary; the Swift build carries a latent UTF-8-vs-UTF-16 column bug from cmark's byte-offset columns (root `rules/MarkdownPM.md` §6.9) — micromark/mdast report character offsets, so choosing it largely dissolves that bug class, but the emphasis-marker reconstruction (§4.3) must be re-validated against the chosen parser's offset semantics.

---

### 3. The dynamic-syntax pattern (locked architecture)

A construct's Markdown markers are **revealed** (shown as literal editable text) when the caret/selection is inside its token, and **hidden/decorated** when the caret leaves. Visual chrome (HR line, blockquote card, code background, bullet glyph, checkbox) is a render-side decoration that does not physically exist in the source.

**Two render lockings, chosen per construct** (from the Swift build's two locked patterns):

| Pattern | When | Constructs |
|---|---|---|
| **Caret-aware reveal/hide** | markers are editable text; chrome replaces them only when caret is OUT | thematic break (HR); inline marks' markers (bold/italic/code/latex/link/heading `#`) |
| **Always-show overlay** | non-interactive static glyph/chrome that never needs to hide | bullet `•`, task checkbox, blockquote card + bar |

A third pattern — **content elision + hover overlay** — applies to foldable headings (§5.1).

**CM6 translation of the pattern:**
- "Active token" = the token whose range contains (or is caret-adjacent to) the current selection head. Compute it from `EditorSelection` exactly as Swift's `computeActiveTokenIndices` does (caret strictly inside `[start,end)` → active; caret at `end` → active unless the token is a wikilink or the last char is `\n`; any selection overlapping a latex token → active). The behavior layer owns this; the `editor/` seam feeds it the selection.
- **Hide a marker** = a CM6 **replace decoration** that collapses the marker range to zero width (the web-clean equivalent of Swift's `font-size:0.1 + clear-color + negative-kern` hack — we do NOT port the 0.1pt/kern mechanism, we just hide the range). **Reveal** = drop the decoration so the literal text shows.
- **Chrome** (HR line, blockquote card/bar, code background, bullet, checkbox, fold chevron, rendered latex/image) = CM6 **widget or line decorations**, drawn from the same token/AST detection the hide logic uses.
- **Single detection source per construct.** Renderer-side decoration and the active/hide logic MUST share one detection function (Swift L2 — drift causes "marker hidden but no chrome drawn" half-states). Hoist each construct's detection into one helper consumed by both.

**Marker hiding by intent** (Swift §6.13, preserved as a principle even though the web mechanism differs): a marker that must keep its layout width (e.g. the invisible gap before bullet content) hides via transparent color; a marker that must be structurally gone (collapsed) hides via a zero-width replace decoration. In CM6 this is simply: width-preserving → styled transparent span; structural → replace decoration. Verify nothing downstream measures a collapsed range.

---

### 4. Parser seam + detection rules

The `parser.ts` seam exposes: (a) a full-document AST (mdast) with per-node `position.start/end.offset`; (b) per-line construct confirmation (parse one line in isolation); (c) the helper queries below. The behavior layer consumes only these.

**~Half of detection is pure regex and ports verbatim — no AST needed.** The other half needs the AST. Both live behind the seam.

#### 4.1 Regex-located constructs (port the patterns 1:1; strip Swift `#"…"#` raw-string delimiters)

| Construct             | Pattern (verbatim)                                                                          | Groups                                               |
| --------------------- | ------------------------------------------------------------------------------------------- | ---------------------------------------------------- |
| Image embed           | `!\[\[([^\]\r\n]*)\]\]`                                                                     | 1 = name                                             |
| Wikilink / connection | `\[\[([^\|\]\r\n]*)\|?([^\]\r\n]*)\]\]`                                                     | 1 = target, 2 = alias                                |
| Markdown link         | `\[([^\]\r\n]+)\]\(([^\)\r\n]+)\)`                                                          | 1 = text, 2 = url                                    |
| Heading               | `^[ ]{0,3}(#{1,6})(?:[ \t]+(.*))?$` (anchors-match-lines)                                   | 1 = `#` run, 2 = text                                |
| Fenced code           | ``^```[ \t]*([A-Za-z0-9_+#.-]*?)[ \t]*\r?\n((?:(?!^```[^\r\n]*$)[\s\S])*?)^(```)[^\r\n]*$`` | 1 = lang, 2 = body, 3 = close                        |
| Inline code           | `` `([^`\n]+)` ``                                                                           | 1 = code                                             |
| Block latex           | `(?s)(?<!\$)\$\$(.+?)\$\$`                                                                  | 1 = formula                                          |
| Inline latex          | `(?<!\$)\$(?!\$)([^$\n]+?)\$(?!\$)`                                                         | 1 = formula (also gated by the math heuristic below) |

**List / checkbox / blockquote line patterns** (used by both detection and styling — keep in lockstep, Swift L13):
- `listRegex` = `^\s*((?:(\d+)\.|[-*+•])(?:\s*\[[ xX]?\])?\s+)` — group 1 = full marker run, group 2 = ordered digits.
- `dashBulletRegex` (styling/render) = `^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$`.
- `bulletListPattern` = same as `dashBulletRegex`; `orderedListPattern` = `^([ \t]*)(\d+\.(?:[ \t]+\[[ xX]\])?[ \t]+)(.*)$`.
- `bareMarkerRegex` = `^\s*([-*+]|\d+\.)\s*$`; `dashNoSpaceRegex` = `^\s*-(?!\s)`; `leadingWhitespaceRegex` = `^\s*`.
- `shorthandCheckboxRegex` = `^([ \t]*)([-*+])\[([ xX]?)\]$` — groups: ws, marker, inner.
- `blockquoteMarkerRegex` = `^[ \t]*>[ \t]`.
- **Deliberate divergence (preserve exactly):** list-*detection* patterns keep the optional inner `\[[ xX]?\]` so a bare `-[]` reads as a list *line* (indents/continues); *checkbox* patterns require non-empty `\[[ xX]\]` so empty `[]` is NOT a checkbox. The lockstep rule holds *within* each class.

**Inline-math heuristic** (gates `$…$` so prose/currency isn't math): reject currency `^[+-]?(\d{1,3}(?:,\d{3})*|\d+)(?:\.\d+)?$`; require "mathy" chars `[\\\^\_\{\}=+\-*/<>]`; with zero mathy chars accept only a 1–3-letter token `^[A-Za-z]{1,3}$`; token-count caps by mathy density (≥3 mathy → reject if >120 whitespace-tokens; ==2 → >40; ==1 → >6).

**Helper queries** (line-scoped scans, no AST): `isInsideCodeBlock(offset)`, `isInsideWikilink(offset)` (depth counter: +1 on `[[`, −1 floored on `]]`, inside iff depth>0), `isInsideLatex(offset)`.

> **Connection syntax:** the Swift tokenizer handles `[[ ]]` and `![[ ]]` only. `{{ }}` is **not** tokenized anywhere in the package — do not add it.

#### 4.2 AST-located (requires the parser seam)

- **Emphasis / strong / bold-italic** (§4.3).
- **Per-line block confirmation** — HR, heading, blockquote use a three-stage detect: Stage 0 code-block guard → Stage 1 cheap regex prefilter → Stage 2 parse the *single line* in isolation and check `children.contains(node is ThematicBreak | Heading | BlockQuote)`. The per-line parse is what makes `---` always an HR with **no setext guard** (a lone `---` line parses as ThematicBreak). Never add a setext-underline guard (Swift §6.3/§9.3 — Pommora removed Setext H2).
- **Foldable headings** (§5.1) — whole-doc AST walk for top-level headings + content ranges + ordinal-disambiguated keys.
- **Plain-text extraction** for counts — AST walk emitting text/inline-code/code-block content, dropping `#`/`*`/`-`/URLs, joining blocks with `\n`, soft/line breaks → space.

#### 4.3 Emphasis tokens (the one subtle AST algorithm)

Walk the AST for `Emphasis` (→ italic, delimiter width 1), `Strong` (→ bold, width 2). Collapse rules:
- Emphasis whose sole child is an identical-range Strong → one **bold-italic** (width 3), don't descend. Symmetric for Strong→Emphasis.
- Strong whose sole child is an identical-range Strong (`****x****`) → descend without emitting (inner emits the single bold).
- Genuine sub-span nesting (`**a *b* c**`) is NOT collapsed — emit bold + nested italic.

**Marker geometry** (the load-bearing part — naive width subtraction mislocates markers when an inner node abuts the outer delimiter run): per side take the *tighter* of `contentStart = max(childSpan.start, full.start + width)` and `contentEnd = min(childSpan.end, full.end - width)`, then place markers exactly `width` chars adjacent to the resolved content. `childSpan` = union of the content node's direct children ranges. **Re-validate this against mdast's offset semantics** — it was written against cmark's delimiter-inclusive ranges.

---

### 5. Construct catalog — exact behavior

Each construct: detection (§4), the active (caret-in) vs inactive (caret-out) rendering, and exact values.

**Appearance lives entirely in one file — `MarkdownPM/Styles.css`.** The behavior layer never holds a color/size literal; it only assigns CSS class names. Styles.css is the single place a construct's look is authored (headings, blockquote, callout, code, checkbox, …), and every color/fill/border in it resolves from the **root design-system tokens via the `--var` bridge** — so values stay DRY-sourced from the token layer, never duplicated. Token mapping: body text → `color.label.primary`; muted markers → `color.label.secondary`; further-muted (phantom link) → `color.label.tertiary`; blockquote/callout fill → `color.fill.tertiary`; borders → `color.separator.*`; HR rule → `color.separator.line`; link/wikilink → `link` (to add); code text → `code` (to add); checkbox-checked → `accent` (to bind). See §1.1.

#### Inline marks (caret-aware marker reveal)

- **Bold / Italic / Bold-Italic** — content gets `font-weight:bold` / `font-style:italic` / both. Markers (`*`/`_`/`**`/`***`) hidden when inactive, shown when active. Heading-aware: emphasis inside a heading renders at the heading's size, not base. Suppressed inside code and inside wikilink/image literal targets.
- **Inline code** — content: monospace, `codeText` color (= `systemRed` @ 0.85 alpha token), code background. Markers (backticks): active → `mutedText`; inactive → `mutedText` @ `inlineCodeMarkerAlpha` (0.5), reduced size.
- **Strikethrough** (`~~…~~`) — `text-decoration: line-through`, color `bodyText` (`.labelColor`). From the supplemental AST pass.
- **Markdown link** `[text](url)` — inactive: `link` color, underline, the `(url)` parenthetical hidden. Active: `link` color @ `activeLinkAlpha` (0.55), no underline, url revealed. URL normalized (prepend `https://` if no scheme). Spell-check disabled on the range.
- **Wikilink / connection** `[[Name]]` — markers `[[`/`]]` always `mutedText`. Inactive + resolves: `link` color + underline, carries the resolved id. Inactive + missing: `secondaryLabelColor` (muted, no link). Active: content unstyled (raw editable source). Resolution comes from the wikilink service seam (§7). **Renders as styled colored inline text, never a chip.** Spell-check disabled.
- **Image embed** `![[name|id|width]]` — inactive: source line collapsed, image rendered as a block widget (width resolved from container, clamped `[50, 650]`-ish, explicit width honored). Active: source shown above the image. Broken/unresolved → falls back to muted source text like a broken link.
- **Inline latex** `$…$` — inactive: rendered math widget (via latex service seam; no-op default shows source). Active: source `$…$` shown. Spell-check disabled.

#### Block constructs

- **Headings** — exact scale (multiplier × base body size), bold, with em-relative top spacing:

  | Level | Size multiplier | Top spacing (em of heading size) |
  |---|---|---|
  | H1 | 2.0 | 0.35 |
  | H2 | 1.75 | 0.35 |
  | H3 | 1.5 | 0.32 |
  | H4 | 1.25 | 0.25 |
  | H5 | 1.15 | 0.21 |
  | H6 | 1.0 (= body) | 0.15 |

  Nothing renders below body size (H6 = 1.0). Heading text always full-size; `#` markers `headingMarker` color (fixed gray, reuse `color.label.tertiary`), hidden when inactive. Bottom spacing = base paragraph spacing. **Only H1–H4 offered in the context menu** (all six render).
  - **Foldable.** A fold chevron appears in the left gutter **on hover only** (not always-on) and toggles collapse of the section (down to the next equal-or-higher heading, or document end). It **reuses the sidebar's exact disclosure language** (not Swift's values): the Lucide **`chevron-right`** icon at size 12, rotating to 90° on expand via the `.twisty` transition; and the collapse/expand animates with the sidebar's **`Reveal`** mechanism — CSS grid `grid-template-rows` `0fr ↔ 1fr` over **180ms `ease`** (`--duration-fast` / `--ease-standard`). This **supersedes the Swift 200ms ease-in-out + SF-Symbol spec** — Pommora-React uses one disclosure standard across sidebar and editor. Fold state persists per-page in frontmatter (`folded_headings`), keyed with ordinal disambiguation for duplicate-text headings. **CM6 note:** CM6's native fold doesn't animate; wrap the folded range's collapse in a height/grid transition (or animate a widget) to match the sidebar — the animation parity is a requirement, not incidental.
- **Lists** — bullet + ordered, portable CommonMark source. Plain `-` renders a `•` glyph (always-show overlay) sized **1.5× base font**, `bodyText` color, with a `bulletTextGap` (3pt) — `*`, `+`, literal `•` render literally; only `-` substitutes. Source stays `-` on disk. Visual indent = `indentPerLevel` (24) per level; source indent unit = one tab (or 2 spaces).
- **Task checkboxes** — GFM `- [ ]` / `- [x]`. Always-show overlay that **reuses the chip checkbox component** (`design-system/tokens/chip.css.ts` → `chipCheckbox`: 17×17, radius 5.5, 1.5px stroke) — the same control chips render, so checkboxes are visually identical across lists and chips (DRY). **Checked color = the nexus accent**, via the live `--accent` CSS var (set by `applyAccent` from `.nexus/settings.json`); unchecked = muted outline. Centered on the bullet advance so task and bullet lines align. Clicking the glyph toggles the source `[ ]`↔`[x]`. The `-[]`/`-[ ]`/`-[x]` shorthand canonicalizes to GFM on the content-starting space (§6.4). Empty `[]` is never a checkbox.
- **Fenced code blocks** — full-width background (code background color, no corner radius), monospace at 0.85× size, symmetric horizontal indent (12), char-wrap, fixed line height, paragraph spacing 2. Fence markers hidden when inactive, shown when active. Syntax-highlight is a pluggable seam with a **no-op default** (plain mono on the code background). A copy button overlays the block's top-right (icon + optional uppercased language, 10px, white@80%, `rgba(0,0,0,0.3)` pill, radius 6, insets top 6 / trailing 8) → copies the block text.
- **Blockquote** — always-show overlay (NOT caret-aware): a rounded card (radius 6) with a 4px accent bar (pill caps radius 2) on the left; text indented (~20px head-indent, 8px right margin) at ~75% body color. Multi-paragraph quotes join contiguously (one element with a left bar). `>` + space markers permanently hidden; bare `>` doesn't activate. Plain Enter continues, Shift+Enter exits (§6). **Colors:** the card fill, bar, and text color are authored in `MarkdownPM/Styles.css` and import their values from the root tokens via CSS vars — fill ← `color.fill.tertiary`, bar ← `color.label.secondary`, text ← `color.label.primary` (alpha'd). No color literals in the blockquote rule.
- **Thematic break** (`---`) — caret-aware: a 1.5px-thick full-text-width rule (`separatorColor`) when caret is off the line; reverts to literal `---` when entered. No setext interpretation, ever.
- **Table** — GFM pipe-tables, **out-of-the-box (no grid engine)**. Rendered styled (monospace, faint background `color.fill` low-alpha) with the **pipes `|` and the `|---|` separator row hidden when the caret is off the table, revealed when it enters** — caret-aware dynamic syntax, same pattern as HR. **Editing is inline as plain text** — you type directly in the source; CM6 handles it natively (the hidden-syntax + inline-edit principles, nothing more). No grid widget, cell editors, drag-reorder, or structural machinery — that engine is explicitly deferred (§9).
- **Callout** (`::` line) — Notion-style bordered container around a block, like blockquote but a full box. **New construct, not in Swift** — full spec in §11. `::` is a shorthand that canonicalizes to portable `> [!type]` on disk (provisional, behind a swappable codec).

---

### 6. Typing helpers (input transforms)

All transforms are **input-time only** (single-character insert); paste preserves literal text. Each applies as one atomic CM6 transaction with a re-entry guard (the analog of Swift's `isProgrammaticEdit` + `shouldChangeText`/`replaceCharacters`/`didChangeText` wrapper) so the handler doesn't re-fire on its own edit. Detect the originating keystroke via the CM6 transaction / `KeyBinding`, not a synthetic event.

1. **List continuation (Enter).** In a list item, Enter inserts the next marker preserving leading indent: unordered keeps the user's marker char; ordered emits `n+1`; checkboxes continue as fresh unchecked `- [ ] ` (canonical GFM, even from shorthand source). Mid-line splits naturally. **Empty-item Enter does NOT exit** — it creates another empty item; the only list exit is Shift+Enter. Bare-marker start (`-`<Enter>) completes the line and opens a sibling. Guard: caret in/before the marker zone → plain newline. `---` is naturally excluded (AST parses it as ThematicBreak, not a list).
2. **Tab indent.** Tab on a list line inserts a tab at line start (nests one level), capped at `maximumNestingLevel` (3); level = tabCount + spaceCount/2. (Shift-Tab outdent is not in the Swift build — falls through.)
3. **Checkbox canonicalization.** `-[]`/`-[ ]`/`-[x]`/`-[X]` + the content-starting space → canonical `<ws><marker> [<box>] ` (box = `x` if inner was x/X, else space), caret landing **after** the trailing space so typing flows. Empty/space inner → `[ ]`.
4. **Character-pair auto-pair + auto-delete.** Pairs: `**`, `__`, `[[`, `((`, `` `` `` (multi-char, triggered on the second char when the preceding char matches), and single `[`, `(`, `{`. Single `[` auto-pairs **only at line start or after whitespace** (so `-[` task shorthand stays fluid); `(`/`{` always pair. Backspace inside an empty pair deletes both halves (for `* _ [ (` `` ` ``; `{}` does not auto-delete). Skip inside code. Gated by an `autoClosePairs` flag.
5. **Bracket-skip on Enter.** Caret between a matched pair on the line (`[ ]`, `( )`, `{ }`, `[[ ]]`) → Enter jumps past the closer (double-jump for `[[ ]]` when both sides present) instead of inserting a newline. Carve-out: the `[ ]` of a list-marker checkbox falls through to list continuation. Gated by `autoClosePairs`.
6. **Dash & arrow auto-format.** `--`<non-dash> → `—` (em); ` - `<space> → ` – ` (en); `-` adjacent to an existing `–` → `—` (en→em promotion, either side); `<-` → `←`, `->` → `→`, `<->` → `↔`. Each defers the substitution to the *next* char so collisions resolve first. Guards: em-dash preserves `---` (HR) via a 3-back dash check; en-dash requires non-whitespace before the `-` (preserves bullets) and skips inside `[[…]]`; all skip inside code blocks. Input-time only.
7. **Enter vs Shift+Enter.** Detect Shift on the Enter keydown (CM6 keybinding modifier — the analog of Swift reading `NSApp.currentEvent.modifierFlags`, since macOS collapses both to `insertNewline:`). Plain Enter continues lists/blockquotes; Shift+Enter inserts a plain newline and exits the construct.
8. **No HR expansion.** `---` is never expanded into a wide dash string (legacy behavior removed in Swift); it stays 3 chars and renders as a rule via decoration.
9. **Smart backspace (whole-marker delete) — all line markers.** When the caret sits at the **start of the content** of any rendered marker line and Backspace is pressed, delete the **entire marker prefix in one step** and put the caret at line-start — instead of nibbling `- [ ] ` down into `- [` and stranding broken syntax. Applies to **bullet, checkbox, ordered (`1. `), blockquote (`> `), and heading (`# `)** markers — one consistent rule. QoL parity with Notion/Bear. One atomic transaction; any content after the marker stays, now flush at column 0.

---

### 7. Service seams (host-injected)

The editor never reaches into the app; the host injects implementations behind these seams (props/context), each with a no-op default:

- **Wikilink resolver** — `resolve(displayName, range) → { id, exists, icon? } | null`. Drives link vs phantom styling; a "connections changed" signal triggers a full restyle so a phantom whose target appears lights up live. Default: returns null. (Click routing / rename cascade depends on the Pommora-side resolver — currently deferred, as in Swift.)
- **Image provider** — `image(ref) → url/blob | null` + a `fingerprint()` for cache busting. Embedded-image cache keyed by id-or-name, busted on fingerprint change. Default: null.
- **Syntax highlighter** — `highlight(code, lang) → spans | null` + `codeFont`/`background`. Default: no-op (plain mono on code background). A real highlighter (e.g. Shiki) slots in later.
- **Latex renderer** — `render(tex, fontSize) → { node, size, baselineOffset } | null`. Default: null → source shown. A real renderer (KaTeX) slots in later.

---

### 8. Save pipeline + shell

- **Pipeline:** keystroke → body change → short debounce → the new `page:updateBody` IPC (§1.1) → `updatePageBody` (`crud/page.ts`) reconstructs the file via `writePageFile` (merges modeled fields into existing YAML, preserving foreign keys/comments) → atomic write (`atomicWrite.ts`, `write-file-atomic`: temp sibling + fsync + rename — already present) → in-memory cache update. Flush on every context loss: page-switch, window-close, app blur/terminate, explicit save.
- **Frontmatter** is re-serialized from the typed object on save, never from a string prefix; the editor binds only to body.
- **Failure handling:** a pending-error alert (Retry / OK) preserves the draft; retry re-schedules the write.
- **Title + divider (exact, ported from Swift).** A structurally separate inline title above the body (filename = title; no `title` field), matched to macOS Notes:
  - **Title field:** 28px **bold** system font, primary text color, placeholder "Untitled", single-line, leading-aligned. Padding: 24px leading/trailing, 24px top, **14px bottom** (the gap to the divider).
  - **Divider:** a 1px hairline in `color.separator.line`, **inset 24px** on each side (runs the width of the text column, *not* edge-to-edge), sitting 14px below the title.
  - **Body top inset:** reserve **90px** at the top of the body for the title overlay (the Swift `titleAreaHeight`), applied as editor *content* padding so the empty zone scrolls *with* the document (not a fixed scroll-view inset). The body's horizontal inset is **24px**, aligning body text directly under the title's padding. A symmetric 90px bottom inset closes the document.
  - **Scroll-tracking overlay:** the title+divider sit in a layer *above* the body's reserved top zone; as the body scrolls, the title translates up in sync (`offset = -clamp(scrollY, 0, 90)`) and clips off-screen once fully scrolled past. (In CM6: a panel/overlay above the editor scroller, driven by the scroll position.)
  - **Body font:** the editor body is 15px (SF Pro Text in Swift → the app's body font in React).
  - **Enter** commits the rename (drop title focus → move focus to the body → rename the `.md` on disk in parallel) and a failed rename reverts the draft and fires the error alert.
  - **Page icon** (when the per-nexus show-page-icon setting is on — default **off**): an icon inline to the *left* of the title on its baseline (~26px), 6px gap; off/unset leaves the title flush-left with no reserved indent.
- **Stats footer** (deferred-friendly): hover-revealed bar — `Vault › Collection › Page` breadcrumb left, line/word/char counts right. Lines count raw source; words/chars count rendered prose (syntax stripped). Counts compute only while open, debounced.
- **Context menu — native OS menu (like Swift's NSMenu).** Right-click pops the **operating-system-native** menu, built in the Electron **main** process (`Menu.buildFromTemplate` + `menu.popup()`, reusing the existing `main/.../menu.ts` infrastructure) — not a styled HTML menu. Flow: renderer's contextmenu event sends the selection + current-line state to main → main builds the template → the chosen item dispatches back via IPC and the editor applies the source transform. Template:
  - **Pass `frame: webContents.focusedFrame` to `menu.popup()`** (Electron 36+; we're on 42). This is what lets the OS inject its native items (Writing Tools, Services, Autofill) into an app-built menu — without it they're suppressed. Do this regardless; it's free.
  - **Standard / system items** (all confirmed available via roles + the `context-menu` event `params`): Cut / Copy / Paste / **Paste and Match Style** / Select All / Undo / Redo (enable each from `params.editFlags` — `canCut`/`canCopy`/`canPaste`…), spelling suggestions (rendered from `params.misspelledWord` + `dictionarySuggestions`, shown only when a flagged word is right-clicked), **Look Up** (`lookUpSelection`), **Services**, **Share** (`shareMenu` + a `sharingItem` from the selection), **Speech** (Start/Stop Speaking), and **Substitutions** (Smart Quotes/Dashes/Text Replacement).
  - **Pommora submenus:** **Format** (Bold, Italic, Strikethrough, Inline Code, Link), **Heading** (Paragraph + H1–H4, `type: 'radio'`), **Lists** (Bullet, Numbered, Task), **Block** (Blockquote, Code Block, Table scaffold, Horizontal Rule, Callout). Gate the whole formatting block on `params.isEditable`. **Checkmark/active state must be computed from CodeMirror's `EditorState`, not from Electron params** — the native menu only takes a static snapshot at popup time, so resolve "is the selection already bold / what heading level is this line" in the renderer and pass it into the template build; each item's `click` dispatches a CM6 transaction back.
  - **Writing Tools — partially available (research-confirmed).** With the `frame` argument the OS surfaces Writing Tools, but its **Rewrite/Replace write-back into a CodeMirror contenteditable surface is unreliable** (proofread/summarize *display* works; in-place replace commonly degrades to copy-only — a known Chromium contenteditable limitation). **Build-time test item:** verify Rewrite-replace against the live CM6 surface; if it fails, accept display-only. Recovering reliable replace would require a WKWebView rebuild (off the table).
  - **Translate — not available.** macOS native Translate isn't reachable from Electron/Chromium without abandoning Chromium for WKWebView. Not feasible in this build.
  - **Custom HTML menu rejected for right-click.** A styled in-app menu would forfeit every OS system item (Look Up, Services, Share, spelling, Writing Tools) and the native feel — the opposite of the goal. Reference `electron-context-menu` (sindresorhus) for the spelling/search-with patterns; don't depend on it (it doesn't model deep custom submenus or the `frame` wiring — exactly our custom parts).
  - **Recommended complement (optional, beyond Swift): a slash menu + selection bubble toolbar** for the *rich/delightful* formatting affordances (icons, live previews, custom layout) — rendered in the renderer where pixel control is wanted. This is how Notion/Linear/Obsidian split it: the OS context menu stays native for system integration; the opinionated formatting UI lives in custom CM6 surfaces. Out of the core port's scope; a natural follow-on if we want formatting flourish the native menu can't express.

---

### 9. Deferred + deliberate extensions

**Deliberate extension beyond Swift** (Nathan-directed): **`::` callouts** (§11). A conscious addition, not a port.

**Deferred:**
- **Table engine** — the interactive grid, inline cell editors, row/column drag-reorder, and the vendored `md-advanced-tables` core are all **deferred for now**. Tables ship out-of-the-box: styled GFM with hidden pipes/separator + inline text editing (§5). The engine is a clean later add (the research is captured in `History.md`/this doc's git history if revived).

- **Wikilink resolver wiring** (click routing + rename cascade) — pending the Pommora-side resolver.
- **Latex math rendering** + **code syntax highlighting** — seams ship with no-op defaults; real renderers opt in later.
- **Image embed provider** — seam present, provider later.
- **Find-in-document UI** — over CM6's search.
- **Column directives / slash menu**, **block editor / Homepage widgets** — net-new vs Swift; out of scope for now.

---

### 10. Module shape — human-legible structure

One folder per concern, plainly named. Appearance is consolidated in a single `Styles.css`; the behavior layer is framework-free logic.

```
src/renderer/src/MarkdownPM/
  Styles.css       // THE stylesheet — all construct appearance; every colour/fill/border resolves from
                   // root tokens via the --var bridge (DRY: no literals the token layer already owns)
  index.ts         // public front door — the <MarkdownEditor> React component

  parser/          // parser seam: mdast AST + per-line confirm + helper queries (isInsideCode, isInsideWikilink…)
  detect/          // detection rules (regex + AST) — one shared helper per construct
  tokens/          // token model (kind, range, contentRange, markerRanges) + active-token (caret-aware) computation
  decorations/     // maps detected tokens → CM6 decorations: which Styles.css class, which widget
  input/           // typing transforms: list continuation, smart-backspace, auto-pair, bracket-skip,
                   //   dash/arrow, checkbox canonicalize, Enter/Shift+Enter
  callouts/        // the :: ⇄ > [!type] codec — the swappable on-disk format lives here only
  widgets/         // the DOM/React widgets: checkbox, HR, blockquote box, callout box, code-copy,
                   //   fold-chevron, image, latex (no table widget — tables are styled text, not a grid)
  services.ts      // host seams (wikilink resolver, image, latex, syntax highlight) + no-op defaults
  constants.ts     // the few non-CSS numbers logic needs (nesting cap, debounce…); regexes live in detect/
  editor/          // CM6 wiring: state/transactions/selection, the decoration plugin, native-menu trigger
```

**Layer split:** the behavior layer (`parser`, `detect`, `tokens`, `decorations` mapping, `input`, `callouts` codec, `services`, `constants`) is framework-free and unit-testable without CM6. `Styles.css`, `widgets/`, and `editor/` are the only CM6/DOM-aware parts. Appearance is in `Styles.css` alone — the logic only ever assigns class names. Test the behavior layer with a corpus mirroring the Swift `MarkdownPMTests/` suites (tokenizer, input-transform, styled-range, heading/HR parity).

---

### 11. Callouts (`::`) — beyond Swift (Nathan-directed)

The one construct that goes past what Swift shipped. It keeps canonical, portable source — the extension is in the *editing experience + render*, not a non-portable on-disk format.

A line beginning with `::` turns its block into a **bordered container** (Notion-style: a border-styled box around the text block), behaving like blockquote in that the render follows the whole block — but as a full box rather than a left-bar card.

- **Render (locked intent):** a bordered, rounded container box around the block's content, with interior padding. **Separators (`---`) inside a callout are bounded to the callout's inner content box** — they inset to the container's padded width and stop at its borders, rather than spanning the page gutters. (This "child separators respect the container, not the page" rule likely generalizes to other contained constructs later.) The marker is hidden in render; the box is an always-show overlay (like blockquote, not caret-aware).
- **On-disk syntax — DECIDED (provisional, swappable).** `::` at line start is an **input shorthand**, not the on-disk format. It canonicalizes to the portable Obsidian callout form **`> [!type]`** (default type `note`) on disk — mirroring the `-[]` → `- [ ]` checkbox canonicalization precedent (§6.4). So: you type `::`, the file stores `> [!note]` + `> ` continuation lines, Pommora renders a Notion-style box, and Obsidian/Bear/GitHub render a real callout. Portability preserved.
  - **Continuation** follows the blockquote model (the canonical form *is* a blockquote variant): Enter continues with `> `, Shift+Enter exits.
  - **Swappability (Nathan: "make sure we can change this").** The on-disk format is provisional. Isolate it behind one **callout codec** (the `::`→canonical transform in one input handler; detection + read/write of the stored form in one place) so switching the stored format later (e.g. to a `::`-native or `:::`-fenced form) touches the codec only — never the renderer or the rest of the behavior layer. Detection consumes the canonical form, not the `::` shorthand.
- **Callout variants** (note / warning / info — each a border tint + icon, off the `[!type]` tag) are a natural follow-on; the codec already carries `type`, so variants are render-only additions.
