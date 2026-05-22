### Markdown Editor — Rules + Reference

The canonical playbook for any agent touching Pommora's page editor — the vendored `swift-markdown-engine` at `External/MarkdownEngine/`, Pommora's customizations on top of it, the Apple `swift-markdown` parser, and the TextKit 2 substrate. Every rule below is grounded in either (a) shipped engine code, (b) Apple-source documentation, or (c) a paradigm decision Nathan has locked. Anything written from intuition or speculation is flagged as such.

This document supersedes prior ad-hoc lessons scattered across `Handoff.md`, `// Features//PageEditor.md`, `// Planning//Page-Editor-Plan.md`, and Transcripts. When those files repeat anything here, the repeats should eventually be trimmed to a pointer.

---

#### 1. Stack — what's actually installed

##### 1.1 Apple `swift-markdown` (parser + AST)

- **Version:** 0.8.0. SPM dep on `swiftlang/swift-markdown`.
- **Role:** Markdown parsing and AST manipulation. Full GFM support including BlockQuote, Table, ThematicBreak, Strikethrough, Strong, Emphasis, Heading, lists, code, links, images, line/soft breaks, HTMLBlock, BlockDirective.
- **Backed by:** cmark-gfm (Apple's port).
- **Mutability:** Nodes are immutable value types with copy-on-write semantics. Mutating a deep node and reading `.root` returns a new tree that shares structure with the old. Cheap.
- **Mutation pattern:** Either (a) get a mutable reference via `child(through:)`, mutate a property, reach the new tree via `.root`; or (b) implement `MarkupRewriter` and return `nil` (delete) or a new `Markup` (replace) from each `visitXxx`.
- **Canonical emission:** `markup.format()` → `String`. For tables, pads cell contents to align widths in the emitted string.
- **Source location tracking:** `markup.range: SourceRange?` with `.lowerBound.line` (1-based) + `.lowerBound.column` (1-based).
- **CRITICAL LATENT BUG:** swift-markdown / cmark-gfm reports columns as **UTF-8 byte offsets** per the CommonMark spec. Pommora's [`LineOffsetIndex`](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) treats them as **UTF-16 code-unit offsets**. ASCII coincides; multi-byte content (emoji, accented chars in a table cell, non-Latin scripts) misaligns. Out of scope to fix in any current patch but documented here so agents who hit it (most likely in Tables) know what they're seeing.

##### 1.2 `swift-markdown-engine` (vendored)

- **Upstream:** `nodes-app/swift-markdown-engine@e683a62`, Apache 2.0.
- **Location:** `External/MarkdownEngine/` — a **local Swift Package**, not raw sources in the Pommora target.
- **Why packaged:** Pommora is Swift 6 + strict concurrency + ExistentialAny; the engine targets Swift 5.9. The package boundary isolates the engine's concurrency contract from Pommora's.
- **Modification log:** `External/MarkdownEngine/NOTICE.md` — per-file record of Pommora's edits to the vendored sources.
- **What it adds on top of Apple's stack:** dynamic syntax (markers shrink when caret leaves AST node, expand when entered — Bear/iA Writer pattern) + Markdown-aware typing helpers (list continuation, block auto-wrap, character-pair auto-pair).
- **Pommora's customizations live in:**
  - `Styling/AppleASTSupplementalStyler.swift` — AST walker for BlockQuote / Strikethrough / Table / ThematicBreak.
  - `Renderer/MarkdownTextLayoutFragment.swift` — custom NSTextLayoutFragment subclass with overlays for HR, code-block backgrounds, LaTeX images, task checkboxes.
  - `TextView/Coordinator/NativeTextViewCoordinator+*.swift` — extensions on the engine's coordinator, including caret-awareness services (the HR visibility service is the canonical example).
  - `Input/MarkdownListHandler.swift` — list continuation + space-creates / Enter-continues / Shift+Enter-exits behavior.
  - `TextView/ContextMenu.swift` — extended right-click menu.
- **Ownership:** Pommora can edit any engine file. Edits get logged in `NOTICE.md`. The `External/` path was chosen so Xcode auto-includes new files without pbxproj surgery.

##### 1.3 TextKit 2 (substrate)

- **Role:** Apple's text layout + rendering system. Pommora targets the modern TextKit 2 stack — `NSTextLayoutManager`, `NSTextContentManager`, `NSTextLayoutFragment`, `NSTextLineFragment`.
- **What we get for free:** Writing Tools (macOS 15.1+), Look Up / Translate, spell-check, autocorrect, IME, dynamic system colors, drag-to-select, native context menu, find-in-document hooks.
- **What we lose if we abandon TextKit 2:** `NSTextTable` is the most-cited example — it exists since OS X 10.4 but was never promoted to TextKit 2. Apple's own TextEdit silently downgrades to TextKit 1 when a table is inserted (Keith Blount quoted in Krzyzanowski Aug 14, 2025, "TextKit 2: The Promised Land"). Apple Notes uses a custom protobuf document model, not the AppKit text system (per public reverse engineering — Ciofeca Forensics, mac4n6, et al.; not Apple-confirmed). **Adopting `NSTextTable` forfeits everything in the previous bullet** — that's why Pommora rejected it.
- **Mainthread guarantee:** TextKit 2 always invokes rendering on the main thread. The engine subclass exploits this via `@unchecked Sendable` + `MainActor.assumeIsolated` wrappers ([MarkdownTextLayoutFragment.swift:29-50](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L29-L50)).

##### 1.4 Pommora-specific design constraints

These are Nathan-locked and override library defaults:

- **Pages are Markdown documents, not block surfaces.** One continuous Markdown stream from top to bottom. Block-level features as a project term belongs to Contexts / Homepage only.
- **Setext H2 (text + `---` underline) is explicitly removed.** `---` always renders as a horizontal rule regardless of what precedes it. This matches Obsidian / Typora. **Do not add "safety guards" for the setext case** — they contradict CLAUDE.md and break Nathan's intended behavior (L5 below).
- **Filename = title.** No `title` field in frontmatter. Renaming a Page renames the file.
- **Frontmatter never reaches the editor canvas.** YAML is stripped by `AtomicYAMLMarkdown.load` before reaching the editor. The editor binds ONLY to body. Frontmatter is held in `viewModel.page.frontmatter`, re-serialized from the typed struct on save.
- **Wikilinks render as styled colored inline text**, not Notion-style chips.

---

#### 2. Source-of-truth contract

The single most-violated principle in past sessions. Internalize this before writing any code.

##### 2.1 The contract

**The `.md` file on disk is the canonical source.** Everything Pommora renders is derived from it. Specifically:

- **Source on disk = source in `textStorage.string`.** No reconstruction layer. `canonicalBody == textStorage.string` at all times. This survives editor swaps.
- **Display ≠ source.** The same source can render differently in Pommora (card chrome, hidden markers, grid overlays, syntax highlighting) without changing what's on disk. This is the whole point of the dynamic-syntax pattern.
- **Mutations to source are user-initiated.** Pommora does NOT auto-mutate source on its own. The only Pommora-initiated source mutations happen at moments of explicit user intent: an input-handler reaction to a keystroke (e.g. Enter inserting a new list item) or an edit-commit (e.g. the popover editor's Done button). Background "tidying" of source is forbidden.
- **Frontmatter holds Pommora-side display state** when needed. A future drag-resize-columns feature stores widths in frontmatter, not in source. Render layer reads frontmatter and applies overrides. Source stays portable across tools.
- **Files canonical (≠ everything is Markdown).** Pages are `.md`. Items are `.json`. Vaults / Collections / Contexts / Homepage all have their own structured files. The principle applies to all of them: the file is the spec; the render is flexible.

##### 2.2 What this rules out

- ❌ Auto-padding table source on every save to align columns visually.
- ❌ Replacing user-typed bare bullet markers like `-` with engine-specific glyphs like `\t• ` in storage.
- ❌ Expanding `---` into a string of visible-width dashes when the user presses Enter (the legacy HR expansion — explicitly removed; see [MarkdownListHandler.swift:387-397](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L387-L397)).
- ❌ Storing user content in any form that's not legible to an external Markdown reader.

##### 2.3 What this enables

- Files open cleanly in Obsidian / Bear / pandoc / iA Writer / GitHub / etc.
- External agents (Claude via MCP, any tool with filesystem access) can read the source directly without going through Pommora.
- Editor swaps are reversible — the `.md` file is the firewall. Any future editor implementation reads the same disk format.

---

#### 3. The dynamic-syntax pattern (locked architecture)

The architectural answer for any **paragraph-level Markdown construct** that has a visual rendering distinct from its Markdown source. Established by the HR ship (Session 12, 2026-05-20) after the first attempt failed across two execution rounds. Extends naturally to blockquotes, and eventually any other block-level construct (e.g. future foldable headings, callouts, etc.).

##### 3.1 When to use it

Use the dynamic-syntax pattern when:

- The construct has a visible "decoration" (line, card, bar, chrome) that should replace the Markdown source visually.
- The source markers should remain visible when the caret is on the line (so the user can edit them as literal text).
- The construct's visual state needs to change as the caret moves — not just on text edits.

Examples: ThematicBreak (`---`), BlockQuote (`> foo`), potential future constructs like callout fences (`:::callout`).

Do NOT use it for:

- Inline marks (bold / italic / strikethrough / inline code) — these are already handled by the engine's regex tokenizer + active-token-tracking system.
- Constructs whose visual state is independent of caret position (e.g. fenced code block backgrounds — those use a different, simpler mechanism described below).

##### 3.2 The three pieces

| Layer | Role | Implementation file |
|---|---|---|
| **Renderer** | Per-fragment custom draw. Detects construct membership via AST-backed detection at draw time. Draws the visual ONLY when the caret is NOT on the fragment's line. | [`MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) — `drawThematicBreak` is the canonical example (line 117-149). |
| **Service** | SOLE writer of the construct's visual attributes (font / color / paragraphStyle on the marker chars). Walks the document on every selection change + every restyle. Applies hidden attrs when caret is OUT; revealed attrs when caret is IN. Reentry-guarded by a per-construct `Bool` flag on the coordinator. | [`NativeTextViewCoordinator+HRVisibility.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift) — `syncHRVisibility` is the canonical example. |
| **Styler** | Emits NOTHING for the construct. The styler has zero authority over this construct's visual state. | [`AppleASTSupplementalStyler.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) — `visitThematicBreak` is the canonical example (line 164-178). |

##### 3.3 Why service-as-sole-writer matters

If the styler and the service can both write the same attributes, a restyle firing while the caret is on the construct undoes the service's work. Result: visible attribute flicker (e.g. dashes vanish despite cursor presence). Splitting ownership cleanly — styler owns NOTHING for the construct, service owns EVERYTHING for the construct — eliminates the race.

The styler still emits attributes for the construct's **neighbors** (base font / color / paragraphStyle on the rest of the document). That's fine. The exclusion is targeted: only attributes that would conflict with the service's hide/reveal toggle.

##### 3.4 Multi-paragraph constructs

BlockQuote can span multiple paragraphs. The HR pattern is per-paragraph. Extending to multi-paragraph requires:

- **Service:** walks the document, parses with `Document(parsing: ts.string)`, iterates each `BlockQuote` node, gets its `NSRange` via `SourceRangeConverter`. For each blockquote, determines if the caret is in ANY of its paragraphs (union of paragraph ranges within the blockquote's range). Applies hide/reveal as a unit, not per-paragraph.
- **Renderer:** per-fragment AST-detection determines IF the fragment is part of a blockquote. Position-within-blockquote (only / first / middle / last) is computed by peeking at neighboring lines in textStorage (`nsText.lineRange(for:)`) and checking whether they also start with `>`. Cheaper than re-parsing the whole document per fragment.

##### 3.5 Card always visible vs hide-while-editing

Nathan-locked 2026-05-21: **the visual chrome (card, bar, line, whatever) is a Pommora-side render that does NOT physically exist in the source.** The pattern is HR-style: caret-out shows the visual; caret-in hides the visual and reveals the source markers. Same approach for HR's line, blockquote's card + bar, and any future construct. Do not invent variants like "card stays visible always" — that's a separate UX pattern with its own consequences and was retired at this lock.

---

#### 4. Detection rules

All construct detection in the engine follows a three-stage pattern to keep the hot path cheap while staying canonical.

##### 4.1 Three-stage detection

**Stage 0 — Code-block guard.** Construct markers that look syntactic in isolation (e.g. `---`, `> foo`, `| a | b |`) parse as the construct when extracted standalone but visually belong to a fenced code block in context. Use the existing `hasCodeBlockBackground` property on `MarkdownTextLayoutFragment` (line 278-283) — it detects code-block membership via the `.backgroundColor` attribute the primary styler emits on code blocks.

**Stage 1 — Cheap string prefilter.** Eliminates ~99% of fragments before any AST parse fires. Examples from shipped code:

- HR ([MarkdownTextLayoutFragment.swift:78-82](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L78-L82)): trimmed length ≥ 3 AND first char in `{-`, `*`, `_`}.
- List context ([MarkdownListHandler.swift:91-96](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L91-L96)): regex match against `bareMarkerRegex` or `listRegex`.

**Stage 2 — AST parse.** Only on fragments that pass Stage 0 + Stage 1. For per-fragment detection: `Markdown.Document(parsing: fragmentString)`, then check `document.children.contains { $0 is ConstructType }`. For document-level detection (services): `Markdown.Document(parsing: textStorage.string)`, then iterate.

##### 4.2 Logic-sharing between renderer and service (L2)

The renderer and the service MUST detect the construct identically. Drift causes "dashes hidden but no line drawn" / "line drawn over visible text" half-applied states. Today the HR detection is **duplicated** between the renderer ([MarkdownTextLayoutFragment.swift:69-87](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L69-L87)) and the service ([NativeTextViewCoordinator+HRVisibility.swift:87-107](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L87-L107)). Fragile but works because both implementations mirror each other exactly.

**For new constructs:** either extract detection into a shared utility, or mirror the stages exactly and audit any divergence in code review. If you find drift, fix it before shipping — don't reason about which side is right.

---

#### 5. State mutation rules

##### 5.1 `isProgrammaticEdit` — the canonical guard

Set true around any code path that programmatically mutates `textStorage` (i.e. anywhere Pommora writes to storage, not in response to a user keystroke). The delegate's `shouldChangeTextIn` short-circuits while it's true ([+TextDelegate.swift:335](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L335)).

Canonical wrapper pattern: see `MarkdownLists.performEdit` ([MarkdownListHandler.swift:15-30](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L15-L30)) — sets the flag, calls `shouldChangeText` + `replaceCharacters` + `didChangeText`, defer-resets the flag.

Use it for:
- Input handlers (list continuation, character-pair auto-pair, auto-delete, etc.)
- Edit-commit paths (table cell-edit splices when those ship)
- Any other "Pommora is editing storage on the user's behalf" path

Do NOT use it as a general "skip restyle" flag. It's specifically for storage mutation.

##### 5.2 Reentry guards on services

Every caret-awareness service writes attributes to storage. Those writes can re-trigger `restyleTextView` (which calls the service) → infinite recursion. Guard with a per-service `Bool` flag on the coordinator: set on entry, defer-reset on exit, early-return if already set.

Canonical example: `isSyncingHRVisibility` ([NativeTextViewCoordinator.swift:74](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift#L74)) + the guard pattern at [NativeTextViewCoordinator+HRVisibility.swift:34-36](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L34-L36).

When adding a new service, either add a per-service flag (preferred for clarity) or share an `isSyncingDynamicSyntax` flag across services (acceptable if multiple services would otherwise compete; verify no real cross-service recursion path exists before sharing).

##### 5.3 Batched mutation

Wrap multiple-character storage mutations in either `ts.beginEditing()` / `ts.endEditing()` (NSTextStorage-level — older AppKit pattern, used by the HR service at [+HRVisibility.swift:51-52](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L51-L52)) or `NSTextContentManager.performEditingTransaction(_:)` (TextKit-2-native form, preferred for new code). Either pattern coalesces layout work and prevents per-char re-render hitches.

##### 5.4 Atomic write contract

The save pipeline is:

`keystroke → viewModel.body didSet → scheduleSave() 300ms debounce → PageSaver.save (protocol in PageEditorViewModel.swift) → ContentManager.updatePage(_:body:in:vault:) → reconstructs PageFile(frontmatter:body:title:) → AtomicYAMLMarkdown.write(frontmatter:body:to:) → atomic temp-file + rename`

This is load-bearing and untouched since v0.2.7.0 ship. **Don't break it.** Specifically:

- The editor binds ONLY to `body` (Markdown, no YAML). YAML is held in `viewModel.page.frontmatter` as a typed struct and re-serialized on save. The user cannot destroy frontmatter via the editor — it's never visible to the editor.
- Flush on context loss: page switch, window close, app resignActive, app willTerminate, ⌘S. All paths exist; don't add a new one without checking why.
- Failure: existing `pendingError` alert pattern with Retry / OK buttons. Draft body preserved; retry re-schedules.

---

#### 6. Anti-patterns — NEVER do these

Each one of these has burned a session. The fix in every case was strip + restart, not iterate.

##### 6.1 Don't use a Pommora-custom NSAttributedString attribute key as a render signal for paragraph-level constructs

**The mistake:** add `nonisolated static let pommoraXxx = NSAttributedString.Key("PommoraXxx")` and emit it from the styler over a paragraph range; have the renderer read it via `enumerateAttribute` to drive drawing.

**Why it fails:** AppKit's attribute-inheritance machinery leaks custom attributes onto newly-typed chars in ways `shouldChangeTypingAttributes` cannot prevent. The first HR attempt's `.pommoraThematicBreak: true` attribute caused the "duplicate HR on every Enter" bug — Enter at end of `---` created a new paragraph that inherited the HR-detection attribute. The shipped engine keeps the `.pommoraThematicBreak` key DEAD-but-reserved at [MarkdownTextLayoutFragment.swift:21-27](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L21-L27) as a reminder.

**What to do instead:** AST-backed detection at draw time. See section 4.

**Exception:** standard attributes like `.backgroundColor` for code-block detection are fine, because they're SET on every char in the range AND the styler re-walks on each restyle to re-set them. The leak vector is for Pommora-custom flag-attributes that the styler doesn't re-set every keystroke.

##### 6.2 Don't have the styler AND the service write the same construct's attributes

**The mistake (forward-looking — applies to any new dynamic-syntax construct, including blockquote when it ships):** styler emits visual attributes (e.g. `.backgroundColor` / `.foregroundColor` / `.paragraphStyle`) AND a caret-awareness service later writes some of those when the caret moves. Today's styler `visitBlockQuote` still emits these — the new blockquote service hasn't been written yet. The race only materializes once both layers are live.

**Why it fails:** restyle fires on every keystroke + every caret move. The styler re-applies its attributes; the service then re-applies its hide/reveal state. Race between them produces visible flicker. The order of execution isn't always what you think — `restyleTextView` runs supplemental styler, THEN `syncHRVisibility` ([+Restyling.swift:121-128](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift#L121-L128)), but a paragraph-scope restyle may not touch the construct's paragraphs and the service still walks the whole doc — those orderings get subtle. HR proved this in Session 12 by going service-sole-writer + styler-emits-nothing for ThematicBreak; the lesson generalizes.

**What to do instead:** when shipping a new caret-awareness service, simultaneously strip the styler's visit method for that construct down to a children-walker only. Service is the sole writer. See section 3.3.

##### 6.3 Don't add a "safety guard" without checking the design docs first

**The mistake:** add a setext-underline guard to HR detection (`if first == "-" && lineAbove non-blank → not HR`) thinking it's prudent.

**Why it fails:** Pommora explicitly removed Setext H2 support (`CLAUDE.md`: "Pommora removed Setext H2 support"). The guard contradicted the design and rejected exactly the case Nathan wanted to render.

**What to do instead:** before adding any "but what if..." guard, check `CLAUDE.md`, `Framework.md`, `// Features//Pages.md`, and `// Features//PageEditor.md` for an explicit design statement on the case. If the design rejects the case, don't guard it. If the design is silent, ASK before guarding.

##### 6.4 Don't pile hotfix on hotfix when something doesn't work

**The mistake:** speculative fix #1 doesn't work → add fix #2 → fix #2 introduces new failure → add fix #3 → etc. The first HR attempt accumulated font-0.1 hide, then renderingSurfaceBounds extension, then attribute removal, then cursor-out push, then atom-delete, then strip-typingAttributes. Each fix introduced a new failure surface.

**Why it fails:** N speculative fixes don't compose into N-times-better behavior; they compound failure modes.

**What to do instead:** when 2-3 speculative fixes don't resolve, **revert all of them** and reconsider the design. The HR ship only began working after a full revert to v0.2.7.1 baseline + replan from scratch. Same lesson surfaced again at the end of Session 12 — the `.rounded()` pixel-snap attempt for first-HR dimness didn't help, so it got reverted rather than left in the tree.

##### 6.5 Don't use `doCommandBy(insertLineBreak:)` to catch Shift+Return

**The mistake:** hook the `insertLineBreak:` selector via `textView(_:doCommandBy:)` thinking Shift+Return triggers it.

**Why it fails:** macOS's default key bindings map both plain Return AND Shift+Return to the `insertNewline:` selector. The `insertLineBreak:` selector only fires on Ctrl+\.

**What to do instead:** detect Shift+Return inside `shouldChangeText`'s `\n` branch via `NSApp.currentEvent.modifierFlags.contains(.shift)`. See [MarkdownListHandler.swift:405-412](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L405-L412).

##### 6.6 Don't use `paragraphStyle.alignment` for per-cell alignment

**The mistake:** assume `paragraphStyle.alignment` can give per-cell alignment in a table row.

**Why it fails:** `paragraphStyle` is per-paragraph. A table row is one paragraph. Setting `.alignment` aligns the ENTIRE row, not individual cells.

**What to do instead:** if per-cell alignment matters visually (it usually doesn't for inline markdown source), let `Markup.format()`'s padded source reflect alignment via cell-left/cell-right whitespace. The separator row `|:------|:---:|----:|` encodes alignment and `format()`'s padding respects it.

##### 6.7 Don't store live AST nodes inside NSAttributedString attributes

**The mistake:** pack a `Table` (or other Markup) AST node into a struct, attach it as a custom attribute on the source range.

**Why it fails:** value semantics + immutability mean the stored node is a snapshot at attribute-emit time. The moment the source mutates, the snapshot is stale. Re-parsing on every render gives fresh info; cached AST nodes go bad on every keystroke.

**What to do instead:** if you need AST info at draw time, parse the fragment text at draw time (per-fragment scope, cheap with prefilter). For service-level operations, parse the whole document at service-walk time (once per pass, not per fragment).

##### 6.8 Don't co-exist source-mutating expansion with visual-overlay rendering

**The mistake:** keep the legacy `---` → `\t• ` (or `---` → 100 dashes) expansion in input handlers while ALSO adding a visual overlay for the same construct.

**Why it fails:** the source mutation inflates the construct's character range; the overlay assumes a fixed source shape. They conflict directly — visible glitches like "100 dashes drawn" or "overlay positioned at wrong baseline".

**What to do instead:** pick one strategy per construct. The new pattern is overlay-only. Delete the legacy expansion when you ship the overlay. See [MarkdownListHandler.swift:387-397](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L387-L397) for the comment explaining the HR expansion removal.

##### 6.9 Don't assume swift-markdown columns are UTF-16

**The mistake:** treat `SourceRange.lowerBound.column` as a UTF-16 code-unit offset and add it directly to a UTF-16 line-start offset to get an NSRange location.

**Why it fails:** swift-markdown / cmark-gfm columns are UTF-8 byte offsets per the CommonMark spec. ASCII coincides; multi-byte content (emoji, accented chars, non-Latin scripts) misaligns.

**What to do instead:** accept that the latent bug exists in `LineOffsetIndex` ([AppleASTSupplementalStyler.swift:206-251](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L206-L251)) and don't make it worse. When the bug actually triggers (most likely in Tables with non-ASCII cell content), the fix is to convert UTF-8 column counts to UTF-16 offsets via codepoint-aware iteration. Out of scope until a feature exercises it.

##### 6.10 Don't try to make natural inline text layout honor custom widths

**The mistake:** assume that TextKit will render `| Apples | 10 |` at custom column widths if you just "tell it where the columns are."

**Why it fails:** TextKit lays out inline text at character positions. There's no native "render this inline text region at a different visual width than its character widths suggest" mechanism. `NSTextTable` would do it but it forfeits TextKit 2 (see 1.3).

**What to do instead:** for any feature that needs custom inline widths (e.g. drag-resize columns), either (a) accept that source padding is the only authority and mutate source on user intent only, or (b) build a custom render layer that overrides natural text positioning (multi-week effort with hit-test + selection consequences). When the Tables work resumes, this is the central architectural question to answer first.

##### 6.11 Don't draft plans with new files when existing files cover the change

**The mistake:** propose new theme properties, new service files, new abstractions when the actual change is a one-line addition to an existing styler dict or an existing case in `handleInsertion`'s switch.

**Why it fails:** bloats the diff, multiplies bug surface, dilutes the review. Pommora's customization slots already exist — `PlainTextSyntaxHighlighter.backgroundColor()`, the `styleCodeBlocks` / `styleInlineCode` attrs dicts, `handleInsertion`'s `>` / `-` / `[` branches. Most "polish" changes slot in as a single property add.

**What to do instead:** before writing a plan, grep the candidate files for the existing extension point. If the change is one entry in an existing dict or one case in an existing switch, propose THAT — not a parallel system. Nathan corrected this several times during v0.2.7.4 planning.

##### 6.12 Don't use AST detection where lockstep with a regex-based styler is required

**The mistake:** detect a construct via `Markdown.Document(parsing: line).children.contains { $0 is UnorderedList }` in a renderer/service, while the styler decides hide-attr application via `NSRegularExpression`.

**Why it fails:** AST and regex disagree on edge cases. `Markdown.Document(parsing: "- ")` (empty bullet, no content) parses as `Paragraph`, not `UnorderedList` — CommonMark requires content after the marker. The styler's regex still matches `- ` and hides the dash; the renderer's AST rejects the line and draws no `•`. Result: blank line where a bullet should be. Cost the "Enter continues empty list" UX during v0.2.7.4 bullet glyph ship.

**What to do instead:** when two layers must agree on detection, use the SAME REGEX in both. `MarkdownDetection.isDashBulletLine` mirrors the styler's exact pattern (`^([ \t]*)([-*+•](?:[ \t]*\[[ xX]?\])?[ \t]+)(.*)$`) verbatim. Drift in either direction = half-applied state. Note this nuances the §4.1 Stage-2 rule: AST is the right confirmation when the styler also uses AST (e.g. HR detection); pick the layer that already exists upstream.

##### 6.13 Don't font-collapse chars whose visual width is consumed downstream

**The mistake:** hide a Markdown marker by setting `font: NSFont.systemFont(ofSize: 0.1) + .foregroundColor: NSColor.clear` over a range that includes characters another layer measures (e.g. the `[` of a task checkbox, whose font size determines the drawn box dimensions).

**Why it fails:** font-0.1 shrinks the char's advance width to near-zero, not just its visible glyph. Code that asks "where does this char sit?" or "how big is it?" (e.g. `drawTaskCheckboxes` reading `font.pointSize` from the `[`) gets a near-zero answer. The checkbox renders invisible. Burned during v0.2.7.4 when the bullet collapse range swallowed the task `[`.

**What to do instead:** pick the hiding mechanism by intent. **Width must be preserved** (e.g. the `-` before bullet content — invisible gap) → `.foregroundColor: NSColor.clear` ONLY. **Char must be structurally gone** (e.g. the `- ` spacer before a checkbox so the box lands at the indent) → font-0.1 + clear-color, AND verify nothing downstream measures the collapsed range.

##### 6.14 Don't let detection regex drift across the multiple sites that describe one construct

**The mistake:** the same construct (e.g. unordered list with optional task brackets) is matched in 4+ regex patterns — `listRegex`, `bulletListPattern`, `taskListRegex`, `isDashBulletLine`. Each one independently encodes (a) which markers count (`[-*+•]`) and (b) whether brackets are optional (`(?:[ \t]*\[[ xX]?\])?`).

**Why it fails:** silent half-applied state. One site accepts `-[]` shorthand, another requires `- [ ]` GFM form → user types `-[]` and gets right-aligned brackets without indent (or indented brackets without a drawn checkbox). Every v0.2.7.4 bullet/task hotfix iteration traced back to one of these four patterns being out of sync.

**What to do instead:** when adding a new detection site for an existing construct, audit ALL existing regex patterns describing it and update them in lockstep — same marker class, same optional-bracket spec. If a pattern is referenced by 3+ sites, consider hoisting it to a `static let` shared constant.

---

#### 7. Engine-specific quirks

##### 7.1 `Pommora.Collection` qualification

`Collection` is both a Pommora type (the Vault sub-folder entity) and a Swift standard-library protocol. Field declarations and type signatures involving Collection must use `Pommora.Collection` to avoid shadowing. The compiler error is `Cannot specialize non-generic type 'Collection'` or similar. Fix at commit `2b54123` and repeated several times since. **This is not specific to the markdown engine but is the most common Swift-6-strict-concurrency footgun in the project.**

##### 7.2 `@MainActor.assumeIsolated` wrappers on fragment overrides

`NSTextLayoutFragment`'s overridable members (`draw(at:in:)`, `renderingSurfaceBounds`) behave as `nonisolated` overrides per the Xcode SDK headers (Apple's published HTML/JSON docs don't surface concurrency modifiers, so this is only verifiable in the local SDK headers). Swift 6 strict concurrency infers the subclass as `@MainActor` due to AppKit's pervasive class-level `@MainActor` annotations + SE-0466 default-actor-isolation inference. To reconcile:

1. Mark the specific overrides `nonisolated` to match the parent declarations.
2. Declare the class `@unchecked Sendable` so `self` and CGContext can cross into the MainActor.assumeIsolated body without sending-check errors.
3. Wrap each override body in `MainActor.assumeIsolated { ... }` — safe because TextKit 2 always invokes rendering on the main thread.

Canonical example: [MarkdownTextLayoutFragment.swift:29-50](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L29-L50) (class declaration) + [161-192](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L161-L192) (renderingSurfaceBounds override) + [196-215](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L196-L215) (draw override).

##### 7.3 Swift 6 strict concurrency + ExistentialAny

The engine targets Swift 5.9; Pommora is Swift 6 strict-concurrency + ExistentialAny. Custom Codable declarations: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`. The local Swift Package boundary at `External/MarkdownEngine/` isolates the engine's older concurrency contract from Pommora's stricter one.

##### 7.4 Restyle scoping vs service whole-document walk

`restyleTextView(paragraphCandidates:)` scopes its work to the candidates ([+Restyling.swift:94-129](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift#L94-L129)). But services like `syncHRVisibility` walk the WHOLE document on every call ([+HRVisibility.swift:54-77](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L54-L77)). For documents with hundreds of paragraphs this is microseconds per pass — acceptable. If a future construct's detection cost is significantly higher (e.g. full-document AST parse), consider scoping the service to the candidate paragraphs too.

##### 7.5 `shouldChangeTypingAttributes` re-baselines every keystroke

The delegate forces base font / paragraphStyle / foregroundColor on every change ([+TextDelegate.swift:22-38](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L22-L38)). Newly-typed chars don't inherit decorative attributes from neighbors. This means:

- **Hide-via-attribute (font 0.1 + clear color) on a Markdown marker char doesn't leak to the next typed char.** Good for the service pattern.
- **But Pommora-custom flag attributes (`.pommoraXxx`) ARE NOT included in the delegate's re-baseline** — the delegate only re-sets the standard attrs. That's why custom flag attrs still leak. See 6.1.

---

#### 8. Lessons learned — citation table

Each lesson is grounded in a shipped engine file or a documented Apple API. Cite these in new plans, in PR descriptions, and in agent dispatches to avoid re-litigating.

| # | Lesson | Source citation |
|---|---|---|
| L1 | AST-backed detection > custom NSAttributedString attribute as render signal | HR Session 12; [MarkdownTextLayoutFragment.swift:21-27](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L21-L27) |
| L2 | Renderer + service detection MUST share their logic | HR Session 12; [MarkdownTextLayoutFragment.swift:69-87](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift#L69-L87) ↔ [+HRVisibility.swift:87-107](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift#L87-L107) |
| L3 | Service is sole writer; styler emits nothing for that construct | HR Session 12; [AppleASTSupplementalStyler.swift:164-178](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L164-L178) |
| L4 | Caret-aware reveal/hide eliminates entire workaround categories | HR Session 12 — eliminates cursor-out push, smart-backspace, caret-policy hide |
| L5 | Don't add safety guards that contradict design intent | HR Session 12 — the setext-underline guard contradicted CLAUDE.md's locked "no setext H2" decision |
| L6 | Legacy source-mutation expansion + visual-overlay can't coexist | HR Session 12 + List Session 13; [MarkdownListHandler.swift:387-397](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L387-L397) |
| L7 | Real-world testing finds bugs heavy planning misses — budget 2-4 hotfix iterations after first ship | HR Session 12 (planned 45min → 4h) + List Session 13 (planned ~1h → ~3h with revert) |
| L8 | When fixing a problem and trying many things, STRIP and try again — don't pile fixes | HR Session 12 + List Session 13 |
| L9 | macOS default key bindings collapse Shift+Return → `insertNewline:` | List Session 13; [MarkdownListHandler.swift:405-412](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift#L405-L412) |
| L10 | `shouldChangeTypingAttributes` re-baselines but Pommora-custom flag attrs still leak | List Session 13 + HR Session 12; [+TextDelegate.swift:22-38](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift#L22-L38) |
| L11 | When two layers must agree on detection, share the regex — AST and regex disagree on edge cases (e.g. empty `- ` parses as Paragraph) | Bullet glyph Session 14 (v0.2.7.4); §6.12 |
| L12 | Font-collapse swallows advance width; use clear-color-only when natural width must survive | Task checkbox Session 14; §6.13 |
| L13 | Detection regex MUST agree across every site describing the same construct — drift = silent half-applied state | Bullet/task Session 14; §6.14 |
| L14 | Always-show overlay (Notion checkbox pattern) > dynamic-syntax caret-aware reveal for non-interactive markers | Bullet glyph Session 14 — shipped at always-show after Session 13's caret-aware reveal was reverted |
| L15 | Position-based intercepts (caret-between-pair) > state-based (was-this-auto-paired) for symmetric edits | Bracket-skip Enter Session 14 — stateless, handles auto-pair/typed/pasted uniformly |
| L16 | Existing extension points (styler dicts, `handleInsertion` switch cases) absorb most "polish" changes — don't draft parallel systems | v0.2.7.4 planning (multiple Nathan corrections); §6.11 |

---

#### 9. Nathan-provided clarifications

Architecture decisions Nathan has locked. These override default behavior + library defaults; when they conflict with any of the rules above, Nathan's locks win.

##### 9.1 The render is the spec, not the source (2026-05-21)

> "The bar + highlight would be the attributed string view render just like the HR divider — it doesn't 'physically' exist, it's just the MD rendering on the Pommora side."

For blockquotes and any future paragraph-level construct: the visual chrome lives in the render layer only. The source on disk stays clean CommonMark. The render is the Pommora-side experience; the source is the portable, agent-readable, externally-editable file. **This is the HR pattern, transposed to every other construct.**

##### 9.2 Files canonical, frontmatter for Pommora-side state (2026-05-21)

> "Drag to resize is on the rendering end just like the other visuals... column sizes would be on the frontmatter. The columns would be the same size on the physical markdown file, but the sizing of each column would be displayed on the Pommora side as drag-to-size."

When a feature needs to remember user-chosen display state (column widths, future per-page editor preferences, etc.), it lives in **frontmatter**, not source. The source on disk stays at canonical uniform width (per `Markup.format()`). The render layer reads frontmatter and applies overrides. This applies generically — anywhere Pommora needs to store display-only state.

**Implementation caveat:** for INLINE constructs (text laid out in a fragment), making the render honor frontmatter widths requires overriding TextKit's natural text positioning, which is non-trivial. See 6.10. For BLOCK constructs (HR line, blockquote card, code-block background), the render is fully independent of text positioning and frontmatter overrides apply cleanly.

##### 9.3 Setext H2 is removed permanently (CLAUDE.md, locked pre-v0.2.7)

> "Pommora removed Setext H2 support so no markdown-feature conflict."

`---` always renders as ThematicBreak regardless of the previous line's content. Matches Obsidian / Typora. Do not add setext-underline detection or guards anywhere — the AST already gives the desired answer; introducing guards re-introduces the conflict.

##### 9.4 Filename = title (CLAUDE.md, locked)

Pages have no `title` field. The filename IS the title. Renaming the title in the UI renames the file on disk. Items, Vaults, Collections, Contexts all follow the same rule (Independent UI titles are a Prospect, not v1).

##### 9.5 Strip-and-revert beats hotfix-on-hotfix (Session 12 + Session 13 reinforced)

Nathan-locked operating principle for any debugging session. When N speculative fixes don't resolve a bug, the right move is to revert all N and reconsider the design — not add fix N+1. Mentioned multiple times across Handoff entries.

##### 9.6 Tables planning is PAUSED (2026-05-21)

> "I'm going to pause the planning in the tables and have that be the final thing we do once we learn more from implementing other features into the markdown editor."

Tables work is deferred. The architecture-stress-test work captured in `// Planning//Page-Editor-Plan.md` is preserved as reference, but no Tables coding starts until other markdown editor features ship and we have a better feel for the engine's behavior. The column-alignment question (Strategy A / B / C / hybrid) remains open and will be answered against accumulated experience, not in a vacuum.

##### 9.7 Bullet glyph substitution SHIPPED (v0.2.7.4 — 2026-05-21)

Source `- item` renders as `• item`; `*`, `+`, legacy `•` render literally (locked: only `-` substitutes). Implementation: always-show overlay in `MarkdownTextLayoutFragment.drawDashBulletGlyph` (no caret-aware reveal — sidesteps the Session 13 failure mode entirely; L14). Pixel-aligned via `window?.backingScaleFactor`. Bullet sized at `baseFont.pointSize * 1.5`. Source on disk stays `-` for portability.

##### 9.8 Pommora `-[]` task shorthand accepted alongside GFM (2026-05-21)

> "Lets change the syntax for task list to this -[] / rather than - [ ]."

Pommora accepts `-[]` / `-[x]` as task-list syntax in addition to GFM's `- [ ]` / `- [x]`. The shorthand is **NOT portable** — Obsidian, iA Writer, GitHub, pandoc render `-[]` as literal text, not a checkbox. Nathan explicitly accepted the tradeoff for typing fluidity. The styler/renderer detection regex must accept both forms (`[-*+•](?:[ \t]*\[[ xX]?\])?` — zero-or-more whitespace before brackets, optional bracket content). See L13.

##### 9.9 Bracket-skip Enter intercept (v0.2.7.4 — 2026-05-21)

When the caret sits between a matched open/close pair on the current line (`[ ]`, `( )`, `{ }`, `[[ ]]`), pressing Enter jumps the caret past the closer instead of inserting `\n` — VS Code's "Tab to escape brackets" pattern mapped to Enter. Position-based detection (no auto-pair state tracking; L15). Gated by `autoClosePairsEnabled`. Carve-out: matched pair inside the list-marker checkbox falls through to list-Enter so the user can continue the list from inside the brackets. Implementation: [MarkdownListHandler.swift](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift) `\n` branch, between the Shift+Enter intercept and the fenced-code completion intercept.

##### 9.10 Blockquote architecture: always-show overlay, NOT dynamic-syntax (v0.2.7.5 — 2026-05-21)

> "The always-show is how it currently works; we have no intent on changing that."

**Status:** ✅ SHIPPED v0.2.7.5 with one carry-over visual TBD (horizontal "highlight not extending into syntax gap" — fix paths documented in `Handoff.md` "Carries to tomorrow"). Architecture + all other behaviors locked.

Blockquote uses the **always-show overlay** pattern — same model as the v0.2.7.4 bullet glyph and task checkbox. NOT the HR-style caret-aware dynamic-syntax pattern. Rationale: L14 (always-show > caret-aware for non-interactive markers), and the alternative "card visible / `>` markers toggle on caret" produces a text-jump on caret-enter when `headIndent` toggles.

Locked behavior (as-shipped):
- `>` markers permanently hidden via font-0.1 + clear-color on `> ` (marker + space). Activation gate requires `>` + space/tab — bare `>` doesn't activate (matches list UX where `-` alone doesn't activate until `- `; L13 — detection regex consistency).
- `paragraphStyle.headIndent = 20` preserved (per Nathan: "text indented just as it is currently").
- Card chrome permanently visible via `MarkdownTextLayoutFragment.drawBlockquoteCard` — renderer-drawn `CGPath` with `NSColor.tertiarySystemFill` (native intensity, adapts light/dark).
- 4pt accent bar in `NSColor.secondaryLabelColor` inside the card on the left (pill-shaped ends).
- **Continuous bar across multi-line quotes** — per-fragment segments butt-jointed via `paragraphStyle.paragraphSpacing = 0` + `paragraphSpacingBefore = 0` on consecutive quote paragraphs. Card AND bar both inflated by `cornerRadius = 6pt` on rounded ends so visual extents match.
- Slight right margin via `paragraphStyle.tailIndent = -8`.
- `paragraphStyle.minimumLineHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)` prevents 1pt line collapse when only collapsed-marker chars exist on the line (empty `> ` line).
- **Plain Enter continues** the quote with `\n<prefix>` (preserves leading indent); **Shift+Enter exits** with plain `\n`. Mirrors list convention. New `MarkdownLists.blockquoteMarkerRegex` (`^[ \t]*>[ \t]`) powers detection.
- Italic text (existing styler emission — only emitted when source has inline `*..*` / `_.._`, untouched by blockquote).
- No service file; no caret-aware logic; no reentry flag. Two files modified: `AppleASTSupplementalStyler.swift` + `MarkdownTextLayoutFragment.swift`. New regex in `MarkdownListHandler.swift`.

This nuances §9.1's general "render is the spec" principle: the chrome is still a Pommora-side render that doesn't physically exist in the source, but it's permanently visible rather than caret-conditional. Both patterns honor §9.1; the choice between them is per-construct per L14.

---

#### 10. Reference index — where things actually live

##### 10.1 Engine internals (vendored, Pommora-editable)

| File | Role | Key entry points |
|---|---|---|
| [`Renderer/MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) | Custom NSTextLayoutFragment subclass. Per-fragment custom draw for code blocks, LaTeX, HR, task checkboxes. | `draw(at:in:)` line 196; `renderingSurfaceBounds` line 161; `hasThematicBreak` line 69; `caretIsInFragment` line 94 |
| [`Styling/AppleASTSupplementalStyler.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) | Apple-AST walker for BlockQuote / Strikethrough / Table / ThematicBreak. Layered on top of the engine's regex tokenizer. | `Visitor.visitBlockQuote` line 58; `visitTable` line 95; `visitThematicBreak` line 164 (emits nothing); `SourceRangeConverter` line 187; `LineOffsetIndex` line 206 |
| [`TextView/Coordinator/NativeTextViewCoordinator.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator.swift) | Main coordinator (NSTextViewDelegate). State: `isProgrammaticEdit`, `isSyncingHRVisibility`, `pendingEditedRange`, etc. | Class declaration line 25; flags line 50, 67-74 |
| [`TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HRVisibility.swift) | Canonical caret-awareness service. Walks doc, applies hide/reveal. | `syncHRVisibility` line 33; `isThematicBreakParagraph` line 87; `applyHRHiding` line 131; `revealHRDashes` line 158 |
| [`TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift) | Restyle pipeline. Primary + supplemental styler runs, then service. | `rebuildTextStorageAndStyle` line 17 (full rebuild); `restyleTextView` line 94 (scoped); `parsedDocument` line 131 (cached parse) |
| [`TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift) | Hot delegate path. `textDidChange`, `textViewDidChangeSelection`, `shouldChangeTextIn`. Service hooks fire at the end of each. | `shouldChangeTypingAttributes` line 22; `textDidChange` line 40; `textViewDidChangeSelection` line 166; `shouldChangeTextIn` line 332 |
| [`Input/MarkdownListHandler.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift) | List continuation, character-pair auto-pair, auto-delete. Canonical input-handler pattern. | `MarkdownLists.performEdit` line 15 (programmatic-edit guard pattern); `detectListContext` line 78 (three-stage detection); `handleInsertion` line 267 |
| [`Parser/MarkdownTokenizer.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownTokenizer.swift) | Primary regex tokenizer. Produces `[MarkdownToken]` for inline marks + code/latex/wikilink boundaries. | (read this when extending inline-mark handling, not for paragraph-level constructs) |
| [`TextView/ContextMenu.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/ContextMenu.swift) | Right-click menu builder. Extended by Pommora's Format / Heading / Lists / Block submenus. | (read this when adding context-menu actions) |

##### 10.2 Pommora-side editor wiring

| File | Role |
|---|---|
| [`Pommora/Pommora/Pages/PageEditorView.swift`](Pommora/Pommora/Pages/PageEditorView.swift) | SwiftUI view hosting `NativeTextViewWrapper`. Title TextField + body editor. Save pipeline entry point. |
| `Pommora/Pommora/Pages/PageEditorViewModel.swift` | ViewModel binding body + frontmatter to ContentManager. |
| `PageSaver` protocol in `Pommora/Pommora/Pages/PageEditorViewModel.swift` | 300ms-debounced save scheduler (protocol + concrete impl). |
| `Pommora/Pommora/Content/ContentManager+CRUD.swift` | `updatePage(_:body:in:vault:)` write path. |
| `Pommora/Pommora/Storage/AtomicYAMLMarkdown.swift` | Atomic temp-file + rename. YAML/body split on load. |

##### 10.3 Specs + history

| Doc | What it carries |
|---|---|
| [`// Features//PageEditor.md`](.claude/Features/PageEditor.md) | Editor implementation spec. Shipped v0.2.7.0 feature surface. "Dynamic-syntax pattern" section is the locked architecture statement. |
| [`// Features//Pages.md`](.claude/Features/Pages.md) | On-disk page format, Markdown features in v1, opening behavior, sidebar visibility, wikilinks. |
| [`// Planning//Page-Editor-Plan.md`](.claude/Planning/Page-Editor-Plan.md) | Active plan — Blockquote in scope, Tables paused. Architecture maps + stress-test results preserved. |
| [`// Guidelines//Paradigm-Decisions.md`](.claude/Guidelines/Paradigm-Decisions.md) | Confirmation protocol + registry. Editor architecture decision recorded here (superseding the dead WKWebView entry). |
| `Handoff.md` | Live session state. Most recent lessons (Session 12 HR + Session 13 Lists) preserved in the entry headers. |
| `History.md` | Locked decision log. Brief — the canonical detail lives in the feature docs. |
| `External/MarkdownEngine/NOTICE.md` | Per-file modification log for Pommora's edits to the vendored engine. |

---

#### 11. How to use this document

- **Before writing any new code** that touches the markdown editor: re-read sections 2 (source-of-truth), 3 (dynamic-syntax), and 6 (anti-patterns). They're the densest summary of "what makes Pommora's editor different from a generic Markdown editor."
- **When planning a new feature**: cite the relevant lessons by number in the plan doc. A plan that ignores L1-L10 risks repeating the failures they encode.
- **When debugging**: section 5 (state mutation rules) + section 6 (anti-patterns) cover the most common footguns. If a bug surfaces, check whether it's a known pattern before adding speculative fixes (L8).
- **When extending the engine itself**: log the modification in `External/MarkdownEngine/NOTICE.md`. Keep Pommora's customizations isolated to the four files named in section 1.2 + new files clearly named with a "Pommora" prefix or in the `+HRVisibility.swift`-style extension pattern.
- **When a Nathan clarification lands**: add it to section 9 with a date stamp. Section 9 entries override any default behavior described elsewhere in this doc.
