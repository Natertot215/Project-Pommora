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
- Headings (`#` through `######` — engine handles; H1-H6 all parse; H5/H6 omitted from right-click menu since they render under body size). **Foldable** as of v0.2.7.6 — hover any heading line to reveal a chevron in the left gutter; click toggles a true zero-height collapse of the section below (down to the next equal-or-higher heading, or document end). See the v0.2.7.6 row below + `// Guidelines//Markdown.md` §9.11 for architecture.
- Bullet + ordered lists (engine's `MarkdownLists` + `MarkdownListHandler` for typing-time helpers)
- **Task list checkboxes** (`- [ ]` / `- [x]` GFM syntax + `-[]` / `-[x]` Pommora shorthand accepted as of v0.2.7.4). Underlying `[ ]` / `[x]` markers are tagged with the `.taskCheckbox` attribute; an SF Symbol glyph is drawn in their place via `MarkdownTextLayoutFragment.drawTaskCheckboxes`. The leading `-` (and any whitespace) before `[` is collapsed via font 0.1 + clear color so only the drawn glyph shows — the bracket pair itself stays at body font (the checkbox draw reads its `pointSize` from the `[` to compute glyph size; collapsing the brackets would zero out the box). **Glyph:** `square` (unchecked) / `checkmark.square.fill` (checked), `NSImage` with `SymbolConfiguration` at body-font-derived point size. **Sizing:** `min(fontHeight * 1.2, [ ]markerWidth * 1.2)`, pixel-aligned via `backingScaleFactor`. **Tint:** `theme.mutedText` (unchecked) / `theme.accentColor` (checked). **Alignment:** checkbox's visual center aligns to the bullet glyph's visual center on a plain `- ` line (so task lines don't visually shift right relative to bullet lines). **Interaction:** mouseDown on the checkbox glyph toggles `[ ]` ↔ `[x]` in source via `toggleTaskCheckboxIfHit` (a programmatic text-storage edit wrapped in `isProgrammaticEdit`). **Source-edit fallback:** when the user's selection intersects the marker range, the glyph hides itself and the raw `[ ]` / `[x]` text becomes visible — so the user can hand-edit the marker if needed. Source on disk stays whatever the user typed (`- [ ]` GFM or `-[]` Pommora shorthand); no auto-canonicalization. External tools see the GFM form natively; the shorthand variant is Pommora-specific (standard Markdown viewers will display `-[]` as plain text instead of a checkbox).
- Fenced code blocks (` ``` `)
- Inline + block LaTeX (`$..$` / `$$..$$`) — markers-shrink behavior ships; actual math rendering deferred (HighlighterSwift + SwiftMath bridges opt-in later)
- **BlockQuote** (`>`) — ✅ SHIPPED v0.2.7.5 (with one visual TBD: horizontal card-to-bar gap; see `Handoff.md` "Carries to tomorrow"). *(Apple-AST supplemental)* italic-when-content-italic + grey-tint card chrome. **Pattern: always-show overlay** (mirrors bullet glyph + task checkbox; no caret-aware reveal — L14 in `// Guidelines//Markdown.md`). **Source `>` hidden** via font-0.1 + clear-color on `> ` (marker + space) at line start; activation gate requires `>` + space/tab (bare `>` doesn't activate, matching list UX). **Renderer-drawn rounded card** via `MarkdownTextLayoutFragment.drawBlockquoteCard` — `CGPath` + `NSColor.tertiarySystemFill` fill. Selective corner rounding driven by per-fragment `BlockquotePosition` enum (`.only` / `.first` / `.middle` / `.last`) so multi-paragraph quotes butt-joint into one visually-contiguous block. **Continuous vertical accent bar** (4pt wide, `NSColor.secondaryLabelColor`, pill-shaped) — bar Y-extent matches card exactly (both inflated by `cornerRadius = 6pt` on rounded ends so the chrome extends slightly above/below the text). `paragraphStyle.paragraphSpacing = 0` between consecutive quote paragraphs + pixel-snapped y-coords so per-fragment bar segments butt-joint flat. **`paragraphStyle.tailIndent = -8`** for slight right margin. **`paragraphStyle.minimumLineHeight`** (body-font line height) prevents 1pt collapse on empty `> ` lines. **Plain Enter continues** the quote with `\n<prefix>` (preserves leading indent); **Shift+Enter exits** with plain `\n`. Mirrors list convention.
- **Strikethrough** (`~~text~~`) — *(Apple-AST supplemental)* via `NSAttributedString.Key.strikethroughStyle`.
- **Table** (GFM `| col | col |`) — *(Apple-AST supplemental)* monospace font + faint bg tint on the table range; `|` pipes hidden via font-0.1 + clear color; separator row (`|---|---|`) fully hidden. **Apple-Notes-style real grid + drag-resize + popover editor + structural context menu — to be implemented.** Full spec in the "Tables — to be implemented" section below. NSTextTable rejected — Apple's own TextEdit downgrades to TextKit 1 to use it; Notes uses custom protobuf rendering.
- **ThematicBreak / HR** (`---` on own line) — *Originally* shipped at v0.2.7.0 as Apple-AST supplemental styling + `MarkdownTextLayoutFragment.drawThematicBreak` (dashes hidden, real 1pt horizontal line drawn). **Reimplemented at v0.2.7.2 with Obsidian-style dynamic syntax** — see "Dynamic-syntax pattern" section below for the new architecture and lessons learned. Current shipped behavior: `---` always renders as a horizontal line when the caret is NOT on the line (regardless of context above — Pommora explicitly rejects Setext H2 interpretation); when the caret IS on the line, the literal `---` text becomes visible for editing.

**Typing helpers:**
- **List continuation** (engine ships): Enter at end of `- item` → next line auto-fills with `- ` (or `1.` → `2.` for ordered, including indent + checkbox preservation).
- **Block auto-wrap** (engine ships): typing adjacent to `$$..$$` or `![[..]]` auto-inserts newlines so the block stays on its own line.
- **Character-pair auto-pair** (Pommora-added): typing the 2nd char of `**`/`__`/`[[`/`` `` `` inserts the matching close with caret between (e.g. `**|**`). Suppressed inside code blocks + when next char is already the close marker. **Single `[`** only auto-pairs when the preceding char is whitespace or the cursor is at line start (v0.2.7.4) — so `-[` can continue cleanly into `-[]` task syntax without the auto-pair stealing input; prose-link case (`text [link]`) still fires normally.
- **Character-pair auto-delete** (Pommora-added): backspace inside an empty pair (`*|*` / `**|**` / `[[|]]` / `` `|` ``) deletes BOTH halves in a single edit (single undo step).
- **Bracket-skip on Enter** (Pommora-added, v0.2.7.4): when the caret sits between a matched open/close pair on the current line (`[ ]`, `( )`, `{ }`, or `[[ ]]`), pressing Enter jumps the caret past the closer instead of inserting `\n` — so `[[ writing|caret ]]` + Enter lands at `[[ writing ]]|`. Position-based detection (works for auto-paired AND manually-typed/pasted brackets). Gated by `autoClosePairsEnabled`. Carve-out: matched pair inside a list-marker checkbox (`-[x|]`) falls through to list-Enter so the user can continue the list.

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
| **v0.2.7.2** | 🟡 PARTIAL SHIP 2026-05-20 | **HR / divider — SHIPPED** (Session 12 — Obsidian-style dynamic syntax; see "Dynamic-syntax architecture" section below). **Lists — SHIPPED** (Session 13 — space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source `- item` / `* item` / `+ item`; `firstLineHeadIndent` visual indent; `bareMarkerRegex` + `ListContext` + `detectListContext` AST-backed; bullet glyph substitution attempted + reverted, deferred as a known caveat). **Blockquote — SHIPPED v0.2.7.5** (always-show overlay, full architecture in "What v0.2.7.0 ships → BlockQuote" above). **Tables — TO BE IMPLEMENTED** (paused 2026-05-21 per Nathan's call; full spec in "Tables — to be implemented" section below). **Auto-transform on 3rd dash — DROPPED** from scope (Enter is the natural trigger via dynamic syntax). **Cursor-atom workaround — DROPPED** (dynamic syntax eliminates the need). **Right-click "Insert HR" — out of scope** this patch. |
| **v0.2.7.4** | ✅ SHIPPED 2026-05-21 | **HR jitter fix.** Two-phase: (a) `syncHRVisibility` no longer walks the full document on every caret tick — a new scoped overload touches only `{currentCaretParagraph, priorCaretParagraph}`; full walks stay on `restyleTextView` + `rebuildTextStorageAndStyle`. (b) HR caret-aware reveal/hide is now layout-constant — dashes always render at `bodyFont`, only foreground color toggles (`bodyColor` ↔ `NSColor.clear`); same paragraph style applies in both states with `paragraphSpacing = max(0, 16 - bodyLineHeight / 2)` preserving the original ~16pt visual margin around the drawn rule line. Eliminates the vertical "auto-adjust" jitter on caret enter/leave. **Bullet glyph SHIPPED** (closes Session 13 deferral) — `- ` lines render `•` via `MarkdownTextLayoutFragment.drawDashBulletGlyph` overlay; source on disk stays `- item` for portability; only `-` triggers (`*` / `+` / `•` render literally); pixel-aligned via `backingScaleFactor`. **Task shorthand `-[]` / `-[x]` accepted** alongside GFM `- [ ]` / `- [x]`. **Bracket auto-pair guard** — `[` only auto-pairs when preceded by whitespace or at line start, so `-[]` flows cleanly. **Arrow auto-format** — typed `<-` → `←` and `<->` → `↔` now fire on input (was paste-only); closes the Session 13 known bug. **Code colors** — text `NSColor.systemRed.withAlphaComponent(0.85)`, background `NSColor.quaternaryLabelColor`. |
| **v0.2.7.5** | ✅ SHIPPED 2026-05-21 (with rework tomorrow) | **Blockquote chrome** — always-show overlay; renderer-drawn rounded `CGPath` card + continuous vertical pill bar; hidden `>` via font-0.1 + clear-color (`> ` activation gate); position enum for multi-paragraph continuity; `paragraphSpacing = 0`; `tailIndent = -8`; `minimumLineHeight` floor; plain Enter continues (preserves indent), Shift+Enter exits. **Carry-over:** horizontal "highlight not extending into syntax gap" visual mismatch — fix paths documented in `Handoff.md`. Architecture + all other behaviors locked. |
| **v0.2.7.6** | ✅ SHIPPED 2026-05-23 | **Foldable headings.** Hover any heading line → chevron appears in left gutter; click toggles true zero-height collapse down to the next equal-or-higher heading (or document end). **Architecture: element-level elision via `NSTextContentManagerDelegate.shouldEnumerateTextElement:options:`** — `NativeTextViewCoordinator` returns `false` for any `NSTextElement` whose source range intersects a folded range (Apple's documented mechanism for hiding elements from layout — `NSTextContentManager.h` line 112-113). The layout manager iterates via `enumerateTextElements` and our filter takes effect per element: no fragments created for skipped elements, no layout space, and selection / find / spell-check route through the same enumeration so folded content is naturally unreachable. **NOT** the sibling `textContentStorage(_:textParagraphWith:)` method — that's for paragraph substitution and CRASHES if the returned paragraph's length doesn't match `range.length`. **Chevron rotation animates over 200ms ease-in-out**; the fold collapse itself is instant. **Coordinator state pattern** — `foldedHeadings` is a plain stored `var` on the coordinator (NOT `@Binding`), with an `onFoldedHeadingsChanged` callback re-installed on every `updateNSView` so click-handler mutations propagate through the current render's fresh `$viewModel.foldedHeadings` binding. Stale-`@Binding`-on-class was the cause of v0.2.7.6's pre-ship "fold inverts within the same frame" bug: the captured binding desynced after the first SwiftUI re-render and the coordinator-side read returned `[]` while the wrapper-side read returned the mutated value, so `applyFoldStateIfChanged` unfolded what the click handler had just folded. **Layout-cascade trigger** in `invalidateFoldLayout`: `invalidateLayout` → `ensureLayout` → `textLayoutFragment(for:)` hit-test → `viewportLayoutController.layoutViewport()` → `needsDisplay`. Invalidation range extends from fold-start through `documentRange.endLocation` so fragments below the fold reposition upward on SHRINK (`invalidateLayout` only refreshes fragments INSIDE its range; fragments after keep cached positions otherwise). **Persistence:** per-Page frontmatter as `folded_headings: ["## Foo", "## Notes [2]", ...]` — ordinal-disambiguated source-line keys (level + heading text + `[N]` for duplicates within the document). **Reconciliation on save:** `PageEditorViewModel.flushNow()` drops keys that no longer match any current heading. **Conditional unfocus on chevron click** — caret preserved unless it would land inside the freshly-folded range (else the layout manager refuses to elide an element containing the active selection point). **Shared helpers:** `HeadingChevronGeometry` (rect, shared by renderer + hover handler), `NSTextLayoutFragment.nsRange` extension, AST-based code-block detection (replaces color comparison). Full architecture at `// Guidelines//Markdown.md` §9.11. 21/21 tests pass. |
| **v0.2.7.7** | ✅ SHIPPED 2026-05-23 | **Dash auto-format.** Typed `--<non-dash>` → `—` (em-dash; fires on next non-dash char after two hyphens); typed ` - <space>` → ` – ` (en-dash; fires on the second space in `<space>-<space>` pattern). **En→em promotion:** typed `-` immediately adjacent to an existing `–` (on either side) upgrades it to `—` and consumes the typed hyphen — closes the path back to em-dash from a previously auto-formatted en-dash. Same `MarkdownLists.handleInsertion` + `performEdit` + `isProgrammaticEdit` pipeline as arrow auto-format. **Conflict guards:** em-dash skips when char N-3 is also `-` (preserves `---` HR + YAML frontmatter delim + 4+ dash HR); en-dash skips when only whitespace precedes the `-` on the line (preserves top-level + nested bullets), and skips inside `[[...]]` wikilink targets via new `MarkdownDetection.isInsideWikilink(location:in:)` (line-scoped `[[` / `]]` depth counter). Both skip inside fenced/inline code via existing `isInsideCodeBlock`. AppKit's `isAutomaticDashSubstitutionEnabled` already forced `false` so no native dash interference. **Out of scope for v1:** paste-time substitution (both branches gate on `replacementString.count == 1`; multi-char paste preserves `--` / ` - ` literally). Full architecture at `// Guidelines//Markdown.md` §9.12. |
| **v0.2.7.8** | ✅ SHIPPED 2026-05-23 | **Page-editor title divider — gutter-aligned 1pt rule.** Adds a `Rectangle().fill(Color(NSColor.separatorColor)).frame(height: 1)` between the title `TextField` and the `NativeTextViewWrapper` in `PageEditorView`, padded `.horizontal, 24` so its edges align with the body content gutters (not the window edges). Uses the system separator color — same hairline AppKit draws for `NSWindow.titlebarSeparatorStyle = .line` and `NSSplitView` dividers; rendered at explicit 1pt rather than SwiftUI's sub-pixel default `Divider` for a slightly bolder presence. Explicitly NOT the body HR style (this is structural chrome separating the title area from the body, not a markdown thematic break). Title bottom padding reduced 20pt → 14pt; body editor `textInsets.vertical` raised 0 → 12pt for symmetric breathing room around the divider. **Phase 2 deferred:** title-scrolls-with-content. Currently the title lives in the parent `VStack` *outside* the body editor's `NSScrollView`, so it's pinned at the top regardless of body scroll position. To unlock cover-image / banner support above the title (so banner + title both scroll off as the user moves through long Pages), the engine wrapper needs an optional `headerView: (() -> AnyView)?` parameter that installs an `NSHostingView` as a subview of a custom flipped `NSView` documentView container, above the `NSTextView`. Width-tracks via constraints; `NSTextView.isVerticallyResizable + frameDidChange` propagates height up through the container so the scroll range covers `headerHeight + textViewHeight`. Estimated ~100-200 lines of new engine code; queued behind the cover-image feature itself since the visual chrome is now in place. |
| **v0.2.7.x (later)** | QUEUED | Code & quote `Enter` auto-completion. Tables (ASAP but realistic estimate 10-15h after divider iteration experience; full spec at "Tables — to be implemented" above). Sidebar + PageType/PageCollection drag-to-reorder (in progress, see Drag-Reorder plan). PreviewWindow primitive build. Phase 4.5 auto-pair polish. Phase 3 engine AST rewrite. Title-scrolls-with-content via engine `headerView` parameter (paired with cover-image / banner work — see v0.2.7.8 row). No specific patch number assignments — pick what's next at session time. |

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

#### Tables — to be implemented

> **Status: PAUSED 2026-05-21** per Nathan's call. The current ship (above, line 64) parses GFM `| col | col |` correctly and applies monospace + faint-bg + hidden-pipes styling. The Apple-Notes-style inline grid + cell-editing UX described below is the target — paused until accumulated engine experience clarifies the column-alignment question.

##### Critical open question: column alignment

**How do columns visually align when the source on disk is not padded?**

Source like `| a | b |\n|---|---|\n| longerword | b |` lays out as inline text in TextKit 2. The current styler hides pipes via font 0.1 + clear color, leaving cell text in place. There is no native column-alignment mechanism in TextKit 2 — `NSTextTable` was evaluated and rejected (forfeits Writing Tools / Look Up / dynamic-color wins; Apple's own TextEdit downgrades to TextKit 1 to use it; Apple Notes uses custom protobuf rendering).

So cells of row 1 (`| a |`) sit at one X position; cells of row 2 (`| longerword |`) sit at a different X. Columns DO NOT visually align unless the source is already padded to equal widths per column. Three candidate strategies:

| Strategy | What it does | Pros | Cons |
|---|---|---|---|
| **A — Padded source canonical form** | Run `Markup.format()` on each table at file load + every save (300ms debounce) + every table edit commit. On-disk source is always padded — `\|Name   \|Count\|Price\|` not `\| Name \| Count \| Price \|`. Natural text layout aligns columns. | Simplest TextKit interaction. Grid alignment "just works." | Mutates user's source on save. File-watcher external edits show as unpadded briefly. May normalize away user-intentional formatting. Violates "files canonical (≠ everything is Markdown)" intent for users who care about exact source bytes. |
| **B — Computed-width grid draw + accept text/grid misalignment** | Compute column widths from the AST (max cell text width per column + padding). Draw the grid at those computed widths in `MarkdownTextLayoutFragment.drawTable`. Accept that cell text may not align with grid columns for unpadded source. | No source mutation. | Visible misalignment looks broken — text might cross grid lines or be offset within cells. Most newcomers would read this as a bug. |
| **C — Hybrid: pad on edit commit only** | Source stays as the user typed it. The popover editor's "Done" action runs `Markup.format()`. Otherwise leave source alone. Inline drag-resize is dropped — drag-resize as designed can't apply custom widths without source mutation. | Less mutation than A. Preserves user typing between edits. | Drag-resize cut. User-typed unpadded tables look slightly off until they pass through the popover. Inline grid still has the alignment problem until first popover edit. |

**Recommendation:** Strategy C, with A as fallback if drag-resize must stay in scope. Strategy B's "visible misalignment" outcome doesn't survive Pommora's quality bar.

**Nathan's locked direction (2026-05-21, `// Guidelines//Markdown.md` §9.2):** source on disk stays uniformly padded; column widths live in frontmatter (`pommora_table_widths`); render layer applies overrides. Implementation cost for inline drag-resize against TextKit's natural-layout constraint documented in `// Guidelines//Markdown.md` anti-pattern §6.10 — non-trivial; not a small render-layer feature. The `pommora_table_widths` key is grandfathered for v0.3.0 per the CLAUDE.md "Pommora prohibited in on-disk schemas" rule; rename when Tables ship.

##### Stage 3.A — Inline grid rendering — BLOCKED on column alignment

Verified architecture elements:

- **Detection of "this fragment is part of a table"**: per-fragment AST parse, same as HR/Blockquote pattern. Stage 1 prefilter — line starts with `|`. Stage 2 — per-fragment `Document(parsing:)` contains a `Table` child. **NOT** a custom `.pommoraTable` attribute (rejected per L1 in `// Guidelines//Markdown.md`).
- **Header detection**: position the fragment within the table via AST — the fragment overlapping `table.head.range` is the header.
- **Grid stroke**: per-fragment, after `super.draw`, stroke 1pt `NSColor.separatorColor` for the cell borders this fragment contains. Mirrors `drawThematicBreak` + `drawCodeBlockBackground` CGPath patterns.
- **Header bg fill**: `Color.primary.opacity(0.04)` fill on the header row's line-fragment rect, before the strokes.
- **renderingSurfaceBounds**: extend per-fragment for the bordering strokes on top + bottom edges. Each fragment owns its part; no cross-fragment bounds extension is possible.
- **Per-cell alignment from GFM `columnAlignments`**: `paragraphStyle.alignment` is per-paragraph, not per-character; a table row is one paragraph with multiple cells. Options: (1) accept that natural text layout doesn't honor `columnAlignments` and let `Markup.format()` reflect alignment in the padded source via cell-left/cell-right whitespace; (2) drop alignment honoring entirely from the inline view.
- **SourceRange → NSRange**: existing `SourceRangeConverter` + `LineOffsetIndex`. UTF-16 vs UTF-8 caveat is live for tables — non-ASCII cell content can mis-locate the splice range and corrupt source on commit. Acceptable for v1 if Pommora's expected content is ASCII-dominant.

##### Stage 3.B — Drag-resize column dividers — SCOPE-AT-RISK

Under Strategy C: **dropped** — can't ship custom widths without source mutation under Strategy C.

Under Strategy A: feasible but expensive — every drag commits new padding to source via `Markup.format()`-style re-emit + splice. High churn; needs verification that the editor stays responsive while dragging.

##### Stage 3.C — Double-click popover editor — VERIFIED, INDEPENDENTLY SHIPPABLE

Doesn't depend on the column-alignment question — the popover hosts its own SwiftUI Grid which IS column-aligned by SwiftUI layout, regardless of how the inline source looks.

- **Trigger**: `mouseDown` in coordinator with `clickCount == 2`, inside a fragment that parses as a Table.
- **Anchor**: `NSPopover` anchored to the table's rect via `textLayoutManager.enumerateTextLayoutFragments(...)` over the table's source range. Existing `viewRect(forCharacterRange:using:)` helper handles coord conversion.
- **Host**: `NSHostingView<PommoraTablePopover>`.
- **Popover content**: SwiftUI `Grid(horizontalSpacing: 0, verticalSpacing: 0)` with `GridRow` per row and editable `TextField` per cell. SwiftUI Grid IS natively column-aligned, so this works regardless of inline-source alignment strategy.
- **Cell styling**: `.textFieldStyle(.plain)` + `.focusEffectDisabled()` + `.multilineTextAlignment(<from columnAlignments>)` + `.lineLimit(1...10)` + `.focused` + `.onKeyPress(.return / .tab)` + inner `.padding` + outer `.frame` + `.background` (header tint or clear) + `.overlay` (1pt accent focus border) + `.contentShape(Rectangle())` + `.onTapGesture` + `.onHover` (NSCursor.iBeam push/pop).
- **Commit**: build a new `Table` via `TableCellsRewriter` conforming to `MarkupRewriter`. Emit canonical GFM via `Markup.format()`. Splice into text storage at the table's source range. Wrap in `NSTextContentManager.performEditingTransaction(_:)` (or `textStorage.beginEditing/endEditing` — either works; the engine uses the latter elsewhere). Set `isProgrammaticEdit = true` during splice.
- **Source-range capture**: capture the NSRange BEFORE splice. After splice, it's invalid (different length). Let the next restyle re-discover the new table via AST parse.

**Open implementation details to verify at ship time:**

- The `MarkupRewriter`'s `mutating func visitTable(_ table: Table) -> Markup?` returns `Table(columnAlignments:header:body:)` constructed with edited cells. Confirm `Table.Cell(...)` accepts an array of inline children (Text + Emphasis + etc.) — existing cell content's inline children must be preserved if the edit is just text-content (else markdown formatting inside cells is lost).
- `Markup.format()` output for tables IS padded (verified via Context7 example output). Confirm this is acceptable as the post-edit source under whichever alignment strategy wins.

##### Stage 3.D — Right-click "Add Row / Add Column" context menu — VERIFIED, INDEPENDENTLY SHIPPABLE

Same commit path as 3.C. New `TableStructureRewriter: MarkupRewriter` with an `Operation` enum (`insertRow(at:)` / `insertColumn(at:)`). Returns a new Table with the row/column inserted at the requested index, preserving all existing cells.

- **Trigger**: extend `ContextMenu.swift` builder. When right-click target is inside a table-containing fragment, append four menu items.
- **Click-point → (row, column) hit-test**: row from click Y vs each row fragment's typographic bounds. Column from click X vs computed cell-x boundaries — **DEPENDS on the column-alignment strategy**. Strategy A: cell X positions derived from the padded source's natural layout. Strategy C: cell X positions derived from `Markup.format()`-equivalent computed widths on the AST.
- **Rewrite + splice**: same `MarkupRewriter` + `Markup.format()` + `performEditingTransaction` + `isProgrammaticEdit` pattern as 3.C. Doesn't open the popover — structural edits aren't in-cell edits.
- **Frontmatter widths interaction** (Strategy A only): row insert preserves column count → widths preserved. Column insert changes column count → widths reset.

##### Risk inventory

| # | Risk | State |
|---|---|---|
| 1 | Two-source-of-truth between text storage and viewModel.body | ELIMINATED. Text storage IS canonical. |
| 2 | `NSTextAttachment` view-bounds bug | N/A. No attachments used. |
| 3 | Restyle loop from substitution mutation | N/A. Cell-edit commits wrapped in `isProgrammaticEdit` + `performEditingTransaction`. |
| 4 | `Markup.format()` pipe-padding normalization | Inherent to whichever alignment strategy wins. Documented behavior. |
| 5 | Find/Replace doesn't find cell text | ELIMINATED. Cells live in text storage as `\| cell \|`; system Find works natively. |
| 6 | swift-markdown SourceRange UTF-8 vs Pommora LineOffsetIndex UTF-16 | UNCHANGED — but **tables are the most exposed surface to this**. Cell content with non-ASCII can misalign the splice range and corrupt source on commit. Out of scope to fix; flagged for users who hit it. |
| 7 | `_fixSelectionAfterChangeInCharacterRange` selection drift on programmatic edits | Watch during testing. |
| 8 | Column-boundary hit-test cache invalidation | Strategy-dependent. Strategy A: boundaries from text layout, invalidate when restyle fires. Strategy C: boundaries from AST, invalidate when AST changes. |
| 9 | `pommora_table_widths` indexed by `(position, columnCount)` loses widths on reordering | Only relevant if Strategy A keeps drag-resize. Otherwise N/A. |
| 10 | Popover anchoring across page scroll | NSPopover handles view-anchored cases automatically. Verify in build. |
| 11 | **Column-alignment strategy unresolved** | **OPEN.** Blocks Stages 3.A and 3.B. Stages 3.C and 3.D ship without it. |

##### Resume-of-work notes

When Tables work resumes:

- Answer the column-alignment question (A / C, possibly D) with accumulated engine experience first — vacuum-derived from the original plan failed.
- Stages 3.C (popover editor) and 3.D (structural context menu) are independently viable and could ship first if Nathan locks "popover-first" — neither depends on the inline-grid alignment strategy.
- Stages 3.A (inline grid) and 3.B (drag-resize) wait for the alignment-strategy lock.
- The `pommora_table_widths` frontmatter key is grandfathered for v0.3.0; rename when Tables ship per CLAUDE.md core principle.

---

#### Deferred beyond v0.2.7.x

- **Phase 3 substantive (engine internal)** — wholesale-rewrite `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. The h.8 supplemental styler covers BlockQuote/Strikethrough/Table/ThematicBreak rendering as a starter on top; the full body swap would unify everything onto Apple AST. Lower priority — engine works as-is.
- **Phase 4.5 polish** — auto-pair selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace (typing space at fresh-pair boundary jumps past close marker) + the 11-test auto-pair test suite.
- **`PommoraWikiLinkResolver`** — Pommora-side `WikiLinkResolver` conformance. **v0.3.2 wikilink** autocomplete + click routing + rename cascade depends on this (moved from v0.2.10 → v0.3.2 RC-2026-05-19 to couple with SQLite at v0.3.3); will extend engine's `WikiLinkService` two-form storage transform (`[[Name|<id>]]` ↔ `[[Name]]`).
- **`:::callout` and `@Columns` directives** — originally scoped for v0.2.9; **v0.2.9 unscheduled** (removed from active v0.2.x sequence RC-2026-05-19 — page editor is functional without them). Re-homes to a later v0.2.x patch, or post-v0.3.x. Via Apple `BlockDirective`. **Slash menu** also in the same deferred bundle.
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
