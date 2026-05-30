### Pommora — Session Handoff

 - **Read first at session start.** Current state + next focuses + fix log only. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

#### Current state (2026-05-29)

> ⚡ **POST-COMPACT RESUME PROMPT — read this FIRST (Nathan's voice).** Implementation happens THIS session; nothing was built yet.
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess. You open the file and LOOK AT THE CODE before you assert anything.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it. We caught this AGAIN today — the plan you wrote carried stale line numbers from an old plan, and the audit caught them before they cost us a session. That audit-before-implement step is non-negotiable.*
>
> *What we found: the "empty tier picker" was never a data problem — my index was fine the whole time (3 Spaces / 2 Topics / 3 Projects in `// The Nexus //`). It was two separate bugs, both fixed: an all-or-nothing index rebuild that wiped itself on one bad row (`02f8a67`), and a picker popover that collapsed to a glass blob (`9deb818`). The lesson is now `CLAUDE.md` quirk #18 ("Layer-confusion check") — a broken-looking UI does NOT mean broken data; confirm the data directly (query the index, read the file) before blaming the store.*
>
> *Then I hit two MORE bugs — both DIAGNOSED, not fixed (written up as **Task 8** in the plan with verified roots): (A) deleting a relation property I made from an Item Type to its Vault mirror throws "the data couldn't be read because it is missing" (the delete cascade blindly decodes my frontmatter-less `.md` docs as Pages); (B) `SQLite error 19 … insert or replace into pages`.*
>
> *How to proceed — IN THIS ORDER, before writing one line of code: (1) read `// Planning // Make-Relations-Real-Plan.md` end to end; (2) **review the code one more time** against the plan's claims — line numbers drift, verify don't trust; (3) **ask me questions**, especially anything unclear about feature requirements; (4) implement what I greenlight — Task 8's two fixes first (they block my testing). And the hard one: **(5) Task 4 (the picker) is GATED. Do NOT build the picker view from the plan's text + mockups alone — STOP and make me walk you through the detailed picker UIX live first; that visual intent does not survive compaction. Only Task 4a (the data query, no UIX) may go before that.** Don't guess. Look at the code. Ask me."*

> **✅ RESOLVED — the "empty tier picker" cluster had TWO roots, both fixed + confirmed on the real nexus.** (1) **Index all-or-nothing rebuild** — one bad row rolled back the whole rebuild → empty index (`02f8a67`: resilient per-row `IndexBuilder.attemptInsert` + defer the `schema_version` stamp until `populate` succeeds via `PommoraIndex.markSchemaVersionCurrent` + `currentSchemaVersion` 5). (2) **Picker popover collapse** — `RelationPicker`'s chromeless popover sized to its zero-size loading state and never grew → a tiny "liquid glass" blob (`9deb818`: fixed picker panel width). The data + wiring were correct the whole time — proven by reading Nathan's real index (`The Nexus/.nexus/index.db`: v5, **3 Spaces / 2 Topics / 3 Projects**); the picker assigns correctly now. Lesson → CLAUDE.md quirk #18 (**"Layer-confusion check"** — confirm the data directly before blaming it). **Part 3** (defensive `upsertPage`): the FK-19 recurred on the mirror-relation path, so it's now warranted → plan Task 8 Bug B (Fix Log #13). **Next = Make Relations Real Task 4** — the grouped relation **value picker**: one data-driven liquid-glass dropdown showing a side-by-side **sub-menu** when candidates have Collections (Vault/Item-Type value lists) and **flat rows** when not (tiers/contexts; the editor's storage-target selector reuses it flat). Spec locked: 150×235/panel, body-regular, 8pt rows, inset separator, Collection rows w/ chevron, leaf rows w/ blue checkmark-on-selected; `RelationChip` = assigned-value inline only. Full re-planned spec → `Planning/Make-Relations-Real-Plan.md`. Clean HEAD = `9deb818`.

Working tree on `main`, green (only the known `PageEditorViewModelTests.debounceCoalescesRapidEdits` editor-timing flake fails).

**Relations Redesign — COMPLETE (Phases 0–22).** Relations and tiers are one linking system: tiers flow through the relation pipeline and the SQLite `relations` table (the `tier_links` table is retired); relations are always-multi (`[{"$rel":"<ULID>"}]`); `RelationTarget` covers Page Type / Item Type / Agenda Tasks / Agenda Events (+ internal `context_tier`); a single-pane editor creates/edits both sides (home + reverse name + reverse icon); deleting a Context cascades source-side; Agenda Tasks/Events are relation targets. The Lean adoption migration normalizes legacy sidecars on a one-time re-save (Type sidecar `schemaVersion` 1→2; index DB `currentSchemaVersion` 2→3 forces a rebuild that backfills tiers) — lossless changes apply silently, and the one lossy step (dropping a context-tier-targeted property) is gated behind an acknowledgment in the adoption preview. Relation values render as the target's **icon + title** in styled colored text (interim — chip visual is Next focus #1). Full play-by-play → `History.md` (2026-05-29 entry); paradigm decisions #8–#12 → `Guidelines/Paradigm-Decisions.md`; `Features/*` specs rewritten forward-only (Phase 21).

**Docs aligned to code (2026-05-29).** Every `Features/*` spec + `PommoraPRD.md` was audited against the source — contradictions fixed (incl. pre-existing ones), bloat trimmed (~2,100 words), the retired `tier_links` table dropped from the PRD's SQLite schema. **Property surfaces (planned, not yet wired):** properties on Pages, Contexts, and storage views will move to a dropdown (`PropertiesPulldown`) so the inspector can host the LLM/CLI interface; the property panel stays for Items, Page Previews, and Agenda items. Today Pages use the property panel in the inspector (`FrontmatterInspector`). Canonical: `Features/Properties.md` § Where Properties Live.

#### Next focuses

1. **Make Relations Real — Tasks 4–7** (active plan → `Planning/Make-Relations-Real-Plan.md`). Tasks 1–3 (render half: index icons + shared `RelationDisplayResolver` + tables render icon+title) shipped. Next: Task 4 grouped value picker (side-by-side sub-menu / flat) → Task 5 tier chips on panels (Fix Log #11) → Task 6 relation/status/tier editors in `PropertyEditorRow` + editable Page tiers → Task 7 v5 rebuild smoke-test.
2. **Item Windows** — build the real Item Window (in-window property editing was deferred off the placeholder; Task 6 wires the editors it will host).
3. **Page Previews** — standalone-window page preview (cross-feature PreviewWindow primitive).

Open relation fixes: legacy Vault/Type Settings "Relation" dead-end (Fix Log #10); edit-side editing of an existing relation's reverse name/icon (create-side sets both; no source-side edit path yet); `LinkedFromDropdown` real Context-side surface (bare stub → logged in `Prospects.md`).

#### Verification gaps — may harbor mistakes

The redesign is unit-test-green (978 tests; only the documented `debounceCoalescesRapidEdits` flake fails). What was **not** verified, and where Claude may have erred:

- **No live smoke test.** The single-pane relation editor, the Context-delete cascade, the tier columns, and the adoption-preview consent gate all pass unit tests but were never clicked through in the running app — runtime + UX behavior is unverified.
- **Migration never run on the real nexus.** The Type-sidecar `schemaVersion` 1→2 re-save and the index-DB `currentSchemaVersion` 2→3 rebuild fire on the next launch (test-verified, not yet exercised on real data). No legacy relation data is expected (the old wizard never persisted), so it should be a benign one-time normalization — but watch the next launch.
- **"icon + title everywhere" is the documented contract, not the current code on every surface.** `ItemWindow` renders tier values as raw joined IDs (TODO left in code); the tier-row panels may show title-only (Fix Log #11). Trust the code over the doc where they differ.
- **The docs audit was subagent-delegated + spot-reviewed**, not re-read line-by-line (~2,100 words trimmed + many code-grounded edits across ~15 docs). Residual over-trim or inaccuracy is possible — the code is ground truth if a doc disagrees.
- **Open subagent flags:** `Architecture.md`'s `SchemaTransaction` internal-shape claim wasn't line-verified against the type; the stale `<nexus>/Items/<TypeFolder>/` wrapper comment in `ItemContentManager+CRUD.swift` is still there.
- **Phases 12–22 were executed by implementer subagents** (I built + committed on green). Test-covered, but the breadth means a subtle spec↔implementation gap that tests don't catch is possible.
- **Superseeded Planss** Superseeded plans aren't reliable sources of codebase truth. Errors are often found, directives are changed, and what one plan says is true is often contradicted in the next session. Use superseeded plans for diagnostic hints rather than codebase truth.

#### Fix Log

Acknowledged, not-yet-fixed — address soon (keep current per Handoff Rules):

1. **Icon picker too large.** The icon picker in View Settings renders far too big; constrain its size.
2. **Settings popout sizing.** The View Settings popout should size to its content dynamically to avoid scrolling (currently pinned to a fixed max height; Nathan likes the min height).
3. **Column reorder broken.** Drag-reordering table columns doesn't work.
4. **"Modified" not hideable.** Last-Edited / "Modified" can't be toggled off in the visibility settings, but it should be.
5. **Schema changes need reload.** Changing "View As", adding properties, or other schema edits don't show until the view is reloaded — they should update live.
6. **Inline-edit lag.** Editing a property value inline has a noticeable performance + update buffer.
7. **Column layout not persisted.** Table column width/order adjustments don't survive across sessions.
8. **Handoff Skill.** Nathan wants to create an actual skill / command to handle the handoff documentation process rather than relying on listed rules or individual session judgement.
9. **Chip Colors.** Teal + Purple render as the exact same color as blue and violet on chips; needs fixing.
10. **Relation-add dead-end in legacy sheets.** Picking "Relation" in the Vault/Type Settings sheets (the context-menu schema editors) silently cancels — relations are created via the View Settings popover editor. Hide the Relation option in those sheets (or route it to the editor) so it isn't a no-op.
11. **Tier-row panels may show title-only.** The tier-row displays (PropertyPanel / PropertiesPulldown / FrontmatterInspector / ItemWindow) render the target's title but may omit its icon (the table cells + picker already show icon + title). Fold in with the relation-chip work → plan Task 5.
12. **Mirror-relation delete decode crash** (diagnosed → plan Task 8 Bug A). Deleting a relation property from an Item Type to its Vault mirror throws "the data couldn't be read because it is missing" — the paired-delete cascade (`DualRelationCoordinator.stageValueStrip`) decodes frontmatter-less `.md` docs as Pages (`keyNotFound(.id)`). Fix = `do/catch { continue }` per member file + 2 sibling loops.
13. **`upsertPage` FK-19** (diagnosed → plan Task 8 Bug B; the deferred Part 3, now warranted). `SQLite error 19 … insert or replace into pages` on an unindexed parent. Fix = defensive skip-on-FK in `IndexUpdater.upsertPage`/`upsertItem`.
12. **Property columns on table views don't show their icons** — that needs to be fixed. Column-sizing is also non-persistent between sessions.

#### Handoff Rules

- **Keep the Fix Log current.** When an issue is acknowledged but not yet fixed, add it to the Fix Log above in 1–2 sentences; remove an entry once resolved.
- **Maintain this file every session** — current state + next focuses + fix log only. Push spec/decisions to their canonical homes (`History.md` / `Framework.md` / `Features/*`); never accumulate per-session work logs here unless double-checked for importance or the work is not yet completed.

#### Document pointers

- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Active plan → none. Relations Redesign complete — `Planning/Relations-Redesign-Plan.md` ready to archive to `Planning/Superseded/`.
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
