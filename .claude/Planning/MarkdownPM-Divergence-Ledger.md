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
| D-HEAD-2 | Heading size multipliers | shipped `[2.0,1.5,1.17,1.0,0.83,0.67]` (H4=body; H5/H6 below body) — pinned in P2 | new scale `[2.0,1.75,1.5,1.25,1.15,1.0]` (H6=body; no heading below body) | 5 | `HeadingSizeTests` (P5) | ACCEPTED (Nathan 2026-06-02) |
| #9-PARSE | Apple Document parses per edit | 1 unfolded / 2 folded (today) | 1 (cached spine) | 3 | per-edit count pinned by P3 `unfoldedEditParsesOnce`/`foldedEditParsesOnce`; P2 `ParseCountProbeTests` characterize the direct-call count (1 per call / 2 on two passes) | PENDING |

Add rows as new divergences are discovered. **Execution is NON-BLOCKING (Nathan ruling 2026-06-02):** proceed on the best read of Nathan's stated direction, LOG every divergence here (with where it can be adjusted), and surface the full ledger at the END of the rebuild for review — do NOT pause mid-build waiting for a pass. Wherever this plan says "sign-off" / "signed off," read it as *logged + best-judgment + reviewed at the end*, never a blocking gate.
