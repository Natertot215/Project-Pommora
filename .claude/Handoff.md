### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-07 — ItemsV2 spec→plan hardened to review-certified, planning-only; ⚠ mid-session doc-loss)

> **Resume prompt (next session):** *"First, PROTECT THE WORK. An unidentified process deleted the superseded ItemsV2 intermediates from `.claude/Planning` mid-session; the active certified artifacts (`06-07-ItemsV2-Spec-V5.md`, `06-07-ItemsV2-Plan-V3.md`, `Guidelines/Review-Discipline.md`, `06-07-ItemsV2-Spec.md`) are UNCOMMITTED and at risk. **Commit them to git before anything else.** (Plan-V1/V2 are recoverable from the Nexus mirror `// The Nexus // Pommora // Planning //` if you want the history; Spec-V3/V4 are gone but fully folded into Spec-V5.) Then EXECUTE `Plan-V3` in a FRESH session, Phase A first, under the verification protocol: a subagent authors each task (hand it the verified anchors), but the orchestrator NEVER trusts its 'done' — verify via a real background build (confirm a NON-ZERO executed test count; beware the `ItemWindowLayoutsTests` 0-test `@Suite` trap), read the actual git diff, and check source/docs before the green commit. SwiftUI/view tasks invoke `swiftui-expert-skill`. Agents lie; the build and the diff don't."*

**Where it started.** Prior session left ItemsV2 spec'd + Plan-V2 written (planning-only, HEAD `b3ccbef`); the standing Next Session #1 was "run another adversarial review round on Plan-V2."

**Key moments (no code commits — all output is planning docs).** Nathan reopened the design rather than just reviewing Plan-V2, driving it via the interrogation method into a materially richer feature: an interactive Item Window with a **pooled conditional-cap engine** (Pool A {select,multi,number}=4 total · Pool B {checkbox,status,date,datetime}=1 each · Pool C {url,file}=2 total; V1 enables select+multi only), a **grouped-by-type checkbox Templates pane**, the existing **window surface KEPT** (no overlay re-host — `WindowGroup`+`.plain`+`PreviewWindow`), `ItemWindowMode`/`commitItemEdits` **deleted**, footer **reuses `DetailFooterBar`** (no `NSPathControl`), and the `.null` gate moved into the shared manager seam. The spec was rebuilt V3→V4→V5 and Plan-V2→Plan-V3 through **six adversarial review rounds (~20 sonnet agents)**: spec V3 (4-agent), V4 (3-agent, clean), V5 cap-engine (2-agent), a leanness/honesty pass (caught a real index-snapshot bug + optimistic "future zones flip on" hand-waving), Plan-V3 (3-agent — found 4 blockers incl. an ungrounded live-index fix and a wrong `validate` call-site list), and a Plan-V3 re-verify (clean). Every round overturned a wrong assumption that would have broken the build. Created `Guidelines/Review-Discipline.md` and folded `swiftui-expert-skill` into the plan's conventions.

**Nathan's voice (the discipline got enforced on me).** He rebuked the premature-confidence pattern directly — *"it's been FIVE reviews when you said the first version was fine"* — the rule being: never call a doc bulletproof before a review round proves it. On execution he named the real trap: *"agents lie, you need verification, and you have access to documentation subagents don't… most of my past plans have had the cornerstone frustration verified when sub-agent driven."* That produced the recommended execution model below (subagent-authored, orchestrator-hard-verified). He also reshaped the design repeatedly (footer: *"use detailfooterbar, skip path control, just have the path displayed"*; the pooled-cap rules by worked example; keep the existing window stub as the surface).

**Where it left off.** HEAD `b3ccbef` (unchanged — no source touched). Working tree: untracked `Planning/06-07-ItemsV2-Spec.md`, `Spec-V5.md`, `Plan-V3.md`, `Guidelines/Review-Discipline.md`, plus the prior session's uncommitted `Handoff.md` edit. **⚠ `Spec-V3`, `Spec-V4`, `Plan-V1`, `Plan-V2` were deleted from `.claude/Planning` by an unidentified mid-session process** (mirror hook verified non-destructive; `git reflog` clean) — Plan-V1/V2 survive in the Nexus mirror; Spec-V3/V4 are gone but folded into Spec-V5. Immediate next action: commit the survivors, then execute Plan-V3.

#### Lessons Learned

- **Review-revise is mandatory; never call a doc "bulletproof"/"fine" before a clean review round proves it** — confidence is earned through evidence. Codified in `Guidelines/Review-Discipline.md` (with the V1-called-fine-then-six-rounds story).
- **Ground every `file:line` in real code before relying on it — even your OWN fixes.** The round-5 live-index "fix" was itself ungrounded (it told the plan to read a `NexusManager` source that doesn't exist in the Item Window scene); the plan's compile-grounding round caught it. The `validate` call-site list was guessed wrong (4 sites, not 6; `updateItemProperty`/`renameItem` don't call it). **→ candidate CLAUDE.md quirk.**
- **Subagent reports are unverified claims.** The orchestrator must verify each against ground truth a subagent can't fake — a real build with a NON-ZERO executed test count, the actual git diff, and source/docs. This is why past subagent-driven plans reproduced the cornerstone frustration; the orchestrator holds context/docs the subagent lacks and must use it to verify.
- **Uncommitted `.claude` docs are NOT safe across a long session** — four `Planning/` files vanished mid-session to an unknown cause. Commit important planning docs promptly; don't assume uncommitted working-tree docs persist. **→ candidate CLAUDE.md quirk + Fix Log.**
- **The `mirror-pommora-docs` hook is non-destructive** (`rsync -rtL`, explicit "NEVER --delete", source→dest). Don't blame it for source-file loss — I did initially, then verified the script and corrected.

#### Next Session

1. **PROTECT FIRST — commit the ItemsV2 artifacts.** `Spec-V5.md`, `Plan-V3.md`, `Guidelines/Review-Discipline.md`, `Spec.md` are uncommitted and an unknown process deleted the superseded intermediates this session. Commit them immediately (first commit: `docs(items): ItemsV2 Spec-V5 + Plan-V3 + Review-Discipline (review-certified)`). Optional: restore `Plan-V1/V2` from the Nexus mirror for history; investigate what deleted the four files.
2. **Execute `Plan-V3`, Phase A first** (A0 `TempNexus` fixtures → A1 `renameItem -> Item` → A2 shared `.null` gate → A3 `validate(isBodyEdit:)` → A4 `property_layout`/`PropertyLayoutMode` → A5 `ItemWindowZoneConfig` pooled-cap engine → A6 `promotedForField` → A7 delete `commitItemEdits` → A8 remove Items placeholder → A9 `NexusEnvironment.nexusManager` for the live index). **Verification protocol:** subagent authors each task (handed the verified anchors); orchestrator verifies via the background builder (real non-zero test count, real `@Suite` names — quirk #1), reads the diff, checks source/docs, THEN green-commits. SwiftUI tasks (Phases C/D/E) invoke `swiftui-expert-skill`. Recommended start fresh for orchestrator context headroom.

#### Pending Focuses

- **[carried from 06-07]** Item Window implementation — now fully spec'd + Plan-V3 review-certified, NOT executed. Lives in Next Session #2; tracked here so it doesn't read as "done."
- **[carried from 06-07]** `markerRanges[0]/[1]` subscripts in `styleItemLinks` (no bounds guard). Can't crash today (tokenizer always emits 2). Add `guard token.markerRanges.count >= 2` if the tokenizer is refactored.
- **[carried from 06-03]** Push `folder-exclusion` → origin — still no upstream, now ~30+ commits ahead. (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch.
- **Nathan: add `excluded_folders` entries + rebuild once** to clear the meta-file leak. Recommended `The Nexus/.nexus/settings.json` additions: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`. Confirm whether `History.md`/`Framework.md`/`Resources.md` are also non-content.
- **Latent (review-flagged):** pages nested ≥2 folders deep in a collection still missing from the launch index scan (`IndexBuilder` non-recursive `children` vs `loadAll` recursive `descendantFiles`). Fix when it bites.

#### Fix Log

1. **`.claude/Planning` mid-session deletion (NEW, investigate).** Spec-V3, Spec-V4, Plan-V1, Plan-V2 were removed from disk during the session by an unidentified process (mirror hook ruled out; reflog clean). Active artifacts survived but were uncommitted. Commit planning docs promptly; root-cause the deleter.
2. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
3. **"Modified" not hideable** in the visibility settings.
4. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
5. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
6. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
7. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
8. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
9. **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 interactive Item Window (SPEC + PLAN review-certified, NOT BUILT 2026-06-07) →** spec `Planning/06-07-ItemsV2-Spec-V5.md`; plan `Planning/06-07-ItemsV2-Plan-V3.md`; review discipline `Guidelines/Review-Discipline.md`. Pending paradigm: amend `Paradigm-Decisions.md` #15 (`property_layout` additive; `layout`/`PromotedProperty.display` decode-tolerated-not-honored; pooled-cap config is code-side data) at execution (Plan-V3 F2).
- **ItemsV2 (SHIPPED 2026-06-03, archetype model — being replaced) →** as-built `Planning/06-03-ItemsV2-Implemented.md`; superseded by the interactive rework above.
- **Connections (PAGE-LEVEL COMPLETE 2026-06-07) →** spec `Features/Connections.md`; plan `Planning/06-05-Connections-Plan.md`. Item chip click path (`onItemLinkClick` → `ItemLinkOpener.loadItem` → `AppGlobals.presentItemAction`) is the entry to the Item Window.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
