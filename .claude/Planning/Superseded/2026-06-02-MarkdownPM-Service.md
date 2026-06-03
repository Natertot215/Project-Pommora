## MarkdownPM — Implementation Plan (v2)

> **For agentic workers:** execute via `superpowers:subagent-driven-development` — fresh subagent per task, two-stage review, green commit per phase. Re-assess between green commits (hard rule #13).
>
> **STATUS: v2 — folds in round-1 convergence (11 must-fixes) + the adopt-and-improve research (construct-by-construct parser scope, DRY map, keep-verbatim) + Obsidian-compat + Nathan's rulings. Pending round-2 of the verification loop.** Decisions: `2026-06-02-MarkdownPM-Decisions.md`.

**The spine (mental model):** take the vendored engine **apart**, understand every piece, **reassemble it cleaner, simpler, better** as the Pommora-owned package `MarkdownPM`. Not reinvented (we keep what swift-markdown + the engine genuinely give us), not preserved-as-is (donor code isn't sacred). The tight test net is what makes "cleaner" *safe* rather than risky. **Pages only.**

**Goal:** Fold `External/MarkdownEngine` into `MarkdownPM`; collapse the dual parse+style passes into one cached Apple-AST-backed parse with one owned styler; route the 3 inline constructs Apple does cleanly to its AST; keep the regex layer for everything Apple can't; transplant + *improve* the TextKit 2 body; fix the #9 caret stutter as a side-effect of the parse collapse.

---

### Parser scope — the construct-by-construct verdict (the locked (a)/(b) answer)

The AST **locates**; our owned styler still decides caret-aware hide/reveal (styling is ours, D-styling-ownership).

- **→ Apple AST (delete/replace our locating):** **Emphasis** (delete `MarkdownTokenizer+Emphasis.swift`, 173 lines), **inline code** (Apple's range includes the backticks by design), **links** (take `.destination`).
- **Split — Headings:** fold path keeps using Apple (`Heading.level` + range, already correct); **marker-reveal/sizing stays regex** (Apple exposes no `#` delimiter sub-ranges).
- **Stay regex (Apple absent or wrong):** wikilinks `[[..]]` + embeds `![[..]]` (no cmark node), the `$…$` math/currency heuristic, bullets/list/empty-`[]` checkbox, the Setext-suppression standalone-parse trick.

### The four buckets

**Adopt-Apple:** emphasis · inline-code · links · heading fold path *(only)*.
**Simplify-ours (DRY, behavior unchanged):** the 11 `isInside*` overloads → one generic `isInside(range:tokens:)` core + wrappers (caret-edge logic in one place; preserve the D25 carve-outs); the ~11 scattered `activeTokenIndices.contains` reads → one accessor + a `markerAttributes(active:)` factory; the two duplicated per-paragraph apply-loops → one `apply(_:to:scopedTo:)`; the duplicated `systemRed@0.85` code color → one `MarkdownPMTheme.codeText` slot (default reproduces it exactly).
**Keep-behavior-improve-code:** the dual-styler merge (staged, D26 — the highest-risk step); the heading marker-reveal path; HR/ThematicBreak detection (route both call sites through the shared predicate); blockquote + table AST walks (replace magic byte-codes with named checks; flag continuous-bar layout for manual verify); all input handlers (thread the single cached parse so none re-tokenizes; preserve every order-dependency).
**Keep-verbatim (Apple can't help / runtime-only / locked):** the math heuristic; the Setext trick; the 9 input transforms (D5); the runtime-only body workarounds (see list) — **manual visual verification mandatory** for each.

---

### Phases

#### Phase 1 — Re-home as `MarkdownPM` *(1-2 sessions)*
- [ ] Rename package/module `External/MarkdownEngine` → `MarkdownPM` (keep relaxed Swift-5.9 settings — the package wall is the isolation seam, D10). Rename public front door `NativeTextViewWrapper` → `MarkdownPMEditor`, `MarkdownEditorConfiguration` → `MarkdownPMConfiguration` (brand the public surface + new brain types only; verbatim body internals keep their names).
- [ ] Update the 3 app import sites + the pbxproj `XCLocalSwiftPackageReference`.
- [ ] **Doc reconciliation (must-fix F3/F10):** rewrite `NOTICE.md`'s planned-migration rows to MarkdownPM names + inside-package placement; correct "6 extensions" → **4** (`+TextStyling/+Links/+Latex/+Images`; code + checkbox styling live *inside* `MarkdownStyler.swift`); drop the `SourceRangeToNSRange` entry (reuse the existing `SourceRangeConverter`); update `Paradigm-Decisions.md` #7 from "vendored swift-markdown-engine" → MarkdownPM-owned. Fix the `Markdown.md` path (Guidelines, not Features) in CLAUDE.md's Document Map.
- [ ] Green: `refactor(markdownpm): re-home vendored engine as the MarkdownPM package`

#### Phase 2 — Characterization net + divergence ledger *(2-3 sessions; gate for all brain work)*
Tests live in **MarkdownPM's own test target** (wired into the test command — Q6), with public-surface/on-disk-round-trip tests in the app target. JSON-snapshot suites survive the refactor.
- [ ] Corpus (must include the **adversarial + byte-changing** cases, not just happy paths): emphasis **rule-of-3 multiples** (`**foo*bar**baz*`, `*foo**bar*baz**`), **cross-line** (`*foo\nbar*`), **punctuation-flanking**, intra-word `a*b*c`; inline-code multi-backtick + space-trim; links incl. (decision: inline-only) reference/shortcut/autolink **flagged**; headings `#`/bare-`#`/`### Foo ###` on **both** detector paths; **empty `[]` vs `- [ ]` vs `-[x]`**; the 9 transforms incl. `--`→`—`, ` - `→`–`, arrows, bracket-skip; smart-quotes (byte-changing); wikilinks (plain/path-qualified-inbound/`.md`-suffixed/multibyte); `$5` vs `$x+y$`; **multibyte/emoji lines** (pins the UTF-8/UTF-16 offset behavior); HR/Setext; CRLF; legacy `•`.
- [ ] Suites: A tokenizer output · B styled-attribute ranges at varied caret positions · C `foldableHeadings` NSRange pairs · D wikilink storage↔display round-trip **+ the D1 guard test** (inject a resolver returning an id, type `[[Title]]`, save → assert on-disk stays plain `[[Title]]`; assert no ULID-shaped token inside `[[…]]`; allow a visible `^anchor`) · E input transforms. Pull `EnterContinuationTests` into the run.
- [ ] **Divergence ledger** started: every intentional behavior change (Apple-emphasis edge cases, inline-code multi-backtick/space-trim, links) logged for sign-off. Nothing silent.
- [ ] Green: `test(markdownpm): characterization net + divergence ledger + D1 on-disk guard`

#### Phase 3 — Single cached parse spine (the #9 fix emerges) *(2-3 sessions)*
- [ ] **Extend the EXISTING `ParsedDocument` struct** (`NativeTextViewCoordinator.swift:143`) — add the Apple `Document`, parsed once inside the existing `parsedDocument(for:)` cache. (Do NOT introduce a new type — F9.)
- [ ] Thread the cached `Document` into `AppleASTSupplementalStyler.styleAttributes` (drop its internal `Document(parsing:)`) and into `syncHeadingFolding` (drop its parse). The **always-on supplemental AST parse is the primary culprit** (F8: it's a *double* parse on unfolded pages, triple only with folds).
- [ ] **Scope the deletion of slow detection overloads precisely (F2):** delete only the re-parsing `isInsideCodeBlock/isInsideLatex/isInsideInlineLatex(…in:String)` overloads; **DO NOT delete `isInsideWikilink`** (it's a line-scoped depth counter, no token equivalent, required by the en-dash transform). Rewire the 4 live callers (SpellingPolicy, Services, ListHandler ×2) to the cached token query.
- [ ] Leave the per-fragment renderer parse (`MarkdownTextLayoutFragment.swift:453`) **out** of the document cache (intentional, §6.7).
- [ ] Measure with Instruments before/after in **both** fold and no-fold states (no false §6.4 citation; the on-topic guidance is §6.7/§6.9/§6.12/§7.4). Snapshots must not move. Green: `perf(markdownpm): single cached parse spine (collapses redundant parses; resolves caret stutter)`

#### Phase 4 — Inline locating on the AST *(3-4 sessions)*
- [ ] Move emphasis/inline-code/links locating to the Apple AST. **Emphasis marker-reconstruction is its own tested sub-task:** derive the 2 hide-ranges by delimiter-width subtraction (1/2/3) from the whole-construct range; assert derived ranges match the old parser on the corpus. Emphasis tokens (`.italic/.bold/.boldItalic`) are **relocated** into the AST walk (formerly `+Emphasis.swift:138`), not dropped.
- [ ] **Gate: delete `MarkdownTokenizer+Emphasis.swift` only after the adversarial corpus is green** (Q2). Links: inline-style only (decision); take `.destination`. Keep `MarkdownToken.swift` + `MarkdownPlainText.swift` verbatim (`[MarkdownToken]` is package-*internal*, frozen by tests, not a public promise).
- [ ] Headings: keep the regex marker path; reconcile-or-freeze the two heading detectors (decision: **freeze + pin** the `^#{1,6}([ \t]|$)` vs `^\s*(#{1,6}) +` divergence with a corpus test). Bullets/list/checkbox detection **stays regex** (Apple gets empty-`[]` wrong — F6). Math heuristic reproduced verbatim + pinned (D11).
- [ ] Green: `refactor(markdownpm): inline locating (emphasis/code/links) on Apple AST; emphasis parser deleted behind corpus`

#### Phase 5 — One owned styler + `MarkdownPMTheme` *(4-6 sessions; staged, D26)*
- [ ] Collapse `primaryStyledRanges + supplementalRanges` (`TextStylingService.swift:94`) into one owned `MarkdownPMStyler` that walks the cached AST once. **Stage it:** safe non-caret constructs first (headings/emphasis/links/code/strikethrough/table); caret-aware ones last; the styler keeps emitting **nothing** for service-owned constructs (HR; blockquote always-shows) — the locked sole-writer rule (don't re-break duplicate-HR).
- [ ] `MarkdownPMTheme` = **rename + merge + re-home** of the existing `MarkdownEditorTheme` (colors) + `MarkdownEditorConfiguration`'s value structs (sizes/spacing), into one file with the 17 grouped sub-structs as MARK sections (Q5 — one file). Keep heading multipliers `[2.0,1.5,1.17,1.0,0.83,0.67]` byte-for-byte (D18). Dark-mode-adaptive system colors (D16). Breadcrumb comments to any computed geometry left in draw code (D17). Keep a clean Item-profile *seam* but build **Pages-only**.
- [ ] Centralize caret-awareness into one decision function (the 2 carve-outs preserved — D25).
- [ ] Snapshots + per-overlay pixel/screenshot diff hold. Green per stage.

#### Phase 6 — Body orchestration tidy + verbatim transplant *(2-3 sessions)*
- [ ] DRY the duplicated paragraph-candidate builder; route HR detection through the shared predicate; hoist the renderer's per-fragment detection onto the cached tokens; thread the cached parse through input handlers.
- [ ] **Transplant the runtime-only body workarounds verbatim; manual-verify each** (see list). Verify every one of Nathan's deliberate additions is intact.
- [ ] Green: `refactor(markdownpm): unify orchestration; verbatim body transplant verified`

---

### Keep-verbatim + manual-verify (runtime-only — no unit test catches these)

Transplant unchanged; **manual visual verification mandatory**; only safe touch = extract shared subview lookups (D24-moderate). Note: **FB-radar numbers live in these file headers, not `NOTICE.md`.**

- **FB22524198** trailing-newline caret Y-snap (`NativeTextView+CaretWorkarounds.swift:68-106`) — KVO-correct loop + re-entrancy guard.
- **FB15131180** extra-line-fragment metrics pin (`MarkdownTextLayoutFragment.swift:717,1185`) — still-open OS bug (worse in macOS 15); the `@objc(extraLineFragmentAttributes)` private-selector bridge + the `nonisolated`/`MainActor.assumeIsolated` contract.
- **Writing-Tools mid-session Cmd+Z recovery** (`+Services.swift:281-397`) — the 0.1pt-marker-font contamination detail ties to marker-hide; a bad rebuild could silently corrupt body text.
- **149pt height-oscillation guard** (`NativeTextViewWrapper.swift:219`) — self-feedback loop; the `abs>1` epsilon + re-entrancy flag.
- **`shouldEnumerateTextElement` fold elision** (`+HeadingFolding.swift:475`) — correct Apple API use; the sibling `textParagraphWith` SIGTRAPs, keep the nil-return + comment.
- **`.pommoraThematicBreak` tombstone** (`MarkdownTextLayoutFragment.swift:21`) — keep it (removing it loses the duplicate-HR regression signal).

### Public contract — must not break
3 app import sites. `MarkdownPMEditor` `NSViewRepresentable` — the init has **15 params** (7 used + 8 dormant, F7); keep the wikilink/inline seams (`isWikiLinkActive`, `pendingInlineReplacement`, `onInlineSelectionChange`, `onPasteImage`), shed only genuinely speculative ones (`onCaretRectChange`/`onCodeBlockSelectionChange`). `MarkdownPMConfiguration` with `.default` + mutable `textInsets`; **`TextInsets` stays a public struct** with `init(horizontal:vertical:)` (F11). `MarkdownDetection.reconcileFoldedHeadings`, `MarkdownPlainText.extract`. Attribute keys `"NodeLinkID"`/`"TaskCheckbox"` exact.

### Wikilink groundwork (preserve only — separate post-rebuild session)
Keep plain `[[Title]]` on disk; **resolve by ID, not location** (no Obsidian-style path-qualification — Nathan's ruling); the `WikiLinkService` transform is **LIVE** on every load/restyle/save (F4 — only the `WikiLinkResolver` *conformance* is dormant; do not "simplify away" the live adapter). Parser must **accept** inbound path-qualified / relative / `.md`-suffixed forms on read. The D1 guard test (Phase 2) enforces no-id-on-disk. Build nothing beyond the seam.

### Risks (carry into every phase)
- **Emphasis deletion** unsafe without the adversarial corpus gate (Q2). **Styler merge** (D26) is the single highest-risk step — stage it, keep the sole-writer rule. **Body-workaround restructure** is the most dangerous DRY temptation — runtime-only, manual-verify mandatory. **Empty-`[]` split** (finalized 2026-06-01) — hoist shared constants, never merge the two regex classes. **Math thresholds** (120/40/6) — freeze by tests before any tidy. **Input-cascade coupling traps** — `-` in the fast-path exclusion (kills `<-`), `isInsideWikilink` in the en-dash branch (corrupts filenames), em-dash order (re-breaks `---`). **No safety net until Phase 2** — Phase 1 is pure rename (safe); Phase 3 touches behavior (the deleted overloads gate dash/checkbox transforms), so Phase 2 must land before Phase 3's behavior changes. **Parallel-branch merge (D12)** — decide order up front.

### Decisions locked on recommendations (veto any)
Q3 locate-only + Apple auto-rewrite off · Q4 measure-then-decide · Q5 one styling file · Q6 deep tests in package target · Links inline-style only · Heading-detector freeze+pin · UTF-8/UTF-16 fix deferred to the D23 swift-markdown bump (pin current behavior with a multibyte corpus now).

### Non-goals
Custom GFM parser · SwiftUI-native body · Item profile / `@`-tagging · the wikilink feature (resolver/index/nav) · swift-markdown bump · reference/shortcut/autolink support · brand color palette · true tables.
