### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Validated AGAIN this session (Items-as-Markdown EXECUTION): per-task spec+quality reviews + **prove-by-grep** shipped 10 green tasks — but it took a multi-agent **cross-cutting** review to catch the one real bug (a consent-gate × hard-gate composition that would hide Items on a declined adoption preview), which **no single per-task review could see** because the launch entry points were never tested. The cornerstone extends: prove completeness by grep; and a green per-task suite is not a correct WHOLE until the **seams between tasks** are reviewed and the **load-bearing paths actually exercised by a test**, not just code-read.

#### Session Summary

> **Resume prompt (next session):** *"Two fix passes were in flight when we stopped — a `simplify` DRY pass (9 code cleanups incl. a `TierRelationCarrying` protocol) and a doc-fix pass (the `PageTypes` cross-kind error + `Items.md` hard-cap wording + others), both UNCOMMITTED in the working tree. Full-suite-verify the code edits (must stay 1153/1153 — they're behavior-preserving), commit code + docs, then close out: archive the shipped plan to `Planning/Superseded/`. Then push when I say."*

An **execution** session — the prior session was planning. It started with the finalized v5 `Items-as-Markdown-Plan.md` + a kickoff prompt to begin execution via `superpowers:subagent-driven-development`.

- **Shipped the whole Items-as-Markdown paradigm** — 10 code tasks + the cap change, each a reviewed green commit (TDD → background builder per quirk #13 → spec + quality review → prove-by-grep → plan re-assess between commits). Arc `5f2ca3a` (preserving codec) → `0a7b1d7` (Class stamp) → `6cae814` (atomic Items→`.md`) → `b017fff` (contentSniff) → `304c8a0` (`.unsorted`) → `58b041d` (launch stamp pass) → `2f39966` (move carries Class) → `fe93f57` (orphan-sidecar self-heal) → `564d782` (`ItemValidator` save-time, 6 CRUD) → `1029f2c` (auto-run `.json`→`.md` migration) → `ebaeb31` (retire dual-format; `.md`-only hard gate). Full suite **1153/1153**.
- **A multi-agent cross-cutting final review** found 8 distinct findings; the headline must-fix was the **decline-skips-migration seam** (Task 10a placed the migration after the consent gate — fine WITH the dual-format net; Task 10b removing the net made it a hard gate, so a declined preview would hide legacy Items). All 8 fixed in **`4ce2836`** (Task 10c) — migration hoisted to run unconditionally on both launch entry points, twin-detection id-compares before trashing, `.unsorted` relocation feeds `forceRebuild`, stray-`.json` swept to `.unsorted`, rename validation scoped to title-only, reload uses `loadLenient` — plus the first integration test of the launch/decline path. Re-review: **ship-ready**.
- **Task 11 docs** reconciled across 18 docs + **registry #14 registered** (Nathan-confirmed; History logged first) + `Planning/README.md` created (`efdf0c1`, `2c09659`). Committed Nathan's parallel-session `CLAUDE.md`/`Handoff.md` edits at his direction (`f1f22b3`).
- **Nathan's voice / load-bearing inputs:** *"All agents MUST use opus"*; *"lets work with an 1000char cap for now"* (→ provisional cap, the reason he edited CLAUDE.md); *"give that to a subagent; don't bloat your context window with that"* (→ delegate file edits); *"don't defer anything that can be fixed now"*; *"docs should check for prose; not just grep."* He also strengthened the cornerstone himself (LOOK + ASK; earned-through-evidence).
- **Where it left off:** clean HEAD `2c09659`. Working tree **dirty** with two uncommitted, not-yet-verified fix passes: the `simplify` code cleanups (`Filesystem`, `ItemFrontmatter`, `KindStamp`, `PageFrontmatter`, `ItemWindow`, `ItemFormatMigration`, `PropertyIDMigration`) and the doc-fix (`Architecture`, `Items`, `PageTypes`, `Properties`, `Prospects`, `PommoraPRD`). Immediate next action: full-suite-verify the code edits, then commit code + docs. (Unattributed `project.pbxproj` + untracked `Wiki-Link.md` / `graphify-out/` left untouched all run per quirk #10.)

#### Lessons Learned

- **A cross-cutting review catches what per-task reviews structurally cannot.** Each task passed its own spec+quality gate; the real bug lived only in the *composition* of two green tasks. Budget a whole-implementation review at the end of any multi-task refactor.
- **Untested private launch paths hide composition bugs.** The same-launch index guarantee was only ever code-read; no test drove `runAdoptionIfNeeded`/`openExisting`. That gap is exactly why the must-fix escaped. → exercise load-bearing private entry points with at least one integration test.
- **Wiring previously-dead code surfaces its latent bugs.** Going live with `ItemValidator` exposed a `validateType` gap (valid `.status`/`.file` values rejected); the auto-run migration exposed the consent-gate placement. Audit dead code's internals before you make it live.
- **Doc-generation agents can INVENT behavior.** The Task 11 pass wrote a "cross-kind Item↔Page move re-stamps Class" rule that doesn't exist. → verify docs against the CODE, and read PROSE for meaning, not just grep for stale tokens.
- **A guard that can't fail is worse than none.** The launch-join integration assertion was a tautology (fresh index rebuilt off `needsRebuild` regardless of the flag); confirm a test would actually FAIL if the fix regressed.

#### Next Session

1. **Land the two in-flight fix passes.** Full-suite-verify the `simplify` code edits — must stay **1153/1153**, behavior-preserving (highest-risk: the `TierRelationCarrying` protocol across `Item`/`ItemFrontmatter`/`PageFrontmatter`/`AgendaTask`/`AgendaEvent`). If green, commit the code simplifications + commit the doc-fix; if red, triage the specific regression. First commit: `refactor(items): DRY/simplify cleanups (simplify pass)`.
2. **Close out the run.** Archive the shipped plan `Planning/2026-06-01-Items-as-Markdown-Plan.md` → `Planning/Superseded/`, move its `Planning/README.md` entry Active→Superseded, fix any doc-map pointer that referenced its old path. Then **push to `main` when Nathan asks**; optionally re-run the docs mirror to The Nexus (the `.claude` docs changed substantially).
3. **v0.4.0 roadmap** (when the above lands) — Symbols / Settings / Trash / Wikilinks + file-watcher + FTS5.

#### Pending Focuses

- **[carried 06-01]** Nathan's one-time **live deletion of the 12 stray `_pagecollection.json` sidecars** in The Nexus — the Task-8 code fix prevents recurrence; the existing strays are his manual cleanup.
- **[new] Two launch-path perf optimizations** the simplify pass flagged but I did NOT apply (risk > marginal small-nexus gain): collapse `autoTagMissingSidecars`'s redundant per-folder walks (two `childFolders` + two `descendantFiles` subtree traversals) into one of each; and a steady-state short-circuit so a fully-migrated nexus doesn't triple-walk Type folders across PropertyIDMigration + autoTag-sweep + ItemFormatMigration every launch. Revisit if launch latency matters at scale. (Also noted-not-applied DRY niceties: `Item.stableHash` vs `PageFile.shortHash` one shared hash; a single module-level `isItemFile` predicate for the ~11 inline copies.)
- **[gated]** The **"retire legacy-Item-JSON migration machinery"** cleanup (captured in `Prospects.md`) — fires once every nexus has run the `.json`→`.md` migration (no `.json` Items remain): drop `ItemFormatMigration`, `Item.decodeLegacyJSON`, the legacy `Item` `CodingKeys`, and `PropertyIDMigration`'s dual member enumerator.
- **[carried]** v0.4.0 kickoff (Symbols / Settings / Trash / Wikilinks + file-watcher + FTS5; a parallel session was on Wikilinks).
- **[carried 05-31]** Live smoke (Nathan's manual): vault/type tables display-only + mirror sidebar; collection/set reorder; relation `type_id` reconcile; relation Mirror name/icon propagation; Edit Icon from popover/sidebar/detail-table.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns* (distinct from rows); folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels; hide it or route to the View Settings editor.
6. **Settings popout sizing** — should size to content dynamically (Nathan likes the min height).
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — the error's doc says events have no `_status`, yet the delete guard still blocks it; decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax (not just the render); also render bullets as label + secondary rather than primary.
9. **Page editor per-caret re-parse is significantly glitchy** — re-parse / adjustment on each caret move; must fix asap.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Planning →** `Planning/2026-06-01-Items-as-Markdown-Plan.md` (the v5 plan — SHIPPED this session; to be archived to `Planning/Superseded/`) · `Planning/2026-06-01-Architecture-Skeptic-Review.md` (the seed review; rec #3 superseded) · `Planning/2026-05-31-vault-table-displayonly-interim.md`. Note: `Planning/Pommora-Wikilink.md` + `Features/Wiki-Link.md` are a parallel session's wikilink work — left untouched (quirk #10).
- Roadmap → `Framework.md` · decisions + ship log → `History.md` (Items-as-Markdown logged 2026-06-02) · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` (**#14 Items-are-Markdown registered**)
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
