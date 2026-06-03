### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Extended (prior session): **a gate answer of "execute" is NOT a license to auto-start building.** Nathan stopped an auto-start TWICE; "continue"/"execute"/"one session" set direction, they are not the trigger. Run NO build/rename/execution step until Nathan gives an explicit, unambiguous "go." (This session DID receive that go — "You may execute.")
>
> Proven again this session: **the discipline pays off in commits, not arguments.** The Phase-1 exit-review workflow caught a build-breaking straggler the green build couldn't see; the characterization net caught **three** places the plan author's model of *current* behavior was wrong (checkbox caret-reveal direction, arrow-completion timing, open-fence ≠ code) — each pinned to reality instead of fiction because implementers LOOKED and reported mismatches rather than transcribing.

#### Session Summary

> **Resume prompt (next session — the MarkdownPM rebuild is MID-EXECUTION on branch `markdownpm-rehome`, NOT `main`):**
>
> *"The MarkdownPM rebuild is ~half done on branch `markdownpm-rehome`. Plan: `Planning/2026-06-02-MarkdownPM-Plan.md`; CodeMap (file:line ground truth): `Planning/2026-06-02-MarkdownPM-CodeMap.md`; **divergence ledger: `Planning/MarkdownPM-Divergence-Ledger.md` — READ its 'Operational corrections + plan mismatches' section FIRST; it lists every plan mismatch to apply when updating the plan.***
>
> ***DONE (all package-leg green; package suite = 9 suites / 84 tests, 0 failures):*** *Phase 1 (re-home `MarkdownEngine`→`MarkdownPM`: `f586927` rename · `3223ca3` re-home · `f7de7a6` docs · `d5fcbf0` straggler purge). Phase 2 (characterization net + `run-tests.sh` gate + ledger: `3d6a855` `c511a80` `8d2621f` `d1c0822` `6237a63` `341ce43` `fe95038` `3af66bb`). Phase 3 — the #9 caret-stutter fix, COMPLETE (`1f2b4fb` spine field · `f92f424` styler reads cache · `de2027b` folding reads cache · `e146204` dead-code · `53abf80` rewire isInside* · `303bb6c` #9 assertion). `Document(parsing:)` now runs once per edit, fold or no fold.*
>
> ***EXECUTION MODEL:*** *subagent-driven — one OPUS implementer per task (it reads its own plan section + a controller scene-setting wrapper); verify package leg with `swift test --package-path "External/MarkdownPM" -Xswiftc -sdk -Xswiftc "$(xcrun --sdk macosx --show-sdk-path)"`; verify app leg via a BACKGROUND `builder` Agent running `xcodebuild` from `<repo>/Pommora` (quirk #13, no focus grab); review via condensed Workflows. **CURATE-STAGE every commit by explicit path — NEVER `git add -A`** (~30 parallel-session files in the tree).*
>
> ***THE BLOCKER + WORKAROUND (critical):*** *the parallel session (date/datetime property redesign) is PARKED until this entire plan is done, but it left the app target NON-COMPILABLE — its uncommitted `DesignSystem/DateTimePicker/DateTimePicker.swift` references a missing `MonthStepControl` (earlier it was `DateTimePickerMetrics`; it rolls). So `xcodebuild test` can't build the app. **Verify the app leg via a throwaway `git worktree add /tmp/mpm-verify markdownpm-rehome`** — a clean checkout of HEAD that EXCLUDES the parallel session's uncommitted breakage, so the app compiles and gives the clean parallel-free baseline (1157 + my additions). Build/test there, then `git worktree remove /tmp/mpm-verify`. This respects "no isolation — main" (it's a verification worktree, not where work happens). NEVER touch/stash/revert the parallel session's working-tree changes (LD-32 / quirk #10).*
>
> ***DO FIRST next session — the DEFERRED Phase-2 app-side work (via the worktree):*** *3 app-side suites are WRITTEN + source-verified but UNCOMMITTED in the working tree: `Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift` (appended cases), `WikiLinkOnDiskGuardTests.swift` (new — DEC-1 honest anchor + a `.disabled` target), `MarkdownPMPublicContractTests.swift` (new). Commit them (curate-staged), then verify the both-legs gate IN THE WORKTREE: force a recompile + check `totalTestCount` (a bare `** TEST SUCCEEDED **` is a false-green trap on a stale host). Suite names: `FoldableHeadings`, `WikiLinkOnDiskGuard`, `MarkdownPMPublicContract`. Green there = Phase-2 exit gate CLOSED.*
>
> ***THEN Phases 4→6 (OUTLINE-level in the plan — expand each task to bite-sized + re-assess against what Phase 3 landed BEFORE dispatching):*** *Phase 4 — inline locating on the Apple AST: delete the 173-line `MarkdownTokenizer+Emphasis.swift`, adopt Apple emphasis + underscore (D-EMPH-1/2), unify the two heading detectors (D-HEAD-1); rule-of-3 exact ranges are the reconstruction target; add a multi-backtick divergence row; USE READ-ONLY PROOFS (the harness is bare — `textDidChange` SIGTRAPs). Phase 5 — one owned `MarkdownPMStyler` + `MarkdownPMTheme`; apply the new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]` (flips `HeadingSizeCorpus`, D-HEAD-2); PRESERVE checkbox-glyph SUPPRESSION-when-active (plan had it backwards); styler emits NOTHING for HR (LD-22). Phase 6 — body tidy + verbatim transplant of runtime workarounds + shed `onCodeBlockSelectionChange`/`onCaretRectChange` (confirmed zero app consumers).*
>
> ***THEN the closing scope Nathan added:*** *a final adversarial review workflow, UPDATE THE PLAN to match reality (apply every ledger 'Operational corrections' item), docs cleanup, and the final handoff. The parallel session resumes ONLY after ALL of that is done. A Phase-3 adversarial review is also recommended (the #9 fix is behavior-adjacent)."*

This session **executed** the finalized MarkdownPM plan through Phase 3, on Nathan's explicit "You may execute," under three standing directives: delegate every task to OPUS agents, use Workflows for review, protect the controller's context. Phase 1 (mechanical re-home) shipped in 5 commits — its adversarial exit-review caught a build-breaker the green build masked. Phase 2 built the characterization net (9 suites) that gates all behavior change; its review found + fixed two coverage gaps (unpinned heading sizes; presence-only rule-of-3). Phase 3 collapsed the dual uncached Apple parses into one cached spine — the #9 fix — proven by read-only parse-count assertions reading 1 in both fold states, every Phase-2 snapshot byte-identical.

The defining friction was the **parallel session** sharing the working tree: mid-session it edited its `DateTimePicker` feature into repeated non-compiling states, blocking every `xcodebuild` app-leg run. Nathan **parked** it until this plan is complete — but its broken changes stay frozen-uncommitted. The resolution is the **verification-worktree** strategy (above): my work is all committed; a worktree of HEAD is parallel-free and compiles. The 3 Phase-2 app-side suites are written + triple-verified-by-inspection but held uncommitted pending that worktree run, so no xcodebuild-unverified test is ever committed.

Where it left off: Phase 3 just committed (`303bb6c`); package leg green at 84 tests; on `markdownpm-rehome`; the 3 app-side suites uncommitted; the parallel session's edits untouched. Nathan asked for this handoff to compact + resume fresh.

#### Lessons Learned

- **A green build ≠ a green *test target*.** `xcodebuild test -scheme Pommora` never compiles the SPM package test target — a stale `@testable import MarkdownEngine` lived there invisibly until the review forced `swift test`. Every gate runs BOTH legs (`run-tests.sh`). **→ candidate CLAUDE.md quirk.**
- **`** TEST SUCCEEDED **` can be a silent no-op** (`totalTestCount: 0`) on a stale `Pommora.app` host that didn't recompile. Force a recompile + verify non-zero count + that the named suites ran. **→ candidate CLAUDE.md quirk.**
- **The unit harness can't drive edits.** A coordinator wired as an NSTextView delegate SIGTRAPs on `textDidChange/performEdit` (windowless layout force-unwrap). Parse-count + detection proofs use the **read-only** path (`parsedDocument(for:)` + direct consumer calls). `syncHeadingFolding` is the one edit-adjacent method that survives the bare harness.
- **A parked parallel session's break is routed around, never fixed by me** — verify against a worktree of committed HEAD (parallel-free); never stash/revert their uncommitted work.
- **Characterization pins reality, not the plan's claims** — the net corrected the checkbox-reveal direction, arrow-completion timing, and open-fence-≠-code. Carry the checkbox-suppression + rule-of-3-exact-ranges facts into Phases 4/5.

#### Next Session

1. **Close Phase 2's app leg via the worktree.** Commit the 3 app-side suites, `git worktree add /tmp/mpm-verify markdownpm-rehome`, run the both-legs gate there (force recompile + `totalTestCount`), confirm `FoldableHeadings`/`WikiLinkOnDiskGuard`/`MarkdownPMPublicContract` execute green at the clean 1157+additions baseline, then remove the worktree.
2. **(Recommended) Phase-3 adversarial review workflow** before Phase 4.
3. **Phase 4 → 5 → 6**, expanding each outline task to bite-sized first (re-assess against Phase 3). Read-only proofs only.
4. **Final review workflow + update the plan** for every ledger "Operational corrections" item + docs cleanup + final handoff (parallel session resumes only after all of this).

#### Pending Focuses

- **[active] MarkdownPM rebuild — Phases 1-3 shipped (package-leg green); Phase-2 app leg + Phases 4-6 + plan-update + docs remain.** Branch `markdownpm-rehome`.
- **[blocked-on-worktree] 3 Phase-2 app-side suites** written + uncommitted; verify + commit via the verification worktree.
- **[Nathan directive] Update the plan to match reality** — apply the ledger's Operational-corrections section. Part of the closing scope.
- **[carried] Push `main`** — the planning arc is committed but unpushed; the rebuild branch is unmerged.
- **[carried] v0.4.0 roadmap** — Symbols / Settings / Trash / **Wikilinks** (owns DEC-1's structural id-guard — the `.disabled dec1TargetNoIdOnDisk` anchor flips green then) + file-watcher + FTS5.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
6. **Settings popout sizing** — should size to content dynamically.
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; OUT of the rebuild scope (a feature-add).
9. ~~**Page editor per-caret re-parse glitch**~~ — **FIXED by the MarkdownPM rebuild Phase 3** (`303bb6c`): the supplemental styler + folding now read one cached Apple parse instead of re-parsing every keystroke; parse count is flat at 1 per edit, fold or no fold. (Runtime/visual confirmation pending the app-leg worktree run.)

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Rebuild →** `Planning/2026-06-02-MarkdownPM-Plan.md` (the plan, branch `markdownpm-rehome`) · `Planning/2026-06-02-MarkdownPM-CodeMap.md` (verified file:line map) · `Planning/MarkdownPM-Divergence-Ledger.md` (behavior divergences + **operational corrections / plan mismatches**) · gate: `External/MarkdownPM/run-tests.sh`.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` (#7 reconciled to MarkdownPM-owned in `f7de7a6`)
- Branch quirks + hard rules → `CLAUDE.md` · Wikilink spec → `Features/Wiki-Link.md` (wikilink feature + DEC-1 id-guard = separate post-rebuild session)
