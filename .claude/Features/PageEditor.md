### Page Editor

Pommora's body editor for Pages — what the user sees and types into when they click a Page row in the sidebar. Data-model concerns (on-disk shape, frontmatter, opening behavior, sidebar disclosure) live in [`Pages.md`](Pages.md); this file covers the editor surface itself.

**Shipped at v0.2.7.0** (2026-05-18; `origin/main` tag `v0.2.7.0` at SHA `9a0b383`) on a native TextKit-2 stack after pivoting away from an initial WKWebView fork attempt that didn't deliver the macOS-native feel Pommora needs.

---

#### Library

| Layer | Source |
|---|---|
| **Parser** | Apple **`swift-markdown`** 0.8.0 — full GFM AST including BlockQuote, Table, ThematicBreak, Strikethrough, Strong, Emphasis, Heading, lists, code, links, images, line/soft breaks, HTMLBlock, BlockDirective. SPM dep on `swiftlang/swift-markdown`. |
| **Renderer** | Apple **`NSAttributedString` + `NSTextView` + `NSTextLayoutManager`** — font, color, paragraph styling, link rendering, selection, find, native context menu, Writing Tools (15.1+), spell-check, autocorrect, IME, drag-select all free. |
| **Live-preview chassis** | **`swift-markdown-engine`** (vendored as a local Swift Package at [`External/MarkdownEngine/`](../../External/MarkdownEngine/), upstream `nodes-app/swift-markdown-engine@e683a62`, Apache 2.0, 46 source files, Swift 5.9). Contributes the two load-bearing features Apple's bare NSTextView doesn't ship: **dynamic syntax** (markers shrink when caret leaves AST node, expand when entered — Bear/Notion/iA Writer pattern) + **Markdown-aware typing helpers** (list continuation; block auto-wrap for `$$`/`![[`; character-pair auto-pair added Pommora-side). |
| **Apple-AST supplemental styling** | Pommora-side `AppleASTSupplementalStyler` in the vendored engine — walks `Document(parsing:)` for BlockQuote / Strikethrough / Table / ThematicBreak and composes attributes on top of the engine's primary regex tokenizer/styler. |
| **Domain wiring** | Survives unchanged from Phase A-G: PageRef, PageFile, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, inspector + sidebar wiring. All 197 v0.2.7 tests pass against the unchanged domain layer. |

The engine is vendored as a **local Swift Package** rather than raw source files in Pommora's main target because Pommora is Swift 6 + strict concurrency + ExistentialAny; the engine targets Swift 5.9. The package boundary isolates the engine's concurrency contract. Pommora fully owns the vendored copy and can edit any file (see `External/MarkdownEngine/NOTICE.md` for the per-file modification log).

---

#### Layout

`PageEditorView` ([Pommora/Pommora/Pages/PageEditorView.swift](../../Pommora/Pommora/Pages/PageEditorView.swift)) is a VStack with two members:

1. **Title TextField** — 28pt bold, plain style, 24pt horizontal padding + 24pt top + 20pt bottom padding. `.background(Color.clear)` defends against window-bg paint-over. Pressing Enter calls `commitRename` (in-flight title → `ContentManager.renamePage` → on-disk `.md` file move + cache refresh) AND hands focus to the body editor (`@FocusState` toggle + `NSApp.keyWindow` first-NSTextView walk + `makeFirstResponder`).
2. **Body `NativeTextViewWrapper`** — from the vendored engine. Configured with `textInsets: TextInsets(horizontal: 24, vertical: 0)` so body text aligns under the title's 24pt padding (applied inside the NSTextView via `textContainerInset`, NOT as SwiftUI padding, so the scrollbar stays at the outer edge).

The inspector + its toolbar toggle live in `ContentView`, not here — so the inspector renders at the window's trailing edge rather than inside this sub-view.

---

#### Save pipeline (load-bearing — preserves "files are canonical")

Keystroke → `viewModel.body` `didSet` → `scheduleSave()` 300ms debounce → `ContentManagerPageSaver.save` → `ContentManager.updatePage(_:body:in:vault:)` (or `inVaultRoot:`) → reconstructs `PageFile(frontmatter:body:title:)` → `AtomicYAMLMarkdown.write(frontmatter:body:to:)` (atomic temp-file + rename, v0.2.5 project standard) → in-memory cache updates.

**Flush on context loss:** page-switch (`PageEditorHost.task(id:)` awaits `old.close()`), window-close (`PageEditorView.onDisappear`), `NSApplication.willResignActiveNotification`, `willTerminateNotification`, `⌘S` (`explicitSave`). All paths existing and untouched from Phase B.

**Frontmatter preservation rule:** Editor binds ONLY to `body` (pure Markdown — YAML stripped by `AtomicYAMLMarkdown.load` before reaching the editor). Frontmatter is held in `viewModel.page.frontmatter` and re-serialized on save from the typed struct, never from a string-prefix. **The user cannot destroy frontmatter via the editor; YAML is never visible.**

**Failure handling:** existing `pendingError` alert pattern in `PageEditorView.body` (Retry / OK buttons); draft body preserved; retry re-schedules.

---

#### What v0.2.7.0 ships

**Inline marks** (engine's regex tokenizer + caret-aware markers-shrink):
- Bold (`**bold**` / `__bold__`)
- Italic (`*italic*` / `_italic_`)
- Bold-italic (`***bold-italic***`)
- Inline code (`` `code` ``)
- Wikilinks (`[[Name]]`) — rendered as styled inline text; click resolution via engine's `WikiLinkResolver` service (Pommora-side resolver lands at v0.2.10)
- Standard Markdown links (`[text](url)`)
- Image embeds (`![[name]]`) — rendered via engine's `EmbeddedImageProvider` service (Pommora-side provider deferred)

**Block constructs** (mix of engine + Apple-AST supplemental):
- Headings (`#` through `######` — engine handles; H1-H6 all parse; H5/H6 omitted from right-click menu since they render under body size)
- Bullet + ordered lists (engine's `MarkdownLists` + `MarkdownListHandler` for typing-time helpers)
- Fenced code blocks (` ``` `)
- Inline + block LaTeX (`$..$` / `$$..$$`) — markers-shrink behavior ships; actual math rendering deferred (HighlighterSwift + SwiftMath bridges opt-in later)
- **BlockQuote** (`>`) — *(Apple-AST supplemental)* dimmed text + bg tint + 20pt indent. Apple-Notes-style rendering (vertical accent bar + heavier bg) deferred to **v0.2.7.1**.
- **Strikethrough** (`~~text~~`) — *(Apple-AST supplemental)* via `NSAttributedString.Key.strikethroughStyle`.
- **Table** (GFM `| col | col |`) — *(Apple-AST supplemental)* monospace font + faint bg tint on the table range; `|` pipes hidden via font-0.1 + clear color; separator row (`|---|---|`) fully hidden. Apple-Notes-style real grid with per-cell borders + click-to-edit deferred to **v0.2.7.3**.
- **ThematicBreak / HR** (`---` on own line) — *(Apple-AST supplemental + custom `MarkdownTextLayoutFragment.drawThematicBreak`)* dashes hidden, real 1pt full-width horizontal line drawn in `NSColor.separatorColor` at 80% alpha. Auto-transform-on-typing lock + inset visual width deferred to **v0.2.7.1**.

**Typing helpers:**
- **List continuation** (engine ships): Enter at end of `- item` → next line auto-fills with `- ` (or `1.` → `2.` for ordered, including indent + checkbox preservation).
- **Block auto-wrap** (engine ships): typing adjacent to `$$..$$` or `![[..]]` auto-inserts newlines so the block stays on its own line.
- **Character-pair auto-pair** (Pommora-added): typing the 2nd char of `**`/`__`/`[[`/`` `` `` inserts the matching close with caret between (e.g. `**|**`). Suppressed inside code blocks + when next char is already the close marker.
- **Character-pair auto-delete** (Pommora-added): backspace inside an empty pair (`*|*` / `**|**` / `[[|]]` / `` `|` ``) deletes BOTH halves in a single edit (single undo step).

**Right-click context menu** (engine ships base + Pommora extends):
- Standard items: Cut / Copy / Paste / Spelling & Grammar / Substitutions / Speech / Layout Orientation / AutoFill / Look Up / Translate (macOS 15.1+: Writing Tools)
- **Format submenu**: Bold, Italic, Strikethrough, Inline Code, Link
- **Heading submenu**: H1, H2, H3, H4 (H5/H6 omitted)
- **Lists submenu**: Bullet, Numbered
- **Block submenu**: Blockquote, Code Block, Table (3×3 scaffold with "Header 1" preselected), Horizontal Rule

**System integration** (free via NSTextView):
- Apple Writing Tools (macOS 15.1+ — Compose / Proofread / Rewrite)
- Look Up (system dictionary + Wikipedia)
- Translate
- Spell-check + grammar-check + autocorrect with per-token suppression for code blocks / LaTeX
- IME (any system input source)
- Dynamic system colors (auto light/dark mode)
- Drag-to-select with momentum
- Find-in-document (planned wiring; engine ships `findScrollToRange` + `findClearHighlights` bus notifications)

---

#### Editable title flow

The title TextField at `PageEditorView.swift:54-64` is structurally separate from the body editor. On Enter:

1. `titleFocused = false` (SwiftUI `@FocusState` — drops the title's first-responder claim cleanly, otherwise NSTextField's default Enter behavior would select-all + stay focused)
2. `focusBodyEditor()` — dispatches async, walks `NSApp.keyWindow.contentView` view tree for the first `NSTextView` (sidebar uses `NSTextField`, so this is safe), calls `window.makeFirstResponder(bodyEditor)`
3. `Task { await commitRename() }` — async in parallel: `ContentManager.renamePage` → on-disk `.md` file move → PageMeta cache refresh → `viewModel.page = updated`. Doesn't block the focus shift.

If `commitRename` fails (e.g. name collision), `pendingError` is set and the alert at `body` fires. Title draft reverts to the previous value.

---

#### Deferred to v0.2.7.x patches

| Patch | Scope |
|---|---|
| **v0.2.7.1** | Page editor touch-ups. **Blockquote** real Apple-Notes-style rendering (vertical accent bar + heavier bg via new `MarkdownTextLayoutFragment.drawBlockquote`; mark ranges with new `.pommoraBlockquote: true` attribute from `AppleASTSupplementalStyler.visitBlockQuote`). **HR** three small fixes — auto-transform lock on typing (hook into `MarkdownInputHandler.shouldChangeTextIn` chain), inset visual width by `textInsets.horizontal`, color confirm. Both replicable from native Apple behavior, not research-grade. |
| **v0.2.7.2** | NavDropdown (Liquid Glass dropdown nav). See [NavDropdown.md](NavDropdown.md). Note: NavDropdown.md currently says v0.2.8; Nathan's Session-9 sequencing puts it at v0.2.7.2 — needs reconciliation. |
| **v0.2.7.3** | Tables custom — Apple-Notes-style real grid with per-cell borders + click-to-edit. Custom `NSTextLayoutFragment` subclass that detects Apple-AST `Table` source ranges + replaces drawing with a true grid. Substantial TextKit-2 work. |
| **v0.2.7.4** | Sidebar re-ordering + drag (not strictly editor-scoped but in the v0.2.7.x patch family). |

---

#### Deferred beyond v0.2.7.x

- **Phase 3 substantive (engine internal)** — wholesale-rewrite `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. The h.8 supplemental styler covers BlockQuote/Strikethrough/Table/ThematicBreak rendering as a starter on top; the full body swap would unify everything onto Apple AST. Lower priority — engine works as-is.
- **Phase 4.5 polish** — auto-pair selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace (typing space at fresh-pair boundary jumps past close marker) + the 11-test auto-pair test suite.
- **`PommoraWikiLinkResolver`** — Pommora-side `WikiLinkResolver` conformance. v0.2.10 wikilink autocomplete + click routing + rename cascade depends on this; will extend engine's `WikiLinkService` two-form storage transform (`[[Name|<id>]]` ↔ `[[Name]]`).
- **`:::callout` and `@Columns` directives** — v0.2.9 via Apple `BlockDirective`. Foldable headings + slash menu also v0.2.9.
- **HighlighterSwift bridge** — code-block syntax highlighting. Opt-in later if Pommora needs it; engine's `SyntaxHighlighter` service has a no-op default.
- **SwiftMath bridge** — LaTeX rendering. Same opt-in pattern; engine's `LatexRenderer` service has a no-op default.
- **Pommora-brand theme overlay** — engine currently uses SwiftUI semantic colors via default `MarkdownEditorConfiguration.theme`. Pommora-brand purple + custom callout treatments land with `// UI-UX//Design//Color+Pommora.swift` (post-v1 design lock).
- **Image embed provider** — Pommora-side `EmbeddedImageProvider` conforming to the engine protocol so `![[name]]` resolves to disk-resident images.
- **Find-in-document UI** — engine ships `findScrollToRange` + `findClearHighlights` bus notifications; Pommora-side find palette wiring TBD.

---

#### Hot-swap surface

If the editor library ever needs replacing again, the swap surface is:

- **`.md` file format** is the firewall — never changes regardless of editor library
- **`PageEditorViewModel` ↔ `ContentManager` chain** — domain layer; editor-library-agnostic (proven by the v0.2.7 swap: all 197 tests passed unchanged through Pallepadehat → swift-markdown-engine)
- **`AtomicYAMLMarkdown` write contract** — v0.2.5 standard; survives any editor
- **Apple swift-markdown AST** — portable across editor choices; once written, the styler logic moves to a new library by re-implementing the rendering layer

The only Pommora-side editor-coupled code is `PageEditorView.swift` (the `NativeTextViewWrapper` call site, ~10 lines) and the vendored `External/MarkdownEngine/` package (Pommora's customizations live in two files: `Styling/AppleASTSupplementalStyler.swift` + extensions to `Input/MarkdownInputHandler.swift`, `Renderer/MarkdownTextLayoutFragment.swift`, `TextView/ContextMenu.swift`).
