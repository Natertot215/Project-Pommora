## MarkdownPM — Implementation Plan

> **For agentic workers:** execute via `superpowers:subagent-driven-development` — one fresh subagent per task, two-stage review (self-review then code-review), a green commit per task, and re-assess the plan between green commits (CLAUDE.md hard rule "Re-assess the plan between green commits"). Phases 1-3 below are bite-sized: exact `file:line`, complete code per step, a failing test written first, the exact `xcodebuild`/`swift` run-command with expected output, and a commit message. Phases 4-6 are a concrete task-level outline (named tasks + gates + recorded open-decisions); their exact assertions depend on what the Phase-2 characterization net reveals and get filled in as bite-sized steps only after Phase 2 is green.
>
> **Execution protocol (stated once; do not restate per task):** Every `xcodebuild test` runs via a background Agent (quirk #13) filtered to `-only-testing:PommoraTests` / the MarkdownPM test filter, visually verifying a non-zero executed count (quirks #1/#17); every commit reverts incidental SPM-package reordering in the pbxproj (quirk #6), never touches unattributed working-tree changes (quirk #10), and ends with the standard CLAUDE.md Co-Authored-By trailer.

_Verified against source 2026-06-02 (see the CodeMap report)._

### Goal

Fold the vendored `External/MarkdownEngine` Swift package into a Pommora-owned package + module named **`MarkdownPM`**, then disassemble and reassemble it cleaner: collapse the two independent parse passes (regex tokenizer + uncached Apple `swift-markdown` AST) into **one cached Apple-AST-backed spine** parsed once per text change; route the three inline constructs Apple parses cleanly (emphasis, inline-code, links) onto that AST and **delete the 173-line hand-rolled asterisk-only emphasis parser**; keep the regex layer for everything Apple is absent or wrong on (wikilinks `[[..]]`, embeds `![[..]]`, the `$…$` math/currency heuristic, the empty-`[]`/`- [ ]`/`-[x]` checkbox split, the Setext-suppression standalone-parse trick, heading marker reveal/sizing); merge the two styler sites into **one owned `MarkdownPMStyler`** with **one merged `MarkdownPMTheme`**; transplant the runtime-only TextKit 2 / OS-bug workarounds verbatim; and fix the #9 caret-stutter as a side-effect of the parse collapse. **Pages only** — Items are excluded beyond keeping a clean inert seam; the wikilink *feature* is a separate post-rebuild session and this plan preserves only its seam.

### Architecture

- **Where the code lives.** The brain (parser, styler, theme, detection, input handlers, renderer) lives **inside the `MarkdownPM` package** — `External/MarkdownPM/Sources/MarkdownPM/`. The package boundary is the deliberate **Swift-6-strict-concurrency isolation seam**: the package stays Swift 5.9 with relaxed concurrency settings, the app stays Swift 6 strict-concurrency + ExistentialAny. New brain/styler code does NOT move into the app target.
- **Public front door.** `MarkdownPM` exposes one SwiftUI bridge, `MarkdownPMEditor` (an `NSViewRepresentable`, renamed from `NativeTextViewWrapper`), configured by one value type `MarkdownPMConfiguration` (renamed from `MarkdownEditorConfiguration`). The app's sole editor call site is `Pommora/Pommora/Pages/PageEditorView.swift:210`. Verbatim-transplanted body internals (`NativeTextViewCoordinator`, `NativeTextView`, `MarkdownTextLayoutFragment`, the `+*.swift` extensions) keep their existing internal names — only the two public-surface types and the new brain types get branded.
- **The two disjoint parse systems today (the thing being collapsed).** (1) The regex tokenizer `MarkdownTokenizer.parseTokens` (no `import Markdown`) feeds a **size-1 memo** `parsedDocument(for:)` (`NativeTextViewCoordinator+Restyling.swift:146`, cache fields `NativeTextViewCoordinator.swift:136-137`) holding **only six `[MarkdownToken]` arrays** in the `ParsedDocument` struct (`NativeTextViewCoordinator.swift:143-150`) — it does **not** hold an Apple `Document`. (2) The Apple `Document(parsing:)` is parsed **uncached** in two hot places: `AppleASTSupplementalStyler.swift:30` (whole-document, every keystroke — the primary #9 culprit) and `NativeTextViewCoordinator+HeadingFolding.swift:160` (`syncHeadingFolding`, only when folds active). Phase 3 extends the existing `ParsedDocument` to also hold the Apple `Document`, parsed once inside `parsedDocument(for:)`, and threads it into both sinks.
- **Styler chain today (the thing being merged).** A **primary** regex-token styler `MarkdownStyler.styleAttributes` (`MarkdownStyler.swift:86`, caret/active-token-aware) and a **supplemental** Apple-AST styler `AppleASTSupplementalStyler.styleAttributes` (`AppleASTSupplementalStyler.swift:25`, caret-unaware; covers BlockQuote/Strikethrough/Table; `visitThematicBreak` is a deliberate no-op) are composed at **two sites**: per-edit `TextStylingService.swift:94` (paragraph-scoped, with a spelling pre-pass) and full-rebuild `NativeTextViewCoordinator+Restyling.swift:76` (whole-range, no spelling pre-pass, its own hand-rolled apply loop). Phase 5 collapses both into one owned styler.

### Tech Stack

- **Apple `swift-markdown` 0.8.0** (cmark-gfm-backed; pinned exact through the entire rebuild — a version bump is a separate decision, D23). Default `ParseOptions` already emit GFM Strikethrough + Table; the re-home must not introduce custom options that disable GFM.
- **TextKit 2** (`NSTextLayoutManager` / `NSTextContentManager` / `NSTextLayoutFragment` / `NSTextLineFragment`). `MarkdownPMEditor.makeNSView` hard-`fatalError`s if a TextKit 2 stack is absent (`NativeTextViewWrapper.swift:140`) — the module/OS-target change must keep TextKit 2 available.
- **Yams** (app-side frontmatter codec, untouched here) + **GRDB** (SQLite index, untouched here).
- **Package manifest:** SPM `swift-tools-version:5.9`, package + product + target renamed `MarkdownEngine` → `MarkdownPM`, testTarget `MarkdownEngineTests` → `MarkdownPMTests`.

### The spine (mental model)

Take the vendored engine **apart**, understand every piece, then **reassemble it cleaner, simpler, better** as the Pommora-owned `MarkdownPM`. It is neither reinvented (we keep what `swift-markdown` + the donor engine genuinely give us) nor preserved-as-is (donor code is not sacred). What makes "cleaner" *safe* rather than risky is the Phase-2 characterization net landing **before** any behavior change: the guarantee is **tested-identical on a fixed corpus, with every intentional divergence flagged + scoped in a divergence ledger — not byte-identical**. The sequence is therefore load-bearing: Phase 1 is a pure rename (safe with no net); Phase 2 builds the net; Phases 3-6 only ever change behavior *behind* that net. **Pages only.**

---

### Locked Decisions

These are Nathan-locked rulings that fold into this plan as its single decisions record (there is no separate decisions doc on disk). They **override** the v2 Service doc wherever they conflict. The CodeMap report is ground truth for every `file:line` + behavior; the v2 Service doc is a structural reference for phase *intent* only.

**Scope**

- **LD-1 — Pages only.** Items are excluded. Build no Item render profile beyond a clean inert seam; build no `@`-tagging. The wikilink *feature* (resolver, index, navigation, autocomplete UI) is a **separate post-rebuild session** — this plan preserves only the seam (see LD-22/LD-23) and builds nothing wikilink-feature-specific.
- **LD-2 — Phase detail split.** Phases 1-3 ship as full bite-sized writing-plans steps (exact `file:line`, complete code, failing-test-first, run-command + expected output, commit). Phases 4-6 ship as a concrete task-level outline (named tasks, gates, recorded open-decisions) — their exact assertions are written only after the Phase-2 net reveals current behavior.

**Module / re-home (Phase 1)**

- **LD-3 — Name = `MarkdownPM`** for both package and module. Pommora-prefixed *type* names (e.g. `PommoraMarkdownStyler`) are permitted: the brand-name ban covers on-disk JSON keys and Swift namespace-qualifier discriminator tricks (no `Pommora.X`), **not** ordinary type names.
- **LD-4 — Keep relaxed Swift 5.9 package settings.** The package wall is the concurrency-isolation seam; do not raise the package to Swift 6 strict concurrency. New brain/styler code lives inside the package, not the app.
- **LD-5 — Rename the public front door only.** `NativeTextViewWrapper` → `MarkdownPMEditor`; `MarkdownEditorConfiguration` → `MarkdownPMConfiguration`. Verbatim body internals keep their existing names.
- **LD-6 — Reconcile the vendoring docs.** Rewrite `NOTICE.md`'s planned-migration rows to MarkdownPM names + inside-package placement, and correct **"6 extensions" → 4** sibling `MarkdownStyler+*.swift` files (`+TextStyling` / `+Links` / `+Latex` / `+Images`; code + checkbox styling live as inline `extension` blocks **inside** `MarkdownStyler.swift`). **Reuse the existing `SourceRangeConverter`** (`AppleASTSupplementalStyler.swift:271`) — do **not** add a duplicate `SourceRangeToNSRange`. Update `Guidelines/Paradigm-Decisions.md` #7 from "vendored swift-markdown-engine" to "MarkdownPM-owned."

**Parser scope, construct-by-construct**

- **LD-7 — Apple AST *locates*; our owned styler still decides caret-aware hide/reveal.** Adopt Apple for **emphasis**, **inline-code** (Apple's range includes the backticks by design), and **links** (take `.destination`).
- **LD-8 — Stay regex** where Apple is absent or wrong: wikilinks `[[..]]` + embeds `![[..]]` (no cmark node); the `$…$` math/currency heuristic; bullets/list/empty-`[]` checkbox; the Setext-suppression standalone-parse trick.
- **LD-9 — Unify the two heading detectors into ONE** (pre-emptive DRY cleanup): the tokenizer's `^#{1,6}([ \t]|$)`-style rule (`MarkdownTokenizer.swift:23-26`, requires a space) vs `MarkdownDetection.swift`'s `^#{1,6}([ \t]|$)` (space/tab/EOL). Adopt **CommonMark semantics (space/tab/EOL)** so the styler and the fold path agree. This is a **behavior change** (bare `#`, tab-separated, trailing-space-only lines): do it **behind the Phase-2 net**, log it in the divergence ledger, signed off. The fold path keeps using Apple `Heading.level` + range; **marker-reveal/sizing stays regex** (Apple exposes no `#` delimiter sub-ranges — reconstruct the 1..6 hide-ranges by width-subtraction).
- **LD-10 — Emphasis: delete the hand-rolled parser, adopt Apple.** `MarkdownTokenizer+Emphasis.swift` (173 lines) is **asterisk-only** (`0x2A`; no underscore) and has exactly one caller (`MarkdownTokenizer.swift:58`). Delete it; adopt Apple emphasis as truth, **relocating** the `.italic` / `.bold` / `.boldItalic` token emission into the AST walk (do not drop the enum cases blind).
- **LD-11 — Emphasis: ADOPT underscore support.** `_italic_` / `__bold__` will newly work (Apple + CommonMark + Obsidian). This is an **intentional behavior change** → divergence ledger + sign-off. **Phase 2 must pin the current asterisk-only behavior** so the divergence is explicit, and the deletion of `+Emphasis.swift` is **gated behind a green adversarial emphasis corpus** (rule-of-3, flanking, intra-word, cross-line).
- **LD-12 — Math/LaTeX has no Apple equivalent.** Keep the `$…$` math/currency heuristic as a Pommora supplemental pass; its thresholds (120/40/6; 1-3-letter run = math, e.g. `$x$`/`$abc$`; pure numbers = money) are **pinned verbatim by Phase-2 tests before any tidy**.
- **LD-13 — Never merge the three empty-`[]` regex classes.** The list-detection class (optional `\[[ xX]?\]`), the checkbox class (non-empty `\[[ xX]\]`), and the dash-bullet glyph class (bracket-excluding) are **deliberately different** (finalized 2026-06-01). Hoist shared constants if useful; never collapse the classes.

**Parse spine / #9 (Phase 3)**

- **LD-14 — #9 emerges from consolidation, not a standalone fix.** Extend the **existing** `ParsedDocument` (`NativeTextViewCoordinator.swift:143-150`) to also hold the Apple `Document`, parsed once inside `parsedDocument(for:)` (`+Restyling.swift:146`). Thread it into `AppleASTSupplementalStyler.styleAttributes` (drop its `Document(parsing:)` at `:30`) and into `syncHeadingFolding` (drop its parse at `:160`). Do **not** introduce a new spine type. The `styleAttributes` signature must still receive `text`/`nsText` (it does NSString-length, substring, and byte→UTF-16 work the `Document` alone can't supply).
- **LD-15 — Leave the per-fragment renderer parse OUT of the cache** (`MarkdownTextLayoutFragment.swift:453`) — intentional per-fragment isolation that avoids the `.pommoraThematicBreak` attribute-inheritance leak.
- **LD-16 — Measure with Instruments in BOTH fold and no-fold states; snapshots must not move.**

**Dead-code removals (CodeMap-verified)**

- **LD-17 — Remove the `isInsideInlineLatex` family entirely** (`MarkdownDetection.swift:410-435`): grep-confirmed **zero callers** outside the file. Do not migrate it.
- **LD-18 — KEEP `isInsideWikilink`** (`MarkdownDetection.swift:367-389`): a line-scoped `[[`/`]]` depth counter, no token/AST equivalent, required by the en-dash transform (`MarkdownListHandler.swift:547`).
- **LD-19 — Delete the re-parsing `in:String` overloads of `isInsideCodeBlock` / `isInsideLatex`** and rewire the live callers (SpellingPolicy, `+Services`, `MarkdownListHandler` ×2, `MarkdownInputHandler` — 4 files / 7 call sites) to the cached-token query.
- **LD-20 — Delete the dead `taskListRegex`** (`MarkdownTokenizer.swift:27`): declared, never used, no `.taskList` kind (Phase 6 DRY). A live near-copy with a different marker class exists at `MarkdownStyler.swift:35` (declaration) / `:526` (use) — leave that one.

**Dual-styler merge (Phase 5)**

- **LD-21 — Collapse BOTH styler-composition sites into ONE owned `MarkdownPMStyler`** — per-edit `TextStylingService.swift:94` and full-rebuild `+Restyling.swift:76` — or they drift. Stage the merge: safe non-caret constructs first (headings/emphasis/links/code/strikethrough/table), caret-aware constructs last. The styler must keep emitting **NOTHING** for HR/ThematicBreak (the sole-writer rule below) and must preserve initial-load unscoped completeness vs per-edit paragraph-clipping.

**Sole-writer + always-collapsed locks**

- **LD-22 — HR/ThematicBreak appearance is owned solely by `syncHRVisibility`.** The styler emits nothing for it (`AppleASTSupplementalStyler.visitThematicBreak` stays a no-op). Re-introducing an HR-specific persisted attribute revives the "duplicate HR on every Enter" regression.
- **LD-23 — Blockquote stays always-collapsed** through the consolidation (do **not** add caret-aware reveal for BlockQuote/Table markers — not asked for). Strikethrough is **inline**, not block.

**Theme (Phase 5)**

- **LD-24 — `MarkdownPMTheme` = one navigable file** merging `MarkdownEditorTheme` (12 color slots: 8 dynamic system + 4 fixed literals) + `MarkdownEditorConfiguration`'s value sub-structs (16 inline sub-structs; the top-level config has 18 props), organized with MARK sections. Keep system colors via named slots (a brand palette is deferred to v0.4.0). Heading multipliers change to the **new scale** `[H1 2.0, H2 1.75, H3 1.5, H4 1.25, H5 1.15, H6 TBD]` (Nathan 2026-06-02 — no heading below body size; supersedes the shipped `[2.0, 1.5, 1.17, 1.0, 0.83, 0.67]`). Intentional Phase-5 visual change (divergence D-HEAD-2): Phase 2 pins the CURRENT shipped values, Phase 5 applies the new scale + scales heading padding/spacing proportionally. **H6 value pending Nathan's confirm.**
- **LD-25 — Hoist the duplicated code-text color** `NSColor.systemRed.withAlphaComponent(0.85)` (`MarkdownStyler.swift:462` **and** `:499`, same file) into one `MarkdownPMTheme.codeText` slot whose default reproduces it byte-for-byte (no visual change).
- **LD-26 — Brand-meaningful renderer-resident values** (blockquote bar/card, divider, 1.5× bullet, checkbox tint): lift the **colors** into named theme slots; leave the **pixel geometry** with the verbatim draw code. Reading a value from the theme inside a verbatim file does **not** count as modifying that file.

**Save path + DEC-1**

- **LD-27 — Two save producers/sinks.** `+TextDelegate.swift:61` *computes* the storage string via `WikiLinkService.makeStorageState`; `:70` is the actual `@Binding` write (inside `DispatchQueue.main.async`, deduped at `:67`). A second producer is `+Services.swift:325` (Writing-Tools commit). `ContextMenu.swift` also has ~10 raw `self.text = tv.string` writes that **bypass** `makeStorageState` (Phase-6 correctness item — verify they do not persist display-form links).
- **LD-28 — DEC-1 (id-on-disk) is deferred to the Wiki-Link session.** Wikilinks stay plain `[[Title]]` on disk; the target Page identity is its own frontmatter ULID (`PageFrontmatter.swift:13`, load-bearing) — the **link never embeds an id**. This rebuild does **not** build the structural id-guard (it is wikilink-feature work). It keeps the safe status quo (no resolver is wired, so no id is ever written) and makes the **consolidated save path the single chokepoint** where the future guard + on-disk-format choice will land. Phase 2 only **characterizes** current behavior (today a resolver-stamped id WOULD be embedded) + carries a `.disabled` anchor naming **both** write sinks (`+TextDelegate.swift:70` + `+Services.swift:325`) as the future regression lock. The strip itself + Unified-ID-vs-Obsidian are the Wiki-Link session's call (the ULID-in-frontmatter is already the portable identity; Obsidian has no note-id).

**Other locks**

- **LD-29 — swift-markdown pinned 0.8.0** through the rebuild (a bump is the separate D23).
- **LD-30 — The UTF-8/UTF-16 column bug is deferred** (`LineOffsetIndex` treats cmark-gfm's UTF-8 byte columns as UTF-16); pin a multibyte corpus **now** so the current behavior is explicit before any future fix.
- **LD-31 — The 9 input transforms live in `MarkdownListHandler.swift:358-898`** (`MarkdownInputHandler` is a thin facade). Smart-quotes are delegated to macOS (`isAutomaticQuoteSubstitutionEnabled = true`); auto-dash is forced OFF (the engine owns dashes). Keep all 9 verbatim + pin them.
- **LD-32 — Active parallel UIX session.** A separate non-editor UIX session may be running; the `Pommora/*` working tree is **not** guaranteed clean between subagent dispatches. Commits stay scoped; **never revert unattributed working-tree changes** — surface them in the report.

---

### Public Contract — must not break

The app touches exactly **3 import sites** + **2 test import sites** and one editor call site (`PageEditorView.swift:210`). Everything below is verified against source.

**The 15-param `MarkdownPMEditor` init** (`NativeTextViewWrapper.swift:85-101`, defaults shown) — **7 used + 8 dormant**:

| # | Param | Status | Disposition |
|---|---|---|---|
| 1 | `text: Binding<String>` | **used** | keep |
| 2 | `isWikiLinkActive: Binding<Bool> = .constant(false)` | dormant (`@Binding`, not a closure) | **KEEP** — wikilink seam |
| 3 | `pendingInlineReplacement: Binding<InlineReplacementRequest?> = .constant(nil)` | dormant (`@Binding`, not a closure) | **KEEP** — wikilink seam |
| 4 | `foldedHeadings: Binding<Set<String>> = .constant([])` | **used** | keep |
| 5 | `configuration: MarkdownEditorConfiguration = .default` | **used** → `MarkdownPMConfiguration` | keep (renamed) |
| 6 | `fontName: String = "SF Pro"` | **used** (app passes its own) | keep |
| 7 | `fontSize: CGFloat = 16` | **used** | keep |
| 8 | `documentId: String = "default"` | **used** | keep |
| 9 | `isEditable: Bool = true` | **used** | keep |
| 10 | `onPasteImage: ((NSPasteboard) -> String?)? = nil` | dormant | **KEEP** |
| 11 | `onLinkClick: ((String) -> Void)? = nil` | dormant | KEEP (the param D20 historically missed — confirms count = 15, not 14) |
| 12 | `onCaretRectChange: ((CGRect) -> Void)? = nil` | dormant | **SHED** (verified below) |
| 13 | `onInlineSelectionChange: ((InlineSelectionState?) -> Void)? = nil` | dormant | **KEEP** |
| 14 | `onCodeBlockSelectionChange: (([CodeBlockSelection]) -> Void)? = nil` | dormant | **SHED** (verified below) |
| 15 | `onScrollOffsetChange: ((CGFloat) -> Void)? = nil` | **used** (the only wired closure, `PageEditorView.swift:217`) | keep |

**Seams kept vs shed:**
- **Keep (wikilink/inline seam):** `isWikiLinkActive`, `pendingInlineReplacement` (both `@Binding`, dormant), `onInlineSelectionChange`, `onPasteImage`, `onLinkClick`.
- **Shed:** `onCaretRectChange` + `onCodeBlockSelectionChange`. **Verified safe** (the CodeMap flagged the code-block copy-overlay feature as a gap to confirm before deleting): the feature is internally plumbed in the engine — `updateCodeBlockSelection` exists (`+Services.swift:230`) and is called from `+TextDelegate.swift:151,326` and `NativeTextViewWrapper.swift:225,242,387` — but it **terminates in the `onCodeBlockSelectionChange` closure (`+Services.swift:232,241,271`), which the app NEVER sets**. The app call site (`PageEditorView.swift:210-217`) wires only `onScrollOffsetChange`; an app-side grep for `onCodeBlockSelectionChange` / `onCaretRectChange` / `updateCodeBlockSelection` returns nothing. Shedding the two params requires removing the internal `updateCodeBlockSelection` plumbing + the `CodeBlockButton`/`CodeBlockSelection` overlay types + `onCaretRectChange` forwarding (`+Services.swift:414`, `+TextDelegate.swift:310`) along with the params — scoped as a Phase 6 task, since nothing app-facing depends on them.

**Frozen attribute-key string literals** (exact; the Swift symbol name diverges from the literal — do **not** rename the literal). Verified at source:
- `wikiLinkID` → `NSAttributedString.Key("NodeLinkID")` (`MarkdownToken.swift:14`) — symbol is `wikiLinkID`, literal is `"NodeLinkID"`.
- `taskCheckbox` → `NSAttributedString.Key("TaskCheckbox")` (`MarkdownToken.swift:15`).
- LaTeX keys (`MarkdownTextLayoutFragment.swift:17-20`): `"LatexRenderedImage"`, `"LatexImageBounds"`, `"LatexIsBlock"`, `"LatexBlockOffsetY"`.
- These are read by the styler / renderer / checkbox toggle / `makeStorageState`; renaming any literal breaks them silently.

**Other frozen public surface (verified):**
- `StyledRange` typealias is defined at `MarkdownStyler.swift:79` (`typealias StyledRange = (range: NSRange, attributes: [NSAttributedString.Key: Any])`) and consumed in `AppleASTSupplementalStyler.swift` + `TextStylingService.swift`. Re-homing the supplemental file in isolation breaks if this typealias isn't resolvable.
- **`TextInsets` stays a public struct** (`MarkdownEditorConfiguration.swift:123`) with `public init(horizontal: CGFloat = 0, vertical: CGFloat = 0)` (`:127`).
- `MarkdownPlainText.extract(from:) -> String` stays public (the only cross-module signature; sole consumer `PageTextStats.swift:36`).
- `MarkdownDetection.reconcileFoldedHeadings` stays public (called by `PageEditorViewModel.swift:92`).
- `MarkdownTokenKind` / `MarkdownToken` are **internal** (`MarkdownToken.swift:18,32`) — `[MarkdownToken]` is a package-internal type frozen by tests, not a public promise.

---

### Keep-Verbatim + Manual-Verify Register

Runtime-only / OS-bug / library workarounds. **No unit test catches these** — manual visual verification is mandatory when transplanted, and they are **off-limits to restructure**. The only safe touch is extracting a shared subview-lookup. Each is cited to the CodeMap's Keep-Verbatim register with the verified `file:line`. (Note: FB-radar numbers live in these file headers, **not** in `NOTICE.md`.)

| Workaround | file:line | Why it's untestable / load-bearing |
|---|---|---|
| **FB22524198** trailing-newline caret Y-snap (KVO on indicator.frame + `isApplyingCaretShift` recursive guard) | `NativeTextView+CaretWorkarounds.swift:69-106` | OS caret-rendering bug; KVO-driven, runtime-only |
| Block-image caret policy (hide/resize `NSTextInsertionIndicator` over block LaTeX) | `NativeTextView+CaretWorkarounds.swift:19-66` | Caret rendering over inline block images |
| **FB15131180** extra-line-fragment metrics pin (`@objc(extraLineFragmentAttributes)` private-selector bridge + delegate seed + `nonisolated`/`MainActor.assumeIsolated` overrides) | `MarkdownTextLayoutFragment.swift:720-721, 1186-1198, 815-816, 727-728, 128` | Still-open OS bug (worse in macOS 15); ~30pt usageBounds inflation; the selector string is a KVC contract |
| Writing-Tools mid-session Cmd+Z recovery (prefer `wtPostUndoSnapshot`) + undo observer | `+Services.swift:312-340, 367-378` (broader block `:281-397`) | macOS 15 stale accept-action corrupts text + contaminates attrs with the 0.1pt marker font; a bad rebuild silently corrupts body text |
| WT child-window position fix (capture origin, re-pin >0.5pt drift, 20×0.05s polling) | `+Services.swift:345-363, 385-397` | macOS 15 mis-positions the WT Done/Original panel |
| 149pt height-oscillation guard (width-delta `>0.5` @222 + height-delta `>1` @231; captured `lastObservedViewportWidth` @218 — **two epsilon gates, no boolean re-entrancy flag**) | `NativeTextViewWrapper.swift:218-234` | TextKit2/AppKit frame-change feedback loop; epsilons tuned to observed behavior |
| `shouldEnumerateTextElement` fold elision (returns Bool) + sibling `textParagraphWith` nil-return | `+HeadingFolding.swift:516-544` (elision) + `:551-556` (the nil-return that SIGTRAPs if a length-mismatched paragraph is substituted) | Correct Apple API use; the substitution path crashes `enumerateTextElementsFromLocation:` |
| `.pommoraThematicBreak` tombstone comment (DEAD-but-reserved) | `MarkdownTextLayoutFragment.swift:21-28` | Removing it loses the duplicate-HR regression signal (L1) |
| Per-fragment in-isolation block detection (NOT attribute-based) | `MarkdownTextLayoutFragment.swift:62-70` | Prior `.pommoraThematicBreak` attribute leaked via inheritance ("duplicate HR on every Enter") |
| `@MainActor.assumeIsolated` + `@unchecked Sendable` fragment-override shim | `MarkdownTextLayoutFragment.swift:29-50, 161-192, 196-215` | Reconciles AppKit's `nonisolated` overrides with Swift-6 inference; safe only because TK2 draws on the main thread |
| Shift+Enter modifier-flag interception (`NSApp.currentEvent.modifierFlags`) | `MarkdownListHandler.swift:680-687` | macOS maps plain + Shift Return both to `insertNewline:` (L9) |
| `performEdit` `isProgrammaticEdit` re-entrancy dance | `MarkdownListHandler.swift:22-25` | NSTextView fires delegate callbacks during programmatic edits |
| `isSyncingHRVisibility` reentry guard | `NativeTextViewCoordinator.swift:90-97`, used in `+HRVisibility` | AppKit edit-notification re-entry recursion |
| HR margin-invariant spacing + dashes-always-body-sized (only foregroundColor flips) | `+HRVisibility.swift:171-183, 256-277` | Eliminates ~11pt vertical jump on caret crossing the HR boundary (Session 12) |
| `LineOffsetIndex` UTF-8-byte→UTF-16 column conversion (+ `\n`/`\r`/`\r\n`) | `AppleASTSupplementalStyler.swift:296-378` | cmark-gfm reports UTF-8 byte columns; multibyte breaks without a per-scalar walk (the LD-30 bug lives here) |
| Table separator-row hiding via source-range arithmetic + font-0.1+clear-color marker collapse | `AppleASTSupplementalStyler.swift:217-241, 148-156, 198-213` | swift-markdown does not expose the `\|---\|` row as a node |
| CommonMark emphasis flanking + Rule-of-3 stack | `MarkdownTokenizer+Emphasis.swift:51-156` | Only transplant if kept transitionally; **deleted in Phase 4 once the corpus is green** (LD-10/LD-11) |
| `isInlineMathContent` currency/math heuristic | `MarkdownTokenizer.swift:210-240` | No Apple-AST equivalent; Pommora money-vs-math discrimination (LD-12) |
| `isInsideWikilink` manual `[[`/`]]` depth counter | `MarkdownDetection.swift:367-389` | No token/AST equivalent; sole en-dash-transform guard (LD-18) |
| Standalone in-isolation parse in `isThematicBreakLine`/`isHeadingLine` | `MarkdownDetection.swift:77, 160` | The isolation IS the Setext-H2 suppression |
| Checkbox-bracket collapse via font 0.1 (NOT zero); bullet `-` hidden via clear-color + kern (NOT font-collapse) | `MarkdownListHandler.swift:296-318, 319-334, 272-287`; styler `MarkdownStyler.swift:540-545` | Checkbox-draw reads `[` pointSize (zero collapses the box); `•` overlay positioning depends on the preserved hidden-`-` width (L12/L13) |
| `mouseDown` dispatch order (checkbox→remap→chevron→boost→super) | `NativeTextView+DragSelectBoost.swift:14-39` | Checkbox/chevron must consume the click before super repositions the caret |
| Heading-fold layout invalidation suite (`nudgeAttributes`, `invalidateFoldLayout` 4-step, `moveSelectionOutOfFoldedRanges`, `unfocusCaretIfInsideFoldedRange`, `chevronAnimationTick` collect-then-remove) | `+HeadingFolding.swift:123, 240, 206, 414, 337-364` | TextKit2 caches Y positions; layout manager refuses to elide the selection-hosting element |

---

### DRY Boundary

**Unify testable brain logic that has drifted; transplant untestable runtime-only workarounds verbatim.** The line between them is whether the Phase-2 net can cover the behavior.

- **UNIFY (testable, behind the net) —** lean toward cleanup wherever the net covers it:
  - The **two heading detectors** → one CommonMark (space/tab/EOL) rule (LD-9).
  - The **two styler-composition sites** → one owned `MarkdownPMStyler` (LD-21).
  - The **duplicated `systemRed@0.85`** → one `MarkdownPMTheme.codeText` slot (LD-25).
  - The **~10 scattered caret/`isInside` spots** → one `isInside(range:tokens:)` core + a `markerAttributes(active:)` factory, **preserving the caret carve-outs** (math-overlap activation + checkbox end-of-syntax reveal).
  - The **dead regexes** (`taskListRegex`, the dead `isInsideInlineLatex` family) — delete (LD-17/LD-20).
- **TRANSPLANT VERBATIM (untestable, manual-verify) —** every item in the Keep-Verbatim register above. These are runtime-only OS-bug workarounds no unit test catches; they stay off-limits to restructure. Reading a theme value inside a verbatim draw file is the *only* permitted touch (LD-26).

---

### Risks (carry into every phase)

- **No safety net until Phase 2.** Phase 1 is a pure rename (safe). Phase 3 is the first behavior-touching phase (the deleted detection overloads gate the dash/checkbox transforms), so **Phase 2 must land green before any Phase-3 behavior change**.
- **Emphasis deletion is unsafe without the adversarial corpus gate** (LD-10/LD-11). Pin asterisk-only behavior in Phase 2; delete `+Emphasis.swift` only when the rule-of-3 / flanking / intra-word / cross-line corpus is green.
- **The styler merge (LD-21) is the single highest-risk step** — divergent signatures (primary caret-aware + paragraph-scoped; supplemental caret-unaware + whole-doc), two apply mechanisms (unscoped initial-load vs per-edit clipping). Stage it; keep the sole-writer rule (don't re-break duplicate-HR, LD-22).
- **Body-workaround restructure is the most dangerous DRY temptation** — runtime-only, manual-verify mandatory.
- **Input-cascade coupling traps:** `-` kept in the fast-path exclusion (deleting it kills `<-`); `isInsideWikilink` in the en-dash branch (removing it corrupts filenames, LD-18); em-dash block order is load-bearing (it's an HR-conflict *preserve* guard, not a re-break).
- **The size-1 parse memo thrashes per keystroke** — `shouldChangeTextIn` (pre-edit string, `+TextDelegate.swift:365`) and `textDidChange` (post-edit string, `:108`) defeat it within one keystroke. Confirm this in a Phase-2 parse-count probe before claiming the regex tokenize "runs once."
- **`Markdown.Document` retention on the `@MainActor` coordinator** — confirm Sendable/safe-to-retain across events before caching it (Phase 3).
- **The empty-`[]` three-class split is fragile** (finalized 2026-06-01) — hoist shared constants, never merge the classes (LD-13).
- **The UTF-8/UTF-16 column bug is latent** in `LineOffsetIndex` (LD-30) — pin a multibyte corpus now; do not make it worse.
- **Parallel UIX session (LD-32)** — never revert unattributed working-tree changes; keep commits scoped; surface anything unexpected.
- **pbxproj churn** — Xcode auto-reorders SPM package entries (Yams/GRDB) on every build; revert that incidental noise before committing so diffs stay limited to intended files. The engine's own `MarkdownEngineTests` are **not** in the Pommora test scheme today (`PommoraTests.packageProductDependencies` = GRDB only; the 2 test imports resolve only via the host-app link) — Phase 2 must wire `MarkdownPMTests` into the run or the net is a **false-green trap**.

---

### Non-Goals

- A custom GFM parser (we keep `swift-markdown`).
- A SwiftUI-native body (TextKit 2 stays).
- Any **Item** render profile or `@`-tagging (Pages only — beyond a clean inert seam, LD-1).
- The wikilink **feature** (resolver / index / navigation / autocomplete UI) — separate post-rebuild session; preserve the seam only (LD-22/LD-23, LD-28).
- A swift-markdown version bump (pinned 0.8.0, LD-29; bump is the separate D23).
- Reference / shortcut / autolink link support (inline-style links only).
- A brand color palette (system colors via named slots; brand palette deferred to v0.4.0, LD-24).
- True tables, the UTF-8/UTF-16 column fix (LD-30), and Fix-Log-#8 backspace-on-checkbox-syntax-delete beyond noting it is *unbuilt* (a Phase-6 new-work item, not a regression).

---

## Phase 1 — Re-home as MarkdownPM

This phase is a **pure rename / re-home**: behavior-preserving, mechanical, and safe to land *before* the Phase-2 characterization net exists, because nothing about parsing, styling, layout, or saving changes. The package keeps its relaxed Swift 5.9 settings (the package wall is the concurrency-isolation seam — do not touch tools-version or add strict-concurrency flags). New brain/styler code from later phases lives **inside** this package, not in the app. After Phase 1, the symbol `MarkdownEngine` no longer appears anywhere in the tree; the import is `MarkdownPM`, the public front door is `MarkdownPMEditor`, and the config type is `MarkdownPMConfiguration`.

The implementing engineer has zero prior context. Every path is absolute-from-repo-root (repo root = `/Users/nathantaichman/The Studio/Projects/Project Pommora`). Run all `git` and `xcodebuild` commands from the repo root. Trust `xcodebuild` over SourceKit/IDE squiggles (CLAUDE.md quirk #3): a "Cannot find type" or "No such module" red mark in Xcode after a rename is almost always stale — only the build result counts.

Decisions governing Phase 1: LD-1, LD-2, LD-3, LD-4, LD-5, LD-6 (see master Locked Decisions). The CodeMap report is ground truth for every `file:line` + behavior claim; the v2 Service doc is a phase-INTENT reference only.

**Verification recorded for a later phase (do NOT act on it in Phase 1):** I traced the code-block copy-overlay seam. `updateCodeBlockSelection` (`NativeTextViewCoordinator+Services.swift:230`) is internally wired (called from `+TextDelegate.swift:151,326` and the wrapper at `:225,242,387`) and fires `onCodeBlockSelectionChange` (`+Services.swift:232,241,271`). But the app passes **no** `onCodeBlockSelectionChange` and **no** `onCaretRectChange` closure — `grep` across `Pommora/Pommora/` + `Pommora/PommoraTests/` returns zero references to either. So the engine machinery runs but its output has no app-side consumer: the feature is unwired at the boundary, confirming both closures are safe to shed in the later phase. Phase 1 keeps all 15 params.

---

### Task 1.1 — Branch + green baseline

Establish an isolated branch and prove the project builds + tests green *before* any rename, so the post-rename green is a true diff.

**Files**
- Modify: none (branch + verification only).

**Steps**

1. From the repo root, create and check out the rebuild branch (CLAUDE.md: branch before committing on `main`):
   ```
   git checkout -b markdownpm-rehome
   ```
2. Confirm the working tree's pre-existing modifications are the parallel-session ones noted in git status (`Pommora.xcodeproj/project.pbxproj`, the two untracked `.claude/` docs, `graphify-out/`). Do **not** revert or stage them — they belong to the parallel UIX session. Record them:
   ```
   git status --short
   ```
   Expected: `M Pommora/Pommora.xcodeproj/project.pbxproj`, `?? .claude/Features/Wiki-Link.md`, `?? .claude/Planning/Pommora-Wikilink.md`, `?? graphify-out/`. Leave them untouched.
3. Build + run the app unit tests as the green baseline:
   ```
   xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests 2>&1 | tail -40
   ```
   Expected: `** TEST SUCCEEDED **` with a **non-zero** executed count. Note: `MarkdownEngineTests` is the package's own test target and is **not** in this scheme today (CodeMap: `Pommora.xcscheme` Testables = PommoraTests + PommoraUITests only) — wiring that target in is a Phase-2 task, not Phase 1. The app's `MarkdownEngine` import resolves transitively through the host-app link.
4. Independently confirm the package itself compiles standalone (catches package-internal breakage the app scheme would mask):
   ```
   swift build --package-path "External/MarkdownEngine" 2>&1 | tail -20
   ```
   Expected: `Build complete!`.

**Commit:** none (baseline only).

---

### Task 1.2 — Atomic rename (manifest + Sources dir + types + imports + pbxproj)

The **product name IS the import symbol**, so the manifest rename, the source-directory rename, the public type renames, every import site, and the pbxproj product dependency cannot land independently — the project won't resolve until all of them agree. This is **one atomic task with one green commit**. Work the ordered checklist below top-to-bottom; do not build for green until the final step (intermediate `swift build --package-path` checks are fine and called out where useful).

Renames in scope:
- Package + library product + target + test target: `MarkdownEngine` → `MarkdownPM` (Package.swift).
- Source directory: `Sources/MarkdownEngine/` → `Sources/MarkdownPM/`; test directory: `Tests/MarkdownEngineTests/` → `Tests/MarkdownPMTests/` (SwiftPM resolves a target's sources by target name under `Sources/<TargetName>/` and there is no `path:` override in the manifest, so the directory MUST match the renamed target).
- Public front door: `NativeTextViewWrapper` → `MarkdownPMEditor`; config type: `MarkdownEditorConfiguration` → `MarkdownPMConfiguration`. All internal types (`NativeTextViewCoordinator`, `NativeTextView`, all `+` extension files, the tokenizer/detection/renderer/stylers) **keep their names**. The `typealias Coordinator = NativeTextViewCoordinator` travels with the renamed outer type, so the alias stays resolvable for its internal callers (`ContextMenu.swift`, `MarkdownListHandler.swift`, `MarkdownInputHandler.swift` per CodeMap).
- App import sites + the front-door call site + config factory.
- App test import sites.
- pbxproj product dependency `productName` + human-readable comments.

The on-disk `External/MarkdownEngine/` **package-root** directory keeps its name through this task (renaming it touches the pbxproj `relativePath` and is its own concern — Task 1.3). Only the inner `Sources/` + `Tests/` directories move here, because those are what the renamed target binds to.

Behavior-preserving guarantees held byte-unchanged: the 15-param public init (7 app-used + 8 dormant; `isWikiLinkActive` + `pendingInlineReplacement` are dormant `@Binding`s — the wikilink seam — plus `onInlineSelectionChange` / `onPasteImage`; the shed of `onCaretRectChange` + `onCodeBlockSelectionChange` is a *later* phase); `TextInsets` stays a public struct with `init(horizontal:vertical:)`; `MarkdownPlainText.extract` + `MarkdownDetection.reconcileFoldedHeadings` stay public; the attribute-key string literals stay frozen exact — `wikiLinkID = "NodeLinkID"` (the Swift symbol diverges from the literal on purpose — do NOT rename the literal), `taskCheckbox = "TaskCheckbox"`, the `latex*` keys in `MarkdownTextLayoutFragment.swift:17-20`, and the `StyledRange` typealias in `MarkdownStyler.swift:79`.

**Files**
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/External/MarkdownEngine/Package.swift`
- Move (directory): `…/Sources/MarkdownEngine/` → `…/Sources/MarkdownPM/`
- Move (directory): `…/Tests/MarkdownEngineTests/` → `…/Tests/MarkdownPMTests/`
- Modify (package-wide, mechanical): every `.swift` under `…/External/MarkdownEngine/Sources/MarkdownPM/` referencing either renamed public symbol (the front-door file `TextView/NativeTextViewWrapper.swift` keeps its filename — it's an internal filename, not a public symbol; renaming it is optional polish that risks pbxproj churn under `PBXFileSystemSynchronizedRootGroup`, so leave it).
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/Pages/PageEditorView.swift`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/Pages/PageEditorViewModel.swift`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora/Pages/PageTextStats.swift`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/Pages/PageTextStatsTests.swift`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj/project.pbxproj`

**Steps (ordered checklist — execute top-to-bottom)**

- [ ] **1. Edit `Package.swift`.** Current manifest: `name: "MarkdownEngine"` (line 24), `.library(name: "MarkdownEngine", targets: ["MarkdownEngine"])` (line 27), `.target(name: "MarkdownEngine", …)` (lines 36-41), `.testTarget(name: "MarkdownEngineTests", dependencies: ["MarkdownEngine"])` (line 42). Apply:
   - Line 24 — package name:
     ```swift
     name: "MarkdownPM",
     ```
   - Line 27 — library product (this is the import symbol):
     ```swift
     .library(name: "MarkdownPM", targets: ["MarkdownPM"])
     ```
   - Lines 36-37 — target name (leave the `dependencies` block, lines 38-40, untouched — the swift-markdown product reference is unchanged):
     ```swift
         targets: [
             .target(
                 name: "MarkdownPM",
     ```
   - Line 42 — test target + its target dependency:
     ```swift
         .testTarget(name: "MarkdownPMTests", dependencies: ["MarkdownPM"])
     ```
   - Lines 4-21 — drop the "vendoring" framing (Paradigm-Decisions #7 reconciliation, partial — the NOTICE.md rewrite is Task 1.4). Replace the comment block so it reads as MarkdownPM-owned (keep the three numbered architectural reasons; re-home the language):
     ```swift
     // MarkdownPM — Pommora's owned Markdown editor engine (the v3 rebuild
     // target). Originally vendored from nodes-app/swift-markdown-engine
     // (Apache 2.0, upstream SHA e683a62); now Pommora-owned and maintained
     // in-tree. Built as a local Swift Package — NOT as raw source files in
     // Pommora's main target — because:
     //
     //  1. The package targets Swift 5.9. Pommora is Swift 6 + strict
     //     concurrency + ExistentialAny. The package boundary lets MarkdownPM
     //     keep its own concurrency contract while Pommora's app code stays
     //     Swift-6-strict.
     //  2. MarkdownPM internals (MarkdownStyler, MarkdownTokenizer) are
     //     module-internal types; the app consumes only the public front door.
     //  3. Apple's swift-markdown supplies the GFM AST.
     //
     // See NOTICE.md for the upstream attribution + per-file modification log.
     ```
   Keep tools-version 5.9 and the swift-markdown `exact: "0.8.0"` pin unchanged.

- [ ] **2. Rename the source + test directories** (immediately after the manifest edit — the renamed target binds to `Sources/MarkdownPM/`). Use `git mv` so history follows the files:
   ```
   git mv "External/MarkdownEngine/Sources/MarkdownEngine" "External/MarkdownEngine/Sources/MarkdownPM"
   git mv "External/MarkdownEngine/Tests/MarkdownEngineTests" "External/MarkdownEngine/Tests/MarkdownPMTests"
   ```
   (Inner directories only — the `External/MarkdownEngine/` package root stays put until Task 1.3.) Optional checkpoint — the package should now resolve its sources under the new path even though the public types still have old names:
   ```
   swift build --package-path "External/MarkdownEngine" 2>&1 | tail -10
   ```
   Expected: `Build complete!` (the package is internally consistent; the app isn't touched yet).

- [ ] **3. Rename the public types inside the package.** Find every occurrence:
   ```
   grep -rn "NativeTextViewWrapper\|MarkdownEditorConfiguration" "External/MarkdownEngine/Sources/"
   ```
   Expected hits (CodeMap + verified): the type declaration + init + `make/updateNSView` bodies in `TextView/NativeTextViewWrapper.swift`; the `MarkdownEditorConfiguration` declaration in `Configuration/MarkdownEditorConfiguration.swift:27` + its `.default` + the `configuration:` param type on the wrapper + doc-comment references (e.g. `NativeTextViewWrapper.swift:22,46`). Apply:
   - `TextView/NativeTextViewWrapper.swift:23` — public struct:
     ```swift
     public struct MarkdownPMEditor: NSViewRepresentable {
     ```
   - Same file — `configuration` property type (`:46`), init parameter type (`:90`), and the file-header doc-comment module-name mentions (`:3` "MarkdownEngine" → "MarkdownPM", `:16` "MarkdownEngine's", `:22` `` ``MarkdownEditorConfiguration`` `` → `` ``MarkdownPMConfiguration`` ``, `:43`):
     ```swift
     public var configuration: MarkdownPMConfiguration
     ```
     ```swift
         configuration: MarkdownPMConfiguration = .default,
     ```
     Leave `typealias Coordinator = NativeTextViewCoordinator` (`:24`) and `typealias NSViewType = NSScrollView` (`:25`) unchanged.
   - `Configuration/MarkdownEditorConfiguration.swift:27` — config struct:
     ```swift
     public struct MarkdownPMConfiguration: Sendable {
     ```
     Fix the file-header prose at `:3` ("MarkdownEngine" → "MarkdownPM"); the filename string at `:2` is a comment, file rename skipped.
   - Sweep remaining internal references across the rest of the `grep` hits — `NativeTextViewWrapper` → `MarkdownPMEditor`, `MarkdownEditorConfiguration` → `MarkdownPMConfiguration`. Do NOT touch `NativeTextViewCoordinator`, `NativeTextView`, or the `//  Xxx.swift` header filename strings beyond prose-only `MarkdownEngine` → `MarkdownPM` module-name corrections.
   - Re-grep to prove zero stragglers of the OLD public names remain in package source:
     ```
     grep -rn "NativeTextViewWrapper\|MarkdownEditorConfiguration" "External/MarkdownEngine/Sources/"
     ```
     Expected: no output.

- [ ] **4. Update the 3 app import sites + the front-door call site** (CodeMap app-integration slice; `PageEditorView.swift` is the sole app file naming the two renamed public types):
   - `PageEditorViewModel.swift` line 2 — `import MarkdownPM`
   - `PageTextStats.swift` line 2 — `import MarkdownPM`
   - `PageEditorView.swift` line 2 — `import MarkdownPM`
   - `PageEditorView.swift` line 16 — doc-comment that names the type (optionally tighten "locally-vendored" → "in-tree MarkdownPM package" to match the NOTICE reconciliation; the literal text isn't load-bearing):
     ```swift
     /// The body editor is `MarkdownPMEditor` from the locally-vendored
     ```
   - `PageEditorView.swift` line 210 — call site (the rest of the call — `text:`, `foldedHeadings:`, `configuration:`, `fontName:`, `fontSize:`, `documentId:`, `onScrollOffsetChange:` — is unchanged; the 15-param init is preserved):
     ```swift
                 MarkdownPMEditor(
     ```
   - `PageEditorView.swift` lines 351-352 — config factory type + `.default` host:
     ```swift
         private static let pommoraEditorConfiguration: MarkdownPMConfiguration = {
             var config = MarkdownPMConfiguration.default
     ```
     Leave line 353 (`config.textInsets = TextInsets(horizontal: 24, vertical: titleAreaHeight)`) unchanged — `TextInsets` is unrenamed and stays a public struct with `init(horizontal:vertical:)`.
   - Confirm no app file still imports the old module or names the old types:
     ```
     grep -rn "import MarkdownEngine\|NativeTextViewWrapper\|MarkdownEditorConfiguration" "Pommora/Pommora/"
     ```
     Expected: no output.

- [ ] **5. Update the 2 app test import sites.** Both PommoraTests files import the module directly and resolve transitively via the host-app link today (CodeMap: PommoraTests `packageProductDependencies` = GRDB only; imports resolve through `TestTargetID=Pommora`). The transitive-resolution brittleness is a **Phase-2** fix (adding `MarkdownPM` to `PommoraTests.packageProductDependencies`) — here we only swap the import string so the existing transitive path keeps working under the new product name.
   - `PageTextStatsTests.swift` line 8 — `import MarkdownPM` (keep `import Testing` at :7 and `@testable import Pommora` at :10 unchanged)
   - `FoldableHeadingsTests.swift` line 2 — `import MarkdownPM`
   - Confirm:
     ```
     grep -rn "import MarkdownEngine" "Pommora/PommoraTests/"
     ```
     Expected: no output.

- [ ] **6. Update the pbxproj product dependency + comments.** Update the `productName` (what Xcode matches against the package's `.library` product name, now `MarkdownPM`) and the human-readable comments. The CodeMap pins the sites: build file `:11`, frameworks link `:64`, product dependency `:129` + its def at `:650-654`. The `relativePath` still points at `../External/MarkdownEngine` and is **left alone here** — the package-root folder isn't renamed until Task 1.3.
   - `XCSwiftPackageProductDependency` definition (`:650-654`):
     ```
             5A0E2D7B1F4C8A9D6B3E5021 /* MarkdownPM */ = {
                 isa = XCSwiftPackageProductDependency;
                 package = 5A0E2D7B1F4C8A9D6B3E5022 /* XCLocalSwiftPackageReference "../External/MarkdownEngine" */;
                 productName = MarkdownPM;
             };
     ```
     (Leave the GUID `5A0E…5021` and the `package =` GUID reference unchanged — only the human-readable comment + `productName` change. The `package` comment still references the old folder path; it gets updated in Task 1.3.)
   - The three human-readable comments naming the product: `:11` and `:64` `/* MarkdownEngine in Frameworks */` → `/* MarkdownPM in Frameworks */`; `:129` `/* MarkdownEngine */` → `/* MarkdownPM */`.
   - Do NOT change `relativePath = ../External/MarkdownEngine` (`:613`) or the `XCLocalSwiftPackageReference "../External/MarkdownEngine"` comment text yet.

- [ ] **7. Resolve + build + test for the single green** (this is the first full-rename build — manifest + dirs + types + imports + pbxproj together):
   ```
   xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests 2>&1 | tail -50
   ```
   Expected: `** TEST SUCCEEDED **` with the **same non-zero** executed count as the Task 1.1 baseline. If Xcode can't resolve the package, run a clean resolve first (`xcodebuild -resolvePackageDependencies -scheme Pommora 2>&1 | tail -20`), then re-run. Also re-confirm the package builds standalone:
   ```
   swift build --package-path "External/MarkdownEngine" 2>&1 | tail -10
   ```
   Expected: `Build complete!`.

**Commit (the atomic rename):** stage explicitly — the parallel-session working-tree changes (`project.pbxproj` parallel edits, the untracked `.claude/` docs, `graphify-out/`) must stay out. The `git mv` directory renames are already staged; add the remaining edits by path, then curate the pbxproj hunks:
```
git add External/MarkdownEngine/Package.swift \
        Pommora/Pommora/Pages/PageEditorView.swift \
        Pommora/Pommora/Pages/PageEditorViewModel.swift \
        Pommora/Pommora/Pages/PageTextStats.swift \
        Pommora/PommoraTests/Pages/PageTextStatsTests.swift \
        Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift
git add External/MarkdownEngine/Sources/MarkdownPM
git add -p Pommora/Pommora.xcodeproj/project.pbxproj
```
Stage only the MarkdownPM-related pbxproj hunks; discard any incidental Yams/GRDB reorder-only hunks and leave the parallel session's unattributed pbxproj edits unstaged. Verify with `git status --short` that no parallel-session file is staged and the directory moves show as renames (`R`).

Commit: `refactor(markdownpm): rename package + module + types MarkdownEngine -> MarkdownPM`

---

### Task 1.3 — Rename the on-disk package-root directory + repoint the path references

With the rename atomically green, move the package-root directory `External/MarkdownEngine/` → `External/MarkdownPM/` and repoint the pbxproj `relativePath` + local-package comments at the new path. (The inner `Sources/` + `Tests/` directories already moved in Task 1.2; this task only re-homes the package root, which is what the pbxproj `relativePath` resolves by.)

Use `git mv` so history follows the files. There are no `path:` overrides in `Package.swift`, so once the package root moves no further manifest edit is needed.

**Files**
- Move (directory): `External/MarkdownEngine/` → `External/MarkdownPM/`
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/Pommora/Pommora.xcodeproj/project.pbxproj` (`relativePath` `:613` + the two `XCLocalSwiftPackageReference "../External/MarkdownEngine"` comments at `:611,652`, plus the references-list comment at `:220`)

**Steps**

1. Rename the package-root directory:
   ```
   git mv "External/MarkdownEngine" "External/MarkdownPM"
   ```
2. Update the pbxproj `relativePath` (`:613`) and the reference comments (`:611`, `:652`, `:220`):
   ```
           5A0E2D7B1F4C8A9D6B3E5022 /* XCLocalSwiftPackageReference "../External/MarkdownPM" */ = {
               isa = XCLocalSwiftPackageReference;
               relativePath = ../External/MarkdownPM;
           };
   ```
   And the `package =` comment in the product-dependency block (`:652`):
   ```
               package = 5A0E2D7B1F4C8A9D6B3E5022 /* XCLocalSwiftPackageReference "../External/MarkdownPM" */;
   ```
   And the reference comment in the package-references list (`:220`): `/* XCLocalSwiftPackageReference "../External/MarkdownPM" */`.
3. Resolve + build + test (proves the path move resolves cleanly):
   ```
   xcodebuild -resolvePackageDependencies -scheme Pommora 2>&1 | tail -10
   xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests 2>&1 | tail -50
   ```
   Expected: clean resolve, then `** TEST SUCCEEDED **` with the same non-zero count. Also re-confirm the package builds standalone at its new path:
   ```
   swift build --package-path "External/MarkdownPM" 2>&1 | tail -10
   ```
   Expected: `Build complete!`.

**Commit:** stage the moved tree + the curated pbxproj path hunks (`git add -A External/MarkdownPM`; `git add -p Pommora/Pommora.xcodeproj/project.pbxproj`). Verify `git status --short` shows the move as a rename `R` and no parallel-session file is staged.

Commit: `refactor(markdownpm): re-home package directory External/MarkdownPM`

---

### Task 1.4 — Reconcile NOTICE.md (MarkdownPM-owned; 4 extensions not 6; drop SourceRangeToNSRange) + Paradigm-Decisions #7

Bring the two docs in line with the CodeMap-verified reality and the MarkdownPM-owned framing. NOTICE.md currently (a) frames the engine as "vendored… consumed as source files (not a Swift Package)" — factually wrong, it IS a Swift Package; (b) claims the styler delete touches "`MarkdownStyler.swift` + 6 extensions" — CodeMap says only **4** sibling `MarkdownStyler+*.swift` files exist (`+TextStyling`, `+Links`, `+Latex`, `+Images`); `+Code` and `+TaskCheckboxes` are inline extension blocks inside `MarkdownStyler.swift`, not separate files; (c) lists `SourceRangeToNSRange` among new Pommora-side files to create — CodeMap corrects that the existing `SourceRangeConverter` (`AppleASTSupplementalStyler.swift:271`) is reused, so no such file is created. Paradigm-Decisions #7 already reads as "superseded" and cites the vendored engine — update its language to "MarkdownPM (Pommora-owned)" and fix the path citations from `External/MarkdownEngine/` to `External/MarkdownPM/`.

Keep edits surgical (StudioMD: fix the claim directly, don't amend around it). Honor the Obsidian preserve-formatting rule — match the existing table/heading style; h2-max in the doc.

**Files**
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/External/MarkdownPM/NOTICE.md` (the file moved with the package in Task 1.3)
- Modify: `/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Guidelines/Paradigm-Decisions.md` (item #7 at line 50)

**Steps**

1. NOTICE.md — rewrite the opening framing (current line 3) so it states MarkdownPM is Pommora-owned and IS a local Swift Package, retaining the Apache-2.0 upstream attribution:
   - Change the heading (current `### swift-markdown-engine — vendored`) to e.g. `### MarkdownPM — Pommora-owned (originally vendored from swift-markdown-engine)`.
   - Change the body sentence "consumed as source files (not a Swift Package) so Pommora can replace…" to state it's a **local Swift Package** at `External/MarkdownPM/`, Pommora-owned and maintained in-tree, with the upstream retained for attribution. Update the path `External/MarkdownEngine/` → `External/MarkdownPM/`.
2. NOTICE.md — fix the styler-delete row (current line 17): change "`Styling/MarkdownStyler.swift` + 6 extensions (`+TextStyling`, `+Links`, `+Code`, `+Latex`, `+Images`, `+TaskCheckboxes`)" to reflect the CodeMap count — **4 sibling extension files** (`+TextStyling`, `+Links`, `+Latex`, `+Images`) plus the inline `+Code` / `+TaskCheckboxes` extension blocks inside `MarkdownStyler.swift`. State it as: "`Styling/MarkdownStyler.swift` (which hosts the inline `+Code` + `+TaskCheckboxes` extension blocks) + its 4 sibling `MarkdownStyler+*.swift` files (`+TextStyling`, `+Links`, `+Latex`, `+Images`)."
3. NOTICE.md — fix the new-files list (current line 45): remove `SourceRangeToNSRange` from the list of new Pommora-side files; add a short note that NSRange conversion reuses the existing `SourceRangeConverter` (`Styling/AppleASTSupplementalStyler.swift:271`) rather than a new duplicate type. Leave the other listed new files (`PommoraMarkdownStyler`, `PommoraInlineScanner`, `MarkersShrinker`, `PommoraWikiLinkResolver`) as forward-looking placeholders — they're later-phase artifacts; this is a doc, not code.
4. NOTICE.md — these are forward-looking plan rows; do NOT mass-edit every `External/MarkdownEngine/` path-citation in the modification-log table to `External/MarkdownPM/` beyond the framing paragraph unless the engineer is also touching that row's content. (The table records historical modifications; over-editing it for a path rename is churn. Fix the framing + the two CodeMap-corrected rows + the new-files note; leave the rest.)
5. Paradigm-Decisions.md line 50 (item #7) — update the editor-stack language to name MarkdownPM and fix the path citation. Current text ends "…the vendored `swift-markdown-engine`** (native NSTextView, no web view). Spec → `// Features//PageEditor.md`; engine rules → `Markdown.md`." Change "the vendored `swift-markdown-engine`" to "the Pommora-owned **MarkdownPM** package (`External/MarkdownPM/`, originally vendored from `swift-markdown-engine`, Apache 2.0)". Keep the spec/rules pointers. Reference the package folder path as inline code (config-folder / non-indexed path → inline code per ClaudeOS wikilink rule), not a wikilink.
6. Sanity-check the docs read clean (no dangling "vendored, not a package" contradictions, no "6 extensions", no "SourceRangeToNSRange" in NOTICE):
   ```
   grep -n "not a Swift Package\|6 extensions\|SourceRangeToNSRange" "External/MarkdownPM/NOTICE.md"
   ```
   Expected: no output.

**Commit (docs-only — explicit doc commit is fine per CLAUDE.md quirk #4):** stage `External/MarkdownPM/NOTICE.md` + `.claude/Guidelines/Paradigm-Decisions.md`.

Commit: `docs(markdownpm): reconcile NOTICE + Paradigm-Decisions #7 to MarkdownPM-owned`

---

### Phase 1 exit gate

- `grep -rn "MarkdownEngine" .` returns no source/manifest/pbxproj hits (only historical NOTICE table rows / commit history, by design). Verify:
  ```
  grep -rn "import MarkdownEngine\|productName = MarkdownEngine\|name: \"MarkdownEngine\"\|struct NativeTextViewWrapper\|MarkdownEditorConfiguration" . --include=*.swift --include=*.pbxproj 2>/dev/null
  ```
  Expected: no output.
- `xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests` is green with the **same non-zero** executed count as the Task 1.1 baseline.
- `swift build --package-path "External/MarkdownPM"` → `Build complete!`.
- The 15-param public init, `TextInsets(horizontal:vertical:)`, the `"NodeLinkID"` / `"TaskCheckbox"` literals, and the `StyledRange` typealias are all byte-unchanged (no behavior delta — this phase ships no test net by design; Phase 2 builds it).
- Re-assess the plan against what landed (CLAUDE.md "re-assess between green commits"): if anything in the atomic rename forced a deviation from the checklist order, record it in the Phase-2 lead-in so the test-target wiring task references the final `Sources/MarkdownPM/` path.

## Phase 2 — Characterization Net (the hard gate)

This is the safety net that must land **before any behavior change** (Phases 3-6). Phase 1 (re-home + rename) is a pure mechanical rename and ships without a net; everything after Phase 2 changes behavior and is gated on a green characterization suite. Every intentional divergence (underscore emphasis adoption, the unified heading detector) gets pinned to its **current** behavior here first, so when Phases 3-5 change it, the test flips deliberately and the change is recorded in the divergence ledger — nothing changes silently.

This section assumes Phase 1 has landed: the package + module are named `MarkdownPM`, the front door is `MarkdownPMEditor`, and the config type is `MarkdownPMConfiguration`. All test code below imports `MarkdownPM`. If you are writing these tests against a still-`MarkdownEngine` tree (Phase 1 slipped), substitute `MarkdownEngine` for `MarkdownPM` in every `import` and `@testable import` line and proceed — the corpus and assertions are identical.

Locked decisions governing this phase: see LD-1 (Pages only), LD-4 (package stays Swift 5.9), LD-9 (heading-detector unification, pinned here), LD-10/LD-11 (emphasis asterisk-only, pinned here), LD-28 (DEC-1 id-on-disk lock + both write sinks), LD-29 (swift-markdown pinned 0.8.0). Phase 2 is the phase that **encodes them as executable assertions** — it changes no behavior, it only pins current behavior so each future flip is explicit and logged.

The shared run protocol for every task below — builder subagents invoke the gate via a background Agent (so `xcodebuild` does not grab window focus), visually verify a non-zero executed count, revert incidental SPM-entry reordering before commit, and surface (never bundle or discard) unattributed working-tree changes — is stated once here and not repeated per task.

---

### Task 2.1 — Wire the MarkdownPM test target into the test command

**Why first:** the CodeMap flags this as the **P2 false-green trap** (claim #26, Change-Site row "Test-run wiring"). Today the engine's own `MarkdownEngineTests` target is run by *neither* `xcodebuild test -scheme Pommora` (the scheme's Testables = `PommoraTests` + `PommoraUITests` only — verified above) *nor* any standalone command in the project's muscle memory. If we write package suites without wiring them in, they pass locally and never run in the gate. Wire the runner before writing a single new test.

**Decision (resolves CodeMap Open Question #27):** keep the package suites in the package test target and run them with `swift test`; keep app-side public-surface + on-disk round-trip suites in `PommoraTests` run with `xcodebuild test`. Two commands, one script. Rationale in plain terms: moving the package-internal suites (which use `@testable import` to reach internal types like `MarkdownLists`, `MarkdownTokenizer`, `MarkdownStyler`) into `PommoraTests` would force those internal types `public`, widening the package's public surface for no product reason. The package's own test target already has `@testable` access. Keep that boundary.

**Step 2.1.1 — Confirm the package test target builds and runs at all.**

Run:

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

Expected: the existing `EnterContinuationTests` + `CheckboxCanonicalizationTests` execute and pass with a non-zero executed count (`Test Suite 'All tests' passed`). Do not pin a hard number — visually verify the count is non-zero. If `swift test` reports `error: no such module 'AppKit'` or fails to find a macOS SDK, add an explicit destination:

```
swift test --package-path "External/MarkdownPM" -Xswiftc -sdk -Xswiftc "$(xcrun --sdk macosx --show-sdk-path)" 2>&1 | tail -40
```

Do not proceed until you see the existing suites execute with a non-zero count. This proves the package test target is real and runnable independent of Xcode.

**Step 2.1.2 — Create the unified test-run script.**

Create `External/MarkdownPM/run-tests.sh` (executable). This is the single command the gate uses; it runs the package suites then the app suites and fails if either fails:

```bash
#!/usr/bin/env bash
# MarkdownPM characterization gate. Runs BOTH the package-own suites
# (swift test) and the app-side public-surface + on-disk suites
# (xcodebuild test -scheme Pommora -only-testing:PommoraTests).
# Exits non-zero if EITHER leg fails.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
PKG_PATH="$REPO_ROOT/External/MarkdownPM"

echo "== MarkdownPM package suites (swift test) =="
swift test --package-path "$PKG_PATH" \
  -Xswiftc -sdk -Xswiftc "$(xcrun --sdk macosx --show-sdk-path)"

echo "== App-side suites (xcodebuild test -only-testing:PommoraTests) =="
xcodebuild test \
  -project "$REPO_ROOT/Pommora/Pommora.xcodeproj" \
  -scheme Pommora \
  -destination 'platform=macOS' \
  -only-testing:PommoraTests
```

Make it executable:

```
chmod +x "External/MarkdownPM/run-tests.sh"
```

**Step 2.1.3 — Verify the gate runs both legs.**

Run:

```
"External/MarkdownPM/run-tests.sh" 2>&1 | tail -60
```

Expected: you see the `== MarkdownPM package suites ==` banner, the existing package tests pass, then the `== App-side suites ==` banner, then `PommoraTests` runs and passes (it currently has its own suites — `FoldableHeadingsTests`, `PageTextStatsTests`, etc.). Visually confirm a non-zero executed count in **both** legs. If `PommoraTests` reports "test runner hung before establishing connection" with 0 tests, the XCTest launch-modal guard (CLAUDE.md quirk #16) has regressed — stop and fix `loadOnLaunch()` before continuing; this Phase cannot gate on a host that won't boot.

This same Task 2.1 commit also folds in the creation of the divergence ledger file (Task 2.2) — one commit, not a separate docs commit.

**Commit:** `test(markdownpm): unified characterization gate runs package + app suites`

---

### Task 2.2 — Start the divergence ledger

**Why:** every intentional behavior change between now and Phase 6 must be signed off, not slipped in. The ledger is the single record. It lives in the Planning folder (not in a doc the engine reads) and is referenced by the commit that lands each divergence. It is the **single source** for divergence rows — the plan body does not re-maintain the same rows; at most one example row appears inline below for orientation.

**Step 2.2.1 — Create the ledger (its creation folds into the Task 2.1 commit; no separate docs commit).**

Create `.claude/Planning/MarkdownPM-Divergence-Ledger.md`:

```markdown
## MarkdownPM — Divergence Ledger

Every intentional behavior change in the MarkdownPM rebuild is recorded here
before it lands. Each row: the construct, the OLD behavior (pinned by a Phase-2
characterization test), the NEW behavior, the phase that flips it, the test that
flips, and Nathan's sign-off. "Tested-identical on a fixed corpus, every
intentional divergence flagged + scoped" — NOT byte-identical. This is the
flagged-and-scoped list.

| # | Construct | OLD (pinned by) | NEW | Phase | Flipping test | Signed off |
|---|---|---|---|---|---|---|
| D-EMPH-1 | Emphasis delimiter | asterisk-only `*`/`**`/`***` (pinned: `TokenizerCorpusTests.underscoreIsNotEmphasis_currentBehavior`) | adopt underscore `_`/`__` (Apple + CommonMark + Obsidian) | 4 | `EmphasisCorpusTests.underscoreIsEmphasis` (added in P4) | ACCEPTED (Nathan 2026-06-02 — adopt underscore) |
| D-EMPH-2 | Emphasis inside inline code / code fence | NOT suppressed (`*x*` inside `` `…` `` still tokenizes — pinned `TokenizerCorpusTests.emphasisInsideInlineCode_notSuppressed_currentBehavior`) | suppressed (Apple AST does not emit emphasis inside code) | 4 | `EmphasisCorpusTests.noEmphasisInsideCode` (P4) | ACCEPTED (Nathan 2026-06-02 — suppress, matches Apple) |
| D-HEAD-1 | Heading detector unification | two divergent regexes (styler `#{1,6} +`, detection `#{1,6}([ \t]\|$)`) — pinned `HeadingDetectorCorpusTests` + `TokenizerCorpusTests` on BOTH paths | ONE rule: CommonMark `#{1,6}([ \t]\|$)` (space/tab/EOL) | 4 | `HeadingDetectorCorpusTests.unifiedRule` (added in P4) | ACCEPTED (Nathan — unify) |
| D-HEAD-2 | Heading size multipliers | shipped `[2.0,1.5,1.17,1.0,0.83,0.67]` (H4=body; H5/H6 below body) — pinned in P2 | new scale `[2.0,1.75,1.5,1.25,1.15,TBD]` (no heading below body) | 5 | `HeadingSizeTests` (P5) | ACCEPTED (Nathan 2026-06-02; H6 TBD) |
| #9-PARSE | Apple Document parses per edit | 1 unfolded / 2 folded (today) | 1 (cached spine) | 3 | per-edit count pinned by P3 `unfoldedEditParsesOnce`/`foldedEditParsesOnce`; P2 `ParseCountProbeTests` characterize the direct-call count (1 per call / 2 on two passes) | PENDING |

Add rows as new divergences are discovered. A divergence with no sign-off MUST NOT land.
```

(That `#9-PARSE` row is the single authoritative home for the parse-count divergence — "Apple Document parses per edit: 1 unfolded / 2 folded (today) → 1 (after Phase 3)". The plan body does not restate it.)

---

### Task 2.3 — Suite A: tokenizer output (regex token characterization)

**Goal:** pin `MarkdownTokenizer.parseTokens(in:)` output for the constructs the regex tokenizer owns. This is the bedrock — emphasis (asterisk-only), inline code, links, headings (styler path), wikilinks, image embeds, the `$…$` math/currency heuristic at its thresholds. Failing-test-first means: write the assertion you EXPECT from reading the source, run it, and if it disagrees, the SOURCE wins — fix the test to match observed behavior (you are characterizing, not correcting).

`MarkdownToken` and `MarkdownTokenKind` are package-internal, so this suite lives in the **package** test target with `@testable import`.

**Step 2.3.1 — Write the suite.**

Create `External/MarkdownPM/Tests/MarkdownPMTests/TokenizerCorpusTests.swift`:

```swift
import Foundation
import Testing
@testable import MarkdownPM

/// Characterizes `MarkdownTokenizer.parseTokens(in:)` — the regex tokenizer
/// that owns emphasis (asterisk-only, pre-Phase-4), inline code, links,
/// headings (styler path), wikilinks, image embeds, and the $…$ math/currency
/// heuristic. These assertions pin CURRENT behavior; Phase 4 flips the ones
/// listed in the divergence ledger.
@Suite("TokenizerCorpus")
struct TokenizerCorpusTests {

    // Helper: kinds present, in append order (emphasis first, then embeds,
    // wikilinks, links, headings, code, latex — see parseTokens ordering).
    private func kinds(_ text: String) -> [MarkdownTokenKind] {
        MarkdownTokenizer.parseTokens(in: text).map(\.kind)
    }
    private func tokens(_ text: String) -> [MarkdownToken] {
        MarkdownTokenizer.parseTokens(in: text)
    }

    // MARK: - Emphasis: asterisk-only (PINNED — divergence D-EMPH-1)

    @Test("Single asterisk pair is italic")
    func italic() {
        let t = tokens("a *b* c")
        let em = t.filter { $0.kind == .italic }
        #expect(em.count == 1)
        // `*b*` starts at utf16 index 2, length 3.
        #expect(em[0].range == NSRange(location: 2, length: 3))
    }

    @Test("Double asterisk pair is bold")
    func bold() {
        let em = tokens("**b**").filter { $0.kind == .bold }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 0, length: 5))
    }

    @Test("Triple asterisk pair is boldItalic")
    func boldItalic() {
        let em = tokens("***b***").filter { $0.kind == .boldItalic }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 0, length: 7))
    }

    @Test("Underscore is NOT emphasis (asterisk-only — flips in Phase 4)")
    func underscoreIsNotEmphasis_currentBehavior() {
        let em = tokens("_b_ __c__").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.isEmpty)
    }

    @Test("Rule-of-3: **foo*bar**baz* resolves per CommonMark")
    func ruleOfThree_a() {
        // Pin whatever the hand-rolled parser produces; the assertion records
        // the count + first range. Read the result, then lock it.
        let em = tokens("**foo*bar**baz*").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        // The stack parser produces a bold over the **…** span. Assert it
        // emits at least one emphasis token and the FIRST is bold at 0.
        #expect(!em.isEmpty)
        #expect(em.contains { $0.kind == .bold && $0.range.location == 0 })
    }

    @Test("Rule-of-3: *foo**bar*baz**")
    func ruleOfThree_b() {
        let em = tokens("*foo**bar*baz**").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(!em.isEmpty)
    }

    @Test("Intra-word a*b*c emphasizes the inner asterisk pair")
    func intraWord() {
        let em = tokens("a*b*c").filter { $0.kind == .italic }
        #expect(em.count == 1)
        #expect(em[0].range == NSRange(location: 1, length: 3))
    }

    @Test("Cross-line *foo\\nbar* does NOT emphasize across the newline")
    func crossLine() {
        // collectAsteriskRuns tracks lineIdx; tryClose rejects opener/closer
        // on different lines. So a single `*` on each of two lines yields no
        // emphasis token spanning the break.
        let em = tokens("*foo\nbar*").filter {
            $0.kind == .italic || $0.kind == .bold || $0.kind == .boldItalic
        }
        #expect(em.isEmpty)
    }

    @Test("Punctuation-flanking *(*  edge cases produce no spurious emphasis")
    func punctuationFlanking() {
        let em = tokens("a * b * c").filter { $0.kind == .italic }
        // Spaces inside the asterisks defeat flanking; no italic token.
        #expect(em.isEmpty)
    }

    @Test("Emphasis inside inline code is NOT suppressed (flips in Phase 4)")
    func emphasisInsideInlineCode_notSuppressed_currentBehavior() {
        // parseTokens appends emphasis FIRST with no code-overlap exclusion
        // (CodeMap claim #12). `*x*` inside backticks still tokenizes.
        let em = tokens("`*x*`").filter { $0.kind == .italic }
        #expect(em.count == 1)
    }

    // MARK: - Inline code (multi-backtick + content range)

    @Test("Single-backtick inline code: marker ranges are the backticks")
    func inlineCodeSingle() {
        let t = tokens("a `code` b").filter { $0.kind == .inlineCode }
        #expect(t.count == 1)
        #expect(t[0].range == NSRange(location: 2, length: 6))   // `code`
        #expect(t[0].contentRange == NSRange(location: 3, length: 4)) // code
        #expect(t[0].markerRanges.count == 2)
    }

    @Test("Multi-backtick run: the inlineCodeRegex only matches single backticks")
    func inlineCodeMultiBacktick_currentBehavior() {
        // inlineCodeRegex = `([^`\n]+)` — a single backtick on each side.
        // ``a`b`` is therefore matched as `b` between the inner ticks, not
        // the whole double-backtick span. Pin whatever it actually does.
        let t = tokens("``a`b``").filter { $0.kind == .inlineCode }
        // Record the count the regex produces (do not assume CommonMark here).
        #expect(t.count == 1)
    }

    // MARK: - Links (take the destination)

    @Test("Markdown link [text](url): contentRange is the text, markers bracket+paren")
    func markdownLink() {
        let t = tokens("see [text](https://x.io) end").filter { $0.kind == .link }
        #expect(t.count == 1)
        #expect((("see [text](https://x.io) end" as NSString)
            .substring(with: t[0].contentRange)) == "text")
        #expect(t[0].markerRanges.count == 4) // [ ] ( )
    }

    // MARK: - Headings (STYLER path — requires a space; PINNED D-HEAD-1)

    @Test("Styler heading regex: `## Foo` is a heading token")
    func headingWithSpace() {
        let t = tokens("## Foo").filter { $0.kind == .heading }
        #expect(t.count == 1)
    }

    @Test("Styler heading regex: bare `##` (no space) is NOT a token")
    func headingNoSpace_currentBehavior() {
        // headingRegex = ^\s*(#{1,6}) +(.*)$  — REQUIRES at least one space.
        let t = tokens("##").filter { $0.kind == .heading }
        #expect(t.isEmpty)
    }

    @Test("Styler heading regex: tab-after-hash `##\\tFoo` is NOT a token")
    func headingTabAfterHash_currentBehavior() {
        // VERIFIED against source: styler headingRegex `^\s*(#{1,6}) +(.*)$`
        // (MarkdownTokenizer.swift:23-24) uses ` +` (U+0020 only, no tabs), so
        // `##\tFoo` does NOT tokenize as a heading on the styler path. The
        // DETECTION path DOES accept it (verified: isHeadingLine("##\tFoo")
        // == true) — that is the real D-HEAD-1 divergence Phase 4 reconciles.
        let t = tokens("##\tFoo").filter { $0.kind == .heading }
        #expect(t.isEmpty)
    }

    // MARK: - Wikilinks + image embeds (STAY regex through the rebuild)

    @Test("Plain wikilink [[Title]] tokenizes; markers are the [[ and ]]")
    func wikilinkPlain() {
        let t = tokens("a [[Title]] b").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
        #expect((("a [[Title]] b" as NSString)
            .substring(with: t[0].contentRange)) == "Title")
    }

    @Test("Path-qualified inbound [[folder/Title]] reads as one wikilink")
    func wikilinkPathQualified() {
        let t = tokens("[[folder/Title]]").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
        #expect((("[[folder/Title]]" as NSString)
            .substring(with: t[0].contentRange)) == "folder/Title")
    }

    @Test(".md-suffixed inbound [[Title.md]] reads as one wikilink")
    func wikilinkMdSuffixed() {
        let t = tokens("[[Title.md]]").filter { $0.kind == .wikiLink }
        #expect(t.count == 1)
    }

    @Test("Image embed ![[Img]] is imageEmbed, NOT wikiLink")
    func imageEmbed() {
        let t = tokens("![[Img]]")
        #expect(t.contains { $0.kind == .imageEmbed })
        #expect(!t.contains { $0.kind == .wikiLink })
    }

    // MARK: - $…$ math vs currency heuristic (thresholds 120/40/6 — PIN VERBATIM)

    @Test("$5 is currency (money), NOT inline LaTeX")
    func dollarFiveIsMoney() {
        let t = tokens("costs $5 today").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    @Test("$1,234.56 is currency, NOT LaTeX")
    func dollarThousandsIsMoney() {
        let t = tokens("$1,234.56").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    @Test("$x+y$ is inline LaTeX (2 mathy chars, short)")
    func mathExpression() {
        let t = tokens("$x+y$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$x$ (1-3 letter run, 0 mathy) is treated as math")
    func singleLetterIsMath() {
        let t = tokens("$x$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$abc$ (3-letter run, 0 mathy) is math")
    func threeLetterIsMath() {
        let t = tokens("$abc$").filter { $0.kind == .inlineLatex }
        #expect(t.count == 1)
    }

    @Test("$abcd$ (4-letter run, 0 mathy) is NOT math")
    func fourLetterNotMath() {
        let t = tokens("$abcd$").filter { $0.kind == .inlineLatex }
        #expect(t.isEmpty)
    }

    // Threshold boundary: 1 mathy char tolerates ≤ 6 whitespace tokens.
    @Test("1 mathy char with 6 tokens is math; 7 is not (threshold 6)")
    func oneMathyThreshold() {
        // Build "a a a a a a +" → 7 whitespace-separated tokens, 1 mathy (+).
        let sevenTokens = "$a a a a a a +$"   // tokens.count == 7 → NOT math
        let sixTokens = "$a a a a a +$"       // tokens.count == 6 → math
        #expect(tokens(sevenTokens).filter { $0.kind == .inlineLatex }.isEmpty)
        #expect(tokens(sixTokens).filter { $0.kind == .inlineLatex }.count == 1)
    }
}
```

**Step 2.3.2 — Run, observe, lock.**

```
swift test --package-path "External/MarkdownPM" --filter TokenizerCorpus 2>&1 | tail -50
```

For any test that fails, the **source is authoritative** — read `MarkdownTokenizer.swift` / `MarkdownTokenizer+Emphasis.swift` again, adjust the assertion to the observed output, and re-run. The two threshold/boundary tests (`oneMathyThreshold`, the rule-of-3 cases) are the most likely to need their expected values corrected against the real `split(whereSeparator:)` + flanking logic; that correction IS the characterization. Iterate until green with a non-zero executed count.

**Commit:** `test(markdownpm): Suite A — tokenizer corpus (emphasis asterisk-only, math thresholds)`

---

### Task 2.4 — Suite B: styled-attribute ranges at caret positions

**Goal:** pin `MarkdownStyler.styleAttributes(…) -> [StyledRange]` for code / inline-code / checkbox (active AND inactive caret) / incomplete-bracket / shrink passes, AND lock the two invariants: primary-runs-before-supplemental, and ThematicBreak emits **zero** from both stylers (HR is the service's sole writer — Keep-Verbatim register + CodeMap claim #8). `StyledRange` and `MarkdownStyler` are internal → package test target, `@testable import`.

The styler is `@MainActor` (`MarkdownStyler.swift:83`), so the suite is `@MainActor`. We feed `precomputedTokens` and an explicit `caretLocation` + `activeTokenIndices` so the test is deterministic without a live NSTextView. `activeTokenIndices` is computed with the same `MarkdownDetection.computeActiveTokenIndices` the engine uses, so caret-aware reveal is exercised honestly.

Theme note: `MarkdownEditorTheme.default` EXISTS today (`public static let default = MarkdownEditorTheme()`, verified `Configuration/MarkdownEditorTheme.swift:114`), so `.default` / `theme: .default` below is valid and is the cited canonical form. The `init(...)` has all-defaulted params (`bodyText:` … `strikethroughColor:`) if you ever need a custom palette. When Phase 5 renames the type to `MarkdownPMTheme`, `.default` survives the rename.

**Step 2.4.1 — Write the suite.**

Create `External/MarkdownPM/Tests/MarkdownPMTests/StyledRangeCorpusTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import MarkdownPM

/// Characterizes `MarkdownStyler.styleAttributes` output (the [StyledRange]
/// list) at varied caret positions, plus the two structural invariants the
/// Phase-5 styler merge must preserve: primary-before-supplemental ordering
/// and ThematicBreak emitting NOTHING from either styler.
@MainActor
@Suite("StyledRangeCorpus")
struct StyledRangeCorpusTests {

    private func styled(
        _ text: String,
        caret: Int
    ) -> [StyledRange] {
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        let active = MarkdownDetection.computeActiveTokenIndices(
            selectionRange: NSRange(location: caret, length: 0),
            tokens: tokens,
            in: text as NSString
        )
        return MarkdownStyler.styleAttributes(
            text: text,
            fontName: "SF Pro Text",
            fontSize: 15,
            caretLocation: caret,
            activeTokenIndices: active,
            precomputedTokens: tokens
        )
    }

    // Does any emitted range cover `location` and carry a foregroundColor
    // equal to the code-text color (currently NSColor.systemRed@0.85,
    // duplicated MarkdownStyler.swift:462+:499)?
    private func hasCodeTextColor(_ ranges: [StyledRange], at location: Int) -> Bool {
        let target = NSColor.systemRed.withAlphaComponent(0.85)
        for r in ranges where NSLocationInRange(location, r.range) {
            if let c = r.attributes[.foregroundColor] as? NSColor,
               c.isClose(to: target) { return true }
        }
        return false
    }

    @Test("Inline code emits the code-text color over its content")
    func inlineCodeColored() {
        let text = "a `code` b"
        let ranges = styled(text, caret: 0)
        // The `c` of `code` sits at utf16 index 3.
        #expect(hasCodeTextColor(ranges, at: 3))
    }

    @Test("GFM checkbox: caret OFF the line keeps marker hidden (inactive)")
    func checkboxInactive() {
        let text = "- [ ] task\nother"
        // caret on the second line, away from the checkbox.
        let ranges = styled(text, caret: 12)
        // The .taskCheckbox attribute is emitted on the checkbox marker range.
        let hasCheckbox = ranges.contains { $0.attributes[.taskCheckbox] != nil }
        #expect(hasCheckbox)
    }

    @Test("GFM checkbox: caret ON the line still emits the checkbox attribute (active reveal)")
    func checkboxActive() {
        let text = "- [ ] task"
        let ranges = styled(text, caret: 3) // caret inside `[ ]`
        let hasCheckbox = ranges.contains { $0.attributes[.taskCheckbox] != nil }
        #expect(hasCheckbox)
    }

    @Test("Empty [] is NOT styled as a checkbox (deliberate 3-class split)")
    func emptyBracketNotCheckbox() {
        let text = "- [] task"
        let ranges = styled(text, caret: 0)
        #expect(!ranges.contains { $0.attributes[.taskCheckbox] != nil })
    }

    @Test("Incomplete bracket [text] (no link) gets an incomplete-link style range")
    func incompleteBracket() {
        // incompleteLinkRegexes match `[text]` not followed by `(`.
        let text = "see [text] here"
        let ranges = styled(text, caret: 0)
        // At minimum: SOME range is emitted over the bracket span (index 4..9).
        #expect(ranges.contains { NSIntersectionRange($0.range, NSRange(location: 4, length: 6)).length > 0 })
    }

    @Test("ThematicBreak --- emits no checkbox/HR-attribute from the styler")
    func thematicBreakEmitsNothingHR() {
        // The styler must not own HR. The negative we assert: no .taskCheckbox
        // attribute is emitted on the `---` line. (HR appearance is owned solely
        // by syncHRVisibility — there is no public HR attribute key by design;
        // if a future change adds a styler-emitted HR attribute, extend this
        // negative to name it.)
        let text = "---\n"
        let ranges = styled(text, caret: 10)
        #expect(!ranges.contains { $0.attributes[.taskCheckbox] != nil })
    }
}

private extension NSColor {
    /// Component-wise closeness in the calibrated/device RGB space; tolerant
    /// of deviceRGB rounding (mirrors the 0.03 tolerance the renderer uses).
    func isClose(to other: NSColor, tolerance: CGFloat = 0.03) -> Bool {
        guard let a = usingColorSpace(.deviceRGB),
              let b = other.usingColorSpace(.deviceRGB) else { return false }
        return abs(a.redComponent - b.redComponent) <= tolerance
            && abs(a.greenComponent - b.greenComponent) <= tolerance
            && abs(a.blueComponent - b.blueComponent) <= tolerance
            && abs(a.alphaComponent - b.alphaComponent) <= tolerance
    }
}
```

**Step 2.4.2 — Add the primary-before-supplemental ordering pin.**

The merge order is the implicit conflict policy (CodeMap §C — supplemental runs AFTER primary, additive). Pin it at the composition seam. Because `TextStylingService` and `+Restyling` both compose, the cheapest pin that survives the Phase-5 merge is at the `AppleASTSupplementalStyler.styleAttributes` boundary: assert it returns ranges for BlockQuote/Strikethrough/Table and an **empty** contribution for ThematicBreak, so when Phase 5 folds it into one styler the "supplemental adds these, owns nothing for HR" contract is executable.

Append to the same file (still inside the `@Suite`):

```swift
extension StyledRangeCorpusTests {

    @Test("Supplemental styler emits ranges for blockquote but NOTHING for HR")
    func supplementalCoversBlockquoteNotHR() {
        let bqRanges = AppleASTSupplementalStyler.styleAttributes(
            text: "> quote\n",
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        #expect(!bqRanges.isEmpty)

        let hrRanges = AppleASTSupplementalStyler.styleAttributes(
            text: "---\n",
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        // visitThematicBreak is a deliberate no-op — supplemental owns nothing.
        #expect(hrRanges.isEmpty)
    }

    @Test("Supplemental strikethrough is INLINE and emits over the ~~span~~")
    func supplementalStrikethrough() {
        let ranges = AppleASTSupplementalStyler.styleAttributes(
            text: "a ~~b~~ c",
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        #expect(!ranges.isEmpty)
    }

    @Test("Supplemental multibyte: emoji line before a blockquote keeps ranges in-bounds")
    func supplementalMultibyte() {
        // Pins the UTF-8/UTF-16 column behavior (deferred bug). The assertion
        // is bounds-safety, not correctness — every emitted range must fall
        // inside the UTF-16 length.
        let text = "👍 hi\n> quote\n"
        let len = (text as NSString).length
        let ranges = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default
        )
        for r in ranges {
            #expect(r.range.location >= 0)
            #expect(NSMaxRange(r.range) <= len)
        }
    }
}
```

> Note: `MarkdownEditorTheme` is renamed to `MarkdownPMTheme` in Phase 5, not Phase 2. In Phase 2 it is still `MarkdownEditorTheme`, and `.default` is the verified canonical value (see the theme note above). When Phase 5 renames the type, `.default` updates with the rename.

**Step 2.4.3 — Run, observe, lock.**

```
swift test --package-path "External/MarkdownPM" --filter StyledRangeCorpus 2>&1 | tail -50
```

The `.taskCheckbox` / `.foregroundColor` assertions depend on exactly which attributes the styler emits — read `MarkdownStyler.swift` checkbox + inline-code passes and correct the assertion to the observed attribute key/value if a test fails. Iterate to green, non-zero count.

**Commit:** `test(markdownpm): Suite B — styled-range corpus at caret positions`

---

### Task 2.5 — Suite C: foldableHeadings NSRange pairs (both detector paths)

**Goal:** the existing app-side `FoldableHeadingsTests` already pins `foldableHeadings` NSRange pairs and the `[N]` ordinal key. Phase 2 EXTENDS that coverage to the gaps the CodeMap flags as untested: the `[N]` ordinal across duplicate-text headings, CRLF vs LF key equivalence, contentRange boundary at the next equal-or-higher heading, and — critically — **both heading detector paths** (the styler regex via `TokenizerCorpusTests.headingNoSpace_currentBehavior` / `headingTabAfterHash_currentBehavior` already, plus the detection regex here via `MarkdownDetection.isHeadingLine`). This pins the D-HEAD-1 divergence on the detection side.

`MarkdownDetection.foldableHeadings(in:)` and `reconcileFoldedHeadings` are **public**, so these can live app-side in `PommoraTests` (extending the existing seed) — which also exercises the cross-module import. `isHeadingLine` is internal, so its pins go in the **package** target.

**Step 2.5.1 — Package-side: pin the detection heading regex (D-HEAD-1, detection path).**

Create `External/MarkdownPM/Tests/MarkdownPMTests/HeadingDetectorCorpusTests.swift`:

```swift
import Foundation
import Testing
@testable import MarkdownPM

/// Pins the DETECTION heading rule (`MarkdownDetection.isHeadingLine`):
/// a Stage-1 regex prefilter `^#{1,6}([ \t]|$)` followed by a Stage-2
/// `Markdown.Document(parsing:)` AST confirm (MarkdownDetection.swift:155,160).
/// This DIVERGES from the styler's `headingRegex` (`#{1,6} +`, space-only).
/// Phase 4 unifies the two to the CommonMark space/tab/EOL rule (divergence
/// D-HEAD-1); this characterizes the detection path's current acceptance set.
@Suite("HeadingDetectorCorpus")
struct HeadingDetectorCorpusTests {

    private func isHeading(_ line: String) -> Bool {
        MarkdownDetection.isHeadingLine(line, isInsideCodeBlock: false)
    }

    @Test("`## Foo` (space) is a heading on the detection path")
    func spaceIsHeading() { #expect(isHeading("## Foo")) }

    @Test("`##\\tFoo` (tab) IS a heading on the detection path (diverges from styler)")
    func tabIsHeading_currentBehavior() {
        // VERIFIED against source + Apple AST: Stage-1 `[ \t]` admits the tab,
        // and the Stage-2 `Document(parsing:)` confirm ALSO yields a Heading
        // node (swift-markdown 0.8.0 accepts a tab after the `#` run). The
        // styler's ` +` does NOT — that is the real D-HEAD-1 divergence Phase 4
        // reconciles to one rule.
        #expect(isHeading("##\tFoo"))
    }

    @Test("Bare `###` (EOL) IS a heading on the detection path")
    func bareIsHeading_currentBehavior() {
        // `^#{1,6}([ \t]|$)` accepts a hash run terminated by end-of-line.
        #expect(isHeading("###"))
    }

    @Test("`#Foo` (no space) is NOT a heading")
    func noSpaceNotHeading() { #expect(!isHeading("#Foo")) }

    @Test("7 hashes `####### x` is NOT a heading (max 6)")
    func sevenHashesNotHeading() { #expect(!isHeading("####### x")) }

    @Test("Heading inside a code block is NOT a heading (stage-0 guard)")
    func insideCodeBlockNotHeading() {
        #expect(!MarkdownDetection.isHeadingLine("## Foo", isInsideCodeBlock: true))
    }
}
```

**Step 2.5.2 — App-side: extend the fold-key + CRLF + ordinal coverage.**

Append to the existing `Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift` (it already imports `MarkdownEngine`; after Phase 1 this is `import MarkdownPM` — match whatever the file currently imports). Add a new section:

```swift
    // MARK: - [N] ordinal disambiguation + CRLF (Phase-2 characterization extension)

    @Test("Duplicate-text headings get [N] ordinal keys in document order")
    func duplicateHeadingsOrdinal() {
        let text = "## Tasks\na\n## Tasks\nb\n## Tasks\nc\n"
        let h = MarkdownDetection.foldableHeadings(in: text)
        #expect(h.count == 3)
        #expect(h[0].key == "## Tasks")
        #expect(h[1].key == "## Tasks [2]")
        #expect(h[2].key == "## Tasks [3]")
    }

    @Test("CRLF and LF produce identical fold keys (trailing-newline stripped)")
    func crlfKeyEquivalence() {
        let lf = MarkdownDetection.foldableHeadings(in: "## Foo\nbody\n")
        let crlf = MarkdownDetection.foldableHeadings(in: "## Foo\r\nbody\r\n")
        #expect(lf.first?.key == "## Foo")
        #expect(crlf.first?.key == "## Foo")
        #expect(lf.first?.key == crlf.first?.key)
    }

    @Test("contentRange ends at the next equal-or-higher heading, not a deeper one")
    func contentRangeStopsAtSameLevel() {
        // ## A  (content includes the ### B subsection, stops at ## C)
        let text = "## A\nbody\n### B\nsub\n## C\ntail\n"
        let h = MarkdownDetection.foldableHeadings(in: text)
        let a = h.first { $0.key == "## A" }!
        let ns = text as NSString
        let cStart = ns.range(of: "## C").location
        #expect(NSMaxRange(a.contentRange) == cStart)
    }

    @Test("reconcileFoldedHeadings drops keys whose heading was renamed")
    func reconcileDropsOrphans() {
        let body = "## Kept\nx\n"
        let folded: Set<String> = ["## Kept", "## Gone"]
        let kept = MarkdownDetection.reconcileFoldedHeadings(folded, in: body)
        #expect(kept == ["## Kept"])
    }

    @Test("Heading on a multibyte line keys + ranges stay UTF-16 consistent")
    func multibyteHeadingKey() {
        let text = "## 日本語\nbody\n"
        let h = MarkdownDetection.foldableHeadings(in: text)
        #expect(h.count == 1)
        #expect(h[0].key == "## 日本語")
        // headingRange covers the full heading line in UTF-16 units.
        let ns = text as NSString
        #expect(h[0].headingRange == ns.lineRange(for: NSRange(location: 0, length: 0)))
    }
```

**Step 2.5.3 — Run both legs.**

```
swift test --package-path "External/MarkdownPM" --filter HeadingDetectorCorpus 2>&1 | tail -30
```

then the app-side leg:

```
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/FoldableHeadingsTests 2>&1 | tail -30
```

Visually verify a non-zero executed count in each. If the `[N]` or contentRange assertions disagree, the source (`MarkdownDetection.foldableHeadings`) is authoritative — correct the assertion to the observed pairs (the suffix is `" [\(count)]"` with a leading space per `:274`).

**Commit:** `test(markdownpm): Suite C — foldableHeadings ordinal/CRLF/contentRange + both detector paths`

---

### Task 2.6 — Suite D: wikilink storage↔display round-trip + the D1 guard

**Goal:** pin `WikiLinkService.makeDisplayState` / `makeStorageState` round-trips (the LIVE transform — runs on every load/restyle/save) AND ship the **DEC-1 anchor test** naming BOTH write sinks. `WikiLinkService` is **public** → this can live app-side, but the round-trip half has no app dependency, so put the transform round-trip in the package target and the on-disk D1 guard in the app target (it touches the save path).

**Step 2.6.1 — Package-side: the transform round-trip.**

Create `External/MarkdownPM/Tests/MarkdownPMTests/WikiLinkRoundTripTests.swift`:

```swift
import AppKit
import Foundation
import Testing
@testable import MarkdownPM

/// Pins the LIVE WikiLinkService display↔storage transform. This is the seam
/// the post-rebuild Wiki-Link session builds on; Phase 2 freezes its current
/// behavior. The transform runs on every load/restyle/save — do NOT
/// "simplify away" the live adapter (CodeMap F4).
@Suite("WikiLinkRoundTrip")
struct WikiLinkRoundTripTests {

    @Test("Storage [[Name|id]] → display [[Name]] strips the id, keeps metadata")
    func storageToDisplayStripsId() {
        let (display, meta) = WikiLinkService.makeDisplayState(from: "see [[Note|01ABC]] end")
        #expect(display == "see [[Note]] end")
        // Metadata recovers the id for the display occurrence.
        #expect(meta.values.contains { $0.id == "01ABC" })
    }

    @Test("Display [[Name]] with NO resolver id round-trips to plain [[Name]]")
    func displayToStoragePlainNoId() {
        let (storage, _) = WikiLinkService.makeStorageState(
            from: "see [[Note]] end",
            existingMetadata: [:],
            textStorage: nil
        )
        // No id anywhere → storage stays plain. This is the DEC-1 default.
        #expect(storage == "see [[Note]] end")
    }

    @Test("Image embed ![[Img]] is EXCLUDED from the wikilink transform")
    func imageEmbedExcluded() {
        // (?<!!) lookbehind routes ![[…]] away from the rewrite.
        let (display, meta) = WikiLinkService.makeDisplayState(from: "![[Img|x]]")
        #expect(display == "![[Img|x]]")   // unchanged
        #expect(meta.isEmpty)
    }

    @Test("Multibyte name round-trips with correct UTF-16 ranges")
    func multibyteRoundTrip() {
        let src = "x [[日本語|01ABC]] y"
        let (display, _) = WikiLinkService.makeDisplayState(from: src)
        #expect(display == "x [[日本語]] y")
    }

    @Test("Round-trip is stable: display→storage→display with no id is identity")
    func stableRoundTrip() {
        let display0 = "a [[One]] b [[Two]] c"
        let (storage, _) = WikiLinkService.makeStorageState(
            from: display0, existingMetadata: [:], textStorage: nil)
        let (display1, _) = WikiLinkService.makeDisplayState(from: storage)
        #expect(display1 == display0)
    }
}
```

**Step 2.6.2 — App-side: the DEC-1 honest anchor (CURRENT engine behavior + known gap).**

This test is an **honest anchor**, not a structural guard. VERIFIED against source (`Services/WikiLinkService.swift:136-151`): `makeStorageState` reads `.wikiLinkID` off the live `textStorage` at the link's content location (`:138`) and, when an id is present, emits `[[Name|id]]` (`:148`); with no id it emits plain `[[Name]]` (`:150`). So **today, with a resolver that stamps a `.wikiLinkID`, the engine DOES embed `[[Note|id]]`** — there is no strip step yet. The real DEC-1 structural strip lands in the Wiki-Link session (LD-28: one guard in the consolidated save path). This Phase-2 test therefore:

1. Asserts the CURRENT behavior positively (an id-stamped link round-trips to `[[Name|id]]`), so the characterization is honest about what ships today, and
2. Records the DEC-1 target ("no id on disk") as a **known-gap / xfail anchor** that flips green when the real structural strip lands in the Wiki-Link session.

It does NOT define a test-local `stripWikiLinkIds` / `assertNoIdInLinks` helper and assert against it — a test of a test-local helper is a tautology, not a structural guard. The two sinks named are `+TextDelegate.swift:70` (normal-typing save) and `+Services.swift:325` (Writing-Tools commit); both compute via `WikiLinkService.makeStorageState`, so pinning the shared producer covers both.

Create `Pommora/PommoraTests/Pages/WikiLinkOnDiskGuardTests.swift`:

```swift
import AppKit
import Foundation
import MarkdownPM
import Testing

/// DEC-1 honest anchor: wikilinks MUST be PLAIN `[[Title]]` on disk (target
/// identity is the page's frontmatter ULID, never embedded in the link). The
/// shared producer for BOTH save sinks is WikiLinkService.makeStorageState:
///   - normal typing:        NativeTextViewCoordinator+TextDelegate.swift:70
///   - Writing-Tools commit: NativeTextViewCoordinator+Services.swift:325
///
/// Verified current behavior: makeStorageState has NO id-strip — when a
/// resolver stamps `.wikiLinkID`, it embeds `[[Name|id]]` (WikiLinkService
/// .swift:148). The structural strip is LD-28 and ships in the Wiki-Link session. This
/// suite pins today's behavior honestly and carries the DEC-1 target as a
/// known-gap anchor that flips when the real guard lands.
@Suite("WikiLinkOnDiskGuard")
struct WikiLinkOnDiskGuardTests {

    @Test("CURRENT: a resolver-stamped id is embedded as [[Name|id]] (no strip yet — shared sink producer)")
    func currentlyEmbedsResolverId() {
        // Simulate the resolver having stamped an id onto the live storage's
        // .wikiLinkID attribute — exactly what makeStorageState reads at :138.
        let attributed = NSTextStorage(string: "see [[Note]] end")
        let nameRange = ("see [[Note]] end" as NSString).range(of: "Note")
        attributed.addAttribute(.wikiLinkID, value: "01HZX9ABCDEFGHJKMNPQRSTVWX", range: nameRange)

        let (storage, _) = WikiLinkService.makeStorageState(
            from: "see [[Note]] end",
            existingMetadata: [:],
            textStorage: attributed
        )
        // Honest pin of today's behavior: the id IS embedded. Both save sinks
        // (+TextDelegate:70, +Services:325) feed this same producer.
        #expect(storage == "see [[Note]] end".replacingOccurrences(
            of: "[[Note]]", with: "[[Note|01HZX9ABCDEFGHJKMNPQRSTVWX]]"))
    }

    /// DEC-1 TARGET — known gap. When the Wiki-Link session's structural strip lands in
    /// the consolidated save path (LD-28), the persisted string must stay
    /// id-free even with a resolver-stamped id. This anchor is expected to
    /// FAIL today and flip green when the guard ships; mark it accordingly
    /// (Swift Testing: enable once the strip lands, or carry as a documented
    /// known-failure). It asserts the POLICY, not a test-local helper.
    @Test("DEC-1 TARGET (the Wiki-Link session): persisted string stays plain [[Name]] even with a resolved id",
          .disabled("DEC-1 structural strip ships in the Wiki-Link session (LD-28); flips green then"))
    func dec1TargetNoIdOnDisk() {
        let attributed = NSTextStorage(string: "a [[X]] b")
        let r = ("a [[X]] b" as NSString).range(of: "X")
        attributed.addAttribute(.wikiLinkID, value: "01HZX9ABCDEFGHJKMNPQRSTVWX", range: r)
        let (storage, _) = WikiLinkService.makeStorageState(
            from: "a [[X]] b", existingMetadata: [:], textStorage: attributed)
        // No id-bearing [[Name|id]] may reach disk once the strip lands.
        let pipeInLink = try! NSRegularExpression(
            pattern: #"(?<!!)\[\[[^\]\r\n]*\|[^\]\r\n]+\]\]"#)
        let ns = storage as NSString
        let hits = pipeInLink.numberOfMatches(
            in: storage, range: NSRange(location: 0, length: ns.length))
        #expect(hits == 0, "an id-bearing [[Name|id]] reached disk: \(storage)")
    }
}
```

> Implementation note for the executing engineer: the DEC-1 structural guard is NOT a Phase-2 deliverable — it is LD-28, landing in the Wiki-Link session's consolidated save path as one strip step in the single save helper. Phase 2 ships only the honest characterization (current behavior pinned) plus the disabled DEC-1 target anchor. When the real guard lands in the Wiki-Link session, enable `dec1TargetNoIdOnDisk`; it becomes the regression lock.

**Step 2.6.3 — Run both legs, lock.**

```
swift test --package-path "External/MarkdownPM" --filter WikiLinkRoundTrip 2>&1 | tail -30
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/WikiLinkOnDiskGuard 2>&1 | tail -30
```

Verify non-zero executed counts. The round-trip assertions should pass against the verified `WikiLinkService` source; if `makeDisplayState` produces a different exact string, correct the expected literal to observed output.

**Commit:** `test(markdownpm): Suite D — wikilink round-trip + DEC-1 honest anchor (both write sinks)`

---

### Task 2.7 — Suite E: the 9 input transforms (byte-level golden) + pull EnterContinuation into the run

**Goal:** pin the 9 input transforms in `MarkdownLists.handleInsertion` (`MarkdownListHandler.swift:358-898`) at byte level, including the two byte-changing dash transforms (`--` → em-dash, spaced ` - ` → en-dash) and the wikilink/code carve-outs, plus the smart-quotes delegation note.

These transforms must be exercised through the **production cached code-block path**, not a bare NSTextView. VERIFIED against source: the dash transforms decide "inside code" via `MarkdownDetection.isInsideCodeBlock(location:in:)` reading `textView.string` directly today (`MarkdownListHandler.swift:381` and `:416`), but Phase 3 rewires those two call sites to read the coordinator's cached code-block query. If the Phase-2 goldens run against a delegate-less NSTextView, that Phase-3 rewire silently flips `dashSkipsInsideCode`. So this suite builds a real `NativeTextViewCoordinator` and sets `tv.delegate = coordinator` (the coordinator type is `NativeTextViewCoordinator`, `public final class … NSTextViewDelegate`; `MarkdownLists` already casts `textView.delegate as? NativeTextViewWrapper.Coordinator` at `MarkdownListHandler.swift:22`). The harness mirrors the Phase-3 `makeCoordinator` wiring, and the goldens are re-pinned against this delegate-backed host. Smart-quotes is delegated to macOS (NOT an engine transform) and auto-dash is forced OFF — both documented, neither tested as engine behavior here. `MarkdownLists` is internal → package target.

The existing `EnterContinuationTests` + `CheckboxCanonicalizationTests` are ALREADY in the package target and were pulled into the gate by Task 2.1. This task adds the dash + arrow + bracket-skip transforms alongside them, AND re-pins those pulled-in suites against the same delegate-backed harness so their goldens survive the Phase-3 rewire.

**Step 2.7.1 — Membership decision (resolves CodeMap Open Question #26).** For Phase 2 characterization purposes the "NINE" transforms pinned are: (1) Enter list continuation, (2) checkbox shorthand → GFM on space, (3) `--`→em-dash, (4) spaced ` - `→en-dash, (5) en→em promotion, (6) `<-`/`->`/`<->` arrows, (7) bracket-skip-on-Enter, (8) Shift+Enter exits list, (9) fenced-code completion. This is the test-membership list only; the canonical D5 product membership is settled later. Each gets at least one byte-level golden + at least one carve-out test.

**Step 2.7.2 — Write the suite.**

Create `External/MarkdownPM/Tests/MarkdownPMTests/InputTransformCorpusTests.swift`:

```swift
import AppKit
import Testing
@testable import MarkdownPM

/// Byte-level golden for the input transforms in MarkdownLists.handleInsertion.
/// Builds a REAL NativeTextViewCoordinator and wires it as tv.delegate so the
/// transforms exercise the PRODUCTION cached code-block path (mirrors the
/// Phase-3 makeCoordinator harness). Without the delegate, Phase 3's rewire of
/// MarkdownListHandler.swift:381/:416 to the coordinator's cached query would
/// silently flip dashSkipsInsideCode. Pins the two byte-changing dash
/// transforms + their carve-outs verbatim before any Phase-6 tidy. Smart-quotes
/// is delegated to macOS (NOT an engine transform) and auto-dash is forced OFF —
/// both documented, neither tested as engine behavior here.
@MainActor
struct InputTransformCorpusTests {

    /// Build a delegate-backed NSTextView host: a real coordinator set as the
    /// text view's delegate, mirroring the Phase-3 makeCoordinator wiring so
    /// MarkdownLists sees the production cached code-block path.
    private func makeHost(_ source: String, caret: Int) -> (tv: NSTextView, coordinator: NativeTextViewCoordinator) {
        // Same init as the Phase-3 ParseSpineTests.makeCoordinator — the real
        // init is 7 params (NativeTextViewCoordinator.swift:178) with
        // `initialFoldedHeadings` defaulted, so this 6-arg call binds the rest.
        // One init shape across both harnesses — they must never drift.
        let coordinator = NativeTextViewCoordinator(
            text: .constant(source),
            fontName: "SF Pro Text",
            fontSize: 15,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        let tv = NSTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 200))
        tv.delegate = coordinator
        tv.string = source
        tv.setSelectedRange(NSRange(location: caret, length: 0))
        return (tv, coordinator)
    }

    /// Type `replacement` at `caret` into `source`; return the resulting
    /// string + caret. Mirrors EnterContinuationTests.pressSpace/pressEnter but
    /// over the delegate-backed host.
    private func type(
        _ replacement: String, on source: String, caretAt caret: Int
    ) -> (handled: Bool, result: String, caret: Int) {
        let (tv, _) = makeHost(source, caret: caret)
        let handled = !MarkdownLists.handleInsertion(
            textView: tv,
            affectedCharRange: NSRange(location: caret, length: 0),
            replacementString: replacement)
        if !handled {
            let ns = tv.string as NSString
            tv.string = ns.replacingCharacters(
                in: NSRange(location: caret, length: 0), with: replacement)
            tv.setSelectedRange(NSRange(location: caret + (replacement as NSString).length, length: 0))
        }
        return (handled, tv.string, tv.selectedRange().location)
    }

    // MARK: - (3) `--` → em-dash (fires on the NEXT non-dash char)

    @Test("Typing a letter after `--` converts to em-dash")
    func emDash() {
        // "a--" then type "b" → "a—b"
        let r = type("b", on: "a--", caretAt: 3)
        #expect(r.result == "a—b")
    }

    @Test("`---` (HR) is preserved: 3rd dash does not em-dash")
    func emDashPreservesHR() {
        // "a--" then type "-" → the em-dash collision guard checks text[N-3];
        // a third dash keeps `---` intact (HR), no em-dash.
        let r = type("-", on: "a--", caretAt: 3)
        #expect(r.result == "a---")
    }

    // MARK: - (4) spaced ` - ` → en-dash (fires on the 2nd space)

    @Test("Spaced ` - ` then a space converts to en-dash")
    func enDash() {
        // "9 -" then type " " → "9 – " (en-dash + trailing space)
        let r = type(" ", on: "9 -", caretAt: 3)
        #expect(r.result == "9 – ")
    }

    @Test("En-dash carve-out: ` - ` inside a [[wikilink]] is NOT rewritten")
    func enDashSkipsWikilink() {
        // Inside `[[Mon - Fri` the en-dash transform must not fire — filenames
        // with ` - ` separators stay literal (isInsideWikilink guard).
        let r = type(" ", on: "[[Mon -", caretAt: 7)
        #expect(r.result == "[[Mon - ")   // literal hyphen preserved
    }

    // MARK: - (5) en→em promotion

    @Test("Typing `-` adjacent to an en-dash promotes it to em-dash")
    func enToEmPromotion() {
        // "a–" (en-dash at index 1) then type "-" → "a—"
        let r = type("-", on: "a\u{2013}", caretAt: 2)
        #expect(r.result == "a—")
    }

    // MARK: - (6) arrows

    @Test("`->` then a char converts to →")
    func rightArrow() {
        let r = type("x", on: "a->", caretAt: 3)
        #expect(r.result == "a→x")
    }

    @Test("Arrow carve-out: `<-` is preserved long enough that the `-` fast-path doesn't eat it")
    func leftArrow() {
        let r = type("x", on: "a<-", caretAt: 3)
        #expect(r.result == "a←x")
    }

    // MARK: - (7) bracket-skip on Enter

    @Test("Enter between a matched [ ] pair jumps past the closer (no newline)")
    func bracketSkipEnter() {
        // caret between `[` and `]` in "x[]" at index 2; Enter jumps to index 3.
        let (tv, _) = makeHost("x[]", caret: 2)
        let handled = !MarkdownLists.handleInsertion(
            textView: tv,
            affectedCharRange: NSRange(location: 2, length: 0),
            replacementString: "\n")
        #expect(handled)
        #expect(tv.string == "x[]")             // no newline inserted
        #expect(tv.selectedRange().location == 3) // caret past `]`
    }

    // MARK: - code carve-out (shared by dash transforms)

    @Test("Dash transform skips inside a fenced code block")
    func dashSkipsInsideCode() {
        let source = "```\na--"
        let r = type("b", on: source, caretAt: (source as NSString).length)
        #expect(r.result == "```\na--b")        // literal, no em-dash
    }
}
```

> Re-pin note: the existing `EnterContinuationTests` and `CheckboxCanonicalizationTests` currently call `MarkdownLists.handleInsertion` on a delegate-less NSTextView. Migrate their helpers to the same delegate-backed `makeHost(...)` shape (set `tv.delegate = coordinator` from the shared `makeHost(...)` helper) and re-confirm their goldens, so all input-transform suites exercise the production code-block path uniformly and survive the Phase-3 rewire of `MarkdownListHandler.swift:381/:416`.

**Step 2.7.3 — Run, lock, and confirm EnterContinuation runs in the gate.**

```
swift test --package-path "External/MarkdownPM" --filter InputTransformCorpus 2>&1 | tail -40
swift test --package-path "External/MarkdownPM" --filter EnterContinuation 2>&1 | tail -20
swift test --package-path "External/MarkdownPM" --filter CheckboxCanonicalization 2>&1 | tail -20
```

The dash/arrow goldens are the ones most likely to need correction — the transforms fire on the *next* character and have single-char collision guards (Markdown.md §9.12). If a golden disagrees, read `MarkdownListHandler.swift:358-898` for that branch and correct the expected string to observed output; that correction IS the byte-level pin. Iterate to green, non-zero count. Confirm `EnterContinuation` + `CheckboxCanonicalization` execute (re-pinned against the delegate-backed harness — this also proves the gate reaches them).

**Commit:** `test(markdownpm): Suite E — input-transform byte-level golden (dashes, arrows, bracket-skip)`

---

### Task 2.8 — Build the parse-count probe + the large-document fixture

**Goal:** the #9 fix (Phase 3) is "collapse redundant uncached Apple-AST parses." To prove Phase 3 actually reduces parses (and to assert it later), Phase 2 must build the measurement instrument that **does not exist today**: a count of `Markdown.Document(parsing:)` invocations per `textDidChange`, plus a large-document fixture for the Phase-3 manual Instruments capture. Neither exists yet (CodeMap Change-Site row "Per-keystroke parse counts").

`Document(parsing:)` is a free initializer on Apple's type — we cannot hook it directly. The probe instead counts calls at OUR call sites by routing the two uncached document parses (`AppleASTSupplementalStyler.swift:30`, `+HeadingFolding.swift:160`) through a thin internal counter shim. This shim is the seam Phase 3 collapses; in Phase 2 it is purely observational (it calls `Document(parsing:)` exactly as before and increments a counter).

**Important — parse-count is size-independent.** The per-edit parse count is a function of how many call sites fire, not document size, so the parse-count assertions below run against a TINY inline doc (`"# A\n> q\nbody\n"`), not the large fixture. The `LargeDocumentFixture` is scoped to the **Phase-3 manual Instruments capture ONLY** (making the cost observable in a trace) — it is not used by any automated parse-count assertion.

**Step 2.8.1 — Add the internal counter shim (package source, behavior-neutral).**

Create `External/MarkdownPM/Sources/MarkdownPM/Parser/AppleDocumentParseProbe.swift`:

```swift
//
//  AppleDocumentParseProbe.swift
//  MarkdownPM
//
//  Behavior-neutral instrumentation: a single chokepoint for the two
//  uncached whole-document Apple parses (AppleASTSupplementalStyler +
//  syncHeadingFolding). Counts invocations so Phase 2 can pin the current
//  parse count and Phase 3 can assert the reduction. The Phase-3 cached
//  spine replaces the call sites; this probe stays as the regression gate.
//
import Foundation
import Markdown

/// Wraps `Markdown.Document(parsing:)` with an invocation counter.
/// Counting is gated to test/DEBUG so production has zero overhead.
enum AppleDocumentParseProbe {
    #if DEBUG
    nonisolated(unsafe) static var count = 0
    static func reset() { count = 0 }
    #endif

    /// Drop-in for `Markdown.Document(parsing: text)` at the two whole-document
    /// call sites. Identical output; increments the counter under DEBUG.
    static func parse(_ text: String) -> Document {
        #if DEBUG
        count += 1
        #endif
        return Document(parsing: text)
    }
}
```

> `nonisolated(unsafe)` is acceptable here because the counter is test-only and all reads/writes happen on the `@MainActor` from the editor's single-threaded keystroke path; the package is Swift 5.9 so this compiles without the strict-concurrency objection. If 5.9 rejects `nonisolated(unsafe)`, use a plain `static var count = 0` — the package's relaxed settings allow it.

**Step 2.8.2 — Route the two whole-document parses through the probe (behavior-neutral edit).**

In `External/MarkdownPM/Sources/MarkdownPM/Styling/AppleASTSupplementalStyler.swift:30`, change:

```swift
        let document = Document(parsing: text)
```

to:

```swift
        let document = AppleDocumentParseProbe.parse(text)
```

In `External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift:160` (the `syncHeadingFolding` parse), make the identical substitution. Do NOT touch the per-fragment renderer parse (`MarkdownTextLayoutFragment.swift:453`) or the per-line `detectListContext` parse — those are intentionally outside the spine.

This is behavior-neutral (the probe calls the same initializer). Confirm with the full gate before asserting anything.

**Step 2.8.3 — Add the large-document fixture (Phase-3 Instruments capture only).**

Create `External/MarkdownPM/Tests/MarkdownPMTests/Fixtures/LargeDocumentFixture.swift`:

```swift
import Foundation

/// A deterministic large Markdown document for the Phase-3 MANUAL Instruments
/// capture only — it makes the parse cost observable in a trace. NOT used by
/// any automated parse-count assertion (parse count is size-independent).
/// ~400 paragraphs mixing headings, prose, lists, checkboxes, code fences,
/// blockquotes, wikilinks, and math so the parse cost is representative, not a
/// degenerate single-construct stream.
enum LargeDocumentFixture {
    static let body: String = {
        var s = ""
        for i in 0..<100 {
            s += "## Section \(i)\n"
            s += "Some prose with *italic* and **bold** and `code` and a [[Note \(i)]] link.\n"
            s += "- bullet one\n- [ ] task \(i)\n- [x] done \(i)\n"
            s += "> a quoted line for section \(i)\n"
            s += "```swift\nlet x = \(i)\n```\n"
            s += "Inline math $x_\(i)+y$ and a price of $\(i),000 here.\n\n"
        }
        return s
    }()
}
```

**Step 2.8.4 — Write the parse-count characterization test (CHARACTERIZING CURRENT behavior — RETIRED in Phase 3).**

Both tests below are **DIRECT-CALL** probes that CHARACTERIZE CURRENT behavior: today the supplemental styler parses the whole document once per call, and two passes on identical text re-parse (no cache). **Phase 3 RETIRES/rewrites both** once the parse moves into the cached memo — at which point the second-pass assertion becomes `== 0` (cache hit) and these characterizations are replaced, not merely tightened. They are the #9 before-snapshot; the ledger row (`#9-PARSE`) records the flip ("1 unfolded / 2 folded today → 1 after Phase 3").

Create `External/MarkdownPM/Tests/MarkdownPMTests/ParseCountProbeTests.swift`:

```swift
import AppKit
import Testing
@testable import MarkdownPM

/// CHARACTERIZES the CURRENT number of whole-document Apple parses per
/// supplemental-style pass via direct calls. Phase 3 RETIRES/rewrites these
/// once the parse moves into the cached memo (the second-pass assertion
/// becomes == 0). Asserts against a TINY inline doc because parse count is
/// size-independent — the large fixture is for the Phase-3 Instruments
/// capture, not these counts.
@MainActor
struct ParseCountProbeTests {

    // Size-independent: the count tracks call sites, not document length.
    private static let tinyDoc = "# A\n> q\nbody\n"

    @Test("CURRENT: one supplemental-style pass triggers exactly one whole-doc parse (RETIRED in P3)")
    func supplementalParseCountIsOne() {
        AppleDocumentParseProbe.reset()
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc,
            baseFont: NSFont.systemFont(ofSize: 15),
            theme: .default)
        // CURRENT behavior: the supplemental styler parses the document exactly
        // once per call. Phase 3 routes this through the cache; this direct-call
        // characterization is retired/rewritten when that lands.
        #expect(AppleDocumentParseProbe.count == 1)
    }

    @Test("CURRENT: two passes on identical text re-parse, no cache yet (RETIRED in P3)")
    func uncachedRepeatedParse_currentBehavior() {
        AppleDocumentParseProbe.reset()
        let font = NSFont.systemFont(ofSize: 15)
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc, baseFont: font, theme: .default)
        _ = AppleASTSupplementalStyler.styleAttributes(
            text: Self.tinyDoc, baseFont: font, theme: .default)
        // CURRENT: 2 (no cache). Phase 3 drives the second identical-text pass
        // to a cache hit (count == 1 total); this characterization is then
        // RETIRED/rewritten. This is the #9 regression anchor (ledger #9-PARSE).
        #expect(AppleDocumentParseProbe.count == 2)
    }
}
```

> `.default` is the verified `MarkdownEditorTheme.default` (see Task 2.4); when Phase 5 renames the type to `MarkdownPMTheme`, `.default` survives.

**Step 2.8.5 — Run, lock, full gate.**

```
swift test --package-path "External/MarkdownPM" --filter ParseCountProbe 2>&1 | tail -30
```

Then run the WHOLE gate to confirm the behavior-neutral probe edits broke nothing:

```
"External/MarkdownPM/run-tests.sh" 2>&1 | tail -60
```

If `supplementalParseCountIsOne` reports a count other than 1, read the styler again — there may be a second internal parse you missed; reconcile (either route it through the probe or correct the expected count). The `uncachedRepeatedParse_currentBehavior` count of 2 is the explicit #9 baseline that Phase 3 will flip to 1 (already logged as the `#9-PARSE` divergence-ledger row).

**Commit:** `test(markdownpm): parse-count probe + large-doc fixture (the #9 before-snapshot)`

---

### Task 2.9 — Public-contract pin + final gate

**Goal:** lock the public surface the rebuild must not break (CodeMap "Public contract" + Service doc §"Public contract"): the `MarkdownPMEditor` 15-param init compiles with app-used args only; the 8 dormant params (incl. the `@Binding` `isWikiLinkActive` / `pendingInlineReplacement` and the `onInlineSelectionChange` / `onPasteImage` closures) are still present; `TextInsets.init(horizontal:vertical:)` exists; `MarkdownPlainText.extract(from:)` and `MarkdownDetection.reconcileFoldedHeadings` are callable; the two frozen attribute-key literals are exact. This is an app-side suite (it consumes the public API), Swift 6.

**Step 2.9.1 — Resolve the onCodeBlockSelectionChange shed-check (CodeMap gap).** Before this suite asserts `onCodeBlockSelectionChange` is shed, VERIFY the code-block copy-overlay feature is truly unwired (the ruling says shed only `onCaretRectChange` + `onCodeBlockSelectionChange`, but first confirm `updateCodeBlockSelection` → `onCodeBlockSelectionChange` is dead). Run:

```
grep -rn "onCodeBlockSelectionChange\|updateCodeBlockSelection\|CodeBlockSelection" "Pommora/Pommora" "External/MarkdownPM/Sources"
```

If the only references are the wrapper's own declaration + an unwired coordinator method (no app call site, no live overlay view consuming it), it is safe to shed in Phase 1. If a live consumer surfaces, record it in the divergence ledger as "shed blocked — wired feature" and KEEP the param. The Phase-2 suite below asserts only what is confirmed; do not assert a shed that the grep contradicts.

**Step 2.9.2 — Write the public-contract suite.**

Create `Pommora/PommoraTests/Pages/MarkdownPMPublicContractTests.swift`:

```swift
import AppKit
import Foundation
import MarkdownPM
import SwiftUI
import Testing

/// Locks the MarkdownPM public surface the rebuild must not silently break:
/// the editor init's app-used params, the surviving dormant seams, the
/// TextInsets public init, the public free functions, and the two frozen
/// attribute-key string literals.
@MainActor
@Suite("MarkdownPMPublicContract")
struct MarkdownPMPublicContractTests {

    @Test("MarkdownPMEditor constructs with only the app-used args")
    func editorConstructsWithAppArgs() {
        // The app passes text, configuration, fontName, fontSize, documentId,
        // isEditable, foldedHeadings, onScrollOffsetChange. All other params
        // default. This compiling IS the contract.
        var text = "# hi"
        var folded: Set<String> = []
        _ = MarkdownPMEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            foldedHeadings: Binding(get: { folded }, set: { folded = $0 }),
            configuration: .default,
            fontName: "SF Pro Text",
            fontSize: 15,
            documentId: "page-1",
            isEditable: true,
            onScrollOffsetChange: { _ in }
        )
    }

    @Test("Dormant wikilink + inline seams survive (isWikiLinkActive, pendingInlineReplacement, onInlineSelectionChange, onPasteImage)")
    func dormantSeamsSurvive() {
        var text = ""
        var active = false
        var pending: InlineReplacementRequest? = nil
        // Passing all four dormant seams must still compile after the rebuild.
        _ = MarkdownPMEditor(
            text: Binding(get: { text }, set: { text = $0 }),
            isWikiLinkActive: Binding(get: { active }, set: { active = $0 }),
            pendingInlineReplacement: Binding(get: { pending }, set: { pending = $0 }),
            onPasteImage: { _ in nil },
            onInlineSelectionChange: { _ in }
        )
    }

    @Test("TextInsets public init(horizontal:vertical:) is callable")
    func textInsetsPublicInit() {
        let insets = TextInsets(horizontal: 12, vertical: 8)
        #expect(insets.horizontal == 12)
        #expect(insets.vertical == 8)
    }

    @Test("MarkdownPlainText.extract(from:) strips markdown to plain prose")
    func plainTextExtract() {
        let plain = MarkdownPlainText.extract(from: "# Title\n\n**bold** text")
        #expect(plain.contains("Title"))
        #expect(plain.contains("bold"))
        #expect(!plain.contains("#"))
        #expect(!plain.contains("**"))
    }

    @Test("reconcileFoldedHeadings is public and drops orphans")
    func reconcilePublic() {
        let kept = MarkdownDetection.reconcileFoldedHeadings(
            ["## A", "## Gone"], in: "## A\nx\n")
        #expect(kept == ["## A"])
    }

    @Test("Frozen attribute-key string literals are EXACT (NodeLinkID / TaskCheckbox)")
    func frozenAttributeKeyLiterals() {
        // The Swift symbol `.wikiLinkID` maps to the literal "NodeLinkID"
        // (divergent on purpose — do NOT rename the literal). renderer +
        // makeStorageState read these by raw string.
        #expect(NSAttributedString.Key.wikiLinkID == NSAttributedString.Key("NodeLinkID"))
        #expect(NSAttributedString.Key.taskCheckbox == NSAttributedString.Key("TaskCheckbox"))
    }
}
```

> `MarkdownPMEditor` / `MarkdownPMConfiguration` are the Phase-1 renamed names. If Phase 1 has NOT yet landed when you write this (the front door is still `NativeTextViewWrapper` / `MarkdownEditorConfiguration`), use the old names here and rename in the Phase-1 commit. The `.default` configuration argument and the `TextInsets` / `InlineReplacementRequest` types are unchanged by the rename. Verify `TextInsets`' property names (`horizontal` / `vertical`) against `NativeTextViewSelectionTypes.swift` or wherever it is declared, and correct the assertions if they differ.

**Step 2.9.3 — Run the public-contract leg, then the FULL gate.**

```
xcodebuild test -project "Pommora/Pommora.xcodeproj" -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests/MarkdownPMPublicContract 2>&1 | tail -40
```

Then the complete characterization gate — this is the Phase-2 exit criterion:

```
"External/MarkdownPM/run-tests.sh" 2>&1 | tail -80
```

Visually confirm: the package leg runs `TokenizerCorpus`, `StyledRangeCorpus`, `HeadingDetectorCorpus`, `WikiLinkRoundTrip`, `InputTransformCorpus`, `ParseCountProbe`, `EnterContinuation`, `CheckboxCanonicalization` with a non-zero total executed count; the app leg runs `FoldableHeadings`, `WikiLinkOnDiskGuard`, `MarkdownPMPublicContract`, `PageTextStats` (existing) with a non-zero executed count. Both legs green.

**Commit:** `test(markdownpm): public-contract pin — editor init, dormant seams, TextInsets, frozen keys`

---

### Phase 2 exit criteria (the gate Phases 3-6 depend on)

All of the following must be true before any Phase-3 work dispatches:

1. `External/MarkdownPM/run-tests.sh` runs BOTH legs and exits zero, with a **visually-verified non-zero executed count** in each leg (the false-green trap is closed).
2. Eight package suites + four app suites are green: `TokenizerCorpus`, `StyledRangeCorpus`, `HeadingDetectorCorpus`, `WikiLinkRoundTrip`, `InputTransformCorpus`, `ParseCountProbe`, `EnterContinuation`, `CheckboxCanonicalization` (package); `FoldableHeadings`, `WikiLinkOnDiskGuard`, `MarkdownPMPublicContract`, `PageTextStats` (app).
3. The corpus pins, as **current behavior**, every case the divergence ledger flags for a future flip: asterisk-only emphasis + emphasis-inside-code (D-EMPH-1/2), both heading detectors (D-HEAD-1), and the uncached-repeated-parse count of 2 (#9-PARSE baseline).
4. The DEC-1 on-disk anchor names **both** write sinks (`+TextDelegate:70` + `+Services:325`), honestly pins TODAY's behavior (a resolver-stamped id IS embedded), and carries the "no id on disk" target as a disabled known-gap anchor. **DEC-1's structural guard ships in the Wiki-Link session (LD-28), not Phase 2** — Phase 2 only characterizes and anchors it.
5. The parse-count probe + large-doc fixture exist (neither existed before Phase 2): the probe pins the current `Document(parsing:)` count against a tiny size-independent doc; the large fixture is reserved for the Phase-3 Instruments capture.
6. `MarkdownPM-Divergence-Ledger.md` exists with its opening rows (its creation folded into the Task 2.1 commit); no divergence has landed (all PENDING) — that is correct, Phase 2 changes nothing, it only pins.

Open decisions recorded for the executing engineer (do NOT guess — surface to Nathan if they block):
- **Q (Task 2.9.1):** confirm `onCodeBlockSelectionChange` is truly unwired before the Phase-1 shed; if a live consumer exists, the shed is blocked and the param stays.
- **Q (multi-backtick inline code):** `TokenizerCorpusTests.inlineCodeMultiBacktick_currentBehavior` pins whatever the single-backtick regex produces for ``` ``a`b`` ```; if Phase 4 moves inline-code locating to the Apple AST (Apple's range includes the backticks by design), this becomes a logged divergence — add a ledger row at that point.
- **Q (rule-of-3 exact ranges):** the two rule-of-3 emphasis tests assert presence + first-token kind, not exact nested ranges, because the hand-rolled parser's exact split is what Phase 4's width-subtraction reconstruction must reproduce; tighten these to exact ranges only after reading the observed output, so the Phase-4 AST reconstruction has a precise target.

## Phase 3 — Single Cached Parse Spine (the #9 fix emerges)

All paths below are post-Phase-1: the package dir is `External/MarkdownPM`, the source dir `Sources/MarkdownPM`, the test dir `Tests/MarkdownPMTests`.

> **Inputs assumed already green.** This phase runs only after **Phase 1** (the package is renamed `MarkdownPM`; module imports are `import MarkdownPM`; all type renames have landed) and **Phase 2** (the characterization test net exists in the `MarkdownPM` test target, the parse-count probe is built, and the large-document fixture exists). Every `file:line` below is from the CodeMap (verified against source on 2026-06-02). Names like `NativeTextViewCoordinator`, `ParsedDocument`, `AppleASTSupplementalStyler`, `MarkdownDetection` are **internal** package symbols and keep their names through this phase — Phase 1 renamed only the front door (`MarkdownPMEditor` / `MarkdownPMConfiguration`) and the package/module.

> **Locked Decisions governing this phase:** LD-1, LD-4, LD-14, LD-15, LD-16, LD-17, LD-18, LD-19 (LD-20 — the dead `taskListRegex` — lands in Phase 6/Task 6.3, not here) (full text at the plan-wide ruling preamble; on any conflict they override the v2 Service doc).

### What "#9" actually is (so you fix the right thing)

The CodeMap correction is load-bearing: `ParsedDocument` does **not** hold an Apple `Document`. The regex tokenizer (`MarkdownTokenizer.parseTokens`) is already cache-deduped through `parsedDocument(for:)` and runs ~once per edit. **The redundant work is the Apple `Document(parsing:)` running uncached** — 1× per restyle with no folds (`AppleASTSupplementalStyler.swift:30`), 2× with folds active (also `+HeadingFolding.swift:160`). That is the stutter. The fix is: parse the Apple `Document` **once**, inside the same size-1 memo that already dedups the regex tokens, and hand the cached `Document` to both consumers.

### Task ordering

- **3.1** Extend `ParsedDocument` to carry the Apple `Document`; parse it once in `parsedDocument(for:)`. (Internal-only; no consumer change yet. Probe still reports 2 Apple parses — the cache field is populated but unused.)
- **3.2** Thread the cached `Document` into `AppleASTSupplementalStyler.styleAttributes` (drop its `:30` parse).
- **3.3** Thread the cached `Document` into `syncHeadingFolding` (drop its `:160` parse).
- **3.4** Remove the dead `isInsideInlineLatex` family.
- **3.5** Delete the slow `in:String` `isInside*` overloads; rewire the live callers (4 files / 7 call sites) to the cache.
- **3.6** Assert the parse-count drop, snapshot stability, and Instruments before/after in both fold + no-fold states.

Each task is its own green commit. Re-read this plan against what landed after every commit (HARD RULE: re-assess between green commits).

---

### Task 3.1 — Add the Apple `Document` to `ParsedDocument` and parse it once in the memo

**Goal.** `ParsedDocument` gains one stored field, `appleDocument: Markdown.Document`, populated inside `parsedDocument(for:)`. No consumer reads it yet — this task is pure plumbing and must compile + pass all Phase-2 snapshots unchanged. The parse-count probe will still report the same Apple-parse count (we have not yet removed the two downstream parses); this is expected and asserted at the end.

#### Step 3.1.a — Write the failing test (the field exists + is populated from the memo)

The Phase-2 net already has a coordinator-bootstrapping harness. Add a focused test that proves (1) the new field exists and (2) `parsedDocument(for:)` returns a `ParsedDocument` whose `appleDocument` reflects the input text.

Create `External/MarkdownPM/Tests/MarkdownPMTests/ParseSpineTests.swift`:

```swift
//
//  ParseSpineTests.swift
//  MarkdownPMTests
//
//  Phase 3: proves the single cached parse spine — the Apple Document is
//  parsed once inside parsedDocument(for:) and reused by every consumer.
//

import AppKit
import Markdown
import Testing

@testable import MarkdownPM

@MainActor
@Suite struct ParseSpineTests {

    /// Builds a coordinator wired to a live NSTextView, matching the
    /// Phase-2 harness. Returns (coordinator, textView).
    private func makeCoordinator(text: String) -> (NativeTextViewCoordinator, NSTextView) {
        var binding = text
        let coordinator = NativeTextViewCoordinator(
            text: Binding(get: { binding }, set: { binding = $0 }),
            fontName: "SF Pro Text",
            fontSize: 15,
            isWikiLinkActive: .constant(false),
            onLinkClick: nil,
            onInlineSelectionChange: nil
        )
        let textView = NSTextView()
        textView.string = text
        textView.delegate = coordinator
        coordinator.textView = textView
        return (coordinator, textView)
    }

    @Test("ParsedDocument carries the Apple Document parsed from the same text")
    func parsedDocumentCarriesAppleDocument() {
        let (coordinator, _) = makeCoordinator(text: "# Heading\n\n> quote\n")
        let parsed = coordinator.parsedDocument(for: "# Heading\n\n> quote\n")

        // The Apple Document must round-trip the same constructs the
        // supplemental styler walks. Heading + BlockQuote must be present.
        let kinds = parsed.appleDocument.children.map { String(describing: type(of: $0)) }
        #expect(kinds.contains("Heading"))
        #expect(kinds.contains("BlockQuote"))
    }

    @Test("Second call with identical text returns the same cached Document instance")
    func memoReturnsSameDocument() {
        let (coordinator, _) = makeCoordinator(text: "hello\n")
        let first = coordinator.parsedDocument(for: "hello\n")
        let second = coordinator.parsedDocument(for: "hello\n")
        // Document is a value type; identity isn't observable. Assert the
        // cache key held: the cached text equals the query text after the
        // first call, so the second call hit the memo (no re-parse).
        #expect(coordinator.cachedParsedText == "hello\n")
        #expect(first.tokens.count == second.tokens.count)
    }
}
```

**Run it (expect a COMPILE failure — `appleDocument` doesn't exist yet):**

```
swift test --package-path "External/MarkdownPM" --filter ParseSpineTests 2>&1 | tail -40
```

**Expected output:** compile error along the lines of `value of type 'ParsedDocument' has no member 'appleDocument'`. (Not a test failure — a build failure. That is the correct red state for an additive field.)

#### Step 3.1.b — Add the field to `ParsedDocument`

In `External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator.swift`, the struct is at lines 143-150. Add the import and the field.

At the top of the file (it currently imports `AppKit` + `SwiftUI` only — it does NOT import `Markdown`, per CodeMap WRONG-#2), add the Markdown import:

```swift
import AppKit
import SwiftUI
import Markdown
```

Then extend the struct (replace lines 143-150):

```swift
    struct ParsedDocument {
        let tokens: [MarkdownToken]
        let codeTokens: [MarkdownToken]
        let latexTokens: [MarkdownToken]
        let blockLatexTokens: [MarkdownToken]
        let wikiLinkTokens: [MarkdownToken]
        let imageEmbedTokens: [MarkdownToken]
        /// The Apple swift-markdown AST for the SAME `text` the regex
        /// tokens were parsed from. Parsed exactly once inside
        /// `parsedDocument(for:)` so the supplemental styler and the
        /// heading-fold sync reuse one parse instead of each running their
        /// own `Document(parsing:)` per keystroke (the #9 fix). Not
        /// `Sendable` — consumed only on the @MainActor coordinator.
        let appleDocument: Document
    }
```

> Do **not** add `: Sendable` to `ParsedDocument` (LD-4). `Markdown.Document` is not `Sendable`; the coordinator is `@MainActor`, so the value never leaves the actor. The package stays Swift 5.9 (relaxed concurrency), so this compiles cleanly inside the package wall regardless.

#### Step 3.1.c — Populate the field in the memo

In `External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift`, `parsedDocument(for:)` is at lines 146-191. The file currently imports `AppKit` only — add `Markdown`:

```swift
import AppKit
import Markdown
```

Parse the document once, right after the regex tokenize (`+Restyling.swift:151`), and pass it into the `ParsedDocument(...)` initializer (`:180-187`).

Replace line 151:

```swift
        let tokens = MarkdownTokenizer.parseTokens(in: text)
```

with:

```swift
        let tokens = MarkdownTokenizer.parseTokens(in: text)
        // Phase 3 — parse the Apple AST ONCE here, in the same size-1 memo
        // that already dedups the regex tokens. The supplemental styler and
        // syncHeadingFolding read this cached Document instead of each
        // running their own Document(parsing:) per keystroke.
        let appleDocument = AppleDocumentParseProbe.parse(text)
```

> `AppleDocumentParseProbe.parse(_:)` is the Phase-2 probe-wrapped `Document(parsing:)` — every counted parse site goes through it so the probe sees exactly the parses that run. After 3.2/3.3 delete the two downstream probe-wrapped parses, exactly **one** probe-wrapped parse remains (this one), and `count == 1` per edit holds honestly.

Then replace the `ParsedDocument(...)` constructor (`+Restyling.swift:180-187`):

```swift
        let parsed = ParsedDocument(
            tokens: tokens,
            codeTokens: codeTokens,
            latexTokens: latexTokens,
            blockLatexTokens: blockLatexTokens,
            wikiLinkTokens: wikiLinkTokens,
            imageEmbedTokens: imageEmbedTokens,
            appleDocument: appleDocument
        )
```

#### Step 3.1.d — Re-run; expect green

```
swift test --package-path "External/MarkdownPM" --filter ParseSpineTests 2>&1 | tail -40
```

**Expected output:** `Test Suite 'ParseSpineTests' passed`, `Executed 2 tests, with 0 failures`. Verify the **2** count is non-zero.

Then run the full Phase-2 snapshot net to prove nothing moved (the field is additive; nobody reads it yet):

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected output:** all Phase-2 suites pass; non-zero executed count; **the parse-count probe still reports 2 Apple parses on a folded edit / 1 on an unfolded edit** (we have not yet removed the downstream parses — that's 3.2/3.3). If the probe count already dropped here, something is wrong — stop and investigate (the field should be unused at this point).

#### Step 3.1.e — Commit

```
git add External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator.swift \
        External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift \
        External/MarkdownPM/Tests/MarkdownPMTests/ParseSpineTests.swift
```
Commit: `feat(markdownpm): cache Apple Document in ParsedDocument (#9 spine, step 1)`

---

### Task 3.2 — Feed the supplemental styler from the cache (drop the `:30` parse)

**Goal.** `AppleASTSupplementalStyler.styleAttributes` stops calling `Document(parsing: text)` (`AppleASTSupplementalStyler.swift:30`) and instead receives the already-parsed `Document` from the caller. Both composition sites (`+Restyling.swift:71` full-rebuild, `TextStylingService.swift:88` per-edit) pass the cached document.

**Why the signature must still take `text`/`nsText`.** CodeMap REFINED-row: `styleAttributes` needs the NSString for length, substring/pipe scanning, and the `LineOffsetIndex` UTF-8→UTF-16 conversion. The `Document` alone is insufficient. So the new signature **adds** a `document:` parameter; it does **not** remove `text`.

#### Step 3.2.a — Write the failing test (the styler accepts a pre-parsed Document and produces identical ranges)

Add to `ParseSpineTests.swift`:

```swift
    @Test("Supplemental styler from cached Document matches parse-from-text output")
    func supplementalStylerCachedMatchesUnparsed() {
        let text = "> quote line one\n> quote line two\n\n~~struck~~ word\n"
        let baseFont = NSFont.systemFont(ofSize: 15)
        let theme = MarkdownEditorTheme.default
        let document = Document(parsing: text)

        let fromCache = AppleASTSupplementalStyler.styleAttributes(
            text: text,
            document: document,
            baseFont: baseFont,
            theme: theme
        )

        // Smoke check only: the 4-arg form accepts a pre-parsed Document and
        // emits ranges (blockquote + strikethrough present). The byte-identical
        // regression gate is the Phase-2 StyledRangeCorpus snapshot net (re-run
        // in 3.2.d) — NOT a same-call self-compare, which would be tautological.
        #expect(!fromCache.isEmpty)
    }
```

**Run (expect COMPILE failure — `styleAttributes` has no `document:` parameter):**

```
swift test --package-path "External/MarkdownPM" --filter ParseSpineTests 2>&1 | tail -40
```

**Expected:** `extra argument 'document' in call` or `incorrect argument label`.

#### Step 3.2.b — Change the styler signature; drop its internal parse

In `External/MarkdownPM/Sources/MarkdownPM/Styling/AppleASTSupplementalStyler.swift`, the entry is at lines 25-41. Replace:

```swift
    static func styleAttributes(
        text: String,
        baseFont: NSFont,
        theme: MarkdownEditorTheme
    ) -> [StyledRange] {
        let document = Document(parsing: text)
        let nsText = text as NSString
        let lineIndex = LineOffsetIndex(text: text)
```

with:

```swift
    static func styleAttributes(
        text: String,
        document: Document,
        baseFont: NSFont,
        theme: MarkdownEditorTheme
    ) -> [StyledRange] {
        // Phase 3 — Document is parsed once in parsedDocument(for:) and
        // handed in. This pass no longer runs its own Document(parsing:)
        // (was the primary #9 culprit: a whole-document Apple parse on
        // every keystroke, uncached).
        let nsText = text as NSString
        let lineIndex = LineOffsetIndex(text: text)
```

> The `LineOffsetIndex(text: text)` build stays — it is a UTF-8↔UTF-16 line offset cache, not a Markdown parse. It is cheap and keep-verbatim (CodeMap Keep-Verbatim row). Do not try to cache it in Phase 3; it is not the `Document` parse.

**Same-commit: reconcile the 5 Phase-2 call-site functions that call the 3-arg `styleAttributes` directly** (7 invocations — `supplementalCoversBlockquoteNotHR` and `uncachedRepeatedParse_currentBehavior` each call it twice). The signature went from 3-arg (`text:baseFont:theme:`) to 4-arg (`text:document:baseFont:theme:`). **Three** add the `document: Document(parsing: <its text>)` argument; the **two** `ParseCountProbeTests` direct-call tests are **retired** (their direct-call premise dies — see below), not updated. By name, the five functions are:

- `StyledRangeCorpusTests.supplementalCoversBlockquoteNotHR`
- `StyledRangeCorpusTests.supplementalStrikethrough`
- `StyledRangeCorpusTests.supplementalMultibyte`
- `ParseCountProbeTests.supplementalParseCountIsOne`
- `ParseCountProbeTests.uncachedRepeatedParse_currentBehavior`

For the three `StyledRangeCorpusTests` cases: add the `document:` argument; their asserted range output is unchanged (LD-16 — byte-identical ranges).

**Retire/rewrite the two `ParseCountProbeTests` direct-call tests.** Their premise — call `styleAttributes` directly and count the parse the styler runs internally — dies the moment the parse moves out of the styler into the memo. Rewrite both as `textDidChange`-scoped assertions (drive a keystroke through the coordinator and read `AppleDocumentParseProbe.count`), which is the contract the spine actually guarantees:

- `supplementalParseCountIsOne` → assert that one `textDidChange` on an unfolded edit yields `AppleDocumentParseProbe.count == 1` (this is the same assertion 3.6.a pins; if 3.6 supersedes it, delete it here rather than duplicate).
- `uncachedRepeatedParse_currentBehavior` → its "uncached, re-parses every call" premise no longer exists; replace it with a `textDidChange`-scoped assertion that a second identical edit does not re-parse beyond the one memo parse, or delete it if 3.6.a covers the contract.

#### Step 3.2.c — Update both composition sites to pass the cached document

**Full-rebuild site** — `+Restyling.swift:71-75`. The function already calls `let tokens = parsedDocument(for: displayText).tokens` at `:48`. Capture the full parsed value once and reuse it. Replace `+Restyling.swift:48`:

```swift
        let tokens = parsedDocument(for: displayText).tokens
```

with:

```swift
        let parsed = parsedDocument(for: displayText)
        let tokens = parsed.tokens
```

Then replace the supplemental call (`+Restyling.swift:71-75`):

```swift
        let supplementalRanges = AppleASTSupplementalStyler.styleAttributes(
            text: displayText,
            document: parsed.appleDocument,
            baseFont: baseFont,
            theme: configuration.theme
        )
```

**Per-edit site** — `TextStylingService.swift:88` (and the merge at `:94`). Read that file first; `TextStylingService.restyle` does not own a coordinator, so the cached `Document` must be threaded in through `restyle`'s parameter list. The cleanest seam (it already takes `precomputedTokens`) is to add a `precomputedDocument: Document` parameter alongside it. Make the edit in two places:

1. In `TextStylingService.restyle`'s signature, add `precomputedDocument: Document` next to `precomputedTokens`, and change line 88's `AppleASTSupplementalStyler.styleAttributes(text: fullString, baseFont:..., theme:...)` call to pass `document: precomputedDocument`.
2. At the one caller, `restyleTextView` (`+Restyling.swift:119-132`), it already passes `precomputedTokens: tokens`. Source the `precomputedDocument:` from the cache **inside** `restyleTextView` — do **not** add a new `document:` parameter to it. Read `parsedDocument(for: textView.string).appleDocument` directly and pass that into `TextStylingService.restyle(precomputedDocument:)`. This is a guaranteed cache hit: `restyleTextView`'s callers (`restyleParagraphs` `+Restyling.swift:245`, `textDidChange` `+TextDelegate.swift:108`) already primed the same `parsedDocument(for:)` memo this keystroke, so the read dedups on text equality — it is not a second parse.

> **DRY guard:** the `precomputedDocument` `restyleTextView` passes down must come from the **same** `parsedDocument(for:)` memo, not a fresh `Document(parsing:)`. The memo dedups on text equality, so reading `.appleDocument` for the current `textView.string` is a cache read in the common path, never an extra parse.

#### Step 3.2.d — Re-run; expect green + probe drop on the unfolded path

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected:**
- All suites pass, non-zero executed count.
- The Phase-2 supplemental-styler snapshot suite is **unchanged** (LD-16: snapshots must not move).
- **The parse-count probe now reports 1 Apple parse on an UNFOLDED edit** (down from the prior count). On a FOLDED edit it still reports 2 (the `+HeadingFolding.swift:160` parse is removed in 3.3). Confirm the unfolded count dropped and the folded count did **not** yet.

If any supplemental snapshot moved, you changed behavior — revert and re-check that `LineOffsetIndex` and the visitor body are untouched (only the parse source changed).

#### Step 3.2.e — Commit

```
git add External/MarkdownPM/Sources/MarkdownPM/Styling/AppleASTSupplementalStyler.swift \
        External/MarkdownPM/Sources/MarkdownPM/Styling/TextStylingService.swift \
        External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+Restyling.swift \
        External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+TextDelegate.swift \
        External/MarkdownPM/Tests/MarkdownPMTests/ParseSpineTests.swift \
        External/MarkdownPM/Tests/MarkdownPMTests/StyledRangeCorpusTests.swift \
        External/MarkdownPM/Tests/MarkdownPMTests/ParseCountProbeTests.swift
```
Commit: `perf(markdownpm): supplemental styler reads cached Document (#9 spine, step 2)`

---

### Task 3.3 — Feed `syncHeadingFolding` from the cache (drop the `:160` parse)

**Goal.** `syncHeadingFolding` (`+HeadingFolding.swift:145-198`) stops calling `Markdown.Document(parsing: text)` at `:160` and reads the cached `Document` instead. The `foldedHeadings.isEmpty` fast-path (`:148-156`) is preserved exactly — when no folds are requested, we never touch the document at all.

**Subtlety to preserve.** The fast-path early-return means the folded-only case is the ONLY one that reaches the parse. So removing the `:160` parse only helps the folded case — but that is precisely the case the probe reports as "2 parses" today. After this task the probe must report **1** parse on a folded edit too.

#### Step 3.3.a — Write the failing test (folded edit produces identical foldedRanges with no second parse)

Add to `ParseSpineTests.swift`:

```swift
    @Test("syncHeadingFolding produces identical foldedRanges via the cached Document")
    func headingFoldUsesCachedDocument() {
        let text = "# A\nunder a\n\n# B\nunder b\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        guard let ts = textView.textStorage else {
            Issue.record("no text storage")
            return
        }
        // Prime the cache the way the restyle path does.
        _ = coordinator.parsedDocument(for: text)
        // Fold the first heading.
        coordinator.foldedHeadings = ["# A"]
        coordinator.syncHeadingFolding(in: ts, textView: textView)
        let ranges = coordinator.foldedRanges

        // The content under "# A" ("under a\n") must be the folded range.
        #expect(ranges.count == 1)
        #expect(ranges.first?.length ?? 0 > 0)
    }
```

**Run (expect green BEFORE the change — this is a characterization assert, then it must stay green AFTER).** This test pins the OUTPUT; the parse-count change is asserted separately by the probe in 3.6. Run it now to confirm it passes against the current (pre-change) code:

```
swift test --package-path "External/MarkdownPM" --filter ParseSpineTests 2>&1 | tail -40
```

**Expected:** passes (the current code already produces this). This is the safety net for the refactor that follows.

#### Step 3.3.b — Read the cached document in `syncHeadingFolding`

In `+HeadingFolding.swift`, replace lines 158-161:

```swift
        let text = ts.string
        let nsText = text as NSString
        let document = Markdown.Document(parsing: text)
        let headings = MarkdownDetection.foldableHeadings(in: document, nsText: nsText)
```

with:

```swift
        let text = ts.string
        let nsText = text as NSString
        // Phase 3 — reuse the Document cached in parsedDocument(for:)
        // instead of re-parsing here. This is the ONLY remaining Apple
        // parse on the folded-edit hot path; folded pages no longer
        // double-parse (tokens + AST) per keystroke. The fast-path above
        // already guarantees we never reach here when no folds are active.
        let document = parsedDocument(for: text).appleDocument
        let headings = MarkdownDetection.foldableHeadings(in: document, nsText: nsText)
```

> `foldableHeadings(in: document, nsText:)` is the **Document-taking** overload (`MarkdownDetection.swift:170+`). It is unchanged — it already accepts a pre-parsed `Document`. The separate `foldableHeadings(in: String)` overload at `:185` (which parses internally) is **not** touched in this phase (it is test-only / reconcile-path — not threaded by the spine).

> The `import Markdown` at the top of `+HeadingFolding.swift` (line 25) stays — `Document` and `foldableHeadings`'s `Document` parameter still need it; only the explicit `Document(parsing:)` call goes away.

#### Step 3.3.c — Re-run; expect green + probe drop on the folded path

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected:**
- All suites pass; non-zero executed count.
- The Phase-2 `foldableHeadings` / `reconcileFoldedHeadings` snapshots are **unchanged**, and `headingFoldUsesCachedDocument` still passes.
- **The parse-count probe now reports 1 Apple parse on a FOLDED edit** (down from 2). With 3.2, the unfolded path is also 1. The spine goal is met: `Document(parsing:)` runs **once per edit** regardless of fold state.

#### Step 3.3.d — Commit

```
git add External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+HeadingFolding.swift \
        External/MarkdownPM/Tests/MarkdownPMTests/ParseSpineTests.swift
```
Commit: `perf(markdownpm): syncHeadingFolding reads cached Document (#9 spine, step 3)`

---

### Task 3.4 — Remove the dead `isInsideInlineLatex` family

**Goal.** Delete `MarkdownDetection.isInsideInlineLatex` (all four overloads, `MarkdownDetection.swift:410-435`). CodeMap WRONG-#15: grep-confirmed dead outside the file (only internal wrappers reference each other). This is a no-behavior removal.

#### Step 3.4.a — Prove it's dead (grep gate, not a unit test)

A "dead-code removal" is verified by the absence of callers, then by the build. Run the grep gate first:

```
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora" && \
grep -rn "isInsideInlineLatex" External/MarkdownPM/Sources/ Pommora/Pommora/ Pommora/PommoraTests/
```

**Expected output:** matches **only** inside `MarkdownDetection.swift` (the four overloads at `:410-435`, each referencing each other). Zero matches in any other file, zero in the app, zero in tests. If anything else matches, STOP — it is not dead; report and do not delete.

#### Step 3.4.b — Delete the four overloads

In `MarkdownDetection.swift`, delete lines 410-435 (the entire `isInsideInlineLatex` block — the two `in: text` overloads, the `range: latexTokens:` overload, and the `location: latexTokens:` overload). Leave `isInsideLatex` (`:394-408`), `isInsideWikilink` (`:367-390`), and the enum's closing brace at `:436` intact.

#### Step 3.4.c — Build + full test net

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected:** builds clean (no "cannot find `isInsideInlineLatex`"); all suites pass; non-zero executed count; no snapshot moved (the symbol was unreachable, so nothing observable changed).

#### Step 3.4.d — Commit

```
git add External/MarkdownPM/Sources/MarkdownPM/Parser/MarkdownDetection.swift
```
Commit: `refactor(markdownpm): remove dead isInsideInlineLatex family`

---

### Task 3.5 — Delete the slow `in:String` `isInside*` overloads; rewire the live callers (4 files / 7 call sites) to the cache

**Goal.** Remove the re-parsing static overloads `MarkdownDetection.isInsideCodeBlock(range:in:)` / `(location:in:)` (`:329-338`) and `isInsideLatex(location:in:)` (`:394-398`). Every live caller must instead go through the coordinator's cached token query. **`isInsideWikilink` stays** (it's a pure line scan, not a token re-parse — LD-18).

The four live caller sites and their rewiring:

| Caller | Current (slow) | Rewire to |
|---|---|---|
| `SpellingPolicy:20` | `?? MarkdownDetection.isInsideCodeBlock(range:in:)` fallback | `?? false` — see note below |
| `SpellingPolicy:27` | `?? MarkdownDetection.isInsideLatex(location:in:)` fallback | `?? false` |
| `+Services:156` | `else { ... isInsideCodeBlock(location:in:) }` | use the coordinator's cached `parsedDocument(for:)` |
| `+Services:162` | `else { ... isInsideLatex(location:in:) }` | use the coordinator's cached `parsedDocument(for:)` |
| `MarkdownListHandler:381` | `MarkdownDetection.isInsideCodeBlock(location:in:)` | coordinator cache via the NativeTextView's delegate |
| `MarkdownListHandler:416` | `MarkdownDetection.isInsideCodeBlock(location:in:)` | coordinator cache via the NativeTextView's delegate |
| `MarkdownInputHandler:78` | raw `MarkdownTokenizer.parseTokens` to build `resolvedCodeTokens` | coordinator cache via the NativeTextView's delegate |

**Design note (the rewire shape).** All these sites have an `NSTextView` in hand whose `delegate` is the `NativeTextViewCoordinator`. The coordinator already exposes cache-backed wrappers: `isInsideCode(range:in:)` (`+Services.swift:188`) and `isInsideLatex(location:in:)` (`:193`). Route every site to those wrappers; when there is no coordinator (theoretically only in a non-bridged NSTextView, which does not occur in Pommora), fall back to `false` (the constructs being guarded — auto-pair, dash transforms, spell suppression — degrade safely to "not inside code/latex" rather than re-parsing). This removes the last re-parse paths and keeps one source of truth (the coordinator cache).

> The Phase-2 input-transform harness now sets `tv.delegate = coordinator`, so the `coordinator?.…` lookups below resolve a real coordinator in tests — the `?? false` fallback never fires there. The input-transform goldens are therefore unchanged: the rewired sites return the same in-code/in-latex decision the slow re-parse did, with no `?? false` behavior flip.

#### Step 3.5.a — Add a small coordinator helper so callers without a `codeTokens` array still hit the cache

`SpellingPolicy` and the `+Services` fallback already call `coordinator?.isInsideCode(...)` / `isInsideLatex(...)`. The ONLY reason the slow static fallback existed was the `?? MarkdownDetection.isInside…(…, in:)` arm. Replace that arm with `?? false`. No new helper needed there.

For `MarkdownListHandler` and `MarkdownInputHandler` (static functions with a `textView` but no direct coordinator reference today), reach the coordinator through the delegate. Add — once — a tiny private resolver at the top of each file's relevant scope:

In `MarkdownListHandler.swift`, before the first slow call (the file already references `textView as? NativeTextView` elsewhere), introduce a local:

```swift
        // Phase 3 — route code-block detection through the coordinator's
        // cached parse instead of re-tokenizing the whole string here.
        let coordinator = textView.delegate as? NativeTextViewCoordinator
```

Then replace `MarkdownListHandler:380-382`:

```swift
                    let inCode = textView.string.contains("`")
                        ? MarkdownDetection.isInsideCodeBlock(location: insertLoc, in: textView.string)
                        : false
```

with:

```swift
                    let inCode = textView.string.contains("`")
                        ? (coordinator?.isInsideCode(
                            range: NSRange(location: insertLoc, length: 0),
                            in: textView.string) ?? false)
                        : false
```

and `MarkdownListHandler:414-417`:

```swift
        let isInCodeBlock =
            textView.string.contains("`")
            ? MarkdownDetection.isInsideCodeBlock(location: affectedCharRange.location, in: textView.string)
            : false
```

with:

```swift
        let isInCodeBlock =
            textView.string.contains("`")
            ? (coordinator?.isInsideCode(
                range: NSRange(location: affectedCharRange.location, length: 0),
                in: textView.string) ?? false)
            : false
```

> The `string.contains("`")` cheap prefilter stays (CodeMap Keep-Verbatim row: behavior-neutral perf guard). `isInsideCode(range:in:)` takes a range; a zero-length range at the location reproduces the `location:` overload's containment semantics (`isInsideCodeBlock(location:codeTokens:)` is just the range form with length 0 — `MarkdownDetection.swift:355`).

In `MarkdownInputHandler.swift`, the slow path is the lazy `parseTokens` at `:78`. Replace `:74-84`:

```swift
        let resolvedCodeTokens: [MarkdownToken]
        if let codeTokens {
            resolvedCodeTokens = codeTokens
        } else {
            resolvedCodeTokens = MarkdownTokenizer.parseTokens(in: textView.string)
                .filter { $0.kind == .codeBlock || $0.kind == .inlineCode }
        }
        if MarkdownDetection.isInsideCodeBlock(
            range: affectedCharRange,
            codeTokens: resolvedCodeTokens
        ) {
            return false
        }
```

with:

```swift
        // Phase 3 — prefer caller-supplied tokens; otherwise hit the
        // coordinator's cached parse rather than re-tokenizing the string.
        let inCode: Bool
        if let codeTokens {
            inCode = MarkdownDetection.isInsideCodeBlock(
                range: affectedCharRange, codeTokens: codeTokens)
        } else if let coordinator = textView.delegate as? NativeTextViewCoordinator {
            inCode = coordinator.isInsideCode(range: affectedCharRange, in: textView.string)
        } else {
            inCode = false
        }
        if inCode { return false }
```

#### Step 3.5.b — Rewrite the `+Services` autocorrect fallback arms to the cache

In `+Services.swift`, `updateAutocorrectSettings` (`:144-186`). The `if let codeTokens` / `if let latexTokens` arms stay (they're already the fast precomputed path). Replace the two `else` arms (`:156` and `:162`) so they hit the cache instead of the slow static overload:

`:155-157`:

```swift
        } else {
            inCode = MarkdownDetection.isInsideCodeBlock(location: caretLocation, in: textView.string)
        }
```

→

```swift
        } else {
            inCode = isInsideCode(
                range: NSRange(location: caretLocation, length: 0),
                in: textView.string)
        }
```

`:161-163`:

```swift
        } else {
            inLatex = MarkdownDetection.isInsideLatex(location: caretLocation, in: textView.string)
        }
```

→

```swift
        } else {
            inLatex = isInsideLatex(location: caretLocation, in: textView.string)
        }
```

> `isInsideCode` / `isInsideLatex` here are the coordinator's own cache-backed methods (`self.` implied, defined at `+Services.swift:188`/`:193`). In practice `updateAutocorrectSettings`'s caller (`+TextDelegate.swift:125`) always passes `codeTokens`/`latexTokens`, so the `else` arms are cold — but routing them through the cache removes the last reference to the slow static overload so it can be deleted.

#### Step 3.5.c — Replace the `?? fallback` arms in `SpellingPolicy`

In `NativeTextView+SpellingPolicy.swift`, replace `:19-20`:

```swift
                let inCode = coordinator?.isInsideCode(range: charRange, in: self.string)
                    ?? MarkdownDetection.isInsideCodeBlock(range: charRange, in: self.string)
```

→

```swift
                let inCode = coordinator?.isInsideCode(range: charRange, in: self.string) ?? false
```

and `:26-27`:

```swift
                let inLatex = coordinator?.isInsideLatex(location: charRange.location, in: self.string)
                    ?? MarkdownDetection.isInsideLatex(location: charRange.location, in: self.string)
```

→

```swift
                let inLatex = coordinator?.isInsideLatex(location: charRange.location, in: self.string) ?? false
```

#### Step 3.5.d — Delete the now-unreferenced slow static overloads

In `MarkdownDetection.swift`, delete:
- `isInsideCodeBlock(range:in:)` (`:329-334`) and `isInsideCodeBlock(location:in:)` (`:336-338`).
- `isInsideLatex(location:in:)` (`:394-398`).

**Keep:**
- The fast `isInsideCodeBlock(range:codeTokens:)` (`:341-353`) and `isInsideCodeBlock(location:codeTokens:)` (`:355-357`) — these are what the coordinator wrappers + precomputed-token callers use.
- The fast `isInsideLatex(location:latexTokens:)` (`:400-408`).
- `isInsideWikilink(location:in:)` (`:367-390`) — LD-18.

#### Step 3.5.e — Grep gate + full test net

Confirm the slow overloads have no remaining callers:

```
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora" && \
grep -rn "isInsideCodeBlock(range:.*in:\|isInsideCodeBlock(location:.*in:\|isInsideLatex(location:.*in:" \
  External/MarkdownPM/Sources/ Pommora/Pommora/ Pommora/PommoraTests/ | grep -v "codeTokens:\|latexTokens:"
```

**Expected output:** empty (no caller passes a bare `in:` String to those names anymore; only the `codeTokens:`/`latexTokens:` fast forms and the coordinator wrappers remain).

Then:

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected:** builds clean; all suites pass; non-zero executed count; **the input-transform snapshots (the 9 transforms), the auto-pair tests, and the spell-suppression tests are unchanged** (LD-16 — these guards now resolve via the cache but must produce identical decisions). If any input-transform snapshot moved, the cache-routed `isInsideCode` returned a different answer than the slow re-parse for some edge case — investigate (most likely a zero-length-range vs location containment-boundary difference at `MarkdownDetection.swift:346-350` `<= end` vs `< end`; the range form with length 0 takes the `range.length == 0` branch, which uses `<= end`, matching the old `location:` overload exactly, so this should not happen — but verify against the snapshot, do not assume).

#### Step 3.5.f — Commit

```
git add External/MarkdownPM/Sources/MarkdownPM/Parser/MarkdownDetection.swift \
        External/MarkdownPM/Sources/MarkdownPM/TextView/NativeTextView/NativeTextView+SpellingPolicy.swift \
        External/MarkdownPM/Sources/MarkdownPM/TextView/Coordinator/NativeTextViewCoordinator+Services.swift \
        External/MarkdownPM/Sources/MarkdownPM/Input/MarkdownListHandler.swift \
        External/MarkdownPM/Sources/MarkdownPM/Input/MarkdownInputHandler.swift
```
Commit: `refactor(markdownpm): route isInside* through the cached parse; drop slow overloads`

---

### Task 3.6 — Assert the parse-count drop, snapshot stability, and Instruments before/after (fold + no-fold)

**Goal.** Lock the #9 win with two automated assertions (parse count == 1 per edit; snapshots unchanged) and one optional Instruments confirmation (CPU + hitch in both fold states). This is the gate that converts "should be faster" into evidence.

#### Step 3.6.a — Parse-count assertion via the Phase-2 probe

The Phase-2 probe counts `Document(parsing:)` invocations per `textDidChange`. Add the assertion tests that pin the post-spine counts. (The probe mechanism — `AppleDocumentParseProbe`, a debug-only counter the package increments at each probe-wrapped `Document(parsing:)` call site, reset per edit — was built in Phase 2; here we only assert against it.)

Add to `ParseSpineTests.swift`:

```swift
    @Test("Unfolded edit triggers exactly one Apple Document parse")
    func unfoldedEditParsesOnce() {
        let text = "# A\n\n> quote\n\nbody text here\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        AppleDocumentParseProbe.reset()
        // Simulate one keystroke at end of doc.
        let editRange = NSRange(location: (text as NSString).length, length: 0)
        coordinator.textView(textView, shouldChangeTextIn: editRange, replacementString: "x")
        textView.string = text + "x"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(AppleDocumentParseProbe.count == 1)
    }

    @Test("Folded edit triggers exactly one Apple Document parse")
    func foldedEditParsesOnce() {
        let text = "# A\nunder a\n\n# B\nunder b\n"
        let (coordinator, textView) = makeCoordinator(text: text)
        coordinator.foldedHeadings = ["# A"]
        if let ts = textView.textStorage {
            coordinator.syncHeadingFolding(in: ts, textView: textView)
        }
        AppleDocumentParseProbe.reset()
        let editRange = NSRange(location: (text as NSString).length, length: 0)
        coordinator.textView(textView, shouldChangeTextIn: editRange, replacementString: "y")
        textView.string = text + "y"
        coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: textView))
        #expect(AppleDocumentParseProbe.count == 1)
    }
```

> `AppleDocumentParseProbe` is the Phase-2 probe type. The assertion is the contract: **1 Apple parse per edit, fold or no fold.** Before Phase 3 this would be 1 (unfolded) / 2 (folded); the regression bar is now flat at 1.

**Run:**

```
swift test --package-path "External/MarkdownPM" --filter ParseSpineTests 2>&1 | tail -40
```

**Expected:** all `ParseSpineTests` pass; **non-zero executed count** (should be ~7 tests in this suite now). Both parse-count assertions read `1`.

> **Open decision recorded (do not resolve here):** the prompt's "assert Document(parsing:) drops to once-per-edit" is satisfied for the two coordinator-owned sites. The renderer's per-fragment parse (`MarkdownTextLayoutFragment.swift:453`) is **deliberately excluded** (LD-15) and is NOT counted by this edit-scoped probe (it fires per layout pass, not per `textDidChange`). If a future session wants the renderer folded into the spine, that is CodeMap Open Question #13 / Phase 3 row "de-dupe per-fragment renderer detection" — it carries the attribute-inheritance-leak risk and is explicitly out of scope here.

#### Step 3.6.b — Full snapshot net (the byte-identical gate)

```
swift test --package-path "External/MarkdownPM" 2>&1 | tail -40
```

**Expected:** every Phase-2 characterization suite passes; non-zero executed count. This is the formal statement of LD-16 — the spine changed parse *count*, never parse *output*.

#### Step 3.6.c — Instruments confirmation (optional)

The automated probe (3.6.a) is the binding gate; this is an optional runtime confirmation. If you want a profile, run a single **Time Profiler** capture on the Phase-2 large-document fixture in the folded state, typing a sustained burst in the middle of the doc:

```
xcrun xctrace record \
  --template 'Time Profiler' \
  --launch -- /path/to/Pommora.app \
  --output ~/Desktop/markdownpm-p3-folded.trace
```

**Expected:** `Markdown.Document.init(parsing:)` (cmark-gfm) self-time per keystroke drops versus the pre-Phase-3 build (folded path went 2 parses → 1). The `swiftui-expert-skill` has guided Instruments steps if you want them; do not adjust the on-screen frame from initial load while recording (global rule — Nathan needs to see his own screen).

#### Step 3.6.d — Commit the assertion tests

```
git add External/MarkdownPM/Tests/MarkdownPMTests/ParseSpineTests.swift
```
Commit: `test(markdownpm): assert one Apple parse per edit in both fold states (#9)`

---

### Phase 3 exit gate

All of the following must hold before Phase 4 is dispatched:

- [ ] `ParsedDocument` carries `appleDocument`; it is parsed exactly once, inside `parsedDocument(for:)`. `ParsedDocument` is **not** `Sendable`.
- [ ] `AppleASTSupplementalStyler.styleAttributes` and `syncHeadingFolding` both read the cached `Document`; neither calls `Document(parsing:)`.
- [ ] The parse-count probe reads **1 Apple parse per edit** in both fold and no-fold states (was 1 / 2).
- [ ] The dead `isInsideInlineLatex` family is gone; `isInsideWikilink` remains; the slow `in:String` `isInside*` overloads are gone and all 4 live callers route through the coordinator's cache.
- [ ] Every Phase-2 characterization snapshot is **byte-identical** (supplemental ranges, `foldedRanges`, the 9 input transforms, spell suppression, auto-pair).
- [ ] Instruments confirmation captured (optional); per-keystroke Apple-parse cost dropped; no new hangs.
- [ ] The 6 out-of-scope `Document(parsing:)` sites are untouched (renderer per-fragment `:453`, `MarkdownDetection.swift:77/:160/:186`, `MarkdownListHandler.swift:135`, `MarkdownPlainText.swift:21`).

### Open decisions surfaced by Phase 3 (do NOT resolve here — they belong to later phases / the Wiki-Link session)

1. **Renderer per-fragment parse** (`MarkdownTextLayoutFragment.swift:453`) stays uncached. Folding it into the spine (CodeMap Open Question #13) risks reintroducing the `.pommoraThematicBreak` attribute-inheritance leak — deferred.
2. **`WikiLinkService` regex scans** are NOT routed through the spine in this phase (LD-1 — Wiki-Link session owns it; CodeMap Phase-3 "WikiLinkService" row explicitly deferred).
3. **`MarkdownDetection.foldableHeadings(in: String)`** (the parsing overload, `:185`) and the standalone in-isolation parses (`:77`, `:160` in Detection — the setext-suppression trick) are intentionally left re-parsing — they parse a single isolated line/paragraph, not the whole document, and the isolation is load-bearing.
4. **`MarkdownInputHandler` / `MarkdownListHandler` reaching the coordinator via `textView.delegate as? NativeTextViewCoordinator`** is the chosen seam for cache access from static input-handler functions. If Phase 6's `performEdit` pure-function refactor (CodeMap Open Question #25) lands, revisit whether these should take the cache as an explicit parameter instead of pulling it off the delegate.

## Phase 4 — Inline Locating on the Apple AST

**Intent.** Move the *locating* of three constructs Apple parses correctly — emphasis, inline code, links — onto the cached `Document` from the Phase-3 spine; delete the 173-line hand-rolled asterisk-only emphasis parser; intentionally adopt underscore emphasis and unify the two divergent heading detectors, both logged in the divergence ledger and signed off. Everything Apple gets absent or wrong (wikilinks, embeds, the `$…$` math/currency heuristic, bullets/list/empty-`[]` checkbox, the Setext-suppression trick) **stays regex**. The AST locates; the owned styler still decides caret-aware hide/reveal (styling ownership is Phase 5; this phase only changes *where ranges come from*).

**Hard cross-phase dependencies.**
- **GATE: Phase 2 must be fully green before any Phase-4 task touches behavior.** The adversarial emphasis corpus (rule-of-3 `**foo*bar**baz*` / `*foo**bar*baz**`, cross-line `*foo\nbar*`, punctuation-flanking, intra-word `a*b*c`, **asterisk-only/no-underscore pinned as the OLD behavior**, no-code-overlap-dedup) is the safety net that makes the emphasis deletion safe. No corpus → no deletion (Service doc Risk; Q2).
- **GATE: Phase 3 must have landed the cached Apple `Document`** (extended `ParsedDocument`, `NativeTextViewCoordinator.swift:143-150`) — Phase 4 consumes it; it does not re-parse.
- This phase precedes Phase 5: emphasis tokens are *relocated*, not dropped, so the Phase-5 styler merge inherits a working `.italic/.bold/.boldItalic` supply.

### Task 4.1 — Emphasis marker-reconstruction by width-subtraction (own tested sub-task)

**Intent.** Apple's `Emphasis`/`Strong` nodes give a whole-construct `SourceRange` but expose **no `*`/`_` delimiter sub-ranges**. The legacy parser produced `range` + `contentRange` + `markerRanges`; `styleEmphasis` (`MarkdownStyler+TextStyling.swift:50-99`) consumes `contentRange` to build its per-char `UInt8` trait array, and the styler hides markers via the `markerRanges`. Reconstruct the two hide-ranges by **delimiter-width subtraction**: `*`/`_` = 1, `**`/`__` = 2, `***`/`___` = 3, derived from the whole-construct NSRange minus the inner content. Build this as a pure helper (`emphasisMarkerRanges(for node:in nsText:) -> (open: NSRange, close: NSRange, content: NSRange)`) with its own unit suite **before** wiring it into the walk.

**Gate.** Helper's derived `(open, close, content)` triples must match the legacy parser's `markerRanges`/`contentRange` byte-for-byte on the full Phase-2 asterisk corpus (the corpus already pins legacy output). Cross-line and rule-of-3 nesting are the adversarial cases — assert these explicitly.

**Open decisions recorded.**
- **D4.1-a (verify-first):** confirm Apple's `Emphasis`/`Strong` `SourceRange` is inclusive of the delimiters (width-subtraction assumes the node range spans `*content*`). If Apple's range is content-only on some construct, width-subtraction flips to width-*addition* — pin the actual behavior with a probe test against swift-markdown 0.8.0 before writing the helper.
- **D4.1-b:** nested `***bold italic***` — decide whether reconstruction walks the outer `Strong`(`Emphasis(...)`) nesting Apple produces, or flattens. The per-char trait OR-merge in `styleEmphasis:55-97` already combines overlapping runs, so flattening to two tokens (bold-over-range + italic-over-range) is the lower-risk target; record the chosen shape.

### Task 4.2 — Adopt underscore emphasis (intentional divergence, ledger + sign-off)

**Intent.** The legacy parser matches `0x2A` (`*`) only — no `0x5F` (`_`) (CodeMap WRONG-claim #11, confirmed `MarkdownTokenizer+Emphasis.swift:62`). Apple's AST + CommonMark + Obsidian all treat `_italic_` / `__bold__` as emphasis. Adopting the AST therefore **newly makes underscore emphasis work**. This is a deliberate behavior change, not a regression.

**Gate.** Phase 2 must already have a test asserting the **old** asterisk-only behavior (underscore renders as literal text). Task 4.2 *flips* that test to the new behavior and moves the old assertion into the divergence ledger as a signed-off intentional change. Do not flip silently — the ledger entry names: construct (underscore emphasis), old behavior (literal), new behavior (emphasis), authority (Nathan ruling), corpus cases covering `_i_` / `__b__` / `___bi___` / intra-word `a_b_c` (CommonMark suppresses intra-word underscore — pin that the AST agrees) / underscore-inside-code (suppressed, see D4.4).

**Open decision recorded.**
- **D4.2-a:** intra-word underscore (`snake_case_word`) must NOT emphasize per CommonMark flanking rules. Confirm Apple's AST suppresses it (it should) and pin it; this is the single highest-value adversarial case because filenames and code identifiers are full of underscores.

### Task 4.3 — Relocate inline-code + link locating to the AST

**Intent.** Inline code: Apple's `InlineCode` range **includes the backticks by design** — relocate the locating off the regex `inlineCodeRegex` (`MarkdownTokenizer.swift:35`) onto the AST node, deriving the marker (backtick) hide-ranges by the same width-subtraction helper family as 4.1 (multi-backtick fences ``` `` code `` ``` must be handled — width is the backtick run length, with CommonMark's leading/trailing single-space trim). Links: take `.destination` from Apple's `Link` node; **inline-style links only** (Service doc decision — reference/shortcut/autolink are non-goals).

**Gate.** Phase-2 inline-code suite (multi-backtick + space-trim) and link suite (inline-style; reference/shortcut/autolink **flagged** as out-of-scope, asserted as currently-rendered behavior so the divergence is explicit) both green before and after the relocation.

**Open decisions recorded.**
- **D4.3-a (divergence):** the legacy regex tokenizer appends emphasis FIRST with **no code-overlap dedup** (CodeMap WRONG-claim #12) — `*emph*` inside `` `inline code` `` still tokenized as emphasis. Apple's AST will NOT emit emphasis inside `InlineCode`. This is an intentional improvement → ledger entry, sign-off, corpus case (`` `a *b* c` `` renders the asterisks literally post-Phase-4).
- **D4.3-b:** autolink (`<https://…>`) and bare-URL behavior — record current rendered state in the corpus, mark as preserved-as-is (no new support), so a later session can decide.

### Task 4.4 — Decide the fate of `.italic/.bold/.boldItalic` enum cases + code/latex suppression

**Intent.** These three `MarkdownTokenKind` cases (`MarkdownToken.swift:19-21`) are emitted *only* by the deleted parser. Re-emit them from the AST walk (Service doc: tokens are **relocated**, formerly `+Emphasis.swift:138`) rather than removing the cases — removing forces a module-wide exhaustive-switch sweep (CodeMap Phase-4 table, HIGH risk). Keeping the cases and re-feeding them from the AST is the lower-risk path and preserves `styleEmphasis`'s consumer unchanged.

**Open decision recorded.**
- **D4.4-a:** Current parser does NOT suppress emphasis inside code blocks / inline code / LaTeX; the AST *will* for code (4.3-a). For **LaTeX** (`$x*y*$`), Apple has no math node, so the AST won't see `$…$` at all and *will* emit emphasis for `*y*` inside it. Decide whether the relocated emphasis walk must additionally consult the regex LaTeX tokens to suppress emphasis inside `$…$` (preserves "math content isn't emphasized") or accept the divergence. Record either way; this is a real edge the AST can't resolve alone.

### Task 4.5 — Unify the two divergent heading detectors (intentional DRY cleanup, ledger + sign-off)

**Intent.** Three heading detectors disagree today: the tokenizer `headingRegex` `^\s*(#{1,6}) +(.*)$` (**requires a space**, `MarkdownTokenizer.swift:23-26`), `MarkdownDetection.isHeadingLine` `^#{1,6}([ \t]|$)` (**space/tab/EOL**, `MarkdownDetection.swift:144-160`), plus the Apple AST walk at `:160`. They disagree on bare `#`, tab-separated `#\tFoo`, and trailing-space-only `# `. Nathan ruling: collapse to **ONE** detector using CommonMark semantics (space/tab/EOL — the `isHeadingLine` form) so styler marker-sizing and the fold path agree. The fold path keeps using Apple `Heading.level + range` (already correct); the marker-reveal/sizing path stays regex (Apple exposes no `#` delimiter sub-ranges — reconstruct by width-subtraction 1..6, same helper family as 4.1).

**Gate.** Phase 2 must pin BOTH detectors' current divergent output on the heading corpus (`#`/bare-`#`/tab-sep/`### Foo ###`/trailing-space, on both detector paths). Task 4.5 unifies behind the net, flips the now-changed cases, and logs the divergence (cause: two detectors drifted; fix: one CommonMark rule; authority: Nathan pre-emptive-DRY ruling). Also hoist the duplicated `[N]` fold-key ordinal computation (`+HeadingFolding.swift:65-82` mirrors `MarkdownDetection.swift:264-274`) to a single source so renderer-key and hover-hit-test can't desync — this is byte-sensitive (fold membership), so assert key equality across both call sites on a duplicate-heading corpus.

**Open decision recorded.**
- **D4.5-a:** `foldableHeadings` "top-level headings only" restriction (`MarkdownDetection.swift:170-172`) — confirm it survives the unification (CodeMap Open Q30). If nested-heading folding is a future expansion, the unified detector must not bake in the top-level assumption in a way that's expensive to relax. Record: preserve top-level-only for v1, leave a seam.

### Task 4.6 — Delete `MarkdownTokenizer+Emphasis.swift` behind the green corpus

**Intent.** Remove the whole 173-LOC file (`:12-173`) and its single call (`MarkdownTokenizer.swift:58`). This is the terminal Phase-4 task — it lands **only** after 4.1–4.4 are green and the adversarial corpus (now including the flipped underscore + code-suppression cases) is green.

**Gate.** Full Phase-2 emphasis corpus green with the AST-emitted tokens; divergence ledger entries for underscore-adoption (4.2) and code-overlap-dedup (4.3-a) signed off.

**Commit:** `refactor(markdownpm): inline locating (emphasis/code/links) on Apple AST; emphasis parser deleted behind corpus`

---

## Phase 5 — One Owned Styler + `MarkdownPMTheme`

**Intent.** Collapse the **two** styler-composition sites into a single owned `MarkdownPMStyler` that walks the cached AST once, and merge the color theme + the config value sub-structs into one navigable `MarkdownPMTheme` file. This is the **single highest-risk phase** (LD-21) — stage it, and preserve the sole-writer invariant (HR owned only by `syncHRVisibility`; the styler emits nothing for ThematicBreak; blockquote stays always-collapsed).

**Hard cross-phase dependencies.**
- **GATE: Phases 2, 3, 4 green.** Phase 5 needs the cached spine (3) feeding one parse, the AST-located inline constructs (4) so the merged styler has one range source, and the full styled-attribute corpus (2, Suite B at varied caret positions) as the regression net.
- The two merge sites are a **CodeMap correction** — collapsing only one leaves the other to drift (WRONG-claim #7).

### Task 5.1 — Stage the merge: collapse both composition sites into `MarkdownPMStyler`

**Intent.** Collapse `primaryStyledRanges + supplementalRanges` from BOTH:
- `TextStylingService.swift:94` (per-edit, paragraph-scoped, with spelling pre-pass, apply-clipped via `NSIntersectionRange` at `:116`), and
- `NativeTextViewCoordinator+Restyling.swift:76` (full-rebuild / initial-load, whole-range, NO spelling pre-pass, hand-rolled apply loop)

into one owned `MarkdownPMStyler` that walks the cached AST once. **Stage it (LD-21):** land safe non-caret constructs first (headings, emphasis, links, code, strikethrough, table), caret-aware ones last (the active-token-aware marker hide/reveal). Each stage is its own green commit.

**Sole-writer preservation (load-bearing).**
- HR/ThematicBreak appearance stays owned solely by `syncHRVisibility`; the merged styler emits **NOTHING** for ThematicBreak (`AppleASTSupplementalStyler.visitThematicBreak:248-262` no-op + `MarkdownStyler.swift:179-183` both emit nothing — Markdown.md §3.3, §6.2; CodeMap WRONG-claim #8). Re-introducing any HR-specific persisted attribute revives the "duplicate HR on every Enter" regression (`MarkdownTextLayoutFragment.swift:21-28` tombstone).
- Strikethrough is **inline**, not block — fold it into the unified inline visitor (it's already AST-located, `AppleASTSupplementalStyler.swift:163-177`).
- Blockquote stays **always-collapsed** — do NOT add caret-aware reveal (Markdown.md §9.10, locked; not asked for).

**Two apply mechanisms.** The rebuild path applies UNSCOPED over the whole doc (initial-load completeness); the per-edit path applies paragraph-clipped. These differ at paragraph boundaries (CodeMap WRONG-claim #6). Unifying into one `apply(_:to:scopedTo:)` (Service doc DRY) must preserve: (a) initial-load whole-doc completeness, (b) per-edit clipping, (c) the spelling pre-pass that the rebuild path currently omits — see D5.1-b.

**Gate.** Suite-B styled-attribute golden (code / inline-code / checkbox active+inactive / incomplete-bracket / shrink-inactive-markers) holds at every caret position on both the scoped and unscoped paths; primary-before-supplemental order (last-writer-wins-per-key) preserved; ThematicBreak emits zero ranges asserted directly.

**Open decisions recorded.**
- **D5.1-a:** BlockQuote/Table markers collapse *unconditionally* today (gated only by trailing space/tab, NOT caret — CodeMap REFINED). Authoritative ruling: **preserve always-collapsed for blockquote** (locked). Table markers — **Nathan ruling (2026-06-02): keep the engine's existing table rendering, but keep the table styling REFINABLE/extensible** (proper tables are a stated future focus per `Features/Pages.md` + `Features/PageEditor.md`) — do not rigidly lock the table path; structure it so the future tables work refines it cleanly.
- **D5.1-b:** the full-rebuild path omits the spelling-disabled pre-pass (`TextStylingService.swift:96-108` has it; `+Restyling.swift` does not). CodeMap Open Q24 flags this as possibly a latent bug (spell-underlines on code/latex until first edit). Decide: unify so both paths run the pre-pass, or preserve the asymmetry. Recommend unify (one apply path) — but confirm it's not load-bearing for initial-load timing.
- **D5.1-c:** centralize the ~11 scattered `activeTokenIndices.contains` caret reads into one accessor + a `markerAttributes(active:)` factory (Service doc DRY), **preserving the two caret carve-outs**: math-overlap activation and the checkbox end-of-syntax reveal (`MarkdownStyler.swift:540-545`). These carve-outs are in the Keep-Verbatim register — the DRY refactor reads them through the new accessor but does not change their logic.

### Task 5.2 — Merge `MarkdownEditorTheme` + config value sub-structs into one `MarkdownPMTheme` file

**Intent.** One navigable file with MARK sections, merging:
- `MarkdownEditorTheme` — 12 color slots (8 system + 4 fixed literals: `headingMarker=.gray`, `latexLightModeText=.black`, `latexDarkModeText=.white`, plus the CodeMap-confirmed 4th; `MarkdownEditorTheme.swift:86,92,93`), and
- `MarkdownEditorConfiguration`'s 16 inline value sub-structs (top-level config has 18 stored props = theme + services + 16 sub-structs; CodeMap REFINED).

Keep system colors via named slots (brand palette deferred to v0.4.0; Service doc D16 dark-mode-adaptive). Heading multipliers: apply the **new scale** `[H1 2.0, H2 1.75, H3 1.5, H4 1.25, H5 1.15, H6 TBD]` (Nathan 2026-06-02; supersedes shipped `[2.0, 1.5, 1.17, 1.0, 0.83, 0.67]`; no heading below body). Intentional change vs the Phase-2-pinned current values (divergence D-HEAD-2); scale heading padding/spacing proportionally. **H6 pending confirm.** The `HeadingStyle` sub-struct is the **only** one with behavior (clamp+lookup helpers, `MarkdownEditorConfiguration.swift:264-272`) — preserve it.

**Open decisions recorded.**
- **D5.2-a:** keep the 16-sub-struct granularity or collapse to fewer grouped structs? (CodeMap Open Q19.) Recommend keep — granularity is cheap and the MARK sections give navigability.
- **D5.2-b:** does `MarkdownEditorServices` (the services seam, separate file) stay a property of the value-config struct, or move out? It's behavior/services, not a value style. The app never touches `config.services` (uses `.default`, all No-Op; CodeMap REFINED). Preserve the seam inert (wikilink groundwork) but record whether it lives in the merged file or stays separate.
- **D5.2-c:** find-highlight has two identical `.systemYellow` colors (`findMatchHighlight` + `findCurrentMatchHighlight`, `MarkdownEditorTheme.swift:90-91`) with strength via a separate `findMatchHighlightAlpha` in a different sub-struct (`MarkdownEditorConfiguration.swift:158`). Cosmetic. Record: unify the source of "current match strength" or leave as-is.
- **D5.2-d (cross-feature non-goal check):** `ScrollersPolicy`/`SafeAreaInsets`/`DragSelectionPolicy`/`LinkStyle`/`InlineLatexStyle`(Void-placeholder) — confirm consumed/unconsumed before any trim (CodeMap Open Q22/Q23). Default: keep all, this phase merges files, it does not prune the public config.

### Task 5.3 — Code-text theme slot, byte-for-byte

**Intent.** Hoist the **duplicated** code-text color `NSColor.systemRed.withAlphaComponent(0.85)` (`MarkdownStyler.swift:462` AND `:499` — same file, two copies; CodeMap-confirmed) into ONE `MarkdownPMTheme.codeText` slot whose default reproduces it **byte-for-byte** (no visual change). The code-block *background* is already service-sourced — this fixes the asymmetry (CodeMap Phase-5 table).

**Gate.** Pixel/screenshot diff of a code block (inline + fenced) before/after = zero change; Suite-B golden unchanged.

**Open decision recorded.**
- **D5.3-a:** should code-text color be a `SyntaxHighlighter` responsibility (like `backgroundColor()`) or a `MarkdownPMTheme` token? (CodeMap Open Q21.) Authoritative ruling already decides: **theme slot**. Record the rejected alternative for the ledger.

### Task 5.4 — Brand-meaningful renderer literals: lift colors, leave geometry verbatim

**Intent.** Lift the **colors** of brand-meaningful renderer-resident values into named theme slots; leave the **pixel geometry** in the verbatim draw code. Reading a value from the theme inside a verbatim draw file does NOT count as modifying it (authoritative ruling). Targets (all `MarkdownTextLayoutFragment.swift`):
- blockquote bar (`secondaryLabelColor` `:655`, width 4 / radius 6 `:567-568`) + card (`tertiarySystemFill` `:639`) — lift colors, leave the 4pt/6pt geometry,
- divider/HR (`separatorColor` `:303`) — lift color,
- bullet 1.5× (`:383`) — confirmed 1.5× not 1.2× (CodeMap REFINED; stale comment at `:758`),
- checkbox tint (`accentColor`) — lift color, leave the hardcoded factors (`:1136/1159`).

**Gate (manual-verify).** The bullet-1.5× ↔ checkbox-alignment coupling (`:1144-1146`) and the pixel-snap math (`backingScaleFactor` floor/ceil, `:556-563,385-390,1150-1155`, Keep-Verbatim register) must survive the geometry/color split intact — manual visual verification of blockquote bar continuity, bullet glyph position, and checkbox box dimensions. CodeMap rates this HIGH risk (exact transplant or visual regression).

**Green per stage.** Snapshots + per-overlay pixel/screenshot diff hold at each stage.

---

## Phase 6 — Body Orchestration Tidy + Verbatim Transplant

**Intent.** DRY the orchestration that has genuinely drifted (duplicated paragraph builder, the two apply blocks, the scattered detection), route HR through the shared predicate, delete the dead `taskListRegex`, thread the cached parse through the input handlers, transplant the runtime-only OS-bug workarounds **verbatim with mandatory manual verification of each**, and verify the ContextMenu raw-write save path. This is the **most dangerous DRY temptation** — the body workarounds are runtime-only and no unit test catches them (Service doc Risks).

**Hard cross-phase dependencies.**
- **GATE: Phases 2–5 green.** Phase 6 threads the Phase-3 cached parse into input handlers and depends on the Phase-5 single styler for the unified apply path.
- The 9 input transforms live in `MarkdownListHandler.swift:358-898` (`MarkdownLists.handleInsertion`); `MarkdownInputHandler` is a thin facade (CodeMap WRONG-claim #20). Keep all 9 verbatim + pinned (Phase-2 Suite E).

### Task 6.1 — DRY the duplicated paragraph-candidate builder + the two apply blocks

**Intent.** Extract the shared `parse → activeTokens → restyle` preamble duplicated across `+TextDelegate.swift:108-150` (textDidChange) and `:184-238` (selection) and `restyleParagraphs` (`+Restyling.swift:244-254`). Unify the two "reset base then layer ranges" apply implementations (rebuild unscoped `+Restyling.swift:44-81` vs per-edit clipped `TextStylingService.swift:105-127`) into one `apply(_:to:scopedTo:)`.

**Gate.** Must preserve: caret-only-move HR sync (`+TextDelegate.swift:339-346` — restyle fires only when `tokensChanged && !pendingEditedRange`); initial-load whole-doc completeness vs per-edit paragraph clipping (the tension is load-bearing). Over-merging regresses the caret-only HR sync (CodeMap Phase-6 table, Medium risk).

### Task 6.2 — Route HR detection through the shared predicate; keep HR-before-folding sync order

**Intent.** Both the renderer (`MarkdownTextLayoutFragment.swift:69-87`) and the service (`+HRVisibility.swift:87-107`) detect HR by **duplicated** mirrored logic (Markdown.md §4.2, L2). Route both through one shared predicate so they cannot drift. Preserve the HR-before-folding sync order on both restyle paths (`+Restyling.swift:140-143` per-edit, `:101-104` rebuild). Remove the dead empty-else block (`+HeadingFolding.swift:195-196`).

**Gate.** The setext-suppression standalone-parse trick (`MarkdownDetection.swift:77,160` — the in-isolation parse IS the setext-H2 suppression, Keep-Verbatim register) must survive — do NOT add a setext guard (Markdown.md §6.3, L5). Assert `---` always renders as HR regardless of the preceding line.

### Task 6.3 — Delete dead `taskListRegex` + the no-op tokenizer expression

**Intent.** `taskListRegex` (`MarkdownTokenizer.swift:27-30`) is declared but never invoked — no `.taskList` token kind exists (CodeMap REFINED; verified: 11 kinds, no list/task-list kind). Delete it plus the computed-and-discarded no-op expression (`:134`). A live near-copy with a *different* marker class exists at `MarkdownStyler.swift:35` (decl) / `:526` (use) — non-empty `[ xX]` requirement at `:43` — that one is **live and in the Keep-Verbatim register** (shorthand→GFM canonicalization contract); do NOT touch it.

**Gate.** Build green; the empty-`[]` three-class split (list-detection optional `?` / checkbox non-empty / dash-bullet bracket-excluding) preserved (Markdown.md §6.14 deliberate-divergence; CodeMap REFINED). **Never merge the two regex classes.**

### Task 6.4 — Thread the cached parse through the input handlers

**Intent.** Remove the raw `parseTokens` bypass calls in the input path (`MarkdownInputHandler:78/197/215`) and thread the Phase-3 cached tokens. Rewire the live `isInside*` callers (SpellingPolicy, Services, ListHandler `:381`/`:416`) to the cached token query (Phase-3 work; verify it holds here). **KEEP `isInsideWikilink`** (`MarkdownDetection.swift:367-389`, line-scoped depth counter, no token/AST equivalent, required by the en-dash transform `MarkdownListHandler.swift:547`).

**Gate.** All 9 input transforms (Suite E byte-level golden) pass, with the coupling traps explicitly asserted: `-` kept in the fast-path exclusion (protects `<-`), em-dash order load-bearing (above the fast-path, the `---` hrConflict PRESERVE guard at `:376-378`), en-dash `isInsideWikilink` carve-out (protects filenames with ` - `). Needs the live `@MainActor` NSTextView host with the XCTest launch-modal guard (CLAUDE.md quirk #16).

### Task 6.5 — Transplant the runtime-only workarounds verbatim + manual-verify each

**Intent.** Transplant unchanged; manual visual verification mandatory; the only safe touch is extracting shared subview lookups. Each is off-limits to restructure:
- FB22524198 caret Y-snap (`NativeTextView+CaretWorkarounds.swift:68-106`) — KVO loop + re-entrancy guard.
- FB15131180 extra-line-fragment pin (`MarkdownTextLayoutFragment.swift:717,1185` via `@objc(extraLineFragmentAttributes)`) — the selector string is a KVC contract; still-open OS bug.
- Writing-Tools mid-session Cmd+Z recovery (`+Services.swift:281-397`) — the 0.1pt-marker-font contamination ties to marker-hide; a bad rebuild silently corrupts body text.
- 149pt height-oscillation guard (`NativeTextViewWrapper.swift:218-234` — width-delta `>0.5` + height-delta `>1`, two epsilon gates, NO boolean re-entrancy flag; CodeMap REFINED corrects the Service doc's "re-entrancy flag" phrasing).
- `shouldEnumerateTextElement` fold-elision (`+HeadingFolding.swift:516-544` returns Bool; the nil-return is the sibling `textParagraphWith:551-556` which SIGTRAPs on length-mismatch — keep the nil-return + comment).
- The `.pommoraThematicBreak` historical-note tombstone (`MarkdownTextLayoutFragment.swift:21-28`) — keep it (removing it loses the duplicate-HR regression signal).

**Gate (manual-verify, no unit test).** Per-workaround manual checklist: trailing-`\n` caret Y position; trailing-heading extra-line height (no ~30pt usageBounds inflation); WT accept + Cmd+Z round-trip preserves body + attributes; no 149pt height oscillation on viewport resize; cold-open of a pre-folded page collapses without a flash. The `mouseDown` dispatch order (checkbox → remap → chevron → boost → super, `NativeTextView+DragSelectBoost.swift:14-39`) is load-bearing — checkbox/chevron must consume the click before super repositions the caret.

### Task 6.6 — Unify the ContextMenu raw-write save path (+ note the deferred DEC-1 guard)

**Intent.** The CodeMap correction: there are **two** save producers — `+TextDelegate.swift:61` computes via `WikiLinkService.makeStorageState`, `:70` is the actual `@Binding` write (dedup at `:67`, gated `!wtActive` at `:60`); a second producer is `+Services.swift:325` (Writing-Tools commit). But `ContextMenu.swift` has **~10 raw `self.text = tv.string` writes** (`:140/167/186/211/227/281/317/352/410/432`) that BYPASS `makeStorageState` and the `lastSyncedText` dedup. Verify these do not persist display-form `[[Name]]` links (they can't today because no resolver ever produces an id — but the asymmetry is the latent bug surface).

**DEC-1 id-guard — DEFERRED to the Wiki-Link session (NOT built here).** Wikilinks stay plain `[[Title]]` on disk; the target Page identity is its own frontmatter ULID (`PageFrontmatter.swift:13`) — the link NEVER embeds an id. This rebuild does **not** add the structural strip (it is wikilink-feature work); it keeps the safe status quo (no resolver wired → no id written) and leaves the **consolidated save path as the single chokepoint** the future guard plugs into. **NOTE for the Wiki-Link session:** the strip step goes inside the one save helper `WikiLinkService.makeStorageState` (the producer both sinks — `+TextDelegate.swift:70` + `+Services.swift:325` — already route through, and ContextMenu's writes route through it after this task's unification); the open on-disk choice is *structural strip* (keep `[[Title]]` plain) vs an *explicit on-disk id format*, ratified then. When it lands, enable the Phase-2 `dec1TargetNoIdOnDisk` anchor (Task 2.6.2) as the regression lock. Unified-ID-vs-Obsidian is parked for that session.

**Open decisions recorded.**
- **D6.6-a — RULED (Nathan): UNIFY.** Route ContextMenu's ~10 raw `self.text = tv.string` writes through the consolidated `makeStorageState` + `lastSyncedText` dedup path so every save is uniform (and flows through the one chokepoint the future DEC-1 guard plugs into). Behavior-preserving today (the transform is identity with no resolver); it closes the bypass inconsistency. (CodeMap Open Q24.)
- **D6.6-b (explicitly OUT of this rebuild — scope flag):** Fix Log #8 (backspace-on-checkbox syntax-delete) is **UNIMPLEMENTED** — zero such code anywhere (CodeMap WRONG-claim #23; it's a TODO at `Handoff.md:58`). Do NOT build it inside the rebuild; the rebuild is a refactor-with-net, not a feature-add. Record it as deferred new work with scope unspecified (whole-marker vs step-through).

**Commit:** `refactor(markdownpm): unify orchestration; verbatim body transplant verified`

---

### Cross-Phase Dependency Map (summary)

| Dependency | Blocks | Reason |
|---|---|---|
| Phase 2 corpus green | All of 4, 5, 6 behavior changes | The net that makes "cleaner" safe; no behavior change lands without it |
| Phase 3 cached `Document` | 4.1, 4.3, 4.5 (AST consumers); 5.1 (one parse) | The merged styler + AST locating consume one cached parse, never re-parse |
| 4.1 marker helper green | 4.6 (parser deletion) | Width-subtraction must match legacy `markerRanges` byte-for-byte first |
| 4.2 + 4.3-a ledger sign-off | 4.6 (parser deletion) | Underscore-adoption + code-overlap-dedup are the intentional divergences gating deletion |
| Phase 4 (relocated emphasis tokens) | 5.1 (styler merge) | The merged styler inherits a working `.italic/.bold/.boldItalic` supply |
| 5.1 single styler | 6.1 (unified apply path) | One apply implementation depends on one styler |
| Phase 3 token threading | 6.4 (input handlers) | Input handlers thread the cached parse, not raw `parseTokens` |

### Open Decisions Index (for sign-off before the affected task)

- D4.1-a Apple `SourceRange` delimiter-inclusivity (probe first) · D4.1-b nested `***` flatten-vs-nest
- D4.2-a intra-word underscore suppression
- D4.3-a code-overlap dedup divergence (sign-off) · D4.3-b autolink/bare-URL preserved-as-is
- D4.4-a emphasis-inside-LaTeX suppression
- D4.5-a top-level-only folding survives unification
- D5.1-a tables: keep existing rendering, kept refinable (Nathan) · D5.1-b rebuild-path spelling pre-pass asymmetry · D5.1-c caret-accessor DRY preserving caret carve-outs
- D5.2-a sub-struct granularity · D5.2-b services seam placement · D5.2-c find-highlight strength source · D5.2-d non-goal config-prune trace
- D5.3-a code-text theme slot vs highlighter (ruled: theme slot)
- D6.6-a ContextMenu raw-write unification (RULED: unify through makeStorageState) · D6.6-b Fix Log #8 deferred (out of rebuild scope)

