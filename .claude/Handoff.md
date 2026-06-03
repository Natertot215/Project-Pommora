### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Proven REPEATEDLY across the rebuild: the discipline pays off in commits, not arguments. Verify-first recon caught that Apple's rule-of-3 ranges can't reproduce the legacy parser (re-pin, don't chase); the Phase-4 review caught a REAL visible regression (a literal `*` styled inside `***bold** then italic*`) that 99 green unit tests + a green app gate had all missed; LOOK-before-staging caught the parallel session's date-redesign entry sitting inside `History.md` an instant before it would have been bundled; and integrated-build-verify-before-commit confirmed the parallel feature compiled before it ever touched a green `main`. Every "green" is a fact; every claim is a hypothesis until the code proves it.

#### Session Summary

> **Resume prompt (next session):** *"Both major work streams are SHIPPED + merged to `main` and the tree is integrated-green (1184 tests / 0 failures). (1) The **MarkdownPM rebuild** is complete + merged (fast-forward to `929ef80`): one cached Apple-AST parse spine (#9 fix), the hand-rolled emphasis parser deleted (emphasis on the AST), unified heading detection, one owned `MarkdownPMStyler` + `MarkdownPMTheme`, new heading scale — four review rounds, all findings fixed, full namespace sweep. Canonical record: the Execution Record at the TOP of `Planning/2026-06-02-MarkdownPM-Plan.md` + `Planning/MarkdownPM-Divergence-Ledger.md`. (2) The **parallel date-redesign + View Settings feature** is committed (`c5b9695`). **`main` is 102 commits ahead of `origin/main` (UNPUSHED)** — pushing is the one remaining outward step (awaiting an explicit go). `markdownpm-rehome` is merged (deletable). Next focus: push (if wanted) → the deferred rebuild polish (logged in the Execution Record + ledger) → v0.4.0 (Symbols / Trash / **Wikilinks**, which owns DEC-1 + bundles the deferred Phase-6.6 ContextMenu-unify + flips the `.disabled dec1TargetNoIdOnDisk` anchor)."*

This session executed the finalized MarkdownPM rebuild to completion (Phases 3.5→6 + four adversarial review rounds + the fix batches), reconciled all docs, **merged it to `main`** (fast-forward, no working-tree disturbance), then — once Nathan confirmed the parallel doc + code work was done — committed the parallel session's date-redesign feature after verifying the integrated tree builds green. The rebuild's full arc is recorded in the plan's Execution Record + the divergence ledger + the `History.md` entry; this handoff is the lean post-merge snapshot.

Where it left off: on `main`, working tree clean (only `graphify-out/` tool output left untracked), integrated build green at 1184 tests. `main` is 102 commits ahead of `origin` (unpushed). Nothing is mid-flight.

#### Lessons Learned

- **Parallel agents must not both touch the git index. → candidate CLAUDE.md quirk.** Two concurrent fix-agents (disjoint files, but both staged/committed) raced: one `git restore --staged` the other's in-flight renames, mistaking them for parallel-session work. The final state survived by luck. Fix: serialize index ops, or have parallel agents only Edit while the controller commits.
- **A green test target ≠ correct behavior.** The Phase-4 emphasis swap passed 99 unit tests + a 1166-test app gate and still shipped a visible regression — only an adversarial review running the pipeline against real inputs found it.
- **Manual-visual gates are unavailable autonomously** — renderer color-lift, OS-bug-workaround restructuring, the `onCodeBlockSelectionChange` shed's runtime check. Defer those to a Nathan-present session rather than ship blind; unit/compile-gated work is safe to complete.
- **Verify a shared doc's diff before staging** — `History.md`/`Framework.md`/`PommoraPRD.md`/`CLAUDE.md` carried the parallel session's uncommitted edits; staging blind would have bundled them.
- **Integrated-build-verify before committing held-back work** — the parallel feature was non-compiling for most of the session (worktree strategy routed around it); a build check confirmed it was actually complete (the new `DateTimePicker/` files filled the gaps) before it touched the green `main`.

#### Next Session

1. **Push `main`** (if wanted) — it's 102 commits ahead of `origin/main` (the rebuild + the date-redesign + ~49 earlier unpushed). One `git push origin main`. (Held back per the standing push-only-when-asked rule.)
2. **Deferred MarkdownPM-rebuild polish** — all logged in the plan's Execution Record + ledger: D-CODE-1 multi-backtick inline-code AST relocation; Task 5.4 renderer-color theme-lift (pairs with the v0.4.0 brand palette); Phase-6.1 apply-path DRY; the `[N]` fold-key ordinal hoist; shedding `onCodeBlockSelectionChange`/`onCaretRectChange` (live internal plumbing — needs a runtime check).
3. **v0.4.0 roadmap** — Symbols / Trash / **Wikilinks** + file-watcher + FTS5. Wikilinks owns DEC-1: the structural id-strip lands in the consolidated save path (LD-28), bundles the deferred Phase-6.6 ContextMenu raw-write unification, and flips the `.disabled dec1TargetNoIdOnDisk` anchor green.
4. **Delete `markdownpm-rehome`** — fully merged into `main` (both at `929ef80`); safe to remove whenever.

#### Pending Focuses

- **[merge done — push pending] `main` 102 ahead of `origin`** — push is the only remaining outward action.
- **[deferred — logged] MarkdownPM rebuild polish** (D-CODE-1, Task 5.4, Phase-6.1, `[N]`-hoist, closure-shed) — best-judgment deferrals, each leaves a working system; Nathan to ratify. Detail in the plan Execution Record.
- **[carried] v0.4.0** — Symbols / Settings (Settings Panel moved to v0.6.0 per the date-redesign roadmap edit) / Trash / Wikilinks (owns DEC-1) + file-watcher + FTS5.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
6. **Settings popout sizing** — should size to content dynamically. _(Partially addressed by the date-redesign `ViewSettingsPane` — confirm scope.)_
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; was OUT of the rebuild scope (a feature-add).
9. ~~**Page editor per-caret re-parse glitch**~~ — **FIXED + MERGED** (MarkdownPM rebuild: the #9 cached spine + the Phase-3.5 `LineOffsetIndex` memo + the appearance-restyle cache-reuse). Parse + index are flat at one pass per edit, pinned by `ParseSpineTests`. Runtime/visual confirmation still wants a click-through.
10. **"Add new" footers on views** — adjust to allow a navigation breadcrumb on the left.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **MarkdownPM (SHIPPED, merged) →** `Planning/2026-06-02-MarkdownPM-Plan.md` (top-of-file **Execution Record** = canonical phases/commits/deferrals) · `Planning/MarkdownPM-Divergence-Ledger.md` (D-EMPH-1..7 / D-CODE-1 / D-HEAD-1/2 / #9 + operational corrections) · `Planning/2026-06-02-MarkdownPM-CodeMap.md` · markdown behavior → `Guidelines/Markdown.md` · gate: `External/MarkdownPM/run-tests.sh`.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` (date redesign → `Features/Properties.md`) · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md` · Wikilink spec → `Features/Wiki-Link.md` (wikilink feature + DEC-1 id-guard = the v0.4.0 wikilink session)
