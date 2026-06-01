### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess. You open the file and LOOK AT THE CODE before you assert anything.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it. We caught this AGAIN today — the plan you wrote carried stale line numbers from an old plan, and the audit caught them before they cost us a session. That audit-before-implement step is non-negotiable."*
>
> Held the line again this session: a background audit agent — handed the *correct* version mapping — still rubber-stamped stale `v0.6.0` lines as "clean." Re-reading every reference by hand found ~35 contradictions it missed. **The cornerstone now generalizes past grep to subagents: treat any search surface's "clean" verdict as an unverified hypothesis until you've read the lines yourself.**

#### Current state (2026-05-31)

`main` green at `b765c2e` (v0.3.4 shipped + tagged + pushed last session). This session was **documentation-only** — Framework realigned to shipped reality + Nathan's own roadmap, History trimmed ~70%, and version contradictions fixed across 14 docs. **All 16 `.claude` edits are uncommitted in the working tree.** A parallel session committed concurrently (`showPageIcon` toggle `b765c2e`, dead-checkbox-scaffolding cleanup `198df75`); `Pommora/Pommora.xcodeproj/project.pbxproj` + untracked `graphify-out/` are theirs/incidental — left untouched (quirk #10).

**Page-header icons shipped (parallel code session, `main` advanced past `b765c2e`).** Per-Nexus `showPageIcon` toggle (default OFF, ON in The Nexus); inline header icon left of the title (baseline-aligned) + hover `plus.app` "Add Icon" affordance; icon propagated to the sidebar row + NavDropdown (custom overrides the per-kind outline default); page-level View Settings popover pre-wired with `PageContentManager` (the pane itself is still empty); no focus-steal to sidebar search on icon edit. Also: checkbox shorthand `-[]` / `-[ ]` / `-[x]` now **canonicalizes to GFM on the content-space** (portable to Obsidian; empty `[]` is no longer a checkbox — it's a transient marker), pinned by a `MarkdownEngine` test target. Resolved: the page-icon "title" in Obsidian was the **Pretty Properties** plugin (`iconProperty: "icon"`, 70px) rendering the SF Symbol name as text — fixed Obsidian-side by repointing its icon key to `display_icon` (Pommora keeps `icon` in frontmatter — data was always clean). Checkbox-shorthand doc claims reconciled across PageEditor / Pages / NavDropdown / Sidebar / Guidelines·Markdown §9.8+L13.

#### Session Summary

Opened post-compact with v0.3.4 already shipped, pushed, and the PreCompact(manual) doc-mirror hook live. Three doc passes, all uncommitted:

- **Framework rework.** Nathan: "rework the Framework document to actually be up-to-date and reflect the work that's actually landed with each commit." The Shipped list had frozen at v0.3.0. Reconstructed the real ledger from git tags + History + the release commit: v0.3.1 (Properties end-to-end), v0.3.2 (View Settings editor rebuild + Folders-reverted, tagged), **v0.3.3 skipped**, v0.3.4 (relations made real + IconPicker + de-dup + display-only + Pages footer, tagged). The `MARKETING_VERSION` field had lagged at `0.2.6` the whole time — tags + History are the real version ledger, not pbxproj.
- **Roadmap realign to Nathan's own doc.** Nathan: "id say whats on my Pommora tasks is actually the working idea since that['s] the doc I maintain myself." Read `Nexus//Pommora//Pommora Tasks.md`; it's coarser + later than Framework. Realigned the upcoming buckets to it — v0.4.0 (Symbols + Settings + Trash + Wikilinks), v0.5.0 (EventKit + Agenda + Calendar), v0.6.0 (Quick Capture + LLM + search), v0.7.0 (the whole view system + Contexts/Homepage editor) — folding Framework-only items into their nearest bucket per his choice. This corrected an earlier wrong guess (wikilinks is v0.4.0, not "next").
- **History trim + cross-doc contradiction fix.** Nathan: "trim the history, especially for locked decisions or architecture prone to go stale or already have." Cut History 646 → ~190 lines (enumerated decision-blocks → `Paradigm-Decisions.md`, SHA/file dumps + editor internals → `PageEditor.md`, superseded brainstorms collapsed). Then swept the rest of the docs: a background Explore agent found only 3 issues and under-reported badly, so a manual pass fixed ~35 version contradictions across 10 files (Settings → v0.4.0, EventKit → v0.5.0, views/saved-views/sort-filter-group → v0.7.0, killed `v0.8.0` + `v0.3.1.x` sub-versions). A final grep confirmed every surviving forward-version reference is intentional.

Left off: working tree dirty with the 16 doc edits, awaiting a docs-only commit. Nothing code-side changed by this session.

#### Lessons Learned

- **Search surfaces under-report doc staleness — subagents included, not just grep.** The Explore audit agent had the correct old→new version mapping and still marked files "clean" while listing their stale assignments as correct. Spotting a contradiction needs the new roadmap and the doc's claim held in tension, not a string match. Re-verify "clean" verdicts yourself. **→ candidate CLAUDE.md quirk**
- **`MARKETING_VERSION` is not the version ledger.** It sat at `0.2.6` from v0.3.0 through the v0.3.2 tag, jumping to `0.3.4` only at release. Git tags + `History.md` ship records are authoritative; the pbxproj field lags.
- **Nathan maintains roadmap intent in `Nexus//Pommora//Pommora Tasks.md`.** It's the canonical priority/sequencing source — coarser and later than Framework. When the two disagree, Framework's version buckets follow the Tasks doc.

#### Next Session

1. **Commit the documentation pass** as one docs-only commit — Framework realign + History trim + the 14-file cross-doc version fixes (16 `.claude` files). Leave `Pommora.xcodeproj/project.pbxproj` (parallel/GRDB churn) and untracked `graphify-out/` out of the commit.
2. **Kick off v0.4.0** per the realigned roadmap — Standardized Symbols / Settings Panel / Archive-Trash / Wikilinks + the file-watcher + FTS5 infra. Pick the lead item and scope a plan; `showPageIcon` (just shipped) is a toe into the Symbols/Settings surface.

#### Pending Focuses

- **[carried from 05-31]** Live smoke (Nathan's manual): vault/type tables display-only + mirror the sidebar; collection/set reorder still works; relation `type_id` reconcile (`fa3e827`) heals drifted collections; relation Mirror name/icon propagation lands on the target Type (`966208e`); Edit Icon from popover / sidebar / detail-table.
- **[carried from 05-31]** `graphify-out/` untracked artifact at repo root — delete or `.gitignore` (Nathan's call).

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns* (distinct from rows); folds into the v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into the v0.7.0 view-system work.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels; hide it or route to the View Settings editor.
6. **Settings popout sizing** — should size to content dynamically (Nathan likes the min height).
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — the error's doc says events have no `_status`, yet the delete guard still blocks it. Behavior preserved through the de-dup; decide separately.
8. Make it so that pressing backspace on a checkbox or listed-item on pages auto-deletes all the syntax so you dont have to delete both the render and the syntax. Also make bullets render label+secondary rather than primary.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Planning →** only `Planning/2026-05-31-vault-table-displayonly-interim.md` remains — the per-view-ordering deferral record (display-only interim; the full per-view system is deferred to v0.7.0). All other plans executed + removed at v0.3.4 (ship log in `History.md`).
- Roadmap → `Framework.md` (now realigned to `Nexus//Pommora//Pommora Tasks.md`) · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
