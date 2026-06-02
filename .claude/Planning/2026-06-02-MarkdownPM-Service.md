## MarkdownPM — The Pommora Markdown Service (Plan)

> **STATUS (2026-06-02): provisional scaffolding — superseded by the locked rulings in `2026-06-02-MarkdownPM-Decisions.md`.** Scope changes since this draft: **Items EXCLUDED (Pages-only)**; **wikilinks are a SEPARATE post-rebuild session** (this rebuild preserves the groundwork/seam only); the **#9 fix folds into the parse-consolidation** (no standalone phase); **tight divergence-ledger testing** (every edge-case / lost function / behavior change flagged + scoped). The finalized plan will be rewritten from the locked decisions + a design doc, then iterated v1→vN.

> **For agentic workers:** execute via `superpowers:subagent-driven-development` — fresh subagent per task, two-stage review, green commit per phase. Steps use `- [ ]`. Re-assess this plan between green commits (hard rule #13): only landed phases are facts; later-phase detail is provisional until the phase before it ships.

**Goal:** Absorb the vendored `External/MarkdownEngine` into a Pommora-owned service, **`MarkdownPM`** — consolidate the dual parser + styler onto one cached Apple-AST spine in Pommora's own format, transplant the battle-tested TextKit 2 foundations verbatim, add per-kind (Item vs Page) rendering profiles, fix the #9 per-caret glitch, and dissolve the external-engine dependency. **Net total simplification** — fewer parses, one styler, one owned module.

**Architecture:** A single cached `Document` parse per text-change feeds *every* consumer (styler, fold walk, renderer detection, caret-context). One AST-driven `PommoraMarkdownStyler` replaces the dual primary-regex + supplemental-AST stylers. The TextKit 2 body (NSTextView subclass, coordinator, renderer, input handlers, ~18 OS-bug workarounds) is **transplanted verbatim** into `MarkdownPM` — not re-derived. A `MarkdownProfile` (Item vs Page) parameterizes the styler so the two entity kinds render differently over one core. The dormant services seam (`WikiLinkResolver` etc.) becomes the live wikilink adapter.

**Tech stack:** TextKit 2 / AppKit, Apple `swift-markdown` (**kept** — the parse foundation), Swift 6 strict concurrency + ExistentialAny, Swift Testing.

---

### Scope decisions — locked + flagged for review

These are the interpretation calls behind the plan. **Flagged ones want a yes/no on review; locked ones follow the blueprint evidence.**

- 🚩 **"Remove the dependency" = dissolve the vendored `MarkdownEngine` package, NOT drop Apple's `swift-markdown`.** `MarkdownPM` keeps `swift-markdown` (the official GFM parser) as its parse foundation — it's the one dependency worth having, and the whole consolidation *rebuilds onto* it. Writing our own GFM parser is explicitly out of scope (reckless, no payoff). *If you meant drop swift-markdown too, stop me — that's a far larger, riskier plan.*
- 🚩 **`MarkdownPM` stays a local SwiftPM package** (renamed/re-homed from `External/MarkdownEngine`), not folded into the app target. Keeps the clean module boundary, isolated tests, and editor-swappability portability — just Pommora-owned and renamed. *Alt: fold into the app target if you'd rather have no package at all.*
- 🔒 **The body is transplanted verbatim** (the ~18 spec-irreproducible OS-bug workarounds are kept, not rewritten) — "keeping the parts that actually work." The rebuild/consolidation happens in the **brain** (parser + styler). Re-deriving the body = +15-25 sessions with no test net and no payoff to the goals.
- 🔒 **Per-kind profiles live in the styler** (`MarkdownProfile.item` / `.page`), the seam that lets Items (inline-only, capped description) and Pages (full document) diverge over one core.
- 🔒 **Locked paradigm #7 is preserved** (TextKit 2 + Apple swift-markdown + an owned engine) — `MarkdownPM` is a rename + consolidation of the "vendored engine" leg, not a revision. Record the rename in `History.md`; no new paradigm-confirmation needed.

---

### Phases

Six phases, each an independent green commit. **Phase 1 ships the #9 fix on its own** (decoupled from the rebuild). Phases 1–3 are detailed; 4–6 are scoped and will be elaborated when reached.

#### Phase 1 — Fix #9: single cached parse spine *(1–2 sessions; ships alone)*

The glitch is a per-tick **double/triple parse**: the regex tokenizer is cached, but the supplemental Apple-AST styler (`AppleASTSupplementalStyler.swift:30`, via `TextStylingService.swift:88` + `Restyling.swift:71`) and the heading-fold walk (`HeadingFolding.swift:160`, via `Restyling.swift:142`) each re-parse the whole document, uncached.

- [ ] **Measure first** (Markdown.md §6.4): Instruments trace arrow-keying a long page; confirm `Document(parsing:)` dominates. (Use `swiftui-expert-skill` trace tooling.)
- [ ] Extend the existing `cachedParsedText`/`cachedParsedDocument` cache (`Restyling.swift:146-191`) to hold one cached Apple `Document` keyed by text identity.
- [ ] Add an `AppleASTSupplementalStyler.styleAttributes` overload taking the precomputed `Document` + `scopedRanges`; thread the shared AST into `syncHeadingFolding` instead of its own `Document(parsing:)`.
- [ ] Delete the slow `MarkdownDetection.isInside…(…in: String)` re-parse overloads (`Detection.swift:329,394,411`) for cached-token overloads.
- [ ] Re-trace to confirm one parse per tick; verify jitter gone. **Stop if 2–3 scoped attempts don't land — revert and reconsider that function's design** (don't pile hotfix on hotfix).
- [ ] Green commit: `perf(editor): collapse per-tick triple-parse onto one cached AST (fixes #9 caret stutter)`

#### Phase 2 — Characterization test net *(2–3 sessions; prerequisite for all rebuild work)*

The engine has ~12 tests vs 11.2k LOC, and they live in `External/MarkdownEngine/Tests` (NOT run by the app's `xcodebuild test`). Build the safety net in the **`PommoraTests` app target** as JSON-snapshot suites over a fixture corpus, so they survive the internal refactor.

- [ ] Corpus covering every construct: headings (incl. duplicate-text `[N]` ordinals), `*`/`**`/`***`, intra-word `a*b*c`, adjacent `***a** b*`, links, wikilinks (id-bearing/id-less/nested/adjacent/multibyte), image-embeds, inline+block code, inline+block LaTeX (incl. currency `$5` vs math), task checkboxes (incl. empty `[]`, `-[x]`), blockquote multi-paragraph, strikethrough, table, HR, CRLF, legacy `•` bullets.
- [ ] Suite A — `MarkdownTokenizer.parseTokens` output (kind + range + contentRange + markerRanges). Locks the type-API 11 consumers depend on.
- [ ] Suite B — merged styled-attribute ranges (styler + supplemental), at **varied caret positions** (caret-in-token vs out — the #9 reveal surface).
- [ ] Suite C — `MarkdownDetection.foldableHeadings` returning the actual `NSRange` pairs (not just keys).
- [ ] Suite D — `WikiLinkService` storage↔display round-trip byte-stability (the rename-safety contract; zero tests today).
- [ ] Suite E — `MarkdownListHandler.handleInsertion` input transforms (Enter/space/dash/bracket-skip/arrows/em-dash). Pull `EnterContinuationTests` into the app target.
- [ ] Smoke test: unit-test host bootstraps (XCTest guard, quirk #16) + build green.
- [ ] Green commit: `test(markdownpm): characterization harness over parser/styler/wikilink/list-input`

#### Phase 3 — Re-home as `MarkdownPM` + hoist utils + activate the wikilink seam *(1–2 sessions)*

This is where the dependency dissolves and the Pommora identity is established.

- [ ] Rename the local package `External/MarkdownEngine` → `MarkdownPM` (package + module name); update the 3 app import sites (`Pages/PageEditorView.swift`, `PageEditorViewModel.swift`, `PageTextStats.swift`) and the pbxproj `XCLocalSwiftPackageReference`. (Confirm package-form vs in-app per the flagged decision before this step.)
- [ ] Hoist `LineOffsetIndex` + `SourceRangeConverter` out of `AppleASTSupplementalStyler.swift` into `Util/` (breaks the Parser→Styling dependency; needed by the rebuilt single-spine parser).
- [ ] Implement `PommoraWikiLinkResolver` against the dormant `WikiLinkResolver` protocol; wire via `configuration.services`, replacing `NoOpWikiLinkResolver` (per `Features/Wiki-Link.md`). Tests stay green.
- [ ] Green commit: `refactor(markdownpm): re-home engine as MarkdownPM; hoist source-range utils; wire live wikilink resolver`

#### Phase 4 — Reimplement parser internals on the shared AST *(3–4 sessions)*

- [ ] Rewrite `MarkdownTokenizer` + `MarkdownDetection` internals to read from the shared Apple AST + a regex scan for the two Obsidian-only constructs (wikilink `[[..]]`, image-embed `![[..]]`), emitting **byte-identical `[MarkdownToken]`**.
- [ ] Delete `MarkdownTokenizer+Emphasis.swift` (emphasis comes off the AST). Keep `MarkdownToken.swift` + `MarkdownPlainText.swift` verbatim (`MarkdownToken` raw keys `"NodeLinkID"`/`"TaskCheckbox"` must stay exact).
- [ ] Gate every change on the Phase-2 snapshots — they must not move. Pay special attention to the untested `isInlineMathContent` heuristic (`Tokenizer.swift:210-240`) and emphasis flanking/rule-of-3.
- [ ] Green commit: `refactor(markdownpm): reimplement tokenizer/detection internals on shared Apple AST (token-API unchanged)`

#### Phase 5 — One AST-driven `PommoraMarkdownStyler` + per-kind profiles *(4–6 sessions)*

- [ ] Replace `MarkdownStyler` + its 6 extensions + `AppleASTSupplementalStyler` with a single `PommoraMarkdownStyler` walking the shared AST for all constructs, overlaying the two Obsidian regex constructs.
- [ ] Centralize caret-awareness into one decision function (replaces the ~9 scattered `activeTokenIndices.contains` checks); honor `scopedRanges` at compute time uniformly (generalize `Links.swift:23`).
- [ ] **Introduce `MarkdownProfile` (`.item` / `.page`)** as a styler parameter: `.page` = full document; `.item` = inline-only, capped, no block constructs (the per-kind divergence goal). Thread the profile from the call site (Page editor = `.page`; future Item rich-description = `.item`).
- [ ] Preserve the load-bearing dispatch order (shrink-inactive-markers last; code overlays after headings), the negative-kern image-collapse helper, the softened-red code color, the marker-collapse-keeps-valid-GFM rule.
- [ ] Snapshots + per-overlay pixel/screenshot diff must hold.
- [ ] Green commit: `refactor(markdownpm): single AST-driven PommoraMarkdownStyler + per-kind profiles`

#### Phase 6 — Tidy the body orchestration (no re-derivation) *(2–3 sessions)*

- [ ] Unify the duplicated paragraph-candidate builder (`TextDelegate.swift:76-148` vs `202-231`); migrate `HRVisibility` color-tolerance code-block check to the AST check; kill the 60Hz chevron storage-edit pressure; hoist the renderer's per-fragment detection (`MarkdownTextLayoutFragment.swift:74,154,453`) onto the shared cached token query.
- [ ] **Transplant ALL workaround files verbatim** (see Preserve-Verbatim). Re-verify caret/Writing-Tools/overscroll workarounds against the current OS.
- [ ] Green commit: `refactor(markdownpm): unify restyle scoping + hoist renderer detection onto cached tokens`

---

### Preserve verbatim — the body workarounds (do NOT re-derive)

These are spec-irreproducible, near-untested OS-bug fixes. Transplant as-is; touching them re-incurs the original debugging with no test to catch a regression. (File:line are pre-rename `MarkdownEngine` paths.)

- `NativeTextView+CaretWorkarounds.swift` — FB22524198 / FB15131180 caret Y-snap + height via KVO on the private `NSTextInsertionIndicator`.
- `NativeTextViewCoordinator+HeadingFolding.swift` — fold elision via `shouldEnumerate` element-omission (substitution route *crashed*); the AppKit-force-lays-out-caret fix; the `invalidateFoldLayout` 4-step cascade incl. the side-effecting `textLayoutFragment(for:)`; `nudgeHeading` redraw (both `setNeedsDisplay` and `invalidateRenderingAttributes` FAIL in TextKit 2).
- `NativeTextViewCoordinator+Services.swift` — macOS-15 Writing Tools Cmd+Z recovery + child-window 20×-poll fix.
- `NativeTextViewWrapper.swift` — viewport-width-only `frameDidChange` guard (kills 149pt height oscillation); `foldedHeadings` as plain stored property + fresh-binding callback (a `@Binding` on a class goes stale).
- `MarkdownTextLayoutFragment.swift` — the HARD prohibition on custom paragraph-level `NSAttributedString.Key`s (reopens the duplicate-HR bug); `@unchecked Sendable` + `MainActor.assumeIsolated`; FB15131180 `extraLineFragmentAttributes` private-selector workaround; per-overlay pixel-snap (`round` for glyphs, `floor`/`ceil` for fills — not interchangeable).
- `NativeTextView+FrameAndOverscroll.swift` / `+DragSelectBoost` / `+ClickRemap` / `ClampedScrollView.swift` — dual TextKit-2 height measurement, mouseDown click-priority chain, live-resize scroll save/restore.
- `MarkdownListHandler.swift` — the order-dependent `handleInsertion` intercept chain (em-dash above the fast-path filter; Shift+Enter via `NSApp.currentEvent.modifierFlags`; task-marker hide leaves `[ ]` at body font; legacy `•` back-compat).
- `MarkdownDetection.swift` — ordinal `[N]` heading-key disambiguation + CRLF-safe key (keys persist in `folded_headings:` frontmatter — changing the format breaks saved fold state).

---

### Public contract — must not break

App coupling is loose (3 import sites, 5 named symbols). The rebuild MUST preserve:

- `NativeTextViewWrapper` as an `NSViewRepresentable` with the 7-param init the app uses: `init(text:foldedHeadings:configuration:fontName:fontSize:documentId:onScrollOffsetChange:)`. (The other 7 init params are app-unused and may be shed.) Behavior: storage-form `[[Name|<id>]]` text with display-form maintained internally; `documentId` change resets undo + per-doc state; `configuration.textInsets.vertical` reserves the title-overlay zone; `onScrollOffsetChange` normalized to 0 at rest.
- `MarkdownEditorConfiguration` with `.default` + a mutable `textInsets` (the only field the app sets, `PageEditorView.swift:351-355`).
- `MarkdownDetection.reconcileFoldedHeadings(_:in:) -> Set<String>` and `MarkdownPlainText.extract(from:) -> String` (used by `PageTextStats.swift:36`).
- Fold keys = exact heading source lines with `[N]` ordinal suffix; canonical store = `page.frontmatter.foldedHeadings`.

---

### Risks & non-goals

- **Highest risk (Phases 4–5):** the untested `isInlineMathContent` currency-vs-math heuristic and the CommonMark emphasis parser — if the Phase-2 corpus misses an edge case, styling diverges silently. **Harness quality IS the safety.**
- **Scope-creep guard:** do NOT "while we're in here" rewrite the body workarounds. That's the rejected full-rebuild (+15-25 sessions, regression risk, no payoff).
- **Non-goals:** writing a custom GFM parser (keep swift-markdown); a SwiftUI-native body (revisit only if a future feature demands it); backlinks/graph UI (separate roadmap).

---

### Open questions for Nathan (the 🚩 above)

1. Confirm: **keep Apple `swift-markdown`** (dissolve only the `MarkdownEngine` *package*), not write our own parser? (Strongly recommended.)
2. Confirm: `MarkdownPM` stays a **local SwiftPM package**, vs folded into the app target?
3. Confirm the name **`MarkdownPM`** for the module (assuming "Pommora Markdown"). Public type prefix → `PommoraMarkdownStyler` etc., or a different convention?
