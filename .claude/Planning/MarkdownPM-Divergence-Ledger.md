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

**Carry-forwards for Phases 4-6:**

- **Phase 4:** the rule-of-3 exact ranges (`ruleOfThree_a`: bold(0,11)+italic(5,10); `ruleOfThree_b`: italic(0,10)+bold(4,11)) are the width-subtraction reconstruction target. Add a **multi-backtick inline-code divergence row** when Phase 4 moves inline-code locating to the Apple AST (Apple's range includes the backticks). Delete `MarkdownTokenizer+Emphasis.swift` (173 lines) only behind a green adversarial emphasis corpus.
- **Phase 5:** the new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]` FLIPS `HeadingSizeCorpus` (update those goldens + log D-HEAD-2 LANDED). **Preserve checkbox-glyph SUPPRESSION when the caret is on the syntax** (the plan modeled it backwards — `StyledRangeCorpus` pins suppression). The merged styler must keep emitting NOTHING for HR/ThematicBreak (LD-22).
- **Phase 6:** `onCodeBlockSelectionChange` + `onCaretRectChange` are confirmed safe-to-shed (zero app consumers — grep-verified in the 2.9.1 check).
