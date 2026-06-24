# Collections / Sets / Sub-Sets — Rename + Recursive Nesting Plan · V2

> **Status:** review-certified — round-1 (2 adversarial passes) + round-2 verification, the latter clean after two plan-text fixes (method-pair merge ordering · O(1) depth check). Ratified; ready to execute Phase 0.
> **For agentic workers:** Swift build (repo root, `Pommora/Pommora/`). Implement task-by-task, one green commit per task. React is reworked concurrently in the `pommora-react` worktree against the same on-disk contract (§ React Coordination). Delegate builds/tests to the `builder` agent, `run_in_background: true`.

**Goal:** Collapse the three-tier Pages hierarchy (`PageType`→`PageCollection`→`PageSet`) into two — a schema-bearing top "Collection" and a recursive `PageSet` ("Set" at depth-1, "Sub-Set" nested) that nests infinitely; only depth-1 Sets carry views.

**Architecture — three phases, reordered after review so the merge and the recursion are one coherent change (they are inseparable), the mechanical rename is isolated, and the irreversible data step is last:**
1. **Merge + recurse** — fold old `PageCollection` + `PageSet` into one recursive `PageSet`, lift the depth cap, behind a thin dual-read. Top tier stays named `PageType` for now.
2. **Top rename** — `PageType`/"Vault" → `PageCollection`. Collision-free (the name was freed in Phase 1). Labels, injection, SQLite table.
3. **Migrate** — back up, rewrite sidecars on Test then The Nexus, drop dual-read.

**Tech Stack:** Swift 6, SwiftUI, GRDB (SQLite index, delete-and-rebuild on version bump), Yams, `MarkdownPM`.

## Global Constraints

- **Identifiers stay `Page`-prefixed.** No bare `Set`/`Collection` type or var (Swift stdlib collision). Exactly two canonical types end-state: `PageCollection` (top), `PageSet` (recursive).
- **User-facing:** "Collection"/"Collections" (top); "Set" (depth-1 PageSet); "Sub-Set" (nested PageSet, hyphenated). All via `SettingsLabels`, user-renameable; "Sub-Set" is derived (§ Sub-Set Derivation), not a label pair.
- **On-disk:** `_pagecollection.json` (top), `_pageset.json` (every PageSet, any depth). `_pagetype.json` retired. Parent ref key = `parent_id`.
- **SQLite is regeneratable** — schema changes = version-constant bump + delete-and-rebuild from disk. No SQLite data migration. (Reviewer-grounded: `PommoraIndex.currentSchemaVersion`, currently 14 — confirm at task time.)
- **Files canonical**; foreign frontmatter preserved by value; filename = title.
- **Never sweep** `React/`, `.git/`, `.build/`, `DerivedData/`, `External/`. The parallel React session owns `React/`.
- **The Nexus is outside this repo's git** — backed up before any migration (Phase 3, Task 3.1). No undo otherwise.
- **Manager injection (CLAUDE.md quirk #11):** every manager is owned by `NexusEnvironment` and injected via `.injectNexusEnvironment(_:)` / `.environment(_:)`. A forgotten rename SIGTRAPs on first selection — Phase 2 has a dedicated injection-audit step.
- **Documentation is controller-owned (Nathan's directive).** Implementer subagents NEVER edit anything under `.claude/` — not feature specs, not `CLAUDE.md`, nothing. They touch code + tests only. Every doc terminology change AND the final corpus-wide sweep are done manually by the controller, reading each doc end to end. Implementers are told this in their dispatch.

## Locked Decisions (→ `History.md` on Phase 3 ship)

| Concept | User-facing | Swift type | Sidecar | SQLite | Was |
|---|---|---|---|---|---|
| Top, schema-bearing | "Collection"/"Collections" | `PageCollection` | `_pagecollection.json` | `page_collections` | `PageType`/"Vault"/`_pagetype.json`/`page_types` |
| Recursive sub-container | "Set" (d1) · "Sub-Set" (nested) | `PageSet` | `_pageset.json` | `page_sets` (+ self-ref) | `PageCollection` **+** `PageSet`, merged |

- Names shift meaning; `PageType` retired. Only collision-safe mapping under "always `Page`-prefixed."
- **Views live only at depth-1** (parent is the top tier). Deeper Sets ignore any `views[]` — graceful, move-safe. View-eligibility is a render-time depth check, never stored state.
- **Move = pure directory move** — no sidecar rename, no view migration, at any depth.
- **Index FK convention — Model A (ratified by Nathan, Phase-2 gate).** `pages.page_collection_id` = the **top-tier Collection id** for EVERY page (any depth); `pages.page_set_id` = the page's **immediate container** id (nil only at the bare top-tier root). The depth-1 collection is *derived* by walking `page_sets.parent_collection_id` (`depthOneCollectionID(forSet:)`), never stored on the page. (The SQLite index is regeneratable, so this is a code convention, not canonical on-disk data.)
- **Delete-Set-keep-pages = up one level (ratified).** Dissolving a Set re-homes its pages into the Set's *immediate parent* (a page in `Drafts`-inside-`Inbox` lands in `Inbox`, `page_set_id = Inbox.id`), never flattened to the vault root. Matches `Sets.md`.

## Manager Ownership Map (resolves review MAJOR — the hidden iceberg)

End-state ownership, both managers owned/injected by `NexusEnvironment`:

| Owns | Manager | Notes |
|---|---|---|
| `PageCollection` array (top tier) + its schema + its own `views[]` | `PageCollectionManager` (renamed from `PageTypeManager` in Phase 2) | Top-tier CRUD, schema editing, top-level view CRUD, top-level reorder → `.nexus/state.json` |
| All `PageSet`s (every depth), keyed by parent id | `PageSetManager` (absorbs old `PageCollection` ownership in Phase 1) | Recursive Set CRUD, moves, `rebuildFolderURLs`, **depth-1 view CRUD**, `setOrder` reorder → parent sidecar |

- **View CRUD splits by tier:** top-tier view methods stay on `PageCollectionManager`; depth-1 Set view methods (`addView`/`removeView`/`updateViewName`/seeding) move onto `PageSetManager`, gated `parent is top-tier`.
- **`onCollectionFolderChanged` → `onSetFolderChanged`:** the existing callback (fires `PageSetManager.rebuildFolderURLs` when a parent folder moves) must survive the rename; it now also fires on any Set rename at any depth.
- `pageCollectionsByType: [String:[PageCollection]]` (on `PageTypeManager`) → `pageSetsByParent: [String:[PageSet]]` (on `PageSetManager`), keyed by parent id (a top-tier id at depth-1, a Set id deeper).

## Sub-Set Derivation (resolves review MINOR — one canonical site)

A single helper, the ONLY place the term is produced: `func setLabel(forDepth depth: Int) -> String` → `depth == 1 ? labels.pageSet.singular : "Sub-" + labels.pageSet.singular`. Depth = distance from the top-tier parent. Used by sidebar rows, breadcrumb, detail headers, context menus. "Sub-Set" is not separately user-renameable in v1 (it tracks the Set label with a fixed "Sub-" prefix).

---

## The Sentinel Sweep (split across Phase 1 and Phase 2)

Mechanical find-replace self-collides (old `PageCollection` tokens are the words `PageType`→`Collection` wants; `VaultScope`→`CollectionScope` smashes the existing `CollectionScope`). **Never** direct-replace. Map each family → unique sentinel → final. The reorder splits the two rename moments so the families never collide in one pass.

**Phase 1 sweep — old `PageCollection` family → `PageSet` (merge):**

| Variants to catch | → |
|---|---|
| `PageCollections`,`PageCollection`,`pageCollections`,`pageCollection`,`page_collections`,`page_collection`,`pagecollection`, `PageCollectionRow`/`PageCollectionDetailView`/`PageCollectionValidator`/`PageCollectionSnapshot`, `pageCollectionsByType`,`onCollectionFolderChanged`,`CollectionScope`, `"Page Collection"`, bare `"Collection"`/`"Collections"` **(UI/prose/comments only)** | `PageSet` family (merge target — expect duplicate-symbol collisions, resolved by the struct merge in Task 1.1) |

**Phase 2 sweep — old `PageType`/`Vault` family → `PageCollection` (now collision-free):**

| Variants to catch | → |
|---|---|
| `PageTypes`,`PageType`,`pageTypes`,`pageType`,`page_types`,`page_type`,`pagetype`,`PAGE_TYPE`, `PageTypeManager`/`PageTypeRow`/`PageTypeDetailView`/`PageTypeValidator`/`PageTypeSnapshot`/`MockPageTypeManager`, `Vaults`,`Vault`,`vaults`,`vault`,`VaultScope`,`forVault`,`byVault`,`ofVault`, `"Page Type"`/`"Page Types"`, bare `"Vault"`/`"Vaults"` **(UI/prose only)** | `PageCollection` family |

**Substring traps — NEVER sweep (verified present in code):** `setOrder`/`set_order` (kept verbatim — keeps its meaning: child-Set order at any depth), `setValue`/`settings`/`offset`/`reset`/`subset`/`superset`/`Set<`/`.inserted`. Do compound `Page*` tokens with word-boundary anchoring; do the **bare-word UI/prose pass separately, file-scoped, manually reviewed** over only `SettingsLabels.swift`, sidebar/detail view strings, and `.md` docs. Verify sentinels unused first: `grep -rn '§' Pommora/`.

---

## Phase 0 — Pre-flight

### Task 0.1: Baseline + guard
- [ ] `git status`; note parallel-session files (React, uncommitted docs) — untouched all phases.
- [ ] Baseline `xcodebuild test` via `builder` (background). Record green count (~1,294) — the regression floor.
- [ ] `grep -rn '§TOP§\|§MID§\|§BOT§' Pommora/` → zero.
- [ ] `git switch -c collections-sets-rename`.

---

## Phase 1 — Merge + recurse (the behavioral change)

Top tier stays `PageType`; old `PageCollection`+`PageSet` become one recursive `PageSet`; cap lifted; dual-read on for legacy sidecars. TDD throughout.

### Task 1.1: Unified recursive `PageSet` struct + 4-era decoder
**Files:** Modify `Pommora/Pommora/Domain/Vaults/PageSet.swift`. **Additive only — `PageCollection.swift` stays put this task** (still referenced by `PageTypeManager`, so deleting it here wouldn't compile; the cutover + deletion is Task 1.2). This task adds the unified struct + its tests beside the existing types and ships green.
**Produces:** the type every later task consumes.

```swift
struct PageSet: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var parentID: String           // top-tier id (depth-1) OR PageSet id (deeper)
    var title: String              // folder name, not persisted
    var folderURL: URL             // runtime only
    var modifiedAt: Date
    var schemaVersion: Int
    var icon: String?
    var pageOrder: [String]?
    var setOrder: [String]?        // direct child PageSets (recursion) — same meaning all depths
    var views: [SavedView] = []    // honored ONLY at depth-1
    var banner: String?            // honored ONLY at depth-1
    enum CodingKeys: String, CodingKey {
        case id, icon, views, banner
        case parentID = "parent_id", modifiedAt = "modified_at", schemaVersion = "schema_version"
        case pageOrder = "page_order", setOrder = "set_order"
        // decode-only legacy fallbacks (dropped Phase 3):
        case legacyVaultID = "vault_id"          // ParadigmV1 (still on real disk — review-found)
        case legacyTypeID = "type_id"            // old PageCollection→Type ref
        case legacyCollectionID = "collection_id" // old PageSet→Collection ref
    }
}
```
`init(from:)` resolves `parentID` in order: `parent_id` → `vault_id` → `type_id` → `collection_id`. `views`/`banner`/`setOrder` decode-if-present → empty/nil (old `_pageset.json` lacks them).

- [ ] **Step 1 (failing tests):** decode old `_pagecollection.json` (has `type_id`,`views`,`set_order`) → `parentID==type_id`, views preserved. Decode old `_pageset.json` (has `collection_id`, no views) → `parentID==collection_id`, `views==[]`. Decode a ParadigmV1 sidecar with `vault_id` → `parentID==vault_id`. Round-trip encode writes only `parent_id` + new keys.
- [ ] **Step 2:** run, verify fail.
- [ ] **Step 3:** implement struct + `init(from:)`/`encode(to:)` + `static func load(from:) throws -> PageSet` / `func save(to:) throws`.
- [ ] **Step 4:** run, verify pass. **Step 5:** commit.

### Task 1.2: Cutover — typealias-bridge, then three green commits
**Re-sliced after recon (was one big-bang commit).** `PageSet` and old `PageCollection` are now structurally identical (same 11 fields; only `parentID` vs `typeID`). So a typealias bridge turns the ~100-site type-delete into a drop-in, and the cutover proceeds in three independently-green sub-tasks. **This task is type + manager unification only — structurally behavior-neutral. NO UI restructure (recursive rows / depth-aware DetailScope belong to Task 1.4); nesting stays capped at depth-2 here (discovery still non-recursive until 1.3).**

**Recon facts (grounding):** PageTypeManager.swift carries the Collection CRUD (`createPageCollection`:390, `renamePageCollection`:427, `deletePageCollection`:481, `reorderPageCollections`:510, `updatePageCollectionIcon`:356), ALL view CRUD (`mutateViews`:680, `addView`:714, `deleteView`:746, `renameView`:760, `updateView`:651, `duplicateView`:732, `setBanner`:556), the Collection discovery + default-view seed in `loadAll`:142-210, `pageCollectionsByType`:9, `onCollectionFolderChanged`:25. PageSetManager.swift has the Set counterparts (`createPageSet`:121, `renamePageSet`:159, `deletePageSet`:240, `reorderPageSets`:470, `updatePageSetIcon`:219, `loadAll(collections:)`:43, `moveSet`:354, `rebuildFolderURLs`:490, `pageSetsByCollection`:17) and ZERO view methods today. `DetailScope.swift` has `ContainerRef { case collection; case set }` (case labels discriminate — typealias-safe), `CollectionScope`/`VaultScope`. NexusEnvironment.swift:94-95 constructs both managers, :97-101 wires `onCollectionFolderChanged`→`rebuildFolderURLs`, :224-228 orchestrates loadAll. View structs to rename: `PageCollectionRow` (Features/Sidebar), `PageCollectionDetailView` (Features/Detail), `PageCollectionValidator` (Core/Validation), `PageCollectionSnapshot` (IndexBuilder).

- [ ] **1.2a — Bridge (green, behavior-identical).** On `PageSet`: add a `typeID` computed alias (get/set `parentID`, like `collectionID`) and a full compat init `PageSet(id:typeID:title:folderURL:modifiedAt:schemaVersion:icon:pageOrder:setOrder:views:banner:)` matching old PageCollection's init. Replace the `PageCollection` struct with `typealias PageCollection = PageSet` (delete `PageCollection.swift`'s struct, keep the alias). Everything compiles unchanged via aliases; both managers still coexist (PageTypeManager loads depth-1 PageSets, PageSetManager depth-2). **Watch for + report any `is/as? PageCollection` runtime checks** — the typealias conflates them with PageSet; if found, they need a non-type discriminator (the `ContainerRef` case labels are safe). Build green.
- [ ] **1.2b — Merge managers (green).** Move all view CRUD (`mutateViews` + add/delete/rename/update/duplicateView + Collection-side `setBanner`) and the Collection CRUD + Collection-discovery + default-view-seed from PageTypeManager into PageSetManager. `pageCollectionsByType` → fold into `pageSetsByParent: [String:[PageSet]]`. `onCollectionFolderChanged`→`onSetFolderChanged` (dual-level rebuild). Update NexusEnvironment loadAll orchestration (PageSetManager discovers depth-1 from Type folders + depth-2). PageTypeManager keeps types + its own top-level views only. `mutateViews` loses its Type/Collection branch → PageSet container lookup. Generalize `OrderPersister` set-order to a `PageSet` parent. Build green.
- [ ] **1.2c — De-alias + rename + sweep (green).** Repoint `.typeID`/`.collectionID` reads/writes → `.parentID`; `PageCollection` → `PageSet`; remove the `typeID`/`collectionID` aliases, the compat inits, and the typealias. Rename view structs `PageCollectionRow`→`PageSetRow`-tier / `PageCollectionDetailView`→`PageSetDetailView` / `PageCollectionValidator`→fold into `PageSetValidator` / `PageCollectionSnapshot`→`PageSetSnapshot` (mind the existing `PageSetRow` — the depth-1 row and depth-2 row may both be PageSet-backed; keep them distinct view structs for now, rendering-merge is 1.4). Run the residual Phase-1 sentinel sweep + rename test files/suites. Build green. `grep -rn 'PageCollection' Pommora/` → only intentional.

### Task 1.3: Recursive discovery + dual-read (name every site)
**Files:** `PageTypeManager.loadAll()`, `PageSetManager.loadAll()`, `Core/Index/IndexBuilder.swift` (the depth-2 walk), `NexusPaths.swift`.
- [ ] **Step 1 (failing test):** fixture `Type/SetA/SubB/SubC/page.md` loads all 3 Set levels; `SubC.parentID==SubB.id` … `SetA.parentID==<type>.id`. Second fixture in **old** layout (`_pagecollection.json`/`_pageset.json`) loads the equivalent tree via dual-read.
- [ ] **Step 2:** run, verify fail (today caps at depth-2 + rolls up).
- [ ] **Step 3:** `PageSetManager.loadAll` recurses into Set folders at any depth (remove roll-up). Dual-read: a sub-folder sidecar `_pagecollection.json` **or** `_pageset.json` both load as `PageSet`; `IndexBuilder` mirrors. Remove the fixed depth-2 walk.
- [ ] **Step 4:** run, verify pass. **Step 5:** commit.

### Task 1.4: N-level structural rendering
**Files:** `Features/Detail/ViewPipeline/GroupResolver.swift`, `ResolvedGroup.swift`, `DetailScope.swift`.
- [ ] **Step 1 (failing test):** structural grouping of a 4-deep tree → nested `ResolvedGroup`s 4 deep, pages bucketed per level, collapse-state keyed per container id at any depth.
- [ ] **Step 2:** run, verify fail (two hardcoded 1–2-level functions today).
- [ ] **Step 3:** replace `structuralVault`/`structuralCollection` with one recursive builder. `ViewScope` stays binary at the *view* level (a view is owned by top-tier or a depth-1 Set); deeper Sub-Sets are structural `ResolvedGroup` children, never view owners. Galleries render nested Sub-Sets as labeled bands (cards don't nest).
- [ ] **Step 4:** run, verify pass. **Step 5:** commit.

### Task 1.5: Depth-1 view rule (O(1)) + moves + promotion (resolves review MAJORs)
**Files:** `PageSetManager.swift`, sidebar move/drag, `DetailScope.swift`, `ActiveViewStore.swift`.
**Depth check is O(1):** maintain `@MainActor private(set) var topTierIDs: Set<String>` (the top-tier container ids) on `PageSetManager`, synced on top-tier load/rename/delete. View-eligibility = `topTierIDs.contains(set.parentID)` — never a per-render hierarchy walk. This set is also what Task 1.2 Step 2's view-CRUD gate uses.
- [ ] **Step 1 (failing tests):** (a) depth-1 Set (`topTierIDs.contains(parentID)`) seeds/renders `views[]`; depth-2 Set with stray `views[]` ignores them. (b) Move depth-1 Set under another Set (→ depth-2): `views[]` stays in sidecar (dormant), stops rendering, **no file rename**. (c) **Promotion** — delete an intermediate Set via `.setOnly` so a depth-2 child becomes depth-1: its dormant views **re-surface** (render-time check, no re-serialize). (d) Insert a new parent above a depth-1 Set (→ depth-2): views go dormant. (e) **Cross-Type move at depth-2** still strips off-schema properties (move logic survives the merge).
- [ ] **Step 2:** run, verify fail. **Step 3:** implement the `topTierIDs` set + sync; view-eligibility via O(1) containment; moves filesystem-only; extend strip-free in-vault move to any depth.
- [ ] **Step 4:** run, verify pass. **Step 5:** commit.

### Task 1.6: NexusAdopter + healing recurse at any depth
**Files:** `NexusAdopter.swift` (`autoTagMissingSidecars`, hard-stops at depth-2 today), `ContainerIDHealer`.
- [ ] **Step 1 (failing test):** adoption auto-tags sidecar-less folders as `PageSet` at any depth (no roll-up); Finder-duplicate healing mints fresh ULIDs at depth.
- [ ] **Step 2–4:** replace the depth-2 walk with recursive `walkAllDepths`; run, verify. **Step 5:** commit.

### Task 1.7: Selection / Recents / breadcrumb / wikilink depth-gating (resolves review MAJOR)
**Files:** Recents + selection store, breadcrumb, `connections` path resolution (folds Vault/Collection/Set/Page).
- [ ] **Step 1 (failing tests):** moving a Set so its depth changes does not leave a stale selectable Recents entry (depth-2+ Sets are non-selectable); breadcrumb renders `Collection › Set › Sub-Set › Page` with non-clickable Set segments at any depth; wikilink path resolution folds arbitrary-depth Set paths.
- [ ] **Step 2–4:** implement; run, verify. **Step 5:** commit.

### Task 1.8: SQLite — recursive `page_sets` (bump 14→15)
**Files:** `IndexSchema.swift`, `IndexUpdater.swift`, `IndexQuery.swift`, `IndexQueryFilter.swift`.
- [ ] `page_sets` gains `parent_type_id` (nullable FK→page_types) + `parent_set_id` (nullable self-ref FK→page_sets); exactly one non-null. `set_order` column added. `pages.page_set_id` stays. Bump `currentSchemaVersion` 14→15 with a changelog comment. Add `IndexQueryFilter.targetSQL` `.pageSet(id)` → `page_set_id = ?` (review MAJOR #12).
- [ ] **Step 1 (failing test):** build index over the 4-deep fixture → `page_sets` rows have exactly one parent non-null; a depth-3 page indexes with the right `page_set_id`; a Set-targeted query returns its pages.
- [ ] **Step 2–4:** implement; run, verify. **Step 5:** commit.

### Task 1.9: Phase-1 docs + gate
- [ ] **CONTROLLER-MANUAL (not delegated):** rewrite `Sets.md` (recursive, "Sub-Set", depth-1 views, no roll-up, move=pure-dir); update `Collections.md` cross-refs (top tier still "Vault"-named until Phase 2 — note the pending rename). Committed by the controller right after the Phase-1 code lands.
- [ ] Full `xcodebuild test` via `builder` — ≥ baseline, zero fail.
- [ ] **Post-functional UIX review (mandatory):** in Test, build a 3-deep Set tree — sidebar nesting, structural detail render, depth-1 views surface / deeper don't, drag-reparent + promotion (delete intermediate) lose no data.

---

## Phase 2 — Top rename: `PageType`/"Vault" → `PageCollection`

Pure mechanical; `PageCollection` name is now free. Behavior-neutral.

### Task 2.1: Phase-2 sweep + file/type renames
- [ ] Run Phase-2 sweep (`PageType`/`Vault` family → `PageCollection`) via sentinel two-pass. Rename `PageType.swift`→`PageCollection.swift`, `PageTypeManager.swift`→`PageCollectionManager.swift`, Row/DetailView/Validator/Snapshot/Mock. Build green via `builder`. Commit.

### Task 2.2: NexusEnvironment injection audit (resolves review BLOCKER — SIGTRAP risk)
**Files:** `NexusEnvironment` + every `.environment(PageTypeManager.self)` / `.injectNexusEnvironment` site.
- [ ] `grep -rn 'PageTypeManager' Pommora/` → zero after sweep. Verify the renamed manager is injected exactly once in `NexusEnvironment` (stored property + `.environment(...)` line). Run a launch smoke test via `builder` (first-selection path) — no `EXC_BREAKPOINT`. Commit.

### Task 2.3: SettingsLabels collapse to two tiers
**Files:** `SettingsLabels.swift`, `Settings.swift` (`defaultsVersion`).
- [ ] Remove `pageType` label pair; `pageCollection` default `Collection`/`Collections`; `pageSet` default `Set`/`Sets`; `SidebarSectionLabels.pages` default `"Vaults"`→`"Collections"`. `defaultsVersion` bump rewrites old defaults → new **only where uncustomized**.
- [ ] **Step 1 (failing test):** old `settings.json` with `page_type: {"singular":"Vault"…}` loads without crash (Codable ignores the dropped key); old default labels migrate; a user-customized label survives. **Step 2–4** implement/run/verify. Commit.

### Task 2.4: SQLite `page_types`→`page_collections` (bump 15→16) + sidecar constant
**Files:** `IndexSchema.swift`+query files, `NexusPaths.swift`.
- [ ] Rename table `page_types`→`page_collections`, `page_sets.parent_type_id`→`parent_collection_id`, `pages.page_type_id`→`page_collection_id`; bump version 15→16. `NexusPaths`: add `pageCollectionSidecarFilename="_pagecollection.json"`; keep `legacyPageTypeSidecarFilename="_pagetype.json"` dual-read (top tier reads either). New top-tier writes use `_pagecollection.json`.
- [ ] `grep -rn 'page_types\|page_type_id' Pommora/` → only intentional. Test rebuild fresh. Commit.

### Task 2.5: Phase-2 docs + gate
- [ ] **CONTROLLER-MANUAL (not delegated):** rewrite `Collections.md` (now the top tier), retire/fold `PageTypes.md`, fix `[[PageTypes]]` wikilinks, update `.claude/CLAUDE.md` Overview to the two-tier model.
- [ ] Full test via `builder` — green. **Post-functional UIX check:** labels read "Collection"/"Set"/"Sub-Set" throughout.

### Task 2.6: Final corpus-wide doc sweep (CONTROLLER-MANUAL — read every doc end to end)
The closing documentation pass, done by hand by the controller per Nathan's directive — not a grep-and-replace, an actual read of each doc for terminology + altitude + wikilink correctness. Cover the FULL corpus, not just feature specs: `.claude/CLAUDE.md`, `Handoff.md`, `History.md`, `Framework.md`, `PommoraPRD.md`, every file in `// Features/` and `// Guidelines/`, and `// Planning/README.md`. Preserve each doc's existing formatting/wikilink/callout conventions (Obsidian rules). `History.md` gets the locked-decisions entry here (or in Task 3.3 if Phase 3 runs in the same pass).
- [ ] Read each doc; update PageType/Vault/Collection/Set terminology to the two-tier model at the right altitude; fix every `[[PageTypes]]`/`[[Sets]]`/`[[Collections]]` wikilink. `git grep -n 'PageType\|Page Type\|\bVault' .claude/` → only intentional history mentions remain. Commit.

---

## Phase 3 — Migration (irreversible; last)

### Task 3.1: Back up The Nexus
- [ ] Copy The Nexus `.nexus/` + all `_page*.json` sidecars to a timestamped backup outside the vault; verify. **No migration runs until this exists.**

### Task 3.2: One-shot sidecar migrator — per-folder recursive, bottom-up
**Files:** new `Domain/Nexus/SidecarRenameMigration.swift` + adoption hook.
Walk **per folder, depth-first, renaming each folder's sidecar in place before recursing into children** (NOT a global depth pass): old `_pagecollection.json` (depth-1) → `_pageset.json`; old `_pagetype.json` (root) → `_pagecollection.json`; rewrite each parent-ref key to `parent_id`. Idempotent (already-new = no-op). Bottom-up-per-folder is mandatory — top-down collides the two `_pagecollection.json` meanings.
- [ ] **Step 1 (failing test):** a **4-level** fixture in old layout (incl. an orphaned sidecar-less depth-4 folder) → after migration: root `_pagecollection.json`, every sub-folder `_pageset.json`, every sidecar has `parent_id`, no sibling collision, **a re-run is a no-op**.
- [ ] **Step 2–4:** implement (include the walk's recursive structure verbatim in code); run, verify.
- [ ] **Step 5:** run against **Test** first; open it; verify identical behavior. Then The Nexus. Commit.

### Task 3.3: Drop dual-read + ratify
- [ ] Remove `legacyPageTypeSidecarFilename`, the `vault_id`/`type_id`/`collection_id` decode fallbacks, old-name discovery branches. New format is the only format. Full test via `builder` — green.
- [ ] Add `History.md` entry (locked-decisions table + the two index-schema bumps). Commit. Update `// Planning//README.md`; move this plan to `Superseded/` on completion.

---

## React Coordination (hand to `pommora-react`)

Shared on-disk contract: **`_pagecollection.json` = top "Collection"; `_pageset.json` = recursive "Set"/"Sub-Set" any depth; parent ref `parent_id` (legacy `vault_id`/`type_id`/`collection_id` decode-only); `_pagetype.json` retired.** Neither build migrates a shared nexus (The Nexus, Test) until **both** read the new format — Swift Phase 3 is gated on React parity. Enforce by convention: the migrator (Task 3.2) only runs by explicit invocation, never auto-on-open, until React confirms parity.

## Round-1 Review Resolutions (folded)

Logic pass: BLOCKER "capped recursive struct" → phase reorder (merge+recurse together). BLOCKER migration proof → Task 3.2 per-folder recursive walk + 4-level fixture. MAJORs Recents/promotion/adopter-recursion → Tasks 1.5/1.6/1.7. MINORs Sub-Set/cross-window → § Sub-Set Derivation + depth-gating in 1.7.
Compile pass: BLOCKER missing `vault_id` fallback → Task 1.1 4-era decoder. BLOCKER injection SIGTRAP → Task 2.2. MAJORs manager fanout / discovery sites / SQLite bump+FK / IndexQuery `.pageSet` → § Manager Ownership Map + Tasks 1.3/1.8/2.4.

## Round-2 verification — resolved (plan certified)
1. **New collision: CONFIRMED, fixed** — `PageTypeManager`'s four CRUD methods on old `PageCollection` collide with `PageSetManager`'s same-named ones under the sweep. Resolution: Task 1.2 merges the four method-pairs into recursive single methods BEFORE sweeping; Task 1.1 made additive-only so it stays green. (Round-2 BLOCKER.)
2. **View-CRUD separability: CLEAN** — `mutateViews` is self-contained (container-id lookup, no `types`-array entanglement); depth-1 view CRUD moves to `PageSetManager` intact. No change needed beyond Task 1.2 Step 2.
3. **O(1) depth check: added** — Task 1.5 now stores `topTierIDs: Set<String>` for `contains(parentID)` gating (was an unspecified O(n) walk). (Round-2 MAJOR.)
4. **Two SQLite bumps: KEEP** — v15 (recursive `page_sets` FK→`page_types`) is internally consistent and the intermediate is required for dual-read; batching to one would break the v15 bridge. Delete-and-rebuild makes double-bump harmless.
5. **Consumer scan: no new omissions** — move-strip (1.5e), Recents/breadcrumb (1.7), adopter recursion (1.6), content-manager URL rebuild, OrderPersister (1.2 Step 1) all covered.
