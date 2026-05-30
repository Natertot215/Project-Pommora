## Make Relations Real — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. Implementer subagents WRITE code only; the controller runs every build via a background `builder` Agent (`-only-testing:PommoraTests`, quirk #14) and commits to `main` on green (stub-and-progressively-replace, quirk #8). Build the picker visuals with `swiftui-expert-skill`.

**Goal:** Finish making relations + tiers real on every surface. The render half shipped (Tasks 1–3); what remains is the **value picker redesign** (the grouped, sub-menu liquid-glass dropdown), **tier chips on panels**, **editable relation/status/tier values in the Item Window + inspector**, and a **real-nexus migration check**.

**Architecture:** One shared, **data-driven** `RelationPicker` — it shows a **sub-menu (side-by-side pop-out)** when the scope's candidates have sub-groups (a Vault/Item-Type value list, where Pages live in Collections) and **flat standard rows** when they don't (tiers/contexts, and the property editor's storage-target selector). Same component, same rows, same `chipDropdownPanel()` chrome; the sub-menu simply appears only when groups exist. Assigned values render via the `RelationChip` primitive inline; the picker rows are icon + title + a selection checkmark.

**Tech stack:** SwiftUI (macOS), Swift 6 strict concurrency + ExistentialAny, GRDB SQLite index, Swift Testing.

---

### Shipped this session (context — do not redo)

- **`02f8a67` — index-rebuild resilience.** `IndexBuilder.populate` is now per-row resilient (`attemptInsert` skips + logs a bad row instead of rolling back the whole rebuild); `schema_version` is stamped only **after** `populate` succeeds (`PommoraIndex.markSchemaVersionCurrent`, called from `NexusManager.openIndex`); `currentSchemaVersion` is **5**. This was a real, separate bug (one bad row could wipe the entire index → empty tier picker + FK error 19 + "data couldn't be read"). Tests: `RebuildResilienceTests`, `IndexPopulationReproTests`.
- **`9deb818` — picker popover-collapse fix.** `RelationPicker` got a fixed panel width so the chromeless popover can't collapse to a zero-size blob before the candidate list loads. This was the *actual* "empty tier picker" cause — the data + wiring were correct all along (verified). **Lesson captured in `CLAUDE.md` → "Layer-confusion check."**
- **Tasks 1–3 (the render half) — DONE.** Entity `icon` is denormalized into the index (`pages`/`items`/`contexts`/`agenda_*`); `EntityRef` carries `icon`; `RelationDisplayResolver` (shared `@Observable`, injected at `ContentView` + the `.detail` chain) turns any target ID → icon + title via `IndexQuery.resolveEntities`; all four detail-view tables warm it and render relation + tier columns as icon + title (no more "(missing)").

### Grounding facts (verified against code — re-verify before proceeding; code wins on conflict)

- **No hierarchy query exists yet.** `IndexQuery.entitiesByTarget(_:)` returns a **flat** `[EntityRef]` per target (`IndexQuery.swift:14`). There is `entityContainer(id:kind:)` (one entity → its container) but nothing that lists "Collections of a Vault" or "members of a Collection." **→ the grouped picker needs a new `entitiesByTargetGrouped` query.**
- **The schema supports the grouped query.** `page_collections.page_type_id` + `pages.page_collection_id` (nullable) exist (`IndexSchema.swift:45,66`); same shape for `item_collections.item_type_id` + `items.item_collection_id` (`:55,78`). `pages`/`items` now carry `icon` (shipped Task 1). Collections tables carry **no** `icon` column — the picker draws a folder glyph for them.
- **`RelationPicker` is reached for every relation target** via `PropertyCellEditor.relationEditor` (`PropertyCellEditor.swift:316-334`), which routes `definition.relationTarget` (incl. `.contextTier(n)` for tiers) + `index: nexusManager.currentIndex`. All four table detail views thread `index` (`PageTypeDetailView.swift:156`, etc.). Tier defs carry `type:.relation` + `relationTarget:.contextTier(n)` (`BuiltInRelationProperties.swift:52-60`).
- **`RelationPicker` currently renders leaf rows with `RelationChip`** (post-cleanup `RelationPicker.swift`, `RelationPickerRow`). Per Nathan: the picker uses **icon + title** rows; `RelationChip` is reserved for the **assigned-value** inline display (table cells, Item Windows, page panels). → restyle the leaf row away from `RelationChip`.
- **`chipDropdownPanel()`** (`Properties/Chips/ChipDropdownPanel.swift`) is the shared liquid-glass panel surface (regularMaterial + hairline border + 12-radius clip; callers own padding + sizing). Reuse it for every picker panel (DRY).
- **The popover host presents relation editors chromeless + unframed** (`PropertyCellEditor.swift:104-116`, the `isChipDropdownEditor` branch: `.presentationBackground(.clear)`, no `.frame`). → the picker owns its own size; never rely on the popover to size it (that was the `9deb818` collapse).
- **`PropertyEditorRow` (ItemWindow / PropertyPanel / FrontmatterInspector / PropertiesPulldown) takes only `definition` + `@Binding value`** — no index. Relation case is a placeholder (`PropertyEditorRow.swift:32-33`); status is read-only text (`:116-124`).
- **`FrontmatterInspector` already has tier-edit plumbing** — `draftTier1/2/3` + `handleTierChange(_:_:)` (`FrontmatterInspector.swift:39-47`); only the Tiers *section* is read-only `LabeledContent` (`:139-147`).

### Design — the value picker (confirmed with Nathan + 3 mockups; static spec LOCKED 2026-05-30)

- **One component, data-driven.** Groups present → sub-menu pop-out; no groups → flat standard rows. The property **editor's target selector** (scopes to Vaults/Item-Types only — *storages, never ID'd items*) therefore renders as flat rows automatically; it needs no sub-menu and no special "editor mode."
- **Sub-menu = side POP-OUT, NOT inline disclosure** (confirmed 2026-05-30). A chevron Collection/Set row opens its members in a **second panel beside the main one** (native-macOS-submenu behavior) — built as an **HStack of two `chipDropdownPanel` panels inside the one popover** (main panel + active collection's member panel, with a gap), NOT a nested `.popover`, NOT a floating window, NOT an in-place expand. The popover grows wider when a collection opens.
- **Sizing is PROPORTIONAL, not literal — 2:4 (width:height ≈ 1:2).** Per Nathan (2026-05-30) the panel is a **2:4** proportion (taller than the original ~2:3 mockup). Figma numbers are *proportional, not point-accurate*; match the 2:4 proportion + relative spacing, tuning the concrete frame by eye against live SwiftUI **Body** type + standard macOS metrics at build. A **fixed frame is retained regardless** (the `9deb818` anti-collapse guarantee — a chromeless popover with no fixed size collapses to a glass blob). Type = **Body**; **8pt** between list items; **each panel scrolls vertically when its rows overflow the fixed height.**
- **Divider:** a slight separator between the Collection/Set rows and the Page/Item rows, **inset to align with the list-item padding** so it does NOT touch the panel edges — same principle as the properties-editor dropdown divider.
- **Row types:**
  - **Collection/Set row:** folder glyph + title + trailing **chevron** (`chevron.right`). Whole row pops out that collection's member panel to the side (sets `activeGroupID`).
  - **Leaf row** (Page / Item / Context): entity **icon + title** (NOT a `RelationChip`), trailing **blue checkmark shown ONLY when selected** (unselected rows show nothing — the multi-select affordance; no always-visible empty box). Tapping toggles selection.
- **`RelationChip` is NOT used in the picker** — it's the inline assigned-value display only (table cells, Item Windows, panels; Task 5).
- **Interaction — RESOLVED (2026-05-30; Nathan delegated — remote, can't verify live; reviews when home):**
  - **Pop-out:** clicking a Collection/Set row opens its members in the right-hand panel — ONE open at a time (click another collection swaps it; click the open one again closes it — toggles `activeGroupID`). Native-macOS-submenu behavior.
  - **Select + dismiss:** a leaf tap toggles selection (multi-select; checkmarks accumulate) and does NOT dismiss — keep picking. Commit the `[ID]` array live per toggle (as today). The picker dismisses on click-away / Esc (standard popover).
  - **States:** subtle rounded fill on row hover; the open Collection row keeps a persistent highlight while its panel shows; brief emphasis on press.
  - **Frame:** ~160×320 per panel (**2:4**, proportional — tuned to Body type at build); ~328 wide with a collection open; fixed frame retained (the `9deb818` anti-collapse); **each panel scrolls vertically when rows overflow.**
  - **Checkmark:** `SelectionCheckmark` (blue rounded square + white check, ~18–20pt), trailing, rendered ONLY when selected (an equal-width spacer when not, so titles stay aligned).
  - **Empty/loading:** render the fixed frame immediately (never content-size, or it collapses); quiet placeholder until grouped data loads.

### Scoping decisions (controller's call; veto on review)

- **Side-by-side via HStack-in-popover, not nested popovers/windows.** Lowest-risk way to get the side-by-side mockup; avoids the dismissal/positioning fragility I flagged. A `style` knob is left in `RelationPicker` so the property editor can request a single-panel **drill-in/back** layout later if a host is too narrow — but since the editor's data is flat (no groups), it never drills, so v1 ships **side-by-side-when-grouped only** and the editor gets flat rows. No second navigation mode is built unless a grouped picker must live in a cramped host (it doesn't today).
- **Add `entitiesByTargetGrouped`** rather than grouping client-side — the index is the query layer, the SQL is trivial (two FK lookups), and it keeps the picker a thin view over a typed result.
- **Editors are mechanics over shared infrastructure, visuals-agnostic** — relation/status/tier editors route through `RelationPicker` / `ChipDropdown` bound to value + commit. No bespoke chrome in `PropertyEditorRow`; the Item Window visual redesign sits on top later as a presentational swap.

### File map

- **Create:** `PommoraTests/Index/EntitiesByTargetGroupedTests.swift`
- **Modify (data):** `Index/IndexQuery.swift` (+`EntityGroup`/`GroupedEntities` + `entitiesByTargetGrouped`)
- **Modify (picker):** `Properties/RelationPicker.swift` (rewrite body: grouped + side-by-side sub-menu; keep `computeSelection` + the public API + the fixed-size guarantee from `9deb818`)
- **Create (Component Library):** `SelectionCheckmark` (blue rounded-square + white check, shown ONLY when selected) — **confirmed required** (audit): `PropertyCheckbox` always draws a box when unchecked, so it can't be reused. Stage under `Pommora/ComponentLibrary/` (HARD RULE).
- **Modify (tier chips):** `ItemWindow/ItemWindow.swift`, `Properties/PropertyPanel.swift`
- **Modify (editors):** `ItemWindow/PropertyEditorRow.swift` + hosts, `Pages/FrontmatterInspector.swift`, `ContentView.swift` (env injection, quirk #16)
- **Tests:** `PommoraTests/Index/IconBackfillTests.swift` (v5 rebuild smoke-test)

---

> ✅ **GATE LIFTED (2026-05-30).** Nathan is remote and can't verify UIX live, so he delegated the picker interaction design to Claude (see **Picker interaction — RESOLVED** in the Design section) and authorized building **Tasks 4 → 7 straight through to green**. Build to the complete design, verify green, finish the plan; Nathan reviews the picker UIX when he's home. Order: Task 4a (data query) → 4b (picker view) → 5 (tier chips) → 6 (editors) → 7 (v5 smoke-test).

---

### Task 4: Relation value picker — grouped, side-by-side sub-menu dropdown

**Files:** `Index/IndexQuery.swift`, `Properties/RelationPicker.swift`, `PommoraTests/Index/EntitiesByTargetGroupedTests.swift`

**4a — Data layer**

- [ ] **Step 1 — Add the grouped query types + method to `IndexQuery`.** Only `.pageType` / `.itemType` scopes produce groups; every other scope returns flat via existing `entitiesByTarget` (DRY). Give the structs **implicit memberwise inits** OR an explicit `nonisolated init` (quirk #5 — the requirement is *nonisolated*, not *implicit*; the shipped `EntityRef` uses an explicit `nonisolated init`. A *plain* explicit init would become `@MainActor` and break inside the GRDB read closure).

```swift
struct EntityGroup: Sendable, Equatable { let container: EntityRef; let members: [EntityRef] }
struct GroupedEntities: Sendable, Equatable { let groups: [EntityGroup]; let rootEntities: [EntityRef] }

/// Collection/set groups + loose (no-collection) leaves for the grouped picker.
/// Groups appear only for `.pageType` / `.itemType`; every other scope (tiers,
/// agenda) returns its entities flat in `rootEntities` and the picker renders
/// flat rows (no sub-menu).
func entitiesByTargetGrouped(_ target: PropertyDefinition.RelationTarget) async throws -> GroupedEntities {
    switch target {
    case .pageType(let typeID):
        return try await index.dbQueue.read { db in
            let cols = try Row.fetchAll(db, sql: "SELECT id, title FROM page_collections WHERE page_type_id = ? ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .pageCollection, title: $0["title"]) }   // collections carry no icon → folder glyph in the row
            var groups: [EntityGroup] = []
            for c in cols {
                let members = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM pages WHERE page_collection_id = ? ORDER BY title", arguments: [c.id])
                    .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"]) }
                groups.append(EntityGroup(container: c, members: members))
            }
            let root = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM pages WHERE page_type_id = ? AND page_collection_id IS NULL ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .page, title: $0["title"], icon: $0["icon"]) }
            return GroupedEntities(groups: groups, rootEntities: root)
        }
    case .itemType(let typeID):
        return try await index.dbQueue.read { db in
            let cols = try Row.fetchAll(db, sql: "SELECT id, title FROM item_collections WHERE item_type_id = ? ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .itemCollection, title: $0["title"]) }
            var groups: [EntityGroup] = []
            for c in cols {
                let members = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM items WHERE item_collection_id = ? ORDER BY title", arguments: [c.id])
                    .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"], icon: $0["icon"]) }
                groups.append(EntityGroup(container: c, members: members))
            }
            let root = try Row.fetchAll(db, sql: "SELECT id, title, icon FROM items WHERE item_type_id = ? AND item_collection_id IS NULL ORDER BY title", arguments: [typeID])
                .map { EntityRef(id: $0["id"], kind: .item, title: $0["title"], icon: $0["icon"]) }
            return GroupedEntities(groups: groups, rootEntities: root)
        }
    default:
        return GroupedEntities(groups: [], rootEntities: try await entitiesByTarget(target))
    }
}
```

- [ ] **Step 2 — Failing test.** `PommoraTests/Index/EntitiesByTargetGroupedTests.swift` (struct named `EntitiesByTargetGroupedTests`, quirk #18). Copy the index setup + FK-respecting seed pattern from `PommoraTests/Index/IndexPopulationReproTests.swift` verbatim (temp-dir `PommoraIndex.open(at:)`, seed the page_type PARENT + `modified_at`). Seed: one page_type, one collection in it with 2 member pages (icons set), 1 loose page. Assert `groups.count == 1`, `groups[0].members.count == 2`, `groups[0].members[0].icon != nil`, `rootEntities.count == 1`; and that `.contextTier(1)` returns `groups.isEmpty == true` with the seeded Spaces in `rootEntities`.

- [ ] **Step 3 — Run; expect FAIL (undefined), implement to PASS.** Controller, background builder, `-only-testing:PommoraTests/EntitiesByTargetGroupedTests`. Visually confirm a non-zero executed count.

**4b — The picker view** (rewrite `RelationPicker` body; keep the public API `selectedIDs`/`scope`/`index`/`onSelect`, `computeSelection`, and the `panelWidth` fixed-size guarantee. Per quirk #13 keep all row rendering in private value-type sub-views.)

- [ ] **Step 4 — Picker state + data load.** Replace the flat-list body — and **drop the current single outer `.frame(width:).padding(8).chipDropdownPanel()` wrapper** (`RelationPicker.swift:22-28`); each panel below now owns its own sizing + chrome. Load grouped data in `.task`; track which collection is open.

```swift
// Proportional placeholders — 2:4 (w:h ~ 1:2), NOT point-accurate. Tune by eye at build
// against live Body type; fixed frame retained (9deb818 anti-collapse); scrolls on overflow.
private static let panelWidth: CGFloat = 160
private static let panelHeight: CGFloat = 320
@State private var grouped: GroupedEntities = .init(groups: [], rootEntities: [])
@State private var activeGroupID: String? = nil   // nil = no sub-menu open

var body: some View {
    HStack(alignment: .top, spacing: 8) {
        mainPanel
        if let active = grouped.groups.first(where: { $0.container.id == activeGroupID }) {
            memberPanel(active)        // side-by-side sub-menu (HStack grows the popover)
        }
    }
    .task { await loadGrouped() }
}

private func loadGrouped() async {
    guard let idx = index else { return }
    grouped = (try? await IndexQuery(idx).entitiesByTargetGrouped(scope)) ?? .init(groups: [], rootEntities: [])
}
```

- [ ] **Step 5 — `mainPanel`** (collections sub-menu rows → divider → loose leaves; flat when no groups). Fixed size; scrolls; inset divider; `chipDropdownPanel()`.

```swift
private var mainPanel: some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(grouped.groups, id: \.container.id) { g in
                RelationCollectionRow(title: g.container.title, isActive: g.container.id == activeGroupID) {
                    activeGroupID = (activeGroupID == g.container.id) ? nil : g.container.id
                }
            }
            if !grouped.groups.isEmpty && !grouped.rootEntities.isEmpty {
                Divider().padding(.horizontal, 8)        // inset to align with row content
            }
            ForEach(grouped.rootEntities, id: \.id) { e in leafRow(e) }
        }
        .padding(8)
    }
    .frame(width: Self.panelWidth, height: Self.panelHeight)
    .chipDropdownPanel()
}

private func memberPanel(_ g: EntityGroup) -> some View {
    ScrollView {
        VStack(alignment: .leading, spacing: 8) { ForEach(g.members, id: \.id) { leafRow($0) } }
            .padding(8)
    }
    .frame(width: Self.panelWidth, height: Self.panelHeight)
    .chipDropdownPanel()
}

private func leafRow(_ e: EntityRef) -> some View {
    RelationLeafRow(
        icon: e.icon ?? RelationDisplayResolver.defaultIcon(for: e.kind),
        title: e.title,
        isSelected: selectedIDs.containsID(e.id)
    ) {
        let updated = computeSelection(id: e.id, wasSelected: selectedIDs.containsID(e.id), current: selectedIDs)
        selectedIDs = updated
        onSelect(updated)
    }
}
```

- [ ] **Step 6 — The row sub-views** (private structs, plain value types):
  - `RelationCollectionRow` — `Image(systemName: "folder")` + `Text(title).font(.body)` + `Spacer()` + `Image(systemName: "chevron.right")`; whole row is the drill button (`onTap`); subtle highlight when `isActive`.
  - `RelationLeafRow` — `Image(systemName: icon)` + `Text(title).font(.body)` + `Spacer()` + **the blue selection checkmark shown only when `isSelected`** (else an empty fixed-width spacer so titles align). Whole row toggles via `onTap`.
  - **Checkmark:** **create `SelectionCheckmark`** (audit-confirmed: `PropertyCheckbox` always draws a box when unchecked, so it does NOT fit). Blue rounded square + white `checkmark`, ~20pt, rendered ONLY when selected; stage under `Pommora/ComponentLibrary/` and reuse (HARD RULE — no one-off).

- [ ] **Step 7 — Build green; commit.** Manual check after the session: a Vault relation cell opens collections (folder + chevron) that pop a second panel to the right with members; loose pages appear below the divider; a tier cell shows a flat list (no sub-menu); selecting toggles the blue checkmark and commits the same `[ID]` value as before; the picker no longer collapses (the `9deb818` guarantee holds — fixed `frame`).

---

### Task 5: Tier rows render via `RelationChip` (not raw IDs) — Fix Log #11

**Files:** `ItemWindow/ItemWindow.swift` (`relationLine`), `Properties/PropertyPanel.swift` (`tierRow`)

**Note (2026-05-30):** the reusable investment is `PropertyPanel.tierRow` (a kept component — Items / Page Previews / Agenda all use it) + the shared chip-render path; the placeholder `ItemWindow.relationLine` is updated as a demonstration only (that window is being replaced — see Task 6 intent).

- [ ] **Step 1 — Item Window tier rows.** Add `@Environment(RelationDisplayResolver.self) private var relationDisplay` (use the name the four detail views already use — DRY/convention) + a `.task` warming `item.tier1 + item.tier2 + item.tier3`. Replace the raw-ID `Text` with a chip row (`RelationChip(icon:title:)` per resolved ID; `"(missing)"` fallback when unresolved; `"—"` when empty). Delete the existing raw-ID TODO comment.
- [ ] **Step 2 — PropertyPanel tier rows.** Apply the identical chip pattern to `PropertyPanel.tierRow`; add the same `@Environment` + warm `.task`.
- [ ] **Step 3 — Build green; commit.** Manual check: tiers show icon + title (chips) in the Item Window + property panel.

---

### Task 6: Inline property-editing CAPABILITY (reusable) — relation/status editors, picker hosting, editable Page tiers

**Intent (Nathan, 2026-05-30) — build the CAPABILITY, not the placeholder's UIX.** The current Item Window is a placeholder slated for replacement; do NOT invest in its layout. Build inline editing as **reusable infrastructure**: an editable `PropertyEditorRow` that hosts the relation/status picker with correct **picker positioning** in a window/panel context + a clean value-commit contract, so **any future Item Window design can drop in property selection + inline editing**. The current Item Window is wired only as a **demonstration / smoke-test host**. `FrontmatterInspector` (a real, kept Page surface) gets editable tiers for real. A **documented integration process** (Step 8) is a primary deliverable, so the eventual rebuild follows a known pattern instead of reverse-engineering this work.

**Files:** `ItemWindow/PropertyEditorRow.swift` (the reusable row), `Pages/FrontmatterInspector.swift`, `Properties/PropertyPanel.swift`, `ContentView.swift` (env, quirk #16), `Guidelines/CRUD-Patterns.md` (the documented process). Touch the placeholder `ItemWindow.swift` only enough to host the row as a demonstration.

- [ ] **Step 1 — `PropertyEditorRow` gains `index`.** Add `var index: PommoraIndex? = nil` to the struct head (defaulted so existing call sites compile).
- [ ] **Step 2 — Real relation editor** (replace placeholder `:32-33`) — mirror `PropertyCellEditor.relationEditor` (`:327-349`, audit-corrected) (the now-grouped `RelationPicker` with `selectedIDs` binding + `scope: target` + `index:` + `onSelect`). Falls back to `Text("Relation has no target")` when `relationTarget == nil`.
- [ ] **Step 3 — Real status editor** (replace read-only text `:116-124`) — mirror `PropertyCellEditor.statusEditor` (`:284-304`, audit-corrected) (`ChipDropdown(.single)` over flattened status groups). Leave `file` deferred with a one-line comment pointing at the `filePlaceholder` (`PropertyCellEditor.swift:351`).
- [ ] **Step 4 — Thread `index` from hosts (keep it generic).** In `PropertyPanel.swift` (kept component) + `ItemWindow.swift` (demonstration host), pass `index: nexusManager.currentIndex` (add `@Environment(NexusManager.self)` if absent). The contract: a host supplies `index` + the value binding; nothing Item-Window-shaped leaks into `PropertyEditorRow`, so any future window reuses it unchanged.
- [ ] **Step 5 — Editable `FrontmatterInspector` tiers.** Add `@Environment(NexusManager.self)`; replace the read-only `tiersSection` (`:139-147`) with a `RelationPicker` per tier bound to the VM's `draftTier1/2/3` + `handleTierChange(tier,$0)` (scope `.contextTier(n)`, `index: nexusManager.currentIndex`).
- [ ] **Step 6 — Inject env at the RIGHT site (quirk #16; audit-corrected).** `FrontmatterInspector` mounts in `ContentView.inspectorContent` (`:318-336`), **NOT `detail`** — its env chain currently carries only `spaceMgr` + `vaultMgr` (`:331-332`). Add `@Environment(NexusManager.self)` there (+ `RelationDisplayResolver` if its tiers render via chips). For any `.task`-bearing DETAIL view that newly reads an env, add it to the `.detail` env chain instead (`:355-362`; the optional-unwrap guard is `:339-348`). SIGTRAP otherwise — verify via a real test bootstrap, not just compile.
- [ ] **Step 7 — Build green; commit.** Smoke-check (when home): a Page's Spaces/Topics/Projects are editable from the inspector; the demonstration Item Window hosts editable relation + status properties via the same reusable `PropertyEditorRow`.
- [ ] **Step 8 — Document the integration process (primary deliverable).** In `Guidelines/CRUD-Patterns.md`, add a concise **"Inline property editing + picker hosting"** section: how a window/panel hosts `PropertyEditorRow`; how the relation/tier picker is presented + positioned (popover anchor, chromeless `.presentationBackground(.clear)`, fixed-frame so it can't collapse — the `9deb818` rule); env requirements (quirk #16 — `RelationDisplayResolver` + `index` / `NexusManager`); and the value-binding + commit contract. Goal: the future Item Window rebuild wires property editing by following this doc, not by reverse-engineering the placeholder.

---

### Task 7: v5 rebuild smoke-test + real-nexus confirmation

**Files:** `PommoraTests/Index/IconBackfillTests.swift`

- [ ] **Step 1 — Backfill test.** Exercise `IndexBuilder` directly (NOT the app — XCTest launch-modal guard, quirk #17). Seed a Space (icon, tier 1) + a Page (icon, `tier1=[Space]`); run a full rebuild; assert `resolveEntities` returns both icons and the tier `relations` rows exist. Copy an existing `PommoraTests/Index/` builder-fixture test verbatim for setup.
- [ ] **Step 2 — Run; iterate to green.** `-only-testing:PommoraTests/IconBackfillTests`, non-zero count.
- [ ] **Step 3 — Real-nexus check (controller, after the session).** Already partially confirmed: Nathan's `The Nexus` index rebuilt to v5 with 8 contexts. After Task 4 ships, click through: relation cell → grouped picker → assign → cell shows the chip. Note the outcome in `Handoff.md`.
- [ ] **Step 4 — Final commit + docs.** Update `Features/Properties.md` (grouped value picker; `PropertyEditorRow` edits relation+status), `Features/Pages.md` (tiers editable from inspector), `Features/Items.md` (Item Window relation/status editing). Move this plan to `Planning/Superseded/`; log the milestone in `History.md`.

---

### Task 8: Relation-lifecycle hardening — paired-delete decode crash + orphan-parent FK — ✅ SHIPPED `f1d66f6` (2026-05-30)

Two live errors on the **Item-Type→Vault mirror relation**, one diagnosed root each. **SHIPPED `f1d66f6`:** fixed via a shared `MemberFileStrip.forEach` resilience helper applied at **all 8** strip sites (broader than the 3 originally scoped — `DualRelationCoordinator.stageValueStrip` ×4 branches + `PageType`/`ItemTypeManager` delete+changeType) + FK-resilient `upsertPage`/`upsertItem` (catch constraint → retry without orphan collection → else skip+log). Tests green: `MemberFileStripResilienceTests` (3) + flipped `IndexPopulationReproTests` Test B; full suite 990/991 (known flake only). Original diagnosis retained below for reference.

**Bug A — "the data couldn't be read because it is missing" on paired create/delete (decode crash).**
- **Root (verified, on-disk):** the paired cascade's value-strip loads EVERY `.md` member of the targeted Vault as `PageFrontmatter` to strip the property value — `DualRelationCoordinator.stageValueStrip` `.pageType` branch (`Vaults/DualRelationCoordinator.swift:278-284`; hard `try` at `:279`). A frontmatter-less `.md` (hand-authored doc) decodes from `"{}"`; `PageFrontmatter.init(from:)` requires `id` (`Content/PageFrontmatter.swift:63`) → `DecodingError.keyNotFound(.id)` → that exact toast (surfaced via `SidebarToast.friendlyMessage:91` / `PropertyEditorErrorMessage.string:25`, neither maps the raw `DecodingError`). The throw aborts the `SchemaTransaction` before commit → orphaned half-pair, toast every attempt. Confirmed on Nathan's `The Nexus/Systems` Vault (10 frontmatter-less `.md` files). **NOT a create-side serialization bug — the mirror is written correctly.**
- **Fix (preferred — preserves the Page `id` invariant):** wrap the per-file load/strip in `do/catch { continue }` in `stageValueStrip`'s `.pageType` branch — a frontmatter-less page can't hold the relation value, so skipping is lossless. Apply the SAME to the sibling strip loops: `PageTypeManager.deleteProperty` (`:914`) + `changeType` (`:1048`). (Do NOT relax `PageFrontmatter.id` to optional — higher blast radius; the call-site catch is contained.)
- **Failing test:** cross-manager pair (Item-Type relation targeting a Vault, `dualProperty` set) + a raw frontmatter-less `.md` written into the Vault folder; `deleteProperty` → pre-fix throws `keyNotFound(.id)` + sets `pendingError`; post-fix deletes cleanly + leaves the `.md` untouched. (`DualRelationWiringTests` uses same-manager pairs with zero member files, so it misses this — add a new case.)

**Bug B — `SQLite error 19: FOREIGN KEY constraint failed … insert or replace into pages` (the deferred Part 3, now warranted).**
- **Root (symptom-level):** `IndexUpdater.upsertPage` inserts a page whose parent (`page_type_id` / `page_collection_id`) isn't in the index → FK violation surfaces as a toast. The index is a regeneratable cache, so a missing parent must never be fatal. Exact trigger not yet pinned (Bug A's aborted transaction can leave the index briefly inconsistent); defensive skip makes it non-fatal regardless.
- **Fix (defensive `upsertPage` — Part 3):** on a FK failure, **skip + `os.Logger`-log** instead of setting `pendingError`/toasting; optionally null an orphan `page_collection_id` so the page still indexes under its type. Mirror in `upsertItem`. After Bug A is fixed, confirm whether B still reproduces; if so, `log`-instrument the exact failing parent.
- **Test:** update `IndexPopulationReproTests` Test B (currently ASSERTS the throw) to assert the resilient outcome (no throw; page indexed or skipped).

**Layer note (per the Layer-confusion check):** Bug A is a genuine DATA/serialization fault (a decode); Bug B is the index (query/display) layer. Neither is the picker — verified, not assumed.

---

### Risks / notes

- **Don't regress `9deb818`.** Every picker panel MUST carry a fixed `.frame(width:height:)` — the chromeless popover will collapse to a blob otherwise. The HStack-of-panels keeps each panel fixed; the popover grows to the HStack. Verify the picker renders at a stable size in BOTH the flat (tier) and grouped (Vault) cases.
- **Default-MainActor isolation (quirk #5).** `EntityGroup`/`GroupedEntities` must be *nonisolated*-constructible inside the GRDB read closure — use implicit memberwise inits OR an explicit `nonisolated init` (the shipped `EntityRef` uses the latter). A plain explicit init becomes `@MainActor` and breaks.
- **GRDB String-overload pollution (quirk #13).** Keep all row rendering in the isolated private sub-views; use the existing `Array.containsID(_:)` helper (`first(where:)`), never `contains`.
- **`@Environment` in the `.detail` chain (quirk #16).** Any new env a `.task`-bearing detail/inspector view reads must be injected at `ContentView.detail` — SIGTRAP otherwise. Tasks 5/6 add envs; verify via a real test bootstrap.
- **Editor target-selector reuse.** Nathan wants the property editor's target selector to use this same picker (flat mode, since storages have no groups). It selects a *target* (a `RelationTarget`), not entity IDs — different selection semantics — so it's a thin adapter, scoped as a follow-on once the value picker ships. The picker is built data-driven specifically so this reuse is a wiring change, not a rebuild.
- **Display-cache staleness.** `RelationDisplayResolver` caches icon+title; after a rename/icon edit call `invalidate()` (or warm-overwrite). v1 warms on appear, so staleness is bounded to a live session; wire `invalidate()` into rename/icon commit paths if it shows.
