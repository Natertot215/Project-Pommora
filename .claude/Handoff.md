### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Proven REPEATEDLY this rebuild: the discipline pays off in commits, not arguments. Verify-first recon caught that Apple's rule-of-3 ranges can't reproduce the legacy parser (re-pin, don't chase). The Phase-4 exit-review caught a REAL visible regression (a literal `*` styled inside `***bold** then italic*`) that 99 green unit tests + a green app gate had all missed. And LOOK-before-staging caught the parallel session's date-redesign entry sitting inside `History.md` an instant before it would have been bundled into a rebuild commit. Every "green" is a fact; every claim is a hypothesis until the code proves it.

#### Session Summary

> **Resume prompt (next session):** *"The MarkdownPM rebuild is COMPLETE on branch `markdownpm-rehome` (48 commits, unmerged) and fully green — package 119 tests / 10 suites, app 1166 tests / 0 failures (1 expected skip), verified in a parallel-free worktree. The plan's top-of-file 'Execution Record' (`Planning/2026-06-02-MarkdownPM-Plan.md`) + the divergence ledger (`Planning/MarkdownPM-Divergence-Ledger.md`, rows D-EMPH-1..7 / D-CODE-1 / D-HEAD-1/2 / #9-PARSE) are the canonical record. The immediate next moves: (1) **merge `markdownpm-rehome` → `main`** (it's complete + green); (2) only AFTER merge can the parked parallel session safely resume; (3) the parallel-CONTAMINATED docs cleanup (the `History.md` rebuild entry, `Framework.md`, `PommoraPRD.md`) was deferred because those files carry the parallel session's uncommitted date-redesign edits — finish them once the parallel work commits. Then the deferred polish + the wikilink/DEC-1 session (see Pending Focuses)."*

This session **executed the entire MarkdownPM rebuild to completion** on Nathan's "continue post-compact … see you when it's done" — autonomous, OPUS subagents per task, Workflows for every review, the controller protecting its own context. It started at the Phase-3 checkpoint (`303bb6c`) and drove through Phases 3.5→6 + a full closing pass.

**What shipped (branch `markdownpm-rehome`, ~48 commits, all green at each gate):** Phase-2 app leg closed (`4889447`); **Phase 3.5** memoized `LineOffsetIndex` into the cached spine after the Phase-3 review flagged a per-consumer rebuild (`7b42aca` `7704b94`); **Phase 4** built `appleEmphasisTokens` on the Apple AST, swapped emission + re-pinned the corpus, **deleted the 173-line hand-rolled emphasis parser**, unified the two heading detectors (`0912831` `361bd20` `1bc0c30` `d74ce0f`), then the exit-review fixes — robust nested-adjacent marker reconstruction (`20fcfbc`), wikilink emphasis suppression (`23eb7ae`), the 3-space heading-indent bound (`818aa3a`); **Phase 5** collapsed the two styler sites into one owned `MarkdownPMStyler`, renamed the theme to `MarkdownPMTheme` (one navigable file), applied the new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]`, added the code-text slot, and DRY'd the caret reads (`e79421c` `3701e92` `c725036` `b399021` `a9a2fd2` `8d9505c`); **Phase 6** shipped the safe tidy — deleted the dead `taskListRegex` + dead input-handler fallbacks (`63bec06` `28cb171`). The closing pass added the plan Execution Record (`fd94d07`), reconciled `Guidelines/Markdown.md` (`c19e94b`), and applied the final-review fixes (`def9213` `a75d7ca` `f7c93ee` `b026953` `54ef31f` `1a8556d`): D-EMPH-6 marker-shrink completion, spine cache-reuse on appearance-change, the extension-file + `MarkdownEditorServices` renames, the D-EMPH-7 ledger row, NOTICE.md as-built rewrite.

**The method that worked:** verify-first recon before each behavior-touching phase (probe the real swift-markdown 0.8.0 behavior, LOOK at the legacy oracle, then build); a per-phase adversarial review Workflow (Phase 3/4/5 + a final whole-branch one) that caught what green tests couldn't; the worktree-of-HEAD app-leg gate to stay parallel-free; re-assessing the plan between green commits (Phase 4 re-ordered, Phase 6 mostly found already-done or load-bearing-keep). The reviews found **real** issues at every behavior phase and the controller fixed them before stacking the next.

**Where it left off:** the rebuild is COMPLETE + green; the working tree's package side is clean; `Handoff.md` rewritten (this file). The ONE friction throughout was the parked parallel session (date/datetime property + ViewSettings redesign) sharing the working tree — its uncommitted edits live in app-side files + several `.claude/*` docs (`History.md`, `Framework.md`, `PommoraPRD.md`, `Domain-Model.md`, `Pages.md`, `Properties.md`, `Prospects.md`, `Design.md`, `Guidelines/README.md`, and a `Handoff.md` Fix-Log line). Every commit was curate-staged by explicit path; not one parallel file was staged, reverted, or discarded.

#### Lessons Learned

- **A green test target ≠ correct behavior.** The Phase-4 emphasis swap passed 99 unit tests + a 1166-test app gate and still shipped a visible regression (a literal `*` styled inside nested-adjacent emphasis). Only an adversarial review that *ran the pipeline against real inputs* found it. Adversarial review after every behavior change is non-negotiable.
- **Parallel implementers must not both touch the git index. → candidate CLAUDE.md quirk.** Two concurrent fix-agents (disjoint *files*, but both staged/committed) raced: one `git restore --staged` the other's in-flight renames, mistaking them for parallel-session work. The final state survived by luck. Fix: serialize index ops, or have parallel agents only Edit while the controller commits.
- **Manual-visual gates are unavailable autonomously.** Tasks gated only by clicking through the live editor (renderer color-lift 5.4, the OS-bug-workaround transplant 6.5, the `onCodeBlockSelectionChange`/`onCaretRectChange` shed's runtime check) can't be verified without a UI — defer them to a Nathan-present session rather than ship blind. Unit/compile-gated work is safe to complete.
- **The plan is a hypothesis; the recon is the verification.** Phase-6 recon found most of the planned "tidy" was already done (Phase 3 did 6.4's substance; 6.2's HR predicate is already shared) or load-bearing-keep. Re-assessing between green commits prevented churn-for-churn's-sake.
- **Shared docs carry parallel contamination.** `History.md`/`Framework.md`/`PommoraPRD.md` (and a `Handoff.md` Fix-Log line) hold the parallel session's uncommitted edits — editing+staging them would bundle that work. The clean-doc cleanups shipped; the contaminated ones deferred. ALWAYS diff a shared doc before staging.

#### Next Session

1. **Merge `markdownpm-rehome` → `main`.** The rebuild is complete + green (package 119, app 1166/0-fail, verified parallel-free). This is the gating step — nothing else (incl. the parallel session) should resume until it merges.
2. **THEN the parked parallel session may resume** (date/datetime property + ViewSettings redesign). Its uncommitted work stays untouched on the branch.
3. ~~Finish the parallel-contaminated docs cleanup~~ — **DONE** (`e4dd5aa`): the `History.md` rebuild entry + `Framework.md` / `PommoraPRD.md` / `CLAUDE.md` stale-ref reconciliation landed on top of the (now-done) parallel doc work, committed together with the parallel session's date-redesign docs. Parallel CODE (DateTimePicker / PUI / ViewSettings / etc.) remains uncommitted.
4. **The wikilink / DEC-1 session** (separate, post-rebuild): build the structural id-strip in the consolidated save path (LD-28), enable the `.disabled dec1TargetNoIdOnDisk` anchor, and bundle Phase-6.6 (ContextMenu save-path unification) with it.

#### Pending Focuses

- **[merge-ready] `markdownpm-rehome` → `main`** — 48 commits, complete + green; unmerged. The parallel session resumes only after this.
- **[done `e4dd5aa`] Docs cleanup for `History.md` / `Framework.md` / `PommoraPRD.md` / `CLAUDE.md`** — the rebuild-reference reconciliation landed on top of the parallel session's (now-done) date-redesign docs, all committed together. Parallel CODE stays uncommitted.
- **[deferred — best-judgment, Nathan to ratify; all logged in the plan's Execution Record + ledger] rebuild polish:** D-CODE-1 multi-backtick inline-code AST relocation (ripples the `codeTokens` bucket); Task 5.4 renderer-color theme-lift (manual-visual; pairs with the v0.4.0 brand palette); Phase-6.1 apply-path DRY (load-bearing-distinct loops); Phase-6.2 HR Stage-0 unification (predicate already shared); Phase-6.6 ContextMenu unify (→ wikilink/DEC-1 session); the `[N]` fold-key ordinal hoist (byte-sensitive; needs a cross-site key-equality test first); shedding `onCodeBlockSelectionChange`/`onCaretRectChange` (live internal plumbing — needs a runtime check).
- **[carried] v0.4.0 roadmap** — Symbols / Settings / Trash / **Wikilinks** (owns DEC-1) + file-watcher + FTS5.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
6. **Settings popout sizing** — should size to content dynamically.
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; OUT of the rebuild scope (a feature-add).
9. ~~**Page editor per-caret re-parse glitch**~~ — **FIXED by the MarkdownPM rebuild** (Phase 3 `303bb6c` + the Phase-3.5 `LineOffsetIndex` memo + the Phase-4.fix appearance-change cache-reuse `f7c93ee`): the supplemental styler + folding + emphasis now read ONE cached Apple parse + line index per edit. Proven by `ParseSpineTests` (read-only). Runtime/visual confirmation still pending a Nathan-present click-through.
10. Adjust the "add new" footers on views to allow for navigation breadcrumb on the left. _(parallel-session entry — preserved, not authored this session)_

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Rebuild (COMPLETE) →** `Planning/2026-06-02-MarkdownPM-Plan.md` (top-of-file **Execution Record** = canonical phases/commits/deferrals) · `Planning/2026-06-02-MarkdownPM-CodeMap.md` (verified file:line map) · `Planning/MarkdownPM-Divergence-Ledger.md` (divergences D-EMPH-1..7 / D-CODE-1 / D-HEAD-1/2 / #9 + operational corrections) · gate: `External/MarkdownPM/run-tests.sh`.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · markdown behavior → `Guidelines/Markdown.md` (reconciled to MarkdownPM)
- Branch quirks + hard rules → `CLAUDE.md` · Wikilink spec → `Features/Wiki-Link.md` (wikilink feature + DEC-1 id-guard = separate post-rebuild session)
