## Storage-Editing + Reorder Fix Pass — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILLS — `superpowers:systematic-debugging` (root cause before fixes) + `superpowers:test-driven-development` (RED → confirm-fails-for-right-reason → GREEN; no production code without a failing outcome test first, per project mandate). Execute task-by-task via `superpowers:subagent-driven-development`. Build every task via a **background** `builder` Agent (`-only-testing:PommoraTests`, quirks #13/#14); commit to `main` on green (stub-and-progressively-replace, quirk #8). Re-assess this plan between green commits (CLAUDE.md hard rule #13).

### Context

**Goal:** make storage units (Vaults/Types, Collections/Sets) and relations fully *manageable* — editable icons/titles on both the popover and the title area, relation name/icon edits that persist + propagate, table reorder that sticks, and no data-layer `kind` leak — via minimal, surgical, code-verified fixes.
**Architecture:** SwiftUI + AppKit; files-canonical (per-entity sidecars); GRDB SQLite index; managers own in-memory state + atomic writes; `OrderPersister` persists display order; `DualRelationCoordinator` + `SchemaTransaction` own paired-relation schema writes.
**Tech stack:** Swift 6 (strict concurrency, ExistentialAny ON), Swift Testing, `xcodebuild` via a background builder agent.

Nathan reported seven defects after the relations + collection-icon work landed. They cluster into a single theme: **a user can see storage units (Vaults/Types, Collections/Sets) but cannot fully *manage* them** — icons/titles aren't editable where expected, relation name/icon edits don't persist, table reordering doesn't stick, and a data-layer `kind` column leaks into the UI. Each fix below is the *minimal, surgical* change verified against the actual code (every claim traced to `file:line`; no fix is built on an unverified assumption).

One item (#3) was found to be **already correct in code** end-to-end; it is re-scoped to an **investigation spike** (data-only — routing untouched), not a blind fix.

### Investigation summary (confirmed against source)

| # | Symptom | Confirmed root cause | Layer |
|---|---|---|---|
| 1 | Relation icon/title edits don't persist; create + edit are separate | `EditPropertyPane` edit path renders **read-only guidance** for paired relations (only *tier* relations get edit UI); `DualRelationCoordinator` has **no update-with-propagation** method | code gap |
| 2 | Collection/Set icon+title not editable in the settings popover | `StorageMenuRoot` gates the inline title/icon editors behind `isTypeScope`; collections render static; no `updateXCollectionIcon` manager method; header hardcodes `"folder"`/`"tray"` ignoring `c.icon` | code gap |
| 3 | Collection "Edit Properties" shows no parent properties | **None found** — selection→scope→pane→resolver→add-target all route to `c.typeID` correctly. Only a stale/mismatched `type_id` on a collection sidecar could reproduce it | data (suspected), NOT routing |
| 4 | Sets show an extra backlink the Collections lack | `ItemCollectionDetailView` header renders a parent-Type breadcrumb (`‹ Type ›`); `PageCollectionDetailView` has none | UI asymmetry |
| 5 | Storage title/icon not editable from the title area | All four detail-view headers render static `Text` + icon; only the page editor has an inline-title pattern | code gap |
| 6 | Table drag-reorder doesn't persist (pages + collections) | All four `handleDrop`s only set `@State sessionOrder` — **zero** manager/`OrderPersister` calls; Items-side `reorderItems` is a Phase-6 stub | unfinished feature |
| 7 | `kind` column shows by default | Hard-coded `TableColumn("Kind")` in two Pages-side detail views; not a property, not in the visibility system | UI leak |

Nathan's decisions: **#3** = the Edit Properties pane (treat as reproduce-then-fix); **#7** = remove entirely.

> *Every file:line, signature, and the #3 "already-correct" conclusion below were re-verified against source by three independent adversarial Explore passes (2026-05-30). Corrections are folded in — notably the #6 mixed-view index remap, the missing `setItemOrder(inType:)` persister, and the #1 cross-manager refresh.*

---

### Progress + lessons (live)

**Shipped green on `main` (commit):** Phase 0 — Kind column removed `bd42545`, Set breadcrumb removed `2a024ca`. Phase 1 — F1 collection icon setters `df43df1`, F2 Items reorder persistence + `setItemOrder(inType:)` `cd55084`, F3 `updatePairedRelation` `8222a2f`. Phase 4 (DRAG-WORK, **DONE**) — `DetailReorderPlanner` `f6985a9` + 4-view wiring `20674c7`. **Phase 2 (DONE)** — Task 2 popover header icon/title editable for all four storage kinds `783fdb6`; Phase 2b sidebar **Edit Icon** for collections/sets + "Edit Title"/"Edit Icon" label standardization `f15af44`; Phase 2c detail-table **Edit Icon** for page/collection/set/item + new `updatePageIcon`/`updateItemIcon` setters (RED-first) `57a1cef`. Plan docs `d43769f`/`fe9b80b`. Parallel-session UIX (RelationPicker/SelectionCheckmark, green-verified, per Nathan) `23ea94b`/`f8d649f`/`bc65d29`; native icon picker `4b564bb` (parallel session, committed here so Phase 3 resolves `.iconPickerPopover`). **Phase 3 (DONE)** — unified 3-row relation editor: editable Mirror side + `updatePairedRelation` manager wrappers (F3 now wired, no longer orphaned), Target locked-pill `966208e`.

**Remaining:** Phase 5 (#3 spike — interactive; needs Nathan at the Mac with a reproducing collection).

**Phase 3 re-scope (Nathan, 2026-05-30, via mockup) — SHIPPED `966208e`:** the relation editor becomes a unified **3-row layout** — Home `[icon][name]` ("this location") / Target `⇄ [pill]` / Mirror `[icon][name]`. Pre-existing work already shipped the create form + Home-side editing; this session's F3 `updatePairedRelation` is orphaned. Remaining: make the **Mirror** row editable (was read-only paired guidance) + restyle the **Target** to the locked `⇄ [pill]`, wired through a new manager wrapper `updatePairedRelation` (mirrors `addProperty`'s paired branch: `resolveDualTargetKind` → F3 → reload both sides via inline + `reloadTypeByID` → re-index). **Decisions:** target is **locked in edit** (re-targeting = post-v1 Prospect, "like Notion" but deferred for complexity); **no confirmation/disclosure on create**; tier-relation reverse keeps its existing editable rows; icons use the new `.iconPickerPopover` (parallel session's native picker).

**Phase 2 scope changes (Nathan, 2026-05-30):** Task 5 (detail-header *inline title* editing) DESCOPED — *"leave it; non-important, risks pollution/complexity. Move on."* The popover (Task 2) is the sufficient title+icon editing surface; the four detail-view headers stay display-only (live-entity render). In its place Nathan added two asks, **both shipped**: **2b** collection/set Edit Icon in the sidebar context menus (`SidebarSheet.IconTarget` + `IconPickerSheet` → F1 setters), and **2c** Edit Icon on every detail-table row (page/collection/set/item) via `IconTarget.page`/`.item` + the new `updatePageIcon`/`updateItemIcon` setters. Also standardized edit-affordance labels app-wide to "Edit Title"/"Edit Icon" — the rename *dialog* (its title + confirm button + message) keeps "Rename" (clearer there; no Edit Icon pairing).

**Lessons (carry forward):**
- **`Array.move(fromOffsets:toOffset:)` is a SwiftUI extension** — test files using it need `import SwiftUI` (not just Foundation/Testing). Bit the 4a RED step.
- **Layer-confusion applies to TESTS too:** a 4a GREEN "failure" was a malformed assertion (`IndexSet(subset.indices)` compared two 0-based subset index spaces), NOT an impl bug — read the test before touching correct code.
- **Reorder sort-override hypothesis REFUTED** (don't re-investigate): no sort-by-modified/created, no column sort, `SavedView.sort` is an unused stub. The cause was purely session-only `handleDrop`. The reorder MODEL was kept (per-kind order arrays + `DetailReorderPlanner` adapter) rather than reworked to a unified `childOrder` (smaller, no migration, meets criteria); type-root stays grouped (pages then folders) — cross-kind interleaving is a deferred Prospect.
- **F3 confirmed** the coordinator can't resolve a Type from an id → Phase 3 must resolve home+target TypeKinds and refresh both managers (in its Save bullet).
- **pbxproj churn:** Xcode reorders the **GRDB** package entries on every build (extends quirk #6) — revert `Pommora/Pommora.xcodeproj/project.pbxproj` before each commit.
- **Parallel session** actively iterates `RelationPicker`/`SelectionCheckmark` (relation *value* picker) — re-check the tree before Phase 3 (which edits `EditPropertyPane`, adjacent) for collisions; commit its green-verified UIX as separate labeled commits.
- **Parallel session is also building a native IconPicker** (replacing third-party SymbolPicker via a `.iconPickerPopover` modifier + `Properties/IconPicker/` dir + `IconFavoritesTests`). It owns `StorageMenuRoot`'s picker swap + `OptionEditPopover` polish + those untracked files — leave them unstaged, never revert (quirk #10). Phase 2c's `IconTarget`/`IconPickerSheet`/setter work is **orthogonal** — `IconTarget` is *what* to edit, the picker is *how* — so no collision; they meet only at `IconPickerSheet`, which the parallel session left alone.
- **Icon setters reuse tested save paths** (don't re-implement persistence): `updatePageIcon` wraps `updatePageFrontmatter` (atomic `.md` rewrite preserving body); `updateItemIcon` wraps `updateItem(_:in:type:)`/`(_:inTypeRoot:)`. Thin delegations — set the icon on a copy, route through the existing method.
- **Label convention (locked):** edit affordances in menus/tooltips/popover = "Edit Title" / "Edit Icon"; the table-row rename **dialog** (title + confirm + message) stays "Rename" (standard, clearer, no icon pairing).

---

### Execution order, dependencies & shared files

**Dependency DAG (foundations first):** F1 → Tasks 2 & 5 · F2 → Phase 4 (Items-side) · F3 → Phase 3. Each dependent task below carries a **Depends on:** tag; don't start it until its foundation is merged green (else it hits a stub and either fails confusingly or re-implements the foundation inline).

**Files edited by more than one task — fixed per-file order** (the cited line numbers are HEAD-relative and go stale the moment the first task in a shared file commits; each later task rebases onto the prior commit, not the numbers below):
- `PageTypeDetailView.swift` + `PageCollectionDetailView.swift`: **Task 7 (delete Kind column) → Task 5 (editable header) → Phase 4 (handleDrop)**.
- `ItemCollectionDetailView.swift`: **Task 4 (delete breadcrumb) → Task 5 (editable header) → Phase 4 (handleDrop)**.
- `ItemTypeDetailView.swift`: **Task 5 (editable header) → Phase 4 (handleDrop)**.
- `EditPropertyPane.swift`: Phase 3 (#1) edits it; Phase 5 (#3) only **reads** it — no collision.

> **Reorder (Phase 1 re-assessment):** Phase 4 now runs **before** Task 5 (pulled ahead per Nathan's priority). On shared detail-view files the order is Task 7/4 (done) → **Phase 4 (handleDrop)** → Task 5 (header). Locate-by-content still governs (cited lines are stale). Also: the parallel session is actively iterating `RelationPicker`/`SelectionCheckmark` (relation *value* picker) — adjacent to but distinct from Phase 3's `EditPropertyPane` (relation *property* editor); re-check the tree before the Phase 3 dispatch for collisions.

**Plan altitude (deliberate):** executed via `subagent-driven-development`, so per project hard rule #13 this is the controller's working theory, not a frozen script. New code (signatures, deletions, test specs) is given concretely; existing bodies a task mirrors verbatim are cited by `file:line` for the controller to lift at dispatch rather than duplicated here (keeps the plan DRY + scannable — a deliberate divergence from writing-plans' inline-everything default, justified by the controller layer).

---

### Phase 0 — Trivial removals (fast green, pure deletions)

**Task 7 — Remove the `kind` column.** Delete the hard-coded `TableColumn("Kind") { ... row.kindLabel }` block from:
- `Pommora/Pommora/Detail/PageTypeDetailView.swift:177-180`
- `Pommora/Pommora/Detail/PageCollectionDetailView.swift:151-154`

(Items-side views already omit it.) The row's leading icon already distinguishes pages from folders, so nothing else changes. No behavioral test (column removal); verify via build. If `row.kindLabel` / the `kind` accessor becomes unused, leave it (data layer) — only the column is removed.

**Task 4 — Remove the Set breadcrumb.** Delete the `if let parent { … }` block in `Pommora/Pommora/Detail/ItemCollectionDetailView.swift:72-85` so the header matches `PageCollectionDetailView`. **Also remove the now-orphaned `let parent = itemTypeManager.parentItemType(for: collection)` at the top of the `header` (`:70`)** — its only consumer is that block (the independent property-cell re-lookup at `:153` stays). Purely a navigation affordance; back-nav remains via sidebar + NavDropdown. Verify via build. (Sequence this **before** Task 5's edit to the same header to avoid line-shift churn.)

---

### Phase 1 — Manager + coordinator foundations (TDD, RED-first)

**F1 — Collection icon setters.** Add (signatures `async throws`, mirroring the type setters):
- `PageTypeManager.updatePageCollectionIcon(_ collection: PageCollection, to icon: String?) async throws`
- `ItemTypeManager.updateItemCollectionIcon(_ collection: ItemCollection, to icon: String?) async throws`

Each does the three things `updatePageTypeIcon` does (verified body `PageTypeManager.swift:274-291` — controller lifts it at dispatch): (1) re-save the `_pagecollection.json`/`_itemcollection.json` sidecar (the `icon` field already exists — `PageCollection.swift:16`, `ItemCollection.swift:19`); (2) best-effort SQLite upsert via `indexUpdater` (the collection-upsert equivalent of the type setter's `upsertPageType(updated)`); (3) sync the manager's in-memory collection array.
- **RED test** — struct **named exactly** `CollectionIconSetterTests` (quirk #17), run `-only-testing:PommoraTests/CollectionIconSetterTests`: set an icon via the new method, reload the sidecar from disk, assert `icon == "<symbol>"`; do both Page + Item sides. Expected RED: compiles-fails or asserts-fails with a **non-zero executed count** (NOT "0 tests" — a 0-count "success" means the filter didn't match; rename until it runs). GREEN after impl; full `-only-testing:PommoraTests` stays green.

**F2 — Finish Items-side reorder persistence.** `ItemContentManager.reorderItems(in:…)` (`:142-155`) and `reorderItems(inType:…)` (`:159-170`) do the in-memory move but skip persistence (Phase-6 stub, confirmed). Wire both through `OrderPersister`, mirroring `PageContentManager.reorderPages` (`:198`/`:217`). Add the **one missing** persister — `OrderPersister.setItemOrder(_ order: [String], inType itemType: ItemType, nexus: Nexus)` — modeled on `setPageOrder(_:inVault:nexus:)` (`OrderPersister.swift:70-74`); the collection variant `setItemOrder(_:in:)` already exists (`:86`). **Prerequisite RESOLVED (verified):** `ItemType.itemOrder: [String]?` exists (`ItemType.swift:30`, key `item_order`) and `ItemCollection.itemOrder` exists (`:25`) — no schema change, just wire.
- **RED test** — struct `ItemReorderPersistenceTests`, `-only-testing:PommoraTests/ItemReorderPersistenceTests`: reorder items in a collection AND at type-root, reload each sidecar, assert `item_order` reflects the new order. Expected RED with non-zero executed count; GREEN after wiring.

**F3 — Paired-relation update with propagation.** Add `DualRelationCoordinator.updatePairedRelation(...)`, modeled on `createPairedRelation` (`DualRelationCoordinator.swift:127-182`, which already stages both sides via `SchemaTransaction` at `:176-179`): given the source property id + new home-name/home-icon/reverse-name/reverse-icon, mutate **both** sides' `PropertyDefinition` entries inside one `SchemaTransaction`. Locate the reverse property by `dualProperty.syncedPropertyID` within the target Type resolved from `dualProperty.syncedPropertyDefinedOnTypeID` (mirror `renameOneSide`'s lookup at `:196-199`; throw if not found). Target is **not** changed (out of scope — re-targeting is a separate, riskier change). **Cross-manager refresh (caught in verification):** after commit, refresh in-memory state + index for **both** affected Types — they may live on **different managers** (a Page↔Item relation touches `PageTypeManager` *and* `ItemTypeManager`); mirror whatever the creation caller (`addProperty`) does and extend to the target side. Member-file values are unaffected (relation values key on property ID, not name).
- **RED test** — struct `PairedRelationUpdateTests`, `-only-testing:PommoraTests/PairedRelationUpdateTests`: create a paired relation, call `updatePairedRelation` changing home + reverse name + icon, reload **both** Types from disk, assert both sides reflect the edits and survive reload. Expected RED with non-zero executed count; GREEN after impl. The single-side `renameOneSide` (`:190-205`) stays intact for its existing callers.

---

### Phase 2 — Storage title + icon editing on both surfaces (#2 + #5)

> **Depends on:** F1 (merged green). Per shared-file order: Task 5's header edits come **after** Tasks 7 & 4 on the same files.

Both surfaces edit the same thing (title + icon, all four storage kinds) and reuse F1 + the existing rename/icon setters. Keep the commit logic in **one** place per side to stay DRY.

**Task 2 — Popover header (`StorageMenuRoot.swift`).**
- Remove the `isTypeScope` gate on `iconAffordance` (`:80-109`) and `titleAffordance` (`:116-165`) so collection scopes get the same tappable icon (SymbolPicker) + inline-rename `TextField` as types.
- Extend `commitRename()` (`:218-230`) and `commitIcon()` (`:207-216`) with the `.pageCollection` / `.itemCollection` cases → route to `renamePageCollection`/`renameItemCollection` (already exist) and the new F1 icon setters.
- Fix `headerIcon` (`:184-192`) to return `c.icon ?? "folder"` / `c.icon ?? "tray"` for collections instead of the hardcoded glyphs.

**Task 5 — Detail-view title areas.** Make the four headers editable by reusing the page editor's inline-title pattern (`PageEditorView.swift:142-166` + `commitRename()` `:254-294`: `@State titleDraft` + `@FocusState` + commit on submit/blur) plus a tappable icon → `IconPickerSheet` (`Sidebar/Sheets/IconPickerSheet.swift`). Wire commits to the same rename + icon-setter methods as Task 2. Headers to convert:
- `PageTypeDetailView.swift:77-88`, `PageCollectionDetailView.swift:50-61`, `ItemTypeDetailView.swift:118-129`, `ItemCollectionDetailView.swift:86-91` (after Task 4 trims its breadcrumb).

Render uses the manager's live entity (existing `livePageType`/`liveCollection` computed props) so edits reflect immediately. Behavioral coverage comes from the F1 tests; the views verify via build.

---

### Phase 3 — Relation create/edit unification (#1)

> **Depends on:** F3 (merged green).

Reuse the **creation** form as the **edit** interface (Nathan's explicit direction — one workflow, not two). The form's `@State` (`relationDraft`, `relationReverseName`, `draftName`) is currently **create-only**, so reuse is feasible but not free (per verification):
- Add `case editRelation(propertyID:)` to `EditPropertyPane.Mode` (today only `.edit` + `.createRelation` exist, `:~56-59`).
- Pre-fill on appear: seed `relationDraft` / `relationReverseName` / `draftName` from the loaded `PropertyDefinition` (home name+icon, `reverseName`, `reverseIcon`) — mirror the existing `.onAppear` that seeds `draftName` for `.edit`.
- **Gate the target picker** (`RelationDraftTargetSection`, `:~159-162`) read-only/hidden in edit mode — target is fixed (re-targeting is out of scope).
- Replace the read-only paired-relation guidance in `editBody` (`relationPairedReverseRow`, `:533-541`) with a chevron-push into that pre-filled form.
- On Save, route to **F3** `updatePairedRelation` (not `addProperty`/single-side edits). **F3 needs BOTH TypeKinds (confirmed building F3):** the coordinator can't resolve a Type from an id, so the call site must resolve the **home** type (being edited) AND the **target** type — find the target via `def.dualProperty?.syncedPropertyDefinedOnTypeID` across `PageTypeManager`/`ItemTypeManager` (it may be either kind), wrap both as `TypeKind`, and pass them in. After the commit (which only writes sidecars, like `createPairedRelation`), **refresh in-memory state + index for BOTH affected types** — they may live on different managers. Reuse `RelationDraftBuilder.makeFinishedDraft` (`RelationDraftBuilder.swift:49`) for packaging the home draft.

Behavioral coverage = the F3 propagation test; the pane verifies via build.

---

### Phase 4 — Persist table reorder (#6)

> **Depends on:** F2 (Items-side only; the Pages-side reorder methods already exist + persist). Per shared-file order: `handleDrop` edits come **last** on each detail-view file.

Replace the session-only `sessionOrder = next` in each `handleDrop` with the manager reorder method the **sidebar already uses successfully** (drop API is `.dropDestination(for: DetailRowDragPayload.self)` → `(offset, payloads)`; `DetailRowDragPayload` carries only `rowID`).
- **Homogeneous tables (clean — do first):** `PageCollectionDetailView.handleDrop` (`:189-195`) → `contentManager.reorderPages(in: collection, …)`; `ItemCollectionDetailView.handleDrop` (`:222-228`) → `itemContentManager.reorderItems(in: collection, …)` (uses **F2**). Source = `rows.firstIndex(of: payload.rowID)` → `IndexSet(integer:)`; destination = the drop `offset`.
- **Mixed type-root tables (`PageTypeDetailView.handleDrop` `:247-253`, `ItemTypeDetailView` `:277-283`):** rows interleave pages/items **and** collections/sets, so switch on `row.kind` (the `DetailRow.Kind` discriminator; collection rows carry `"collection-"`/`"set-"`-prefixed IDs) and **remap indices into the same-kind subset** — the drop `offset` indexes the full mixed `rows`, but the manager reorders a homogeneous array (`pagesByTypeRoot` / `itemsByTypeRoot` / the collections array). Compute source+destination *within the filtered same-kind subset* before calling `reorderPages(inVault:)` / `reorderItems(inType:)` / `reorderPageCollections(in:)` / `reorderItemCollections(in:)`. This subset remap is the one piece the naive `IndexSet(integer:)` derivation does **not** cover.

**Acceptance criteria + symptoms (Nathan, added mid-Phase-1 — this is the gating bug; Phase 4 PULLED FORWARD to run right after Phase 1, ahead of Phases 2–3, since its dep F2 is already green):**
- (a) dragging an object *within a folder* reorders it freely and **persists** across navigation/relaunch;
- (b) it must **NOT** move the parent collection or other items/folders — Nathan reports a page-drag currently *promotes the collection to the very top* (the mixed-row conflation above — the drop offset/payload is hitting the wrong row kind);
- (c) folders (collections) are reorderable, and each folder's child order persists independently + alongside others.
- **INVESTIGATE FIRST (Nathan's lead):** a default **sort-by-modified/created**, or the `OrderResolver` alphabetical fallback, may be re-sorting rows on load and overriding manual `pageOrder`/`itemOrder`. Confirm whether the detail-view `rows` are sorted by a column/default before `OrderResolver` applies persisted order — if a sort wins, manual reorder can never stick. Manual order must take precedence when present. Verify the real `rows`/sort pipeline before wiring drops.

**Scope boundary:** same-kind reorder only — cross-kind drag (a page between collections) stays out of scope (separately-queued "cross-container drag"). `sessionOrder` becomes redundant once persistence lands (`OrderResolver` reapplies persisted order on reload — confirmed); remove it. **Doc fix:** `Framework.md:95` ("works") vs `:55` ("queued") — reconcile to "persisted" once this ships.

---

### Phase 5 — #3 investigation spike → conditional fix (routing is correct; only DATA may change)

All three verification passes confirmed the selection→scope→pane→resolver→add-target chain routes a collection to its parent Type correctly (`ContentView.swift:72-95`, `PropertiesListPane.swift:78-102`, `PropertyTypePickerPane.swift:110-119`, `EditPropertyPane.swift:757-765`). **The routing code (`scopeTypeID`/`resolvedProperties`/`viewSettingsScope`) will NOT be modified.** The only thing that can produce the empty-pane symptom is a collection whose stored `type_id` ≠ its parent vault's `id` — a data/adoption fault. This is a SPIKE, not a guaranteed task:

1. **Reproduce + confirm the layer (quirk #18).** With Nathan (he's at the Mac), or by reading the failing collection's `_pagecollection.json` `type_id` and comparing to the parent folder's `_pagetype.json` `id`.
2. **Branch A — `type_id` mismatch (data bug → fixable):** add a one-time reconcile that re-points a collection's `type_id` to its containing folder's parent Type, run at adoption / `loadAll` (cf. `NexusAdopter.autoTagMissingSidecars`, quirk #14). **RED test** — struct `CollectionTypeIDReconcileTests`: a collection sidecar with a wrong `type_id` → after reconcile, `resolvedProperties` returns the parent's schema; non-zero executed count.
3. **Branch B — `type_id` matches (routing correct, pane still empty):** **STOP and report to Nathan** with the captured scope / typeID / parent-lookup values. A temporary debug readout to gather evidence is fine; writing a production "fix" against provably-correct routing is **not** — that contradicts the plan's own #3 discipline. Resume only once a specific failing layer is named.

---

### Verification

- **Per task:** RED test first (F1/F2/F3 + any data fix in Phase 5), confirm it fails for the right reason, then GREEN. Full `xcodebuild test -only-testing:PommoraTests` via background builder after each commit (visually confirm a non-zero executed count — quirks #1/#17). Known-flaky `PageEditorViewModelTests.debounceCoalescesRapidEdits` may fail; everything else green.
- **Live smoke (Nathan, when home):** (2/5) edit a Collection's + Vault's icon/title from both the popover header and the detail title area — confirm rename moves the folder and the icon persists across relaunch. (1) edit a relation's name + icon, reopen the paired property on the target Type, confirm both updated. (6) reorder rows in a collection table + a vault table, navigate away and back, confirm order held. (7) confirm no `kind` column. (4) confirm the Set header no longer shows the parent breadcrumb. (3) reproduce the empty Edit Properties pane so we can confirm the layer.

### Execution note

This is **workflow-friendly**: Phase 0 deletions + foundations F1/F2/F3 go first (parallel-safe, RED→GREEN each), then the dependent UI fixes (Phases 2/3/4) honoring the dependency DAG + per-file order above, each verified by a background `builder`. Phase 5 is interactive (needs Nathan or his nexus data) and runs last.

**Per-phase report-back (Nathan-mandated):** after EACH phase ships green, the controller (1) consolidates any adjustments the phase surfaced into this plan file (rewrite affected later tasks — hard rule #13), and (2) reports back a concise phase summary + those adjustments before starting the next phase. Implementers write code only; the controller verifies every build via a background `builder` Agent and commits per green task.

### Risks / guardrails

- **Sidebar is load-bearing (quirk #8/#9):** all reorder + header changes here are in **detail views**, not `SidebarView` — keep it that way.
- **Filename = title:** rename = file move; reuse the existing atomic rename methods (don't hand-roll moves).
- **#3 discipline:** correct code stays untouched; fix only a confirmed failing layer.
- **Parallel-session caveat (quirk #10):** Pommora working tree may carry unattributed UI tweaks — surface, don't revert.
