### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything, You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it." ASK ME when you're unsure! Don't make assumptions when asking directly will give concrete directive; honesty is key, confidence must be earned through evidence.*
>
> Proven REPEATEDLY: verify-first recon caught Apple's rule-of-3 can't reproduce the legacy parser; the Phase-4 review caught a real `*`-styling regression 99 green tests missed; LOOK-before-staging caught a parallel session's entry an instant before bundling. **This execution session adds three:** the final integration review caught `renameItemCollection` silently DROPPING a Set's `templateConfig` (data loss) that **1278 green tests never exercised**; LOOK-before-executing found T4.0's `ItemWindow` refactor was throwaway (the scene hosts the renderer, not `ItemWindow`) and simplified it; and ASK-when-unsure surfaced that the plan *named* the save-machinery move but **no task scheduled it** — caught at T4.4 before shipping a read-only window.

#### Session Summary

> **Resume prompt (next session):** *"**ItemsV2 is SHIPPED + green** (1283 tests) — the single config-driven floating Item Window + per-Type/Collection template system landed on branch `folder-exclusion` (as-built spec → `Planning/06-03-ItemsV2-Implemented.md`). The flexibility review ran (5 confirmed lock-ins; #1 = the renderer's hard-coded region body) and Nathan then **brainstormed the next rework**, now captured DESIGN-ONLY in `Planning/06-03-ItemsV2-Planned.md`: a **zone framework that RETIRES `LayoutArchetype`** — fixed type-bound zones, templates assign capped schema properties into them, layout emerges, and the live window becomes a **display-only stub** first. Next: promote the Planned doc to a spec → plan → build, FIRST step = strip the live window to that clean stub. Two old follow-ups (live property-value editing; non-standard archetype visuals) are SUPERSEDED by the rework. No push yet."*

This was a **pure execution session**: the prior session left the bulletproofed ItemsV2 plan + a CRITICAL parallel-session collision; this session executed the whole plan via `superpowers:subagent-driven-development` (fresh background implementer per task → controller verification → green-per-task, by-path commits) and shipped the feature.

Key moments, in order: confirmed a **green baseline** (1203 tests, including the parallel session's uncommitted work) before touching anything. Phases 1–2 (schema + DRY layers) landed clean (`a027145`…`e6b17eb`). At the Phase-3 boundary — the footer-collision gate the handoff flagged — Nathan chose (via AskUserQuestion) to **commit the parallel session's UI work as a clean base** (`c84a1e7`: `DetailFooterBar` + date-picker) and **reuse `DetailFooterBar`** for the Item Window footer. Phase 3 built the one `ItemWindowRenderer` (`6ce36d9`…`854b94d`); Phase 4 made it a native floating scene and **deleted `ItemWindow.swift`** (−729 lines, `70aaeaf`). The final review found 0 critical / 2 important — both fixed (`6508d28`): the rename data-loss bug + the live-window cap now honoring the Collection override. Phases 5–6 shipped the Templates editor pane + doc sweep. Housekeeping closed out the (intentional) MarkdownPM doc deletions + a stale `ComponentLibraryView` string.

**Two plan deviations I made and flagged in-flight:** T4.0 simplified to just publishing `AppGlobals.current` (the `ItemWindow` relationDisplay refactor was throwaway), and **T4.5 was INSERTED** to restore live editing/save — the plan's File Structure *named* the `hydrate`/`commitSave` move "into the renderer" but no task did it, and T4.4 deleted the old machinery, which would have shipped a read-only window.

Nathan's voice: cut me off twice on verbosity — *"stop with the exhaustive reports; just say task done or not, and MINIMAL info"* (between-task output dropped to one-line status after that). On the T4.5 scope: *"create the machinery; not the UIX on the front-end; the preview can remain very simple with just a title + icon + textbox for now."* On the parallel work + footer: *"Commit it now"* + *"Reuse DetailFooterBar."* And the closing pivot: *"I have a few ideas I want to float by you regarding template design and item architecture. I've also done figma work — FIRST you need to send another batch of review agents looking for DRY violations, or code that locks us into things."*

Where it left off: clean HEAD at **`40d910f`** on `folder-exclusion`, working tree clean, all 30 ItemsV2 commits + the parallel checkpoint landed. The flexibility-review workflow (`wf_63f251f7-a5d`) was still running; its synthesized report is the immediate next thing to read.

#### Lessons Learned

- **Green tests don't cover untested paths — the integration review does.** 1278 green tests never exercised `renameItemCollection`, which rebuilt the collection from a fresh `init` and silently dropped `templateConfig`/icon/pins/views. A whole-implementation review caught it; per-task review + unit tests structurally couldn't. **→ candidate CLAUDE.md quirk:** update/rename manager methods that rebuild an entity via `init(...)` drop every unpassed field — always copy-mutate (`var updated = existing; updated.x = …`), never reconstruct.
- **A plan can name work that no task schedules.** "hydrate/commitSave moves into `ItemWindowRenderer`" lived in the File Structure note but appeared in no task; T4.4 deleted the old machinery and would have shipped a read-only window. Re-assess File-Structure *intentions* against the task list, not just task-to-task.
- **Verify a plan step is still needed before executing it.** T4.0's `ItemWindow` refactor became throwaway once the renderer (not `ItemWindow`) was the scene's content — LOOK-before-executing simplified it to a one-line publish.
- **Background implementer agents that self-background their xcodebuild spawn nested notifications that can swallow the commit step** (happened once at T1.2). Instruct implementers to run the build as a single SYNCHRONOUS foreground command.

#### Next Session

1. **Advance the Item Window zone-framework rework.** The design is captured (design-only) in `Planning/06-03-ItemsV2-Planned.md` — promote it to a spec → plan → build. **First build step: strip the live Item Window to a clean display-only stub** (icon + title + body + footer; no editing surfaces) so the zone framework builds onto bedrock, not the current renderer. First commit = the display-only stub. Then: zone data model (`zone → {types, cap, field design}`, retiring `LayoutArchetype`) → emergent-layout renderer → the Templates pane as the zone assigner.
2. **SUPERSEDED by the rework — do NOT pursue:** "wire property-value editing into the live window" (the rework makes the live window display-only) and "build the non-standard archetype visuals" (archetypes retire entirely). Both were queued pre-brainstorm; the zone framework replaces them.
3. **Item Chips (`@item` in-page tags)** — their own spec once the rework's field-row component exists (single-click dropdown + settings pane + double-click-opens-window); the v0.4.0 wikilink/graph thread.

#### Pending Focuses

- **[carried] Push → origin** — branch `folder-exclusion` has no upstream tracking; was 100+ ahead before this session's 32 commits. One push when wanted.
- **[carried] v0.4.0 roadmap** — Symbols / Trash / **Wikilinks** + file-watcher + FTS5; the ItemsV2 `@item` chips + graph edge-weighting connect here (deferred per LD-11).
- **[carried] Delete `markdownpm-rehome`** — merged; safe to remove.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns*; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels.
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
9. **Agenda description-cap doc mismatch** — the specs claim a 1000-char cap for Agenda Tasks/Events, but the Agenda validators enforce NO length cap (grep-confirmed during the ItemsV2 doc sweep). Decide the intended Agenda cap or drop the doc claim. (Item-side cap is correctly 250.)
10. **Live Item Window is read-display for property VALUES** — title/icon/description edit + save; property-value rows are read-only until the editable-rows follow-up (Next Session #2). Save machinery is already wired through (`draftProperties` carries values).
11. **Page / Heading Jerk:** Assumed fixed MarkdownPM initially, it's not. Placing my caret in-line of a heading still causes the entire page to "jerk" and look like its buffering / reloading. Nathans hypothesis: the parser triggers and reloads the page upon each caret-enter, rather than loading headings and protocals for what happens when my caret enters it on-load, and the bug may be found in the toggle and text-fragment exclusion mechanics implemented in Markdown Engine as AMMENDMENT to already sloppy code. 
12. **Title Changes:** Changing a pages title doesn't change its title on the pinned section of the navigation dropdown unless re-pinned. Works fine with recents since it's constantly updating; likely needs a file-watcher that may be either be overkill or naturally fixed what a file-watcher is implemented. It's a non-issue for now.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 (SHIPPED 2026-06-03) →** as-built spec `Planning/06-03-ItemsV2-Implemented.md` (what EXISTS) + execution record `Planning/06-03-ItemsV2-Plan.md` (30 tasks, all green); ship entry in `History.md`; schema in `Guidelines/Paradigm-Decisions.md` (#15). Feature surfaces reconciled in `Features/Items.md` + `PommoraPRD.md`.
- **ItemsV2 rework (PLANNED — design-only) →** `Planning/06-03-ItemsV2-Planned.md` — the zone framework that retires `LayoutArchetype`; the next build. **Do NOT conflate with the Implemented doc** (built vs. planned).
- **MarkdownPM (SHIPPED, merged) →** `Planning/2026-06-02-MarkdownPM-Plan.md` (Execution Record = canonical phases/commits) · markdown behavior → `Guidelines/Markdown.md` · gate: `External/MarkdownPM/run-tests.sh`. _(The CodeMap + Divergence-Ledger companions were intentionally removed this session.)_
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md` · Wikilink spec → `Features/Wiki-Link.md` (v0.4.0 wikilink session; owns the ItemsV2 `@item`/graph thread)
