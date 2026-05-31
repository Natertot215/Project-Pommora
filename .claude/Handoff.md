### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess. You open the file and LOOK AT THE CODE before you assert anything.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it. We caught this AGAIN today — the plan you wrote carried stale line numbers from an old plan, and the audit caught them before they cost us a session. That audit-before-implement step is non-negotiable."*
>
> Held the line again this session: **#3 ("collection shows no properties") was a DATA drift, not the routing** — proven by reading the on-disk `type_id`s before touching code; the reorder bug was traced to the actual `dropDestination`/`ForEach(rows)` binding; the delete error to the exact guard line via reading live nexus data. **Next session: read the code (and the data) before you plan around it.**

#### Current state (2026-05-30)

`main` green — 1023 passing; only the known `PageEditorViewModelTests.debounceCoalescesRapidEdits` flake fails. HEAD = `7253d01` (my docs) atop `fa3e827`; the parallel session's native icon-picker + SymbolPicker-dependency removal are also landed (`4b564bb`, `86fb2c6`, `3398f50`, `68fb5a7`). Working tree clean except this Handoff. **The 7-issue Storage-Editing + Reorder pass is COMPLETE.** Two follow-on bugs are now **root-caused with minimal fixes specced (NOT yet implemented)** — see Next Session.

#### Session Summary

**Storage-Editing + Reorder Fix Pass — COMPLETE** (plan + full lessons: `Planning/Storage-Editing-Reorder-Fix-Plan.md`). Executed RED-first TDD, per-green commits, builds via background `builder` agent (quirk #13).

- **Phase 0** — removed the data-layer `kind` column `bd42545`; removed the Set's redundant parent breadcrumb `2a024ca`.
- **Phase 1 foundations** — collection icon setters `df43df1`; Items-side reorder persistence + `setItemOrder(inType:)` `cd55084`; `DualRelationCoordinator.updatePairedRelation` (F3) `8222a2f`.
- **Phase 4** — table-reorder persistence: `DetailReorderPlanner` + 4-view wiring `f6985a9`/`20674c7`. ⚠️ **INCOMPLETE — see Bug A in Next Session** (per-kind scoping is mis-coordinated for outline views).
- **Phase 2** — icon/title editable across THREE surfaces: View Settings popover header `783fdb6`; sidebar "Edit Icon" on collection/set rows + app-wide **"Edit Title" / "Edit Icon"** label standardization (rename *dialog* keeps "Rename") `f15af44`; detail-table "Edit Icon" on page/collection/set/item rows + new `updatePageIcon`/`updateItemIcon` setters `57a1cef`. (Inline title-area editing on the detail header was **descoped** by Nathan.)
- **Native icon picker** (parallel session, committed by me to unblock Phase 3's `.iconPickerPopover`) `4b564bb`; parallel session then removed the `xnth97/SymbolPicker` SPM dep.
- **Phase 3** — unified 3-row relation editor (Home / Target-locked-pill / Mirror): the **Mirror (reverse) side is now editable** and propagates to the target Type via `updatePairedRelation` manager wrappers (wires F3, previously orphaned) `966208e`. Re-targeting deferred as a Prospect.
- **Phase 5 / #3** — confirmed a DATA fault: a vault re-adoption left **11 collections** (Systems ×3, Materials ×5, Assets, Claude/II. Transcripts) with stale `type_id`s → empty Edit Properties pane. `loadAll` now reconciles each collection's `type_id` to its containing vault (folder-authoritative, idempotent, re-saves the sidecar) `fa3e827`. **Heals on next launch.**

#### Lessons Learned

- **Verify the DATA, not just the code (quirk #18):** #3 looked like a routing bug; reading the on-disk `type_id`s vs the vault `id`s proved it was drift from a re-adoption. The reconcile heals it; routing was always correct.
- **Tests must cover the real shape:** `DetailReorderPlannerTests` used **leaf-only fixtures** (`children: nil`), so the outline/disclosure reorder bug shipped green and invisible. A test with a collection-carrying-children fixture would have caught Bug A.
- **Parallel-session discipline (quirk #10) held:** the native icon picker, `OptionEditPopover` polish, `SelectionCheckmark`/`RelationPicker` tweaks were all Nathan's — committed as separate labeled commits or left untouched, never bundled into feature commits. Revert GRDB pbxproj churn before each commit.
- **Icon setters reuse tested save paths** (`updatePageFrontmatter` / `updateItem`); F3 wrappers mirror `addProperty`'s paired branch (`resolveDualTargetKind` → coordinator → reload both sides via inline + `reloadTypeByID`).
- **id-drift is a systemic hazard:** raw ULIDs in `type_id` / `relationTarget` / `syncedPropertyDefinedOnTypeID` are silently invalidated by re-adoption. `loadAll` heals collection `type_id`s; relation target ids are NOT yet healed (Bug B's deeper cause).

#### Next Session — implement the two diagnosed fixes (root-causes verified; do not re-investigate from scratch)

**Bug A — table reorder mis-routes (page drag perceived as reordering collections).** Root cause: `Detail/DetailReorderPlanner.swift:44-46`. The type-root views (`PageTypeDetailView`, `ItemTypeDetailView`) are **outlines** — collections/sets are disclosure parents with child rows; `rows` is **top-level only**, ordered as blocks (pages-then-collections / sets-then-items). `.dropDestination` is bound to `ForEach(rows)` → the drop `offset` is a **top-level index**, but the planner computes `destInSubset = rows[0..<clampedDrop].filter{same kind}.count` assuming a flat same-kind space. A root-page drop landing in the collection block yields a boundary value (`0`/`subset.count`) → the no-op guard trips or `toOffset` goes out of range → drag does nothing / reads as collections shuffling. **Also:** child pages inside an expanded collection are NOT `.draggable` (only parent disclosure rows + flat leaf rows are), so "reorder a page *inside* a collection" is impossible today.
  - **⚠️ SCOPE DECISION NEEDED FROM NATHAN** before implementing:
    - **(a) Planner-clamp only** — make `DetailReorderPlanner` clamp `destInSubset` into `subset.count` and compute the destination in the offset space SwiftUI actually reports (the doc-confirmed binding is `ForEach(rows)` = top-level, but **instrument once** to confirm whether expanded children are counted in the reported offset — that determines the exact form). Stops root-page drags from corrupting the collection block. Does NOT enable reordering pages inside a collection.
    - **(b) + child-row drag** — additionally add `.draggable` + a child-scoped `.dropDestination` to the inner `ForEach(kids)` (`PageTypeDetailView` ~:190, `ItemTypeDetailView` ~:227) and route a child payload to `reorderPages(in: collection)`. This is the feature "reorder a page inside a collection actually works." Larger change.
  - **RED test first:** add a `DetailReorderPlannerTests` case with a collection row carrying `children: [page,page]` (the current fixtures are all leaf-only — that gap hid the bug). Assert a page drag yields `plan.kind == .page` with `toOffset ≤ pagesSubset.count`, never `.collection`.

**Bug B — `PageTypeManagerError error 1` deleting a cross-vault paired relation.** Root cause: `Vaults/PageTypeManager.swift:946` — the owner-side property guard throws `propertyNotFound` (case ordinal 1) when `propertyID` is already absent from the resolved type (re-adoption re-minted vault ids and desynced it; surfaces via `SidebarToast`/`pendingError`, since `EditPropertyPane.commitDelete` pops the pane first). NOT a stale target (that's `typeNotFound`=0), NOT a collection-scoped target, NOT an empty `syncedPropertyID`.
  - **Minimal surgical fix (clear, low-risk — RED-first):** change the guard at `PageTypeManager.swift:944-947` from `throw PageTypeManagerError.propertyNotFound` to an idempotent return — `try? indexUpdater?.deletePropertyDefinition(id: propertyID); return` (delete-of-absent is a no-op success). Apply the identical change to the mirror site `ItemTypeManager.swift:983-986`.
  - **RED test:** `deleteProperty(id:in:)` for a `propertyID` not present on the type does NOT throw and leaves `pendingError == nil`.
  - **Deeper (separate, optional) durable fix:** heal drifted `relationTarget` / `syncedPropertyDefinedOnTypeID` ids during `loadAll`, mirroring the collection-`type_id` reconcile (`PageTypeManager.swift:127-130`).

#### Pending Focuses

- **Bug A + Bug B above** — diagnosed, fixes specced, not implemented.
- **Live smoke (Nathan, when home):** relaunch to trigger the #3 reconcile (heals the 11 drifted collections → II. Commands etc. show Systems' properties); edit a relation's Mirror name/icon and confirm it lands on the target Type; edit icons from popover/sidebar/detail-table.
- Test nexus for repro lives at `~/Test/.nexus`; the real nexus is `~/The Nexus`.

#### Fix Log

Acknowledged, not-yet-fixed (parallel/prior + this session's diagnosed bugs):

1. **Bug A — table row-reorder mis-routes** (diagnosed; see Next Session — needs scope decision).
2. **Bug B — delete paired relation throws error 1** (diagnosed; minimal fix specced in Next Session).
3. **Column reorder broken.** Drag-reordering table *columns* doesn't work (distinct from row reorder).
4. **"Modified" not hideable** in the visibility settings.
5. **Inline-edit lag** — editing a property value inline has a noticeable update buffer.
6. **Column layout not persisted** across sessions (and property columns don't show their icons).
7. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels; hide it or route to the View Settings editor.
8. **Settings popout sizing** — should size to content dynamically (Nathan likes the min height).

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- Active plan → `Planning/Storage-Editing-Reorder-Fix-Plan.md` (7-issue pass COMPLETE; carries the per-phase commit log + lessons + the two diagnosed bugs).
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
