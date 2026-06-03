## MarkdownPM — Divergence Ledger

Every intentional behavior change in the MarkdownPM rebuild is recorded here
before it lands. Each row: the construct, the OLD behavior (pinned by a Phase-2
characterization test), the NEW behavior, the phase that flips it, the test that
flips, and Nathan's sign-off. "Tested-identical on a fixed corpus, every
intentional divergence flagged + scoped" — NOT byte-identical. This is the
flagged-and-scoped list.

| # | Construct | OLD (pinned by) | NEW | Phase | Flipping test | Signed off |
|---|---|---|---|---|---|---|
| D-EMPH-1 | Emphasis delimiter | asterisk-only `*`/`**`/`***` (pinned: `TokenizerCorpusTests.underscoreIsNotEmphasis_currentBehavior`) | adopt underscore `_`/`__` (Apple + CommonMark + Obsidian) | 4 | **LANDED `361bd20`** — `TokenizerCorpusTests.underscoreIsEmphasis` (`_b_` italic(0,3), `__c__` bold(4,5)) | ACCEPTED (Nathan 2026-06-02 — adopt underscore) |
| D-EMPH-2 | Emphasis inside inline code / code fence | NOT suppressed (`*x*` inside `` `…` `` still tokenizes — pinned `TokenizerCorpusTests.emphasisInsideInlineCode_notSuppressed_currentBehavior`) | suppressed (Apple AST does not emit emphasis inside code) | 4 | **LANDED `361bd20`** — `TokenizerCorpusTests.emphasisInsideInlineCodeSuppressed` (`` `*x*` `` → 0 emphasis) | ACCEPTED (Nathan 2026-06-02 — suppress, matches Apple) |
| D-EMPH-3 | Rule-of-3 nesting (`**foo*bar**baz*`, `*foo**bar*baz**`) | legacy emits TWO OVERLAPPING runs — `ruleOfThree_a` bold(0,11)+italic(5,10); `ruleOfThree_b` italic(0,10)+bold(4,11) (pinned `TokenizerCorpusTests`) | Apple emits ONE clean CommonMark node — `8a` Strong(0,11) only; `8b` Emphasis(0,10) only (probe-verified 0.8.0). Re-pin, NOT reproduce — `styleEmphasis` reads only kind+contentRange so render stays correct | 4 | **LANDED `361bd20`** — `TokenizerCorpusTests.ruleOfThree_a` (1 bold(0,11)) / `ruleOfThree_b` (1 italic(0,10)) re-pinned | LOGGED (best-judgment; recon-verified) |
| D-EMPH-4 | Cross-line emphasis (`*foo\nbar*`) | legacy REJECTS cross-line (per-line stack → `crossLine` empty) | Apple emphasizes across the SoftBreak (one node, NSRange (0,9)) — CommonMark-correct, matches Obsidian; keep Apple behavior | 4 | **LANDED `361bd20`** — `TokenizerCorpusTests.crossLine` re-pinned (1 italic(0,9)) | LOGGED (best-judgment — revertable via a multi-line-node filter if Nathan prefers old) |
| D-CODE-1 | Multi-backtick inline code (`` ``a`b`` ``) | legacy regex matches inner `` `b` `` only | Apple `InlineCode` covers the whole double-backtick span (NSRange len 7, `.code`=`` a`b ``) — backtick-inclusive + CommonMark single-space trim | 4→DEFERRED | inline-code corpus pin (future) | **DEFERRED** (see Phase-4 scope note) — `.inlineCode` tokens feed the load-bearing `codeTokens` bucket; relocating ripples the dash carve-out + latex/link/active-token suppression for a multi-backtick edge case. Regex stays; reversible future polish |
| D-HEAD-1 | Heading detector unification | two divergent regexes (styler `#{1,6} +`, detection `#{1,6}([ \t]\|$)`) — pinned `HeadingDetectorCorpusTests` + `TokenizerCorpusTests` on BOTH paths | ONE rule: CommonMark `#{1,6}([ \t]\|$)` (space/tab/EOL) | 4 | **LANDED `f89bca0`** — styler `headingRegex` → `^\s*(#{1,6})(?:[ \t]+(.*))?$`; `TokenizerCorpusTests.headingDetectorsUnified` proves styler+detection agree on `##\tFoo`/`###`/`#Foo`; flipped pins `headingNoSpaceIsNowToken` + `headingTabAfterHashIsNowToken` | ACCEPTED (Nathan — unify) |
| D-HEAD-2 | Heading size multipliers | shipped `[2.0,1.5,1.17,1.0,0.83,0.67]` (H4=body; H5/H6 below body) — pinned by `HeadingSizeCorpus.h1`…`h6` + `HeadingSizeCorpus.derivedMultiplierArray` (observed pointSizes at base 16: 32.0/24.0/18.72/16.0/13.28/10.72; multipliers match the stated array exactly) | new scale `[2.0,1.75,1.5,1.25,1.15,1.0]` (H6=body; no heading below body) | 5 | `HeadingSizeTests` (P5) | ACCEPTED (Nathan 2026-06-02) |
| #9-PARSE | Apple Document parses per edit | 1 unfolded / 2 folded (was; pinned P2) | 1 both fold states (cached spine) | 3 | **LANDED `303bb6c`** — `ParseSpineTests.unfoldedEditParsesOnce`/`foldedEditParsesOnce` (read-only proof, NOT `textDidChange` — see harness note below); P2 `ParseCountProbeTests` RETIRED in 3.2 (direct-call premise died) | **LANDED Phase 3** (best-judgment, non-blocking) |

Add rows as new divergences are discovered. **Execution is NON-BLOCKING (Nathan ruling 2026-06-02):** proceed on the best read of Nathan's stated direction, LOG every divergence here (with where it can be adjusted), and surface the full ledger at the END of the rebuild for review — do NOT pause mid-build waiting for a pass. Wherever this plan says "sign-off" / "signed off," read it as *logged + best-judgment + reviewed at the end*, never a blocking gate.

---

### Operational corrections + plan mismatches (fold into the plan when updating — Nathan's directive)

These are NOT behavior divergences — they are corrections execution surfaced against the plan's text + run-commands. **Apply them when updating the plan.**

**Run-command / verification corrections (OPS):**

- **OPS-1 — `xcodebuild` runs from `<repo>/Pommora`**, NOT the repo root (the plan says repo root; the repo root has no `.xcodeproj`/workspace). Only `swift build/test --package-path` + `git` are repo-root-relative.
- **OPS-2 — `PommoraTests` is Swift Testing**, so it emits NO `Executed N tests` stdout line. Authoritative count = `xcrun xcresulttool get test-results summary --path <newest .xcresult>` → `totalTestCount`. Clean (parallel-free) app baseline = **1157**.
- **OPS-3 — moving a SwiftPM package root invalidates the `.build` ModuleCache** (`.pcm` bakes absolute paths). On a stale-`.pcm` error, `rm -rf External/MarkdownPM/.build` (gitignored) + rebuild.
- **OPS-4 — the live app-test count drifted 1157 → 1171** because the parallel session's +14 uncommitted tests are compiled by `xcodebuild` (it builds the working tree). Verify against a **worktree-of-HEAD** (parallel-free) for the clean 1157+mine baseline. Gate on "0 failures + my named suites executed (non-zero)", not an absolute count.
- **SILENT-NO-OP — `** TEST SUCCEEDED **` can be a FALSE GREEN** (`totalTestCount: 0`) when xcodebuild reuses a stale `Pommora.app` host without recompiling. Every app-leg run MUST force a recompile (control run / clean) AND confirm `totalTestCount > 0` + the named suites ran.

**Test-harness reality (the biggest mismatch — affects Phases 4-6):**

- The plan (line 2389 + the 3.1.a/3.6.a snippets) assumes the test harness wires `tv.delegate = coordinator` and can drive `textDidChange`. **FALSE** — a delegate-wired coordinator SIGTRAPs the moment a transform/edit fires `performEdit → didChangeText → restyle` on a windowless `NSTextView` (force-unwraps layout infra). So `InputTransformCorpusTests` uses a BARE host, and every parse-count / detection proof uses the **READ-ONLY path** (`parsedDocument(for:)` + direct consumer calls). `syncHeadingFolding` IS harness-safe (its layout guards short-circuit); the edit/restyle path is NOT. **Phases 4-6 must use read-only proofs, never `textDidChange`-driven ones.** `ParseSpineTests.makeCoordinator` is the working read-only harness.

**Tests retired / converted:**

- **`ParseCountProbeTests` (both) DELETED in 3.2** — direct-call premise died when the parse moved to the memo; #9 is now pinned by `ParseSpineTests.unfoldedEditParsesOnce`/`foldedEditParsesOnce`.
- **`dashSkipsInsideClosedCode` + `dashFiresInsideOpenFence` REMOVED from InputTransformCorpus in 3.5** (bare harness can't supply a coordinator post-rewire); replaced by read-only `ParseSpineTests.cacheRoutedCodeBlockCarveOutDetection` (isInsideCode true inside closed code / false in open fence).

**Plan snippet gaps (fixed in-flight):**

- `ParseSpineTests` needs `import SwiftUI`; `TextStylingService.swift` + `StyledRangeCorpusTests.swift` need `import Markdown` — the plan snippets omitted them.
- Task 3.1 touches **3 files** (struct in `NativeTextViewCoordinator.swift`, memo in `+Restyling.swift`), not 2.
- The styler `:30` / folding `:160` "before" snippets in 3.2/3.3 were **pre-2.8** (`Document(parsing:)`); post-2.8 they read `AppleDocumentParseProbe.parse(text)`.
- **3.5.e grep regex is imprecise** — it false-positives on the coordinator's own `isInside*` wrapper signatures; qualify with `MarkdownDetection.` to confirm zero callers of the deleted statics.
- Task 1.2 step-3 grep "no output" conflicts with the plan's own keep-the-filename instruction → 2 benign file-header filename comments remain (`NativeTextViewWrapper.swift`, `MarkdownEditorConfiguration.swift` — files deliberately un-renamed).

**Phase-1 defect caught + fixed by the exit-review workflow (`d5fcbf0`):**

- The plan's Phase-1 exit grep did NOT sweep the package `Tests/` dir, and `git mv` carried a stale `@testable import MarkdownEngine` (R100 rename) → the package TEST target wouldn't compile (hidden because `xcodebuild test -scheme Pommora` never builds the SPM test target). Also swept the 44 file-header `//  MarkdownEngine` → `//  MarkdownPM` the plan asked for but the rename missed. **Lesson:** every gate must compile the package test target (`swift test`), not just `swift build`; `run-tests.sh` (2.1) bakes this in.

**Net gaps the Phase-2 review found + fixed (`3af66bb`):**

- D-HEAD-2 heading sizes were claimed-but-not-pinned → `HeadingSizeCorpus` added (7 tests). The two rule-of-3 emphasis tests were presence-only → tightened to exact ranges (Phase 4's reconstruction target).

**Phase-3 review follow-ups (Phase 3.5):**

- `LineOffsetIndex` is now memoized INTO the spine (`ParsedDocument.lineIndex`, built once via `LineOffsetIndexProbe.make`) alongside the cached Document — the styler + heading-fold reuse one O(n) index build, not one each (preps Phase 4's inline walk).
- The parse-count proof is scoped to the **whole-document spine parse**; per-fragment single-line parses (`isThematicBreakLine` / `isHeadingLine` / `hasBlockquote` / `foldableHeadings(in: String)`) are an accepted, uncounted, cheap residual — NOT routed through any probe.
- New `ParseSpineTests.combinedConsumersShareSingleSpine` pins "2→1" end-to-end: styler + `syncHeadingFolding` off one prime → `AppleDocumentParseProbe.count == 1` AND `LineOffsetIndexProbe.count == 1`.

**Carry-forwards for Phases 4-6:**

- **Phase 4:** width-subtraction reproduces legacy byte-for-byte ONLY for the non-nested cases (`*a*`, `**b**`, `***c***`, intra-word asterisk). The rule-of-3 cases are NOT a reconstruction target — recon proved legacy's overlapping runs (`ruleOfThree_a` bold(0,11)+italic(5,10); `ruleOfThree_b` italic(0,10)+bold(4,11)) cannot exist in Apple's AST (one clean node) → they are re-pinned divergences (D-EMPH-3). Multi-backtick (D-CODE-1) + cross-line (D-EMPH-4) likewise logged. Delete `MarkdownTokenizer+Emphasis.swift` (173 lines) only after the swap commit lands green (parser goes dead first, then a terminal deletion commit).

**Phase-4 recon (probe-verified against swift-markdown 0.8.0, 2026-06-02):**

- **D4.1-a CONFIRMED:** Emphasis/Strong/InlineCode/Link node ranges are **delimiter-inclusive** → width-subtraction is valid (marker width 1=Emphasis, 2=Strong; `content = (loc+w, len−2w)`). Converter to reuse is `SourceRangeConverter.nsRange(from:in:lineIndex:)` (`AppleASTSupplementalStyler.swift:277`), handles multi-line ranges.
- **D4.1-b RULED:** `***c***` → Apple `Emphasis(Strong(Text))`, outer=inner=(0,7). Synthesize a SINGLE `.boldItalic` token (range (0,7), contentRange (3,1), markers [(0,3),(4,3)]) to keep the `boldItalic` pin byte-identical — do NOT emit two overlapping tokens.
- **D4.2-a CONFIRMED:** intra-word underscore suppressed (`snake_case` stays plain); intra-word asterisk emphasized. Pin both.
- **D4.4-a CONFIRMED no-divergence:** Apple emits emphasis inside `$…$` exactly as legacy → status quo, NO action.
- **Links:** inline `[text](url)` is in-scope (Link node, `.destination`); autolink `<url>` is also a Link node but OUT of scope (preserve-as-is); bare URL is plain Text (preserve).
- **Emission seam:** `MarkdownTokenizer.swift:58` (`parseEmphasisTokens(in:)` is the first appended group) is where emission switches legacy→AST. `styleEmphasis` (`MarkdownStyler+TextStyling.swift:50-99`) consumes ONLY `kind`+`contentRange` (OR-merged trait map) — never `markerRanges`/`range` — so the swap is invisible if token shape is preserved.
- **Execution order (re-assessed, differs from plan numbering):** 4.1 build helper (additive, no wire) → swap emission to AST + re-pin corpus (parser goes dead; highest-risk) → terminal deletion of the dead parser → unify heading detectors (D-HEAD-1) → [inline links + multi-backtick DEFERRED, see scope note]. Route emphasis through the cached `parsed.appleDocument`+`lineIndex` (honor #9 single-parse; assert `AppleDocumentParseProbe.count == 1`).
- **Phase-4 scope note (best-judgment re-assessment 2026-06-03 — NATHAN: reverse in minutes if you disagree):** Phase 4 LANDED its load-bearing core — the 173-line hand-rolled emphasis parser is deleted + emphasis locates on the cached AST (4.1/4.2), underscore adopted, intra-word/inside-code/rule-of-3/cross-line re-pinned (D-EMPH-1..4), heading detectors unified (D-HEAD-1). **Inline-code relocation (D-CODE-1) and inline-LINK relocation are DEFERRED** to a future session, for two reasons: (1) `.inlineCode` tokens are bucketed into `codeTokens` (`+Restyling.swift:194`), which `isInsideCodeBlock(range:codeTokens:)` feeds to the dash-transform carve-out (`isInsideCode` in ListHandler/InputHandler/SpellingPolicy), LaTeX/link suppression, and active-token computation — so relocating inline-code ripples a range change (Apple's multi-backtick span is broader) through load-bearing input transforms for an edge case; (2) link regex works and the benefit is marginal. **Neither blocks Phase 5** — the merged styler consumes tokens regardless of source (regex or AST), and the plan already keeps wikilinks/`$…$`/bullets/Setext on regex (a hybrid is the design). Both relocations are isolated, reversible future polish. The rebuild's thesis (remove the parser liability, one cached spine, one owned styler) is fully served without them.
- **Phase 5:** the new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]` FLIPS `HeadingSizeCorpus` (update those goldens + log D-HEAD-2 LANDED). **Preserve checkbox-glyph SUPPRESSION when the caret is on the syntax** (the plan modeled it backwards — `StyledRangeCorpus` pins suppression). The merged styler must keep emitting NOTHING for HR/ThematicBreak (LD-22).
- **Phase 6:** `onCodeBlockSelectionChange` + `onCaretRectChange` are confirmed safe-to-shed (zero app consumers — grep-verified in the 2.9.1 check).
