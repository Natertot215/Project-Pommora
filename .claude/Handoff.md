### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Validated AGAIN this session (MarkdownPM rebuild PLANNING): the whole plan rested on one linchpin — "Apple's `swift-markdown` AST can replace our hand-written parser." Research-verified against the library's actual SOURCE (not its reputation) revealed Apple gives only a whole-construct range with NO delimiter positions — so marker hide-ranges must be *reconstructed by math*. Knowing that BEFORE committing reshaped the plan. The v→vN verification loop then caught 11 precision defects in plan v1 (wrong param counts, an over-broad deletion that would have killed a live transform, stale cross-doc contradictions) a builder would have trusted. The cornerstone now extends to PLANS, not just code: verify the linchpin against the dependency's source; run the plan itself through adversarial rounds until zero claims are unproven.

#### Session Summary

> **Resume prompt (next session):** *"We're mid-planning the **MarkdownPM** engine rebuild — NOT executing yet. Plan **v2** is committed at `Planning/2026-06-02-MarkdownPM-Service.md`; the 26-decision surface + locked rulings at `Planning/2026-06-02-MarkdownPM-Decisions.md`. **Round-2 verification came back NEEDS-V3 — but ALL doc-precision** (it independently verified the architecture + every ruling + all 11 round-1 fixes as SOUND; "a v3 doc-sync pass closes them"). Apply the 8 fixes below → **v3**, run a **round-3** to confirm bulletproof, then execute Phase 1→6 via `superpowers:subagent-driven-development`. Round-2's full spec (file:line per fix) is in task `wt2nz0oqw`'s output.*
>
> ***The 8 v3 fixes:*** *F12 (major) sync Decisions-doc D20 "14 params"→"15" (lines 232/238/293). F13 (major) Phase-4 "mixed-file" note: `MarkdownTokenizer.swift` ALSO hosts keep-verbatim items (`isInlineMathContent` thresholds 120/40/6, the heading regex) — only the emphasis-integration call (parseTokens:58) is in scope; pin the math thresholds in the Phase-2 corpus BEFORE Phase 4. F14 D1 guard test must name BOTH write paths (`+TextDelegate.swift:61` + `+Services.swift:325`). F15 sub-struct count → descriptive ("16 config sub-structs + merged theme", not "17"/"18"). F16 drop the stale "fix Markdown.md path in CLAUDE.md" Phase-1 clause (no longer exists post-restructure). F17 reword "`.pommoraThematicBreak` tombstone"→"historical-note comment :21-28" (+ fix `Markdown.md` §6.1:208 to match). F18 reword "11 isInside*"→"10 token-based + `isInsideWikilink` stays separate (F2)". F19 fix citation `:219`→`:230-231` (149pt guard). **DEC-1 (the one open call):** structural lock vs test-only for "no hidden id ever reaches disk" — REC the structural lock (aligns with your "nothing slips"); confirm with Nathan. Commit v3."*

A **planning** session for the next big build. Opened intending to push `main` + start v0.4.0 (the prior handoff's plan), but Nathan redirected into "what should we build next?" → which became a deep, multi-workflow design of the **MarkdownPM** markdown-engine rebuild. No production code shipped this session — it's all investigation + planning.

- **Stray-sidecar close-out (`e36e8b4`).** Cleaned 4 stray `_pagecollection.json` from The Nexus vault, root-caused the auto-tagger-vs-self-heal mechanism (the auto-tagger *adds* a sidecar to any untagged Vault sub-folder; Task-8's self-heal only *removes* duplicates — so it never "prevented" the doc-mirror strays), and corrected the Handoff's false "Task-8 prevents recurrence" claim. The docs-mirror script now gitignores `graphify-out/` + excludes `worktrees/`.
- **"What to build next" multi-perspective workflow** (5 lenses + synthesis, against a refreshed 16,140-node graph) ranked the **page-editor per-caret glitch (Fix Log #9)** #1.
- **Nathan pivoted to rebuilding the markdown engine.** A cascade of evidence-gathering followed (all in `/private/tmp/.../tasks/` if needed): engine-rebuild decision investigation → verdict **rebuild-brain / keep-body** (a full rewrite rejected by all 5 lenses incl. the steelman); Nathan's redirect to **map-then-rebuild**; an exhaustive engine map → rebuild blueprint; then Nathan's decision: **MarkdownPM** — fold the vendored engine into a Pommora-owned package, consolidate the brain onto one Apple-AST parse, own the styling + dynamic-syntax, keep the working body, **Pages-only**.
- **Brainstorm → 26-decision surface → Nathan's rulings** (all in `Planning/2026-06-02-MarkdownPM-Decisions.md`). **Plan v1** written → **round-1 verify** (6 agents incl. swift-markdown research) → **needs-v2**: approach verified *sound*, 11 must-fixes, the linchpin nuance (marker reconstruction). **Obsidian-compat research** (spec confirmed accurate + 3 precisions) + **adopt-and-improve research** (5 lenses) → the **construct-by-construct parser scope**: emphasis/inline-code/links → Apple's AST; headings split (fold=AST, markers=regex); wikilinks/embeds/math/bullets/checkbox/Setext stay regex. **Plan v2** written folding all of it → **round-2 verification running** (`wt2nz0oqw`).
- **Nathan's voice / load-bearing inputs:** *"we're not reinventing the wheel, we're taking it apart and putting it back together cleaner, simpler, and better"* · *"Opus 4.8 didn't write THEIR shit"* (donor code isn't sacred — own + improve it) · *"our system should own styling"* + *"our dynamic-syntax should stay, learn from what's implemented"* · *"resolve by ID, not location"* (wikilinks; reject Obsidian path-qualification) · *"Items should be EXCLUDED"* (`@`-tagging is a separate future feature) · *"NO #9 fix now — it comes naturally through the rebuild"* · *"testing and quality needs to be tight, nothing slips through the cracks"* · *"no limit on question number"* · *"use research agents to combat our own approaches with simpler / Apple-provided ones."*
- **Where it left off:** plan **v2** committed; **round-2 verification returned NEEDS-V3** (8 doc-precision fixes F12–F19 + one open decision DEC-1 — all in the resume prompt; architecture + rulings verified SOUND). Next: apply the 8 fixes → v3 → round-3 confirmation → execute. Uncommitted: `CLAUDE.md` only (Nathan's intentional edits — leave). No production code touched; `Pommora/*` untouched all session.

#### Lessons Learned

- **Adopt + improve — not reinvent, not preserve-verbatim.** The rebuild-trap (re-deriving spec-irreproducible OS-bug workarounds) is avoided by mapping first; the verbatim-trap (keeping donor cruft we don't understand) is avoided by a tight test net that makes improvement *safe*. The donor code isn't sacred — but its load-bearing *runtime-only* behavior is (FB-radar caret/Writing-Tools quirks → keep-verbatim + manual-verify, no unit test can catch them).
- **Research challenging our OWN approaches resolves scope decisions empirically.** Rather than guess "keep ours vs use Apple's," agents attacked each construct against `swift-markdown`/TextKit — the evidence drew the line (Apple for the 3 inline constructs where it's clean; regex stays everywhere Apple is absent or wrong, e.g. empty-`[]` checkbox, wikilinks).
- **Verify the linchpin against the dependency's SOURCE.** "Apple's AST can replace the parser" was true for *locating* but not for *marker positions* (whole-construct range only) — discovered by reading `swift-markdown`'s source, not assuming. Reshaped the plan into a "reconstruct markers by width-subtraction" sub-task.
- **The v→vN loop is the cornerstone applied to the PLAN.** Round-1 caught 11 defects a builder would have trusted (a wildcard deletion that would've killed the en-dash transform; "6 extensions" that don't exist; stale `NOTICE.md` specifying overruled names). Plans get adversarially verified too, not just code.
- **Front-load the decision surface.** The 26-decision sweep surfaced every on-disk-locked + hard-to-reverse choice *before* any code, so Nathan ruled with full visibility — far cheaper than discovering them mid-build.

#### Next Session

1. **Finish the MarkdownPM plan loop, then execute.** Pick up round-2 (`wt2nz0oqw`) → apply must-fixes → vN until **bulletproof** (zero must-fix, zero open decisions); commit the final plan; then execute **Phase 1→6** via `superpowers:subagent-driven-development` (re-home → test-net → single-parse-spine/#9 → inline-on-AST/delete-emphasis-parser → one owned styler+theme → body tidy). The build is gated on the test net (Phase 2) before any behavior change (Phase 3).
2. **Commit the uncommitted v2 plan + this handoff.** (Leave `CLAUDE.md` — Nathan's intentional edits.)
3. **(deferred) Push `main` + v0.4.0** — both were deferred when the session redirected into the engine rebuild; the rebuild is now the near-term work. Push when Nathan asks.

#### Pending Focuses

- **[active] MarkdownPM rebuild** — plan in the v→vN loop; execute once bulletproof. Spec: `Planning/2026-06-02-MarkdownPM-Service.md`; rulings: `Planning/2026-06-02-MarkdownPM-Decisions.md`.
- **[carried] Push `main` + optional Nexus docs re-mirror** — deferred this session; the Items-as-Markdown run is shipped + archived but unpushed.
- **[carried] v0.4.0 roadmap** — Symbols / Settings / Trash / Wikilinks + file-watcher + FTS5. **Wikilinks is now explicitly a SEPARATE post-MarkdownPM session** (the rebuild only preserves the wikilink groundwork/seam). Obsidian-compat brief captured (resolve-by-ID, plain `[[Title]]` on disk).
- **[gated]** Retire legacy-Item-JSON migration machinery (`Prospects.md`) — once every nexus has run the `.json`→`.md` migration.
- **[carried] Two launch-path perf optimizations** the simplify pass flagged (autoTag redundant walks; steady-state triple-walk short-circuit) — revisit if launch latency matters at scale.
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
9. **Page editor per-caret re-parse is significantly glitchy** — **→ being addressed by the MarkdownPM rebuild** (folded into Phase 3's single-parse-spine, NOT a standalone fix, per Nathan's ruling). Not a separate task.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Planning →** `Planning/2026-06-02-MarkdownPM-Service.md` (the active rebuild plan, v2, in the verify loop) · `Planning/2026-06-02-MarkdownPM-Decisions.md` (26-decision surface + locked rulings) · `Planning/Superseded/2026-06-01-Items-as-Markdown-Plan.md` (SHIPPED + archived) · `Planning/2026-05-31-vault-table-displayonly-interim.md`. Wikilink spec: `Features/Wiki-Link.md` (committed; the wikilink feature is a separate post-rebuild session).
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` (#14 Items-are-Markdown; **#7 still says "vendored swift-markdown-engine" — MarkdownPM Phase 1 updates it**)
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
