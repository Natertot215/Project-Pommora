### Markdown Editor — Rules + Reference

The canonical playbook for any agent touching Pommora's page editor — the vendored `swift-markdown-engine` at `External/MarkdownEngine/`, Pommora's customizations on top of it, the Apple `swift-markdown` parser, and the TextKit 2 substrate. Every rule below is grounded in either (a) shipped engine code, (b) Apple-source documentation, or (c) a paradigm decision Nathan has locked. Anything written from intuition or speculation is flagged as such.

This document supersedes prior ad-hoc lessons scattered across `Handoff.md`, `// Features//PageEditor.md`, and Transcripts. When those files repeat anything here, the repeats should eventually be trimmed to a pointer.

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

##### 7.1 `Pommora.Collection` qualification — RETIRED post-ParadigmV2

**Retired 2026-05-22.** The `Collection` Swift struct was renamed to `PageCollection` (Pages-side) and the new Items-side struct is `ItemCollection` — both bare-unambiguous, no qualification needed. Historical context: pre-ParadigmV2, `Collection` was both a Pommora type (the Vault sub-folder entity) and a Swift standard-library protocol; field declarations had to use `Pommora.Collection` to avoid shadowing. The ParadigmV2 rename eliminates the collision and the qualification requirement. CLAUDE.md quirk #6 is no longer active.

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

Tables work is deferred. The architecture-stress-test work originally captured in `// Planning//Page-Editor-Plan.md` was folded into `// Features//PageEditor.md → Tables — to be implemented` when the planning doc was retired (2026-05-23). No Tables coding starts until other markdown editor features ship and we have a better feel for the engine's behavior. The column-alignment question (Strategy A / B / C / hybrid) remains open and will be answered against accumulated experience, not in a vacuum.

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

##### 9.11 Foldable headings — content-manager elision + hover-overlay chevron (v0.2.x)

**Status:** ✅ SHIPPED. Hover a heading line → chevron appears in the left gutter; click toggles a true zero-height collapse of the content under that heading (down to the next equal-or-higher heading or document end). Chevron rotates 0 → π/2 over 200ms ease-in-out between right (folded) and down (expanded). Caret + selection preserved unless the caret would otherwise land inside the freshly-folded range (conditional unfocus — Decision 2). Per-Page state persists via `folded_headings: [String]` in YAML frontmatter; duplicate-text headings disambiguated via `[N]` ordinal suffix (Decision 1); renaming a heading drops its entry, with orphan keys reconciled on save.

Foldable headings fit neither §9.1 (dynamic-syntax caret-reveal) nor §9.10 (always-show overlay) cleanly. They are the third locked pattern: **content-manager paragraph elision + hover-overlay chevron + frontmatter persistence**.

###### Why neither prior pattern fits

- Dynamic-syntax (§9.1, HR) hides source markers on caret leave. Foldable headings NEVER hide the `##` markers — the heading text stays visible at all times. So caret-aware reveal is not the lever.
- Always-show overlay (§9.10, blockquote, bullet, task checkbox) draws stateless chrome that's always visible. The chevron is interactive + stateful — it appears only on hover (per the design decision) and its orientation reflects fold state. So permanently-visible chrome is also not the lever.

###### The five pieces

| Layer | Role | Implementation file |
|---|---|---|
| **Detection** | `MarkdownDetection.foldableHeadings(in:nsText:)` walks the AST once per restyle and returns `[FoldedHeading]` (key + level + headingRange + contentRange). Computes ordinal-disambiguated keys (Decision 1) so duplicate-text headings are independent fold targets. Both renderer and service consume the same set. `reconcileFoldedHeadings(_:in:)` filters a Set against current AST headings — used by Pommora-side save path to drop orphan keys. | [`Parser/MarkdownDetection.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownDetection.swift) |
| **Content elision** | `NativeTextViewCoordinator` conforms to `NSTextContentStorageDelegate` (which inherits from `NSTextContentManagerDelegate`); implements `textContentManager(_:shouldEnumerate:options:)` returning `false` for any `NSTextElement` whose source range intersects `foldedRanges`. Apple's documented mechanism (`NSTextContentManager.h` line 40: *"it can skip a range… or hide some elements from the layout"*; line 112-113: *"Returning NO indicates textElement to be skipped from the enumeration"*) — the layout manager iterates via `enumerateTextElements` and our filter takes effect at each element. No fragments are created for skipped elements, no layout space allocated, and selection / find / spell-check naturally route through the same enumeration so folded content is unreachable to all of them. Wired in `NativeTextViewWrapper.makeNSView` BEFORE the first layout pass so cold-open of a page with pre-existing folds opens already-collapsed (no flash). | [`+HeadingFolding.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift), [`NativeTextViewWrapper.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift) |
| **Service** | Sole writer of `coordinator.foldedRanges`. `syncHeadingFolding` rebuilds the set from AST + `foldedHeadings` set; when it changes, calls shared `invalidateFoldLayout(in:union:)` over the affected range (extended from fold-start through document-end so fragments BELOW the fold reposition upward when content shrinks). `applyFoldStateIfChanged` is the fold-toggle path (chevron click) — delegates to `syncHeadingFolding` and handles the engine-specific overscroll recalc. Owns the chevron rotation animation timer. The four-step layout-cascade trigger sequence (`invalidateLayout` → `ensureLayout` → `textLayoutFragment(for:)` hit-test → `textViewportLayoutController.layoutViewport()` → `needsDisplay = true`) is necessary because the chevron-click path skips `super.mouseDown` (to prevent caret jumping), so the natural hit-test layout cascade NSTextView would otherwise run has to be reproduced manually. | [`+HeadingFolding.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift) |
| **Renderer** | Draws the chevron via SF Symbol `chevron.right` rotated by `coordinator.currentChevronAngle(...)` in `draw(at:in:)` when this fragment is the hovered heading. Stage-0 code-block guard reads `coordinator.isFragmentRangeInsideCodeBlock(...)` (AST-grounded, not the prior fragile color-comparison). No `isInsideFoldedRange` guard needed — folded fragments don't exist in the layout model. Chevron rect computed via shared `HeadingChevronGeometry.rect(...)` so hover hit-test agrees with the drawn glyph (L2). | [`Renderer/MarkdownTextLayoutFragment.swift`](External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) |
| **Hover + click** | Single-create NSTrackingArea (`.inVisibleRect`); unified `headingHitTest(at:)` consumed by `mouseMoved`, `updateHeadingChevronCursor`, and `handleHeadingChevronClick`. Click handler mutates `coordinator.foldedHeadings`, calls `applyFoldStateIfChanged`, starts chevron rotation, and calls `unfocusCaretIfInsideFoldedRange` (Decision 2 — drop focus only when the caret would otherwise vanish inside an elided range). Mouse-down hook lives in `+DragSelectBoost.swift` (single mouseDown override; chevron hit-test comes before drag-boost arms). | [`NativeTextView+HeadingFoldHover.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+HeadingFoldHover.swift), [`+DragSelectBoost.swift`](External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextView/NativeTextView+DragSelectBoost.swift) |
| **Persistence + reconciliation** | `PageFrontmatter.foldedHeadings: [String]?` (CodingKey `folded_headings`) — encoded-if-non-empty so empty folds don't pollute YAML. `PageEditorViewModel` exposes `Set<String>` with a `didSet` that mirrors to frontmatter + calls `scheduleSave()`. `flushNow()` calls `MarkdownDetection.reconcileFoldedHeadings(_:in:)` before save so orphan keys (heading renamed/deleted) get dropped — the on-disk list stays in lockstep with the current body's headings. | [`PageFrontmatter.swift`](Pommora/Pommora/Content/PageFrontmatter.swift), [`PageEditorViewModel.swift`](Pommora/Pommora/Pages/PageEditorViewModel.swift) |

###### Why `shouldEnumerateTextElement:`, not `textParagraphWith` paragraph substitution

The first attempt at content-manager elision used the sibling delegate method `NSTextContentStorageDelegate.textContentStorage(_:textParagraphWith:)` returning an empty `NSTextParagraph` for source ranges intersecting `foldedRanges`. **It crashed.** Apple's documented contract for that method (`NSTextContentManager.h` line 120) is explicit: *"The attributed string for a custom text paragraph must have range.length"* — i.e. the returned paragraph's attributedString must have characters matching the requested source range length. We returned a zero-length string for non-zero source ranges. `NSTextContentStorage.enumerateTextElementsFromLocation:` then called `setParagraphSeparatorRange:` on the returned paragraph, which called `characterAtIndex:` past the end of the empty string, hit `mutateError`, and `SIGTRAP`ed inside a 19-level recursive layout cascade.

The lesson: `textParagraphWith` is the wrong primitive — it's for paragraph SUBSTITUTION (swap one paragraph for another of equivalent range coverage), not paragraph ELISION (skip a range entirely from layout enumeration). Apple has a separate primitive for elision: `NSTextContentManagerDelegate.shouldEnumerateTextElement:options:`, documented explicitly as *"Returning NO indicates textElement to be skipped from the enumeration."* The layout manager iterates via `enumerateTextElements` — skipping elements at the delegate level means the layout manager never sees them. Zero space allocated, no fragments built, selection / find / spell-check unreachable by construction.

Hiding fragments at the layout-MANAGER layer was also tried (override `layoutFragmentFrame` to zero-height, or use attribute writes to shrink line height). Neither worked: `NSTextViewportLayoutController` is aggressive about re-flowing downstream fragments when fragments GROW but lazy when they SHRINK; CoreText floored line heights to small positive values leaving residual hairlines; the override approach left fragments still routable to caret / find / selection. `shouldEnumerateTextElement` is the only primitive that fully elides.

###### Why a stored property + callback, not `@Binding` on the coordinator class

A subtle SwiftUI bug surfaced in v0.2.7.6 final iteration. The coordinator originally stored `@Binding var foldedHeadings: Set<String>` captured at `makeCoordinator()` time. SwiftUI rebuilds the wrapper struct on every render with a fresh `$viewModel.foldedHeadings` binding, but the coordinator kept its original. Within the same frame, the wrapper-side binding (current render) returned the correct mutated value while the coordinator-side binding (captured at first render) returned stale `[]` for the SAME `viewModel.foldedHeadings` property. The fold's `applyFoldStateIfChanged` saw `[]`, diffed against `lastSynced=["##"]`, ran sync with empty ranges, and UNFOLDED what the click handler had just folded — within the same frame. Smoking-gun log line that pinned it: `wrapper.foldedHeadings=["##"]` vs `coordinator.foldedHeadings=[]`, same point in time.

**Architectural rule:** **never store SwiftUI `@Binding` on a class that survives across SwiftUI re-renders.** SwiftUI builds fresh bindings on each render; the class holds a stale one. The captured `@Bindable` proxy goes out of sync after the first render cycle, and subsequent reads through the captured binding return stale values.

The locked pattern: coordinator owns a plain stored property (`var foldedHeadings: Set<String> = []`) + a callback (`var onFoldedHeadingsChanged: ((Set<String>) -> Void)?`). The wrapper's `updateNSView` does two things on EVERY call: (a) syncs FROM the wrapper's fresh-binding `foldedHeadings` TO the coordinator's stored property if they differ (handles external changes like initial load, undo, etc.); (b) re-installs the callback closing over THIS render's `$foldedHeadings` binding so click-handler mutations always push through the freshest available binding. Click handler invokes `coordinator.onFoldedHeadingsChanged?(coordinator.foldedHeadings)` after toggling — propagates to viewModel → frontmatter → save pipeline through the current-render binding, not a stale captured one. Same shape applies to ANY future class-stored state that needs to two-way-bind to a SwiftUI view model.

Knock-on cleanup that fell out of switching to the right elision primitive:
- `skipCaretOutOfFoldedRangesIfNeeded` (the original caret-skip-on-selection-change patch) deleted — selection can't enter elided ranges in the first place.
- `unfocusCaretIfInsideFoldedRange` + `moveSelectionOutOfFoldedRanges` survived but in cleaner shape — they only fire on chevron click when the caret was already inside the section being folded (Decision 2 + the layout-manager refusing to elide an element containing the active selection point).
- `isInsideFoldedRange` renderer guards deleted — folded fragments don't reach the renderer.
- `recalcOverscroll` + `clampToInsets` kept on the toggle path: engine-specific bottom-overscroll math derives from `baseContentHeight` rather than directly observing the layout manager, so it needs an explicit kick.

###### Why frontmatter, not a sidecar

Per `§9.2` (display state in frontmatter): when a feature needs per-Page UI state that survives across launches, it lives in YAML frontmatter, not in body content and not in a separate sidecar. `folded_headings: ["## Foo", "## Notes [2]"]` is the canonical example. Same shape extends to future per-Page UI state (column widths, scroll position, etc.).

###### Why ordinal disambiguation, not stable per-heading IDs (Decision 1)

Two real-world Pommora workflows have duplicate-text headings: project Pages with multiple `## Tasks` / `## Notes` sections under different projects, and structured templates with recurring section names. Exact-text keys would collide — folding one would fold all identical-text siblings.

Ordinal disambiguation appends `[N]` to the Nth identical occurrence in document order. Costs ~15 lines in `MarkdownDetection.foldableHeadings`, mirrored in the renderer's `headingKey` and the hover handler via shared `NativeTextViewCoordinator.disambiguatedHeadingKey(forLineRange:in:)`. Doesn't change the frontmatter shape (still a `[String]`). Doesn't change rename behavior (still drops state — orphan reconciliation cleans on save). One edge case: reordering duplicate-text sections shifts the ordinals; rare enough for v1.

Stable per-heading IDs (UUIDs in a `heading_ids:` map) is the v2 escalation if the ordinal scheme causes real friction.

###### Failure modes the locked pattern eliminates

- **`@MainActor` isolation cascade.** Helpers that read `coordinator.foldedRanges` / `hoveredHeadingKey` / `chevronAnimations` MUST be `@MainActor` because the coordinator is `@MainActor`. The renderer's `nonisolated` overrides (`renderingSurfaceBounds`, `draw(at:in:)`) wrap bodies in `MainActor.assumeIsolated`. The renderer's `isInsideCodeBlockAST` computed property is nonisolated but its body uses `MainActor.assumeIsolated` so the existing nonisolated stage-0 guards (`hasThematicBreak`, etc.) can call it directly without isolation cascade.
- **Frontmatter mutation needs its own save trigger.** The existing pipeline routes body keystrokes through `scheduleSave`; pure frontmatter changes (fold toggle) don't touch body. The `foldedHeadings` `didSet` on `PageEditorViewModel` explicitly calls `scheduleSave()` to bridge this gap.
- **`hasSuffix("\n")` is wrong for CRLF-terminated files.** Swift treats `\r\n` as a single extended grapheme cluster, so `"## Foo\r\n".hasSuffix("\n")` returns false. The fix is `trimmingCharacters(in: .newlines)` which handles LF / CR / CRLF / Unicode line/paragraph separators uniformly.
- **`mouseDown` collision.** `NativeTextView` already has a `mouseDown` override in `+DragSelectBoost.swift`. Adding a parallel override in `+HeadingFoldHover.swift` fails to compile. The fix: integrate chevron hit-test into the existing `mouseDown`, positioned AFTER prior intercepts but BEFORE drag-boost arms.
- **Class-level `final` blocks `open`.** `NativeTextView` is `final`; `override open func` on extension overrides emits a compiler diagnostic. Drop `open` on the overrides — `override func` is enough.
- **Content storage delegate must be set BEFORE first layout.** Otherwise cold-open of a page with `folded_headings: ["## Foo"]` renders the section expanded for a frame, then collapses when the next layout pass queries the now-set delegate. Wire-up in `NativeTextViewWrapper.makeNSView` between layout-manager-delegate setup and `textView.string` assignment.
- **`@Binding` stored on a class goes stale across SwiftUI re-renders.** See "Why a stored property + callback" section above. The coordinator must NOT hold `@Binding<T>` — the captured `@Bindable` proxy desyncs after the first wrapper render and reads/writes return stale values while a fresh wrapper-side binding works correctly. Use a stored property + callback re-installed in `updateNSView` on every call.
- **`textContentStorage(_:textParagraphWith:)` is for paragraph SUBSTITUTION, not ELISION.** Returning a paragraph whose `attributedString` doesn't match `range.length` (e.g. empty string for a non-empty source range) crashes `NSTextContentStorage.enumerateTextElementsFromLocation:` inside `setParagraphSeparatorRange:` via out-of-bounds `characterAtIndex:`. For elision use `NSTextContentManagerDelegate.shouldEnumerateTextElement:options:` returning `false`.
- **Chevron click skips `super.mouseDown`.** Returning `true` from the chevron-click handler short-circuits NSTextView's standard mouseDown processing — which is what we WANT (prevents caret jumping to the click point) but loses the natural layout-cascade NSTextView would otherwise run via `textLayoutFragment(for:)` hit-test. The fold-toggle path has to reproduce that cascade manually via `invalidateLayout` + `ensureLayout` + `textLayoutFragment(for:)` + `viewportLayoutController.layoutViewport()` + `needsDisplay`.
- **Layout invalidation must extend through document-end for SHRINKING content.** `invalidateLayout(for:)` only refreshes fragments INSIDE the passed range; fragments AFTER the range keep their cached Y positions. When content shrinks (fold), everything below the fold needs to reposition upward — so invalidate from fold-start through `documentRange.endLocation`, not just the fold's own range.

###### Reentry guards in this construct

- `isProgrammaticEdit` — not used here; the service doesn't write to `textStorage` at all (no attribute writes; content elision happens via delegate vending).
- Implicit guard: `applyFoldStateIfChanged` early-returns when `foldedHeadings == lastSyncedFoldedHeadings`, which protects against re-entry from SwiftUI's binding-driven `updateNSView` cascade (the most common reentry source — chevron click mutates the binding, SwiftUI re-fires updateNSView with the same state, the early-return absorbs it).

###### Files touched

Full per-file table in [`External/MarkdownEngine/NOTICE.md`](../External/MarkdownEngine/NOTICE.md).

##### 9.12 Dash auto-format — em / en via input-time lookbehind (v0.2.7.7)

**Status:** ✅ SHIPPED. Typed `--<non-dash>` → `—` (em-dash); typed ` - <space>` → ` – ` (en-dash); typed `-` adjacent to an existing `–` → `—` (en→em promotion). All three live in `MarkdownLists.handleInsertion` ([`Input/MarkdownListHandler.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift)) alongside the arrow auto-formats (`<-` → `←`, `->` → `→`, `<->` → `↔`), mirroring their pattern — defer the substitution to the *next* character so collisions resolve before the conversion fires.

###### Pattern: input-time lookbehind with single-char collision guards

This is the second instance of the input-time-transform pattern in the engine. The locked shape:

1. **Trigger on the *next* character, not on the marker chars themselves.** Em-dash fires when a non-dash is typed after `--`; en-dash fires when the second space is typed in the ` - ` pattern. Deferring the conversion until the user's intent reveals itself avoids stomping `---` (HR) for em-dash and avoids stomping bullets / wikilinks for en-dash.
2. **Use a single-character lookbehind for collision avoidance.** Em-dash checks `text[N-3] != "-"` (preserves `---` HR / YAML frontmatter / 4+ dash HR). En-dash checks "line has non-whitespace before the `-`" (preserves top-level + nested bullets).
3. **Inherit per-construct skip guards.** Both gate on `MarkdownDetection.isInsideCodeBlock(location:in:)`; en-dash additionally gates on the new `MarkdownDetection.isInsideWikilink(location:in:)` (line-scoped `[[ / ]]` depth counter) so filenames containing ` - ` aren't rewritten on disk.
4. **Wrap the write in `MarkdownLists.performEdit`** — sets `isProgrammaticEdit = true` for the duration, calls `shouldChangeText` + `replaceCharacters` + `didChangeText` in sequence, and respects the styler pipeline.

###### Why this trigger set (not iA Writer's `--` → `–`)

The `--<non-dash>` → en-dash convention (iA Writer / Ulysses) is a keyboard mnemonic; the ` - <space>` trigger maps onto en-dash's actual typographic role — spaced ranges and named-pair separators (`Monday – Friday`, `9 – 5`, `Paris – Berlin`). The earlier `~~` → en-dash proposal was rejected because `~~` is GFM strikethrough syntax (shipped feature with theme color at [`MarkdownEditorTheme.swift:74`](../External/MarkdownEngine/Sources/MarkdownEngine/Configuration/MarkdownEditorTheme.swift#L74), context-menu insertion at [`ContextMenu.swift:31`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/ContextMenu.swift#L31), and AST styler at [`AppleASTSupplementalStyler.swift:163`](../External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift#L163)) — auto-converting `~~` would silently kill strikethrough on typed input, paste, and the right-click "Strikethrough" command. Apple's `NSTextView.isAutomaticDashSubstitutionEnabled` is forced `false` at [`NativeTextViewWrapper.swift:181`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/NativeTextViewWrapper.swift#L181) and [`+Services.swift:185`](../External/MarkdownEngine/Sources/MarkdownEngine/TextView/Coordinator/NativeTextViewCoordinator+Services.swift#L185), so the engine has full control over dash transforms with no native AppKit race.

###### En→em promotion — closing the path back to em-dash

The auto-formatted `–` is a *typographically correct* substitution for ` - ` ranges, but Pommora can't read the user's mind on whether they actually wanted en-dash or em-dash there. Without a promotion path, the only way back to em-dash is delete-and-retype `--`. The promotion rule fixes that: typing `-` immediately adjacent to a `–` (on EITHER side) replaces the en-dash with `—` and consumes the typed hyphen. Two-sided so users don't have to remember which side of the en-dash they parked the caret. Skips inside code blocks for consistency with the other dash transforms; intentionally does NOT skip inside `[[...]]` wikilink targets (the en-dash-skip-in-wikilinks rule protects the AUTO-FORMAT trigger from accidentally firing while typing filenames; the promotion rule is an explicit user gesture, so the user wants it to fire).

###### Out of scope (v1)

- **Paste-time substitution.** Both auto-format branches gate on `replacementString.count == 1`; multi-char paste strings preserve `--` / ` - ` literally. Phase 2 follow-up could walk pasted strings applying the same per-char rules.
- **Discrete undo for the substitution.** `MarkdownLists.performEdit` doesn't register a paired undo action; `Cmd+Z` undoes the storage write + the original typed character together as one step. Matches AppKit's native dash-substitution undo behavior.
- **Em→en demotion.** Em-dash is the higher-prominence form; users rarely want to go BACK to en-dash from an em-dash, and there's no obvious keystroke pattern that disambiguates "demote this dash" from "type a literal hyphen here." Standard manual edit (select + Option+Hyphen) is the path.

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
| [`// Features//PageEditor.md`](.claude/Features/PageEditor.md) | Editor implementation spec. Shipped v0.2.7.0 feature surface + "Tables — to be implemented" deferred-work spec (folded in from the retired Page-Editor-Plan 2026-05-23). "Dynamic-syntax pattern" section is the locked architecture statement. |
| [`// Features//Pages.md`](.claude/Features/Pages.md) | On-disk page format, Markdown features in v1, opening behavior, sidebar visibility, wikilinks. |
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
