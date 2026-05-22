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
- Wikilinks (`[[Name]]`) — rendered as styled inline text; click resolution via engine's `WikiLinkResolver` service (Pommora-side resolver lands at v0.3.2 — wikilinks moved from v0.2.10 → v0.3.2 RC-2026-05-19 to couple with SQLite at v0.3.3)
- Standard Markdown links (`[text](url)`)
- Image embeds (`![[name]]`) — rendered via engine's `EmbeddedImageProvider` service (Pommora-side provider deferred)

**Block constructs** (mix of engine + Apple-AST supplemental):
- Headings (`#` through `######` — engine handles; H1-H6 all parse; H5/H6 omitted from right-click menu since they render under body size)
- Bullet + ordered lists (engine's `MarkdownLists` + `MarkdownListHandler` for typing-time helpers)
- Fenced code blocks (` ``` `)
- Inline + block LaTeX (`$..$` / `$$..$$`) — markers-shrink behavior ships; actual math rendering deferred (HighlighterSwift + SwiftMath bridges opt-in later)
- **BlockQuote** (`>`) — *(Apple-AST supplemental)* dimmed text + bg tint + 20pt indent. **Apple-Calendar-event-card chrome** (grey rounded card + 3pt vertical accent bar inside; per-fragment corner-rounding for multi-line continuity; `BlockquoteMetadata` struct attribute payload; mirrors `drawCodeBlockBackground`'s CGPath + bg-fill pattern) — deferred to **v0.2.7.2** (Round 6 visual target supersedes earlier Apple-Notes-minimal-bar plan).
- **Strikethrough** (`~~text~~`) — *(Apple-AST supplemental)* via `NSAttributedString.Key.strikethroughStyle`.
- **Table** (GFM `| col | col |`) — *(Apple-AST supplemental)* monospace font + faint bg tint on the table range; `|` pipes hidden via font-0.1 + clear color; separator row (`|---|---|`) fully hidden. **Apple-Notes-style real grid** (Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` + drag-resize column dividers + `pommora_table_widths` frontmatter persistence + double-click NSPopover hosting SwiftUI Grid with editable TextField cells + right-click structural add-row/add-column context menu) deferred to **v0.2.7.2**. NSTextTable rejected — Apple's own TextEdit downgrades to TextKit 1 to use it; Notes uses custom protobuf rendering.
- **ThematicBreak / HR** (`---` on own line) — *Originally* shipped at v0.2.7.0 as Apple-AST supplemental styling + `MarkdownTextLayoutFragment.drawThematicBreak` (dashes hidden, real 1pt horizontal line drawn). **Reimplemented at v0.2.7.2 with Obsidian-style dynamic syntax** — see "Dynamic-syntax pattern" section below for the new architecture and lessons learned. Current shipped behavior: `---` always renders as a horizontal line when the caret is NOT on the line (regardless of context above — Pommora explicitly rejects Setext H2 interpretation); when the caret IS on the line, the literal `---` text becomes visible for editing.

**Typing helpers:**
- **List continuation** (engine ships): Enter at end of `- item` → next line auto-fills with `- ` (or `1.` → `2.` for ordered, including indent + checkbox preservation).
- **Block auto-wrap** (engine ships): typing adjacent to `$$..$$` or `![[..]]` auto-inserts newlines so the block stays on its own line.
- **Character-pair auto-pair** (Pommora-added): typing the 2nd char of `**`/`__`/`[[`/`` `` `` inserts the matching close with caret between (e.g. `**|**`). Suppressed inside code blocks + when next char is already the close marker. **Single `[`** only auto-pairs when the preceding char is whitespace or the cursor is at line start (v0.2.7.4) — so `-[` can continue cleanly into `-[]` task syntax without the auto-pair stealing input; prose-link case (`text [link]`) still fires normally.
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

#### v0.2.7.x patch status

| Patch | Status | Scope |
|---|---|---|
| **v0.2.7.1** | ✅ SHIPPED 2026-05-19 | NavDropdown (Liquid Glass dropdown nav — Pinned + Recents tabs, single-click select / double-click open, right-click Pin/Unpin context menu, back/forward arrows, per-nexus `state.json` persistence). See [NavDropdown.md](NavDropdown.md). |
| **v0.2.7.2** | 🟡 PARTIAL SHIP 2026-05-20 | **HR / divider — SHIPPED** (Session 12 — Obsidian-style dynamic syntax; see "Dynamic-syntax pattern" section below). **Lists — SHIPPED** (Session 13 — space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source `- item` / `* item` / `+ item`; `firstLineHeadIndent` visual indent; `bareMarkerRegex` + `ListContext` + `detectListContext` AST-backed; bullet glyph substitution attempted + reverted, deferred as a known caveat). **Blockquote — DEFERRED** to a later patch (will use the same dynamic-syntax architecture; Apple-Calendar-event-card visual target preserved). **Tables — DEFERRED** to a later patch (estimated 10-15h with hotfix iterations; "ASAP but not immediate" per Nathan's call). **Auto-transform on 3rd dash — DROPPED** from scope (Enter is the natural trigger via dynamic syntax). **Cursor-atom workaround — DROPPED** (dynamic syntax eliminates the need). **Right-click "Insert HR" — out of scope** this patch. Original plan still at [`// Planning//Page-Editor-Plan.md`](../Planning/Page-Editor-Plan.md) for the blockquote + tables visual specs. |
| **v0.2.7.4** | ✅ SHIPPED 2026-05-21 | **HR jitter fix.** Two-phase: (a) `syncHRVisibility` no longer walks the full document on every caret tick — a new scoped overload touches only `{currentCaretParagraph, priorCaretParagraph}`; full walks stay on `restyleTextView` + `rebuildTextStorageAndStyle`. (b) HR caret-aware reveal/hide is now layout-constant — dashes always render at `bodyFont`, only foreground color toggles (`bodyColor` ↔ `NSColor.clear`); same paragraph style applies in both states with `paragraphSpacing = max(0, 16 - bodyLineHeight / 2)` preserving the original ~16pt visual margin around the drawn rule line. Eliminates the vertical "auto-adjust" jitter on caret enter/leave. **Bullet glyph SHIPPED** (closes Session 13 deferral) — `- ` lines render `•` via `MarkdownTextLayoutFragment.drawDashBulletGlyph` overlay; source on disk stays `- item` for portability; only `-` triggers (`*` / `+` / `•` render literally); pixel-aligned via `backingScaleFactor`. **Task shorthand `-[]` / `-[x]` accepted** alongside GFM `- [ ]` / `- [x]`. **Bracket auto-pair guard** — `[` only auto-pairs when preceded by whitespace or at line start, so `-[]` flows cleanly. **Arrow auto-format** — typed `<-` → `←` and `<->` → `↔` now fire on input (was paste-only); closes the Session 13 known bug. **Code colors** — text `NSColor.systemRed.withAlphaComponent(0.85)`, background `NSColor.quaternaryLabelColor`. |
| **v0.2.7.x (later)** | QUEUED | Blockquote rendering (Apple-Calendar-event-card chrome). Code & quote `Enter}` auto-completion. Tables (ASAP but realistic estimate 10-15h after divider iteration experience). Sidebar + Vault/Collection drag-to-reorder. PreviewWindow primitive build. Phase 4.5 auto-pair polish. Phase 3 engine AST rewrite. No specific patch number assignments — pick what's next at session time. |

---

#### Dynamic-syntax architecture

The architectural rules for paragraph-level constructs with hide-when-out / reveal-when-in markers (HR, future Blockquote, etc.) live in **[`// Guidelines//Markdown.md`](../Guidelines/Markdown.md)**:

- Section 3 — the locked three-piece architecture (renderer / service / styler)
- Section 4 — detection rules (three-stage prefilter + AST)
- Section 5 — state-mutation rules (`isProgrammaticEdit`, reentry guards, atomic write contract)
- Section 6 — anti-patterns to avoid (with the historical context of each burn)
- Section 8 — lessons L1–L10 with file:line citations

That document is the canonical source for HOW to build constructs of this family. This feature spec only records WHAT the editor currently ships and its visible surface (above). When implementing a new construct, read Markdown.md first — it's the contract.

##### Known caveat (acceptable; not chasing)

- **First HR appears slightly dimmer than subsequent HRs.** Almost certainly sub-pixel anti-aliasing from the first paragraph's fractional Y position. `.rounded()` snap was tested and did NOT resolve. Punted. If it bothers in practice, next investigation should test `NSScreen.backingScaleFactor`-aware half-pixel snapping (the simple integer round we tried was insufficient on retina), or explicit `CGContextSetShouldAntialias(false)` on the line draw to force a crisp hairline regardless of position.

---

#### Deferred beyond v0.2.7.x

- **Phase 3 substantive (engine internal)** — wholesale-rewrite `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. The h.8 supplemental styler covers BlockQuote/Strikethrough/Table/ThematicBreak rendering as a starter on top; the full body swap would unify everything onto Apple AST. Lower priority — engine works as-is.
- **Phase 4.5 polish** — auto-pair selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace (typing space at fresh-pair boundary jumps past close marker) + the 11-test auto-pair test suite.
- **`PommoraWikiLinkResolver`** — Pommora-side `WikiLinkResolver` conformance. **v0.3.2 wikilink** autocomplete + click routing + rename cascade depends on this (moved from v0.2.10 → v0.3.2 RC-2026-05-19 to couple with SQLite at v0.3.3); will extend engine's `WikiLinkService` two-form storage transform (`[[Name|<id>]]` ↔ `[[Name]]`).
- **`:::callout` and `@Columns` directives** — originally scoped for v0.2.9; **v0.2.9 unscheduled** (removed from active v0.2.x sequence RC-2026-05-19 — page editor is functional without them). Re-homes to a later v0.2.x patch, or post-v0.3.x. Via Apple `BlockDirective`. Foldable headings + slash menu also in the same deferred bundle.
- **HighlighterSwift bridge** — code-block syntax highlighting. Opt-in later if Pommora needs it; engine's `SyntaxHighlighter` service has a no-op default.
- **SwiftMath bridge** — LaTeX rendering. Same opt-in pattern; engine's `LatexRenderer` service has a no-op default.
- **Pommora-brand theme overlay** — engine currently uses SwiftUI semantic colors via default `MarkdownEditorConfiguration.theme`. Pommora-brand purple + custom callout treatments land with `Pommora/Pommora/Color+Pommora.swift` (alongside `Assets.xcassets`; post-v1 design lock).
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
