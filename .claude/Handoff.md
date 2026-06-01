### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess. You open the file and LOOK AT THE CODE before you assert anything.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it. We caught this AGAIN today — the plan you wrote carried stale line numbers from an old plan, and the audit caught them before they cost us a session. That audit-before-implement step is non-negotiable."*
>
> Held the line again this session: **the prior handoff's two "specced fixes" were BOTH wrong on mechanism** — reading the code caught it before implementing. Bug A's planner was innocent (real cause: SwiftUI `Table` can't nest-reorder under a disclosure); Bug B's `:944` guard *cannot fire* on the paired path (real cause: `resolveDualTargetKind`'s legacy-collection arm). The whole vault-reorder redesign was then built on **verified scaffolding** (`SavedView`/`views[]` already exist), not assumptions. **Next session: read the code (and the data) before you plan around it — even your own prior handoff is a hypothesis.**

#### Current state (2026-05-31)

`main` green. **Bug B (delete cross-vault paired relation) — FIXED + shipped `95f662d`** (tolerant reverse-resolution + `LocalizedError` friendly text; RED→GREEN proven, `RelationDeleteToleranceTests`). **Bug A (in-vault nested page drag) — shipped `fee6804`, then Nathan's live smoke proved it broken** → root-caused to a SwiftUI `Table` limit → **superseded by a design decision** (below). A code-simplification + review pass on the Bug B code is in flight.

**DECISION — per-view ordering (interim + deferral):** vault/type detail tables become **display-only for ordering** (they mirror the sidebar's file-level order live); **collection/set tables keep their reorder** (flat, reliable, non-structural); the full Notion-style per-view system (per-view `order`, group-by, sort, the reorder engine) is **deferred** to the view work (v0.5.0–v0.6.0). Rationale + scope: `Planning/2026-05-31-vault-table-displayonly-interim.md`. Ready-to-run plan: `Planning/2026-05-31-vault-table-displayonly-plan.md` (Tasks 1–4 ready; Task 5 gated on Nathan).

Working tree: a parallel session has uncommitted edits to `Guidelines/Paradigm-Decisions.md` / `History.md` / `Relations-Redesign-Plan.md` — left untouched (quirk #10).

#### Session Summary

- **Diagnosed + corrected** the prior handoff's two bugs by reading the actual code/data (both prior mechanisms were wrong).
- **Bug B shipped `95f662d`** — `deleteProperty` now tolerates an unresolvable/legacy reverse target (owner-side delete always succeeds; best-effort reverse-index cleanup); both manager error enums conform to `LocalizedError` so manager errors never surface as raw `Pommora.X error N`. RED→GREEN verified.
- **Bug A v1 shipped `fee6804`** (nested child-drag) → live smoke showed mis-target / no-op. Root cause: SwiftUI `Table` supports **grouping (`DisclosureTableRow`) XOR reliable reorder (flat `.dropDestination`)**, never both.
- **Brainstormed the view system** → found it ~70% scaffolded (`SavedView` + `views[]` + `updateView` + default-view migration already exist; only a per-view `order` field + a reorder engine are missing). Converged with Nathan on the **display-only-vault interim + deferral**; wrote the decision doc + implementation plan.
- **Researched reorder libraries** (globulus = bleeds when nested; `visfitness/reorderable` = `DragGesture`-isolated, nests cleanly, macOS 15+, MIT).

#### Lessons Learned

- **Even your own prior handoff is a hypothesis (cornerstone / quirk #18).** Both specced fixes named the wrong mechanism; reading the code corrected them before any implementation.
- **SwiftUI `Table` = grouping XOR reliable reorder.** `DisclosureTableRow` (the only grouping primitive) is exactly where reorder breaks; the reliable flat `.dropDestination` needs flat rows (Table has no section headers). Hence vault-level structural nested reorder is deferred; collection-level (flat) reorder is reliable + kept.
- **Verify scaffolding before designing.** The per-view system was already mostly built — Nathan's "this was discussed before" was right; mining code/docs reframed a "big design" into a narrow gap (add a per-view `order` + an engine).
- **Reorder engine for later (Nathan's note — carry forward):** `visfitness/reorderable` (vendor it, MIT; `DragGesture`-isolated so nested instances don't bleed; macOS 15+) is the candidate for the future per-view reorder — and is **equally useful for the other unpolished reorder spots**: property reordering in Settings (see Prospects "Property-order drag", `Features/Prospects.md`) and any list where reorder exists but is rough. Make it the go-to when we polish reordering broadly.

#### Next Session

- **Execute `Planning/2026-05-31-vault-table-displayonly-plan.md`** — Tasks 1–4: make `PageTypeDetailView` + `ItemTypeDetailView` display-only (remove their drag); delete dead `SessionRowOrdering` (+ tests) + retire 2 vault `DetailReorderPlannerTests`; document the decision in `Paradigm-Decisions.md` + `PageTypes.md`. Per-green commits, background builder. **Task 5 (default order → file/creation, not alphabetical) is gated on Nathan confirming "file order" = creation order.**
- **Then live-smoke:** vault tables display-only + mirror the sidebar live; collection/set reorder still works.
- **Deferred (v0.5.0–v0.6.0):** the full per-view system — per-view `order` on `SavedView`, group-by-collection-vs-property (mutually exclusive; property-group flattens collections), sort, multi-saved-view tabs, and the table-engine choice (flat-`Table` vs `visfitness` vs AppKit `NSOutlineView`). Design captured in the interim doc.

#### ⚖️ Two-track sequencing — advice (2026-05-31, de-dup session)

**✅ SHIPPED 2026-05-31 — A → B1 → B2 all landed green (full suite 1045); see `History.md`.** Both tracks executed: vault-table display-only + creation-order default; `ItemTypeManager` normalized (`typesByID` removed, managers symmetric); and the 4-manager property-mutation de-dup behind `PerTypeSchemaService` + `SingletonSchemaService` (+ a post-review cleanup making the Agenda member-strip resilient). The sequencing advice below is retained as the historical record.

- **A · Vault-table display-only** (`Planning/2026-05-31-vault-table-displayonly-plan.md`) — ready (Tasks 1–4), small, removal-only; the established Next Session. Edits the **detail views** (PageType/ItemTypeDetailView drag) + `SessionRowOrdering` + reorder tests + docs. **Does NOT touch the type managers.**
- **B · Manager property de-dup** (`Planning/Normalize-ItemType-Lookup-Plan.md` → `Manager-Property-Dedup-Plan.md`) — planned + adversarially verified; **awaiting Nathan's go**. Internal/behavior-preserving. Edits the **type managers** (5 property methods; Normalize also strips `typesByID` + ~18 `rebuildTypesByID()` calls) + one line of `ItemTypeDetailView` (`liveType`).
- **Why A first:** ready, lower-risk, removal-only; leaves the managers untouched so B runs on a clean base.
- **Cross-dependency is mild** — the only shared file is `ItemTypeDetailView.swift`: A edits the rows/drag region (~222–307), B (Normalize) edits `liveType` (~134) — non-overlapping. **Cornerstone: whoever runs second re-derives line numbers by grep before editing** (each plan now carries a Coordination note). Within B, Normalize precedes Dedup and shifts the managers' method lines.
- **This session (de-dup track):** graphify map → structural review → quantified the 4-manager property-mutation duplication (~590–845 lines) → wrote + adversarially verified both B plans → refreshed the `Nexus//Pommora` doc mirror (real copies; symlink drift deferred).

#### Pending Focuses

- **Execute the interim plan (above).**
- **Live smoke from the prior session (still pending — Nathan):** relaunch to trigger the `#3` `type_id` reconcile (`fa3e827`; heals the 11 drifted collections → II. Commands etc. show Systems' properties); edit a relation's Mirror name/icon and confirm it lands on the target Type (`966208e`); confirm Edit Icon from popover / sidebar / detail-table.
- **`History.md` log pending:** the Storage-Editing pass + this session's per-view decision should get a brief `History.md` entry once the parallel session's uncommitted `History.md` edits are committed (couldn't add cleanly now — quirk #10).
- **`Nexus//Pommora` mirror — symlink drift (deferred, Nathan's call):** doc-mirror symlinks keep materializing into stale real files (`/doc-mirror --audit` → 31 SHADOW), likely the automated "vault backup" git commits. Now on **real-copy refresh** (re-run the doc copy after edits). Proper fix later: adjust the vault-backup automation to preserve symlinks then re-link, or automate the real-copy refresh.
- Test nexus: `~/Test`; real nexus: `~/The Nexus`.

#### Fix Log

- ✅ **Bug B — delete cross-vault paired relation** — FIXED `95f662d`.
- ↪️ **Bug A — in-vault nested page reorder** — superseded: vault tables go display-only (interim plan); reliable nested reorder is part of the deferred per-view system.

Acknowledged, not-yet-fixed (several subsumed by the deferred per-view/view system):

1. **Column reorder broken** — drag-reordering table *columns* (distinct from rows); folds into the view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into the view-system work.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels; hide it or route to the View Settings editor.
6. **Settings popout sizing** — should size to content dynamically (Nathan likes the min height).

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Active plan → `Planning/2026-05-31-vault-table-displayonly-plan.md`** (interim, ready to run); decision/deferral record → `Planning/2026-05-31-vault-table-displayonly-interim.md`.
- Other active plans → `Planning/Make-Relations-Real-Plan.md` · `Manager-Property-Dedup-Plan.md` · `Normalize-ItemType-Lookup-Plan.md` (+ the parallel session's `Relations-Redesign-Plan.md`). *(`Storage-Editing-Reorder-Fix-Plan.md` removed — complete + superseded.)*
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
