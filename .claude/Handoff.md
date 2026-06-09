### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-09 cont. — PagesV2 stress-tested to ratified V4; Figma PagePreview captured; operating contract baked in; ready to execute)

> **Resume prompt (next session):** *"PagesV2 is RATIFIED (V4) and committed (HEAD `a8a82d3`, clean tree except this Handoff). Two adversarial review rounds + the Figma PagePreview design are folded in; the operating contract binds execution. We are DONE planning — next is EXECUTION. Start P0 (MarkdownPM chip-link rename + gate) via `superpowers:subagent-driven-development`. Honor the operating contract every task: STOP and ASK on any guess; verify each task's completion FIRST-HAND (read the diff + confirm a non-zero test count, never trust an agent's 'done'); fold any flagged finding back into the plan + P10's doc list. You do NOT guess — you LOOK, you ASK."*

**Where it started.** Continued from the strip-pivot session: PagesV2 (the Items→Pages strip plan) was authored + committed but not yet stress-tested. Nathan's directive: stress-test the plan against live code until bulletproof, fold in a Figma PagePreview design when it arrived, then refresh the handoff and explain the plan.

**Key moments.** (1) A 10-region code-grounded verification (10 Explore agents) → **8 CRs** + ordering rules + simplifications → folded as **V2** (`489186c`). It caught classic "claim-treated-as-fact" bugs: a MarkdownPM gate field that didn't exist, a static call to an injected `MainWindowRouter`, an `ItemLinkOpener` delete scheduled before its consumer was stripped, a wrong `ItemWindow/` file count (11 not 13, two phantom names), and a P10 archival step pointing at already-deleted docs. (2) Nathan delivered the **Figma PagePreview design** mid-stream; captured into P5 — 475×475 Liquid-Glass panel, inline title/icon, **lock = edit-gate** (opens locked/read-only; unlock → editable+live-save), **"Open Page"/"Lock-Unlock" via right-click context menu**, window-dismiss control, footer `Compact|Window` toggle. (3) A focused agent proved the page-native property editor (`FrontmatterInspector`) **already exists** — "re-implement" collapsed to "move two generic files (`PropertyEditorRow`+`MultiSelectChips`) out of `ItemWindow/` before P3 deletes it" (**CR-8**). (4) A second 4-agent review pass (standard agents, no workflow) came back clean — every P5 symbol exists as stated, ordering holds, the `#15` lockstep is fully mapped, plan↔spec aligned — folding 5 hardening fixes as **V3** (`4a18a7a`). (5) Baked the **operating contract** (STOP/ASK; controller-verified completion; flag-back-into-plan) + total-erasure P10 mandate as **V4** (`a8a82d3`). Spec `06-09-Items-Strip-Spec.md` reconciled throughout.

**Nathan's voice.** *"dont use workflows"* / *"use standard dispatched agents"* → recorded as a Review-Discipline rule (reviews run via standard agents unless he asks for a workflow). *"each task must return, and have YOU verify it was complete; dont trust the agents word."* *"if anything requires you to guess… you must ASK!"* *"make it so that the code leaves no trace that items ever existed… beyond a simple note in CLAUDEmd and History."* The lock model was his refinement on the spot: lock gates editing, open is a context-menu action — cleaner than the button-transform I'd drafted.

**Where it left off.** Clean tree at HEAD `a8a82d3` (only this `Handoff.md` modified). PagesV2 is V4-ratified, decision-complete, execution-ready. No code written yet — the next action is P0 execution.

#### Lessons Learned

- **The cornerstone pays off loudest at the planning layer.** Every high-value find this session was a bug in the plan's *assumptions*, not the code — a fabricated symbol, a static-vs-injected call, a delete-before-consumer-stripped ordering. All caught by opening the file before asserting. **→ candidate CLAUDE.md quirk** reinforcement.
- **Verify-before-plan can shrink the work, not just de-risk it.** The "re-implement the property editor" task evaporated once an agent confirmed `FrontmatterInspector` already does it page-native. Investigating first turned the biggest perceived risk into a 2-file move.
- **Two review agents disagreed on whether `ViewSettingsPane` has a footer slot; the one citing the exact `file:line` snippet won.** Evidence beats assertion even between agents — trust the cited diff, not the summary.
- **Reviews run as standard dispatched agents, not the Workflow tool, unless Nathan asks.** Recorded in `Guidelines/Review-Discipline.md`.

#### Next Session

1. **BEGIN EXECUTION — P0 (MarkdownPM chip-link rename + off-by-default gate)** via `superpowers:subagent-driven-development`. Independent of the rest; the natural first green ship. Honor the operating contract: STOP/ASK on any guess; controller-verify the package build + renamed suites (non-zero count) first-hand; commit only the intended files.
2. **Then P1→P2** — collapse item arms, then the enum-spine compiler gate (the discovery seam).
3. **Re-assess the plan between every green commit** (CLAUDE.md hard rule); fold any flagged finding back into the plan + P10's doc list before dispatching the next task.

#### Pending Focuses

- **ItemsV2 forward agenda remains SUPERSEDED — do not re-add.** (Phase F merge, Item Templates pane, pinned-properties scaffolding — all deleted by the strip; pinned → Prospect.)
- **[carried from 06-03]** Push `folder-exclusion` → origin (~30+ commits ahead). (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch. (carried 3×+ — confirm still wanted.)
- **Nathan: add `excluded_folders` entries + rebuild once** — `The Nexus/.nexus/settings.json`: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`.
- **Latent (review-flagged):** pages nested ≥2 folders deep in a collection are missing from the launch index scan (`IndexBuilder` non-recursive vs `loadAll` recursive). Fix when it bites.

#### Fix Log

1. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
5. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
6. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
7. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
8. **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ACTIVE — Items→Pages strip (PagesV2) →** plan `Planning/PagesV2.md` (**V4, ratified**; 11 phases P0–P10; operating contract + 8 CRs + Figma P5 + total-erasure P10). Zero-assumption spec `Planning/06-09-Items-Strip-Spec.md` (reconciled to V4). Decision record `Planning/06-09-Items-Pages-Collapse-Evaluation.md`. Status: ratified + committed (`489186c`/`4a18a7a`/`a8a82d3`); **next = execution from P0.**
- **Connections (being reduced to `[[`-only) →** spec `Features/Connections.md`. PagesV2 declasses `[[`, collapses `{{` at the connection layer, removes the item-chip click path; the chip render is kept dormant + renamed page-native (`chipLink*`) in MarkdownPM.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
