### Page Editor

Pommora's body editor for Pages — what the user sees and types into when they click a Page row in the sidebar. Data-model concerns (on-disk shape, frontmatter, opening behavior, sidebar disclosure) live in [`Pages.md`](Pages.md); this file covers the editor surface itself.

The editor runs on a native TextKit-2 stack. **HOW the editor's constructs are built** — the dynamic-syntax architecture, detection rules, state-mutation guards, anti-patterns, engine quirks, and every Nathan-locked editor decision (date-stamped) — is the contract in [`// Guidelines//Markdown.md`](../Guidelines/Markdown.md); read it first when implementing any construct. This spec records only WHAT the editor currently ships and its visible surface.

---

#### Library

| Layer | Source |
|---|---|
| **Parser** | Apple **`swift-markdown`** 0.8.0 — full GFM AST including BlockQuote, Table, ThematicBreak, Strikethrough, Strong, Emphasis, Heading, lists, code, links, images, line/soft breaks, HTMLBlock, BlockDirective. SPM dep on `swiftlang/swift-markdown`. |
| **Renderer** | Apple **`NSAttributedString` + `NSTextView` + `NSTextLayoutManager`** — font, color, paragraph styling, link rendering, selection, find, native context menu, Writing Tools (15.1+), spell-check, autocorrect, IME, drag-select all free. |
| **Live-preview chassis** | **`swift-markdown-engine`** (vendored as a local Swift Package at [`External/MarkdownEngine/`](../../External/MarkdownEngine/), upstream `nodes-app/swift-markdown-engine`, Apache 2.0, Swift 5.9). Contributes the two load-bearing features Apple's bare NSTextView doesn't ship: **dynamic syntax** (markers shrink when caret leaves AST node, expand when entered — Bear/Notion/iA Writer pattern) + **Markdown-aware typing helpers** (list continuation; block auto-wrap for `$$`/`![[`; character-pair auto-pair added Pommora-side). |
| **Apple-AST supplemental styling** | Pommora-side `AppleASTSupplementalStyler` in the vendored engine — walks `Document(parsing:)` for BlockQuote / Strikethrough / Table / ThematicBreak and composes attributes on top of the engine's primary regex tokenizer/styler. |
| **Domain wiring** | `PageRef`, `PageFile`, `PageContentManager.updatePage`, `PageEditorViewModel`, `PageEditorHost`, `AppGlobals`, inspector + sidebar wiring — editor-library-agnostic. |

Engine vendoring rationale + per-file modification log → `// Guidelines//Markdown.md` §1.2 + `External/MarkdownEngine/NOTICE.md`.

---

#### Layout

`PageEditorView` ([Pommora/Pommora/Pages/PageEditorView.swift](../../Pommora/Pommora/Pages/PageEditorView.swift)) is a `ZStack(alignment: .topLeading)` of two layers:

1. **Body `NativeTextViewWrapper`** (bottom layer) — from the vendored engine. `textInsets` apply 24pt horizontal (so body text aligns under the title's padding) + a 90pt vertical inset that reserves a scrollable empty zone at the top of the text container for the title overlay.
2. **Title + divider overlay** (top layer) — a 28pt-bold plain `TextField` matched to macOS Notes' large title line, above a 1pt system-separator divider. The overlay tracks body scroll via `.offset` so the title scrolls in sync with the body and moves off-screen once scrolled past. Pressing Enter commits the rename and hands focus to the body editor.

The inspector + its toolbar toggle live in `ContentView`, not here — so the inspector renders at the window's trailing edge rather than inside this sub-view. A cover-image / banner drops into the same overlay VStack above the title with no engine changes.

The Page-editor titlebar carries no properties pulldown — page properties surface via the pop-out inspector pane, and the main-window inspector slot is reserved for the Claude chat interface (see [`Prospects.md`](Prospects.md)).

---

#### Save pipeline (load-bearing — preserves "files are canonical")

Keystroke → `viewModel.body` `didSet` → `scheduleSave()` 300ms debounce → `PageContentManager.updatePage(_:body:in:vault:)` (or `inVaultRoot:`) → reconstructs `PageFile(frontmatter:body:title:)` → `AtomicYAMLMarkdown.write(frontmatter:body:to:)` (atomic temp-file + rename) → in-memory cache updates.

**Flush on context loss:** page-switch (`PageEditorHost` awaits `old.close()`), window-close (`PageEditorView.onDisappear`), `NSApplication.willResignActiveNotification`, `willTerminateNotification`, `⌘S` (`explicitSave`).

**Frontmatter preservation rule:** the editor binds ONLY to `body` (pure Markdown — YAML stripped by `AtomicYAMLMarkdown.load` before reaching the editor). Frontmatter is held in `viewModel.page.frontmatter` and re-serialized on save from the typed struct, never from a string-prefix. **The user cannot destroy frontmatter via the editor; YAML is never visible.**

**Failure handling:** the `pendingError` alert in `PageEditorView.body` (Retry / OK); draft body preserved; retry re-schedules.

---

#### Editable title flow

The title `TextField` is structurally separate from the body editor. On Enter:

1. `titleFocused = false` — drops the title's first-responder claim cleanly (otherwise NSTextField's default Enter behavior selects-all + stays focused).
2. `focusBodyEditor()` — walks `NSApp.keyWindow.contentView` for the first `NSTextView` (the sidebar uses `NSTextField`, so this is safe) and makes it first responder.
3. `Task { await commitRename() }` — async in parallel: `PageContentManager.renamePage` → on-disk `.md` file move → `PageMeta` cache refresh → `viewModel.page = updated`. Doesn't block the focus shift.

If `commitRename` fails (e.g. name collision), `pendingError` fires the alert and the title draft reverts to the previous value.

---

#### Current editor surface

What the editor renders and supports today.

**Inline marks** (engine regex tokenizer + caret-aware marker-shrink):
- Bold (`**` / `__`), italic (`*` / `_`), bold-italic (`***`), inline code (`` ` ``)
- Wikilinks (`[[Name]]`) — rendered as styled inline text; click resolution lands with the Pommora-side resolver (see Deferred)
- Standard Markdown links (`[text](url)`)
- Image embeds (`![[name]]`) — render hook present; Pommora-side image provider deferred

**Block constructs** (engine + Apple-AST supplemental):
- Headings (`#`–`######`; H5/H6 render under body size and are omitted from the right-click menu). **Foldable** — hover a heading line to reveal a gutter chevron; click toggles a zero-height collapse of the section down to the next equal-or-higher heading (or document end). Fold state persists per-Page in frontmatter (`folded_headings`).
- Bullet + ordered lists, with portable CommonMark source (`- item`). A `•` glyph renders over the `-` marker; source on disk stays `-` for portability.
- **Task-list checkboxes** — GFM `- [ ]` / `- [x]` and Pommora `-[]` / `-[x]` shorthand both accepted. An SF Symbol glyph draws in place of the bracket marker; clicking it toggles the source. Source on disk stays whatever the user typed (no auto-canonicalization).
- Fenced code blocks (` ``` `)
- Inline + block LaTeX (`$..$` / `$$..$$`) — marker-shrink behavior ships; math rendering deferred.
- **Blockquote** (`>`) — grey-tint rounded card + continuous vertical accent bar; multi-paragraph quotes join into one contiguous block. Plain Enter continues the quote; Shift+Enter exits.
- **Strikethrough** (`~~text~~`)
- **Table** (GFM `| col | col |`) — parsed and styled (monospace + faint background; pipes hidden; separator row hidden). The rich Apple-Notes-style inline grid + cell-editing UX is **paused** (see "Tables" below).
- **Thematic break / HR** (`---` on its own line) — renders as a horizontal line when the caret is off the line; the literal `---` becomes visible for editing when the caret enters it. Pommora rejects the Setext-H2 interpretation of `---`.

**Typing helpers:**
- List continuation (Enter at end of `- item` auto-fills the next marker, preserving indent + checkbox).
- Block auto-wrap (typing adjacent to `$$..$$` / `![[..]]` keeps the block on its own line).
- Character-pair auto-pair + auto-delete for `**` / `__` / `[[` / `` ` `` (single `[` only auto-pairs at whitespace / line start so `-[]` flows cleanly).
- Bracket-skip on Enter (caret between a matched pair jumps past the closer).
- Dash auto-format (`--` → em-dash, ` - ` → en-dash; en→em promotion) and arrow auto-format (`<-` → `←`, `<->` → `↔`), input-time only — paste preserves the literal text.

**Right-click menu** (engine base + Pommora extensions): standard system items (Cut/Copy/Paste, Spelling, Substitutions, Speech, Look Up, Translate, Writing Tools on 15.1+) plus Format (Bold/Italic/Strikethrough/Inline Code/Link), Heading (H1–H4), Lists (Bullet/Numbered), and Block (Blockquote/Code Block/Table/Horizontal Rule) submenus.

**System integration** (free via NSTextView): Writing Tools (15.1+), Look Up, Translate, spell/grammar/autocorrect with per-token suppression for code/LaTeX, IME, dynamic light/dark colors, drag-to-select. Find-in-document highlighting bus is present; the Pommora-side find palette is deferred.

---

#### Tables — to be implemented

Tables are a **major future deliverable**, not a polish pass. Pommora is just getting started, and proper Apple-Notes-style inline-grid tables (drag-resize columns, double-click popover cell editor, structural context menu for add/delete row/column + cell alignment) are a real named feature on the roadmap.

**Current ship:** GFM `| col | col |` syntax parses and renders with monospace + faint background + hidden pipes + hidden separator row. No grid alignment, no editing affordances, no drag-resize.

**Target experience:** inline grid that looks and feels like Apple Notes' table — cell-by-cell alignment, drag-to-resize column widths, double-click any cell for a popover editor, right-click for structural operations.

**Central open question — inline-column alignment.** With unpadded source laid out as inline text in TextKit 2, cells don't visually align unless source is padded to equal column widths. `NSTextTable` is rejected — it forfeits Writing Tools / Look Up / dynamic-color and forces a TextKit-1 downgrade (`// Guidelines//Markdown.md` §1.3 + §6.10). Nathan's locked direction (`// Guidelines//Markdown.md` §9.2 + §9.6): source on disk stays uniformly padded via `Markup.format()`, column widths live in frontmatter, the render layer applies overrides — but making *inline* layout honor custom widths is non-trivial. Three candidate strategies (A / B / C / hybrid) remain open; the decision waits on accumulated experience with other editor features.

**Independently shippable pieces** that don't depend on the alignment question: the popover cell editor (hosts its own column-aligned SwiftUI Grid) and the structural context menu. Those can land while the inline-grid architecture is still being decided.

> The `pommora_table_widths` frontmatter key is grandfathered per the CLAUDE.md "Pommora prohibited in on-disk schemas" rule; rename when Tables ship.

---

#### Deferred

Future direction lives in [`Framework.md`](../Framework.md); the changelog of what shipped when lives in [`History.md`](../History.md). Editor work not yet wired:

- **`PommoraWikiLinkResolver`** — Pommora-side conformance to the engine's `WikiLinkResolver`; unblocks wikilink autocomplete + click routing + rename cascade (couples with the SQLite layer).
- **`:::callout` + `@Columns` directives** + **slash menu** — via Apple `BlockDirective`; the editor is functional without them.
- **HighlighterSwift bridge** (code-block syntax highlighting) and **SwiftMath bridge** (LaTeX rendering) — the engine ships no-op service defaults; both are opt-in.
- **Pommora-brand theme overlay** — the engine currently uses SwiftUI semantic colors; brand purple + custom callout treatments land with `Color+Pommora.swift`.
- **Image embed provider** — Pommora-side `EmbeddedImageProvider` so `![[name]]` resolves to disk images.
- **Find-in-document UI** — Pommora-side find palette over the engine's existing find bus.
- **Auto-pair polish** — selection-wrap (typing `*` around a selection) + auto-exit-on-whitespace.

---

#### Hot-swap surface

If the editor library ever needs replacing again, the swap surface is:

- **`.md` file format** — the firewall; never changes regardless of editor library.
- **`PageEditorViewModel` ↔ `PageContentManager` chain** — domain layer, editor-library-agnostic.
- **`AtomicYAMLMarkdown` write contract** — survives any editor.
- **Apple swift-markdown AST** — portable across editor choices; the styler logic moves to a new library by re-implementing the rendering layer.

The only Pommora-side editor-coupled code is the `NativeTextViewWrapper` call site in `PageEditorView.swift` (~10 lines) plus the Pommora customizations inside the vendored engine (`Styling/AppleASTSupplementalStyler.swift` + extensions to `Input/MarkdownInputHandler.swift`, `Renderer/MarkdownTextLayoutFragment.swift`, `TextView/ContextMenu.swift`).
