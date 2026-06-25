# React–Swift On-Disk Alignment Implementation Plan — V2

> **For agentic workers:** REQUIRED SUB-SKILL: use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`. Steps use checkbox (`- [ ]`) syntax. React tasks run in the `pommora-react` worktree (`//Projects//Pommora-react-worktree`, branch `pommora-react`); Swift tasks run on `main`.

**Goal:** Make the React build's on-disk format byte-compatible with the Swift build's current 2-tier Collections/Sets model, consolidate entity ids to ULID-only on both builds, and align the `.nexus/` config layer — so one nexus folder opens fully intact in either app.

**Architecture:** Swift is the reference (it owns the post-rename format and already keeps disk ULID-only). Nearly all change is React-side: collapse its 3-tier model (`pageType → collection → set`, depth-capped) into Swift's 2-tier model (a `Collection` nesting recursive `Set`s), adopt Swift's exact sidecar + config keys, and add a stamp-on-open adopter mirroring Swift's `NexusAdopter` + `PageStamper`. Swift's only change is a guard test.

**Tech Stack:** React 19 · TypeScript · Electron (electron-vite) · Zustand · zod v4 · better-sqlite3 · eemeli/yaml · Vitest. Swift 6 / SwiftUI · GRDB · Yams.

**Review provenance (V1→V2):** three adversarial review passes folded in — *grounding* (premises confirmed against real code), *over-engineering* (dropped the redundant `tier-config.json` task; merged Phase-3 key-renames), *logic/coverage* (found the missed-file surface incl. `io/walk.ts` + renderer/store/view consumers, and the TypeScript compile-window flaw → expand-migrate-contract).

## Global Constraints

- **Swift is the reference. Adopt Swift's EXACT on-disk keys.** Casing is per-file: `settings.json` + all `_page*.json` sidecars + page frontmatter are **snake_case**; `nexus.json`, `homepage.json`, `saved-config.json`, `sidebar-sections.json` are **camelCase** (`schemaVersion`, `createdAt`, `collectionIDs`).
- **React architecture invariants:** main owns all fs; renderer talks only via typed IPC; IPC returns `{ ok:true,… } | { ok:false, error }`; colors authored as hex. The read walk stays read-only **except** the one new explicit adopt/stamp write-pass (Phase 2), which runs at open, not inside the read.
- **2-tier model, exactly** (canonical: `//.claude//Features//PageCollections.md` + `PageSets.md`): top folder = `_pagecollection.json` (schema-bearing); every nested folder at any depth = `_pageset.json`; **no `_pagetype.json`, no depth cap, no roll-up.** Sets recurse on the real folder tree; `parent_id` healed from folder position on load. Depth-1 (parent is a Collection) carries `views[]`; deeper Sub-Sets ignore them. Depth-1-ness is a runtime O(1) check, never stored.
- **Model A index** (regeneratable, per-build): every page row has `page_collection_id` (always) + `page_set_id` (NULL only at the bare Collection root); `page_sets` rows have `parent_collection_id` (depth-1) XOR `parent_set_id` (deeper).
- **Every persisted entity id is a ULID.** The deterministic `adopted-<sha256(path)[:16]>` placeholder is KEPT as an in-memory, read-stable id (it's what keeps ids stable when a write fails) but is **never written to disk** — the open-time adopter stamps a real ULID before any write captures it, and order writers filter it out.
- **Tier labels live in `settings.labels`, NOT `tier-config.json`.** Review confirmed Swift renders Context tier labels from `SettingsLabels` (`sidebar_sections.{areas,topics}` + `project.{singular,plural}`); `tier-config.json` is only a property-definition name fallback (`BuiltInContextLinkProperties`), not a UI label source. React reads tier labels from `settings.labels`. Do **not** build a `tier-config.json` reader.

### Commit discipline for the TypeScript type migration (load-bearing)

Renaming `NexusTree.vaults`→`collections` and deleting `PageTypeNode` breaks **every** consumer's compile at once — a naive per-file commit goes red and fails `npm test`. Use **expand-migrate-contract** so each commit is green:

1. **Expand** — in `types.ts`, ADD the new shapes alongside the old (keep `vaults` AND add `collections`; keep `PageTypeNode`; add `SetNode.sets` + `CollectionNode.properties`). Green: nothing consumed it yet.
2. **Migrate** — move consumers onto the new shapes in grouped green commits (read path; renderer/store/selection/view; CRUD/index). The old shapes still exist, so each group compiles + tests pass.
3. **Contract** — a final commit removes `vaults`/`PageTypeNode`/`'pageType'` once no consumer references them. Green.

- **Green gate:** React baseline **511 tests / 63 files** (`npm test` = `vitest run` in the worktree). Every commit ends green. Swift tasks gated by `xcodebuild test` via the `builder` agent (don't commit Xcode's Yams/GRDB pbxproj reorder).
- **Commit `.claude/*` docs explicitly** to the active branch.

---

## Phase 1 — Rename Port (React reads/writes/indexes/renders the 2-tier format)

Ordered as expand → migrate (data, then index, then renderer/view) → contract. Every task is TDD (write/adjust the failing test, implement, green, commit).

### Task 1: Expand — additive 2-tier shapes + sidecar schemas

**Files:**
- Modify: `React/src/shared/types.ts` (additive only), `React/src/shared/schemas.ts`, `React/src/main/paths.ts`
- Test: `React/src/shared/schemas.test.ts`

**Interfaces — Produces (additive; old shapes remain):**
- `types.ts`: add `CollectionNode { kind:'collection', id, title, icon?, path, properties?: PropertyDefinition[], sets: SetNode[], pages: PageNode[] }`; add `sets: SetNode[]` to `SetNode`; add `'collection'` already exists in `NodeKind`; add `NexusTree.collections?: CollectionNode[]` alongside `vaults`. Keep `PageTypeNode`, `vaults`, `'pageType'` for now.
- `schemas.ts`: `pageCollectionSidecar` gains `properties?: PropertyDefinition[]` (keep `property_definitions` readable as a deprecated alias during migration); `pageSetSidecar` gains `parent_id?: string` (keep `collection_id` readable). `SidecarKind` keeps `pageType` for now.
- `paths.ts`: unchanged this task.

- [ ] **Step 1: Failing tests** — `schemas.test.ts`: `pageCollectionSidecar` accepts a Swift sample with `properties`; `pageSetSidecar` accepts `parent_id`; both still accept the old keys (no regression).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** the additive fields. No consumer changes.
- [ ] **Step 4: Run, verify pass** (full `npm test` stays green — purely additive).
- [ ] **Step 5: Commit** — `feat(react): expand types+schemas with 2-tier shapes (additive, Swift keys)`

### Task 2: Migrate read path — recursive 2-tier walk

**Files:**
- Modify: `React/src/main/readNexus.ts`, `React/src/main/io/walk.ts` (the depth-cap/roll-up home), `React/src/main/readPage.ts` if it branches on tier
- Test: `React/src/main/readNexus.test.ts`, `React/src/main/readPage.test.ts`, `React/src/main/sidecarIO.test.ts`, `React/src/main/kind.test.ts`, `React/src/main/exclusion.test.ts` (fixture folder names only)

**Interfaces — Consumes:** Task 1. **Produces:** `readNexus(root) → NexusTree` populating `collections[]` from root folders bearing `_pagecollection.json`, each nesting `SetNode`s recursively from `_pageset.json` at any depth; reads schema from `properties`.

- [ ] **Step 1: Rewrite fixtures + failing tests** — `readNexus.test.ts`: sidecar fixture = root `Assignments/_pagecollection.json` (+`properties`) → `Spring/_pageset.json` (+`parent_id`) → `Midterm/_pageset.json` → `.md`, with a **3-deep** Set to prove no cap. Assert `tree.collections[0].kind==='collection'`, `.properties` read, depth-3 Sub-Set loads with its immediate `parent_id`, a Collection-root `.md` lands in `collections[0].pages`. Keep the stable-adopted-id-across-reads test (assert on `collections`).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — In `io/walk.ts`: remove the depth cap + loose-`.md` roll-up so the walker descends arbitrarily. In `readNexus.ts`: delete `readPageType`; `readCollection`→`readPageCollection` (gate `_pagecollection.json`, attach `properties`); `readSet` recurses (its root `.md`→`pages`, each `_pageset.json` subfolder → `readSet` with `parent_id`=this set's id). Root loop gates folders on `_pagecollection.json`, builds `collections[]`; top-order key reads `collection_order` (fall back to `vault_order` for one release). **Still also populate `vaults` (alias to `collections`) so renderer stays green until Task 5.**
- [ ] **Step 4: Run, verify pass** (read suites + full `npm test`).
- [ ] **Step 5: Commit** — `feat(react): recursive 2-tier read walk (Collection→Set*, no cap/rollup)`

### Task 3: Migrate CRUD + IPC contract

**Files:**
- Modify: `React/src/main/crud/schema.ts`, `React/src/main/crud/reorder.ts`, `React/src/main/crud/folderEntity.ts`, `React/src/main/mutate.ts`, `React/src/shared/mutate.ts` (the IPC `StateOrderKey`/kind contract), `React/src/main/contextMenu.ts` (New Collection/Set menu)
- Test: `React/src/main/crud/schema.test.ts`, `React/src/main/crud/reorder.test.ts`, `React/src/main/crud/folderEntity.test.ts`, `React/src/main/mutate.test.ts`

**Interfaces — Produces:** create top folder → `_pagecollection.json{id:ULID, properties:[]}`; create nested folder → `_pageset.json{id:ULID, parent_id}`; schema CRUD targets the Collection's `properties`; order writers persist `collection_order`/`set_order`/`page_order`.

- [ ] **Step 1: Update failing tests** — schema target writes/reads `properties`; only `collection`+`set` carry order; nested-create stamps `parent_id`; menu offers New Collection/New Set (not Vault).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — `crud/schema.ts`: `PAGE_TARGET.kind`→`'collection'`, schema key→`properties`. `crud/reorder.ts`: `CONTAINER_SIDECARS`=`[collection,set]`; top key→`collection_order`. `folderEntity.ts`/`mutate.ts`: nested create stamps `parent_id`. `shared/mutate.ts`: `StateOrderKey` `vault_order`→`collection_order`; drop `'pageType'`/`'vault'` kinds. `contextMenu.ts`: relabel + reroute create kinds.
- [ ] **Step 4: Run, verify pass** (full `npm test`).
- [ ] **Step 5: Commit** — `feat(react): 2-tier CRUD + IPC contract (properties schema, parent_id, collection_order)`

### Task 4: Migrate SQLite index — Model A

**Files:**
- Modify: `React/src/main/index/schema.ts`, `React/src/main/index/build.ts`, `React/src/main/index/upsert.ts`
- Test: `React/src/main/index/schema.test.ts`, `React/src/main/index/build.test.ts`, `React/src/main/index/upsert.test.ts`, `React/src/main/index/open.test.ts`, `React/src/main/sessionIndex.test.ts`

**Interfaces — Produces:** `page_collections(id,title,icon,modified_at,schema_version)`; `page_sets(id,parent_collection_id?,parent_set_id?,title,icon,modified_at,schema_version)`; `pages(id,page_collection_id,page_set_id?,title,icon,properties,modified_at)`. `SCHEMA_VERSION` bumped (forces delete-and-rebuild).

- [ ] **Step 1: Update failing tests** — no `page_types` table; depth-3 page → `page_collection_id` set + `page_set_id`=its immediate set; depth-1 set → `parent_collection_id` set, `parent_set_id` NULL; depth-2+ → `parent_set_id` set, `parent_collection_id` NULL; Collection-root page → `page_set_id` NULL.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — `schema.ts`: bump `SCHEMA_VERSION`; drop `page_types`+indexes; `page_sets` parents→`parent_collection_id`/`parent_set_id`; `pages`→`page_collection_id NOT NULL`+`page_set_id` nullable; fix indexes. `upsert.ts`: delete `upsertPageType`; `upsertCollection` (no parent); `upsertSet({parentCollectionId|parentSetId})`; `upsertPage(collectionId, setId?)`. `build.ts`: delete `TypeData`; walk `tree.collections` with `collectSets(node, collectionId, parentSetId?)` emitting one row per set (parent_collection_id at depth-1, parent_set_id deeper) + one per page (collection_id always, set_id = immediate set or null).
- [ ] **Step 4: Run, verify pass.**
- [ ] **Step 5: Commit** — `feat(react): Model A index — page_collection_id/page_set_id, recursive page_sets, drop page_types`

### Task 5: Migrate renderer + store + view pipeline

**Files:**
- Modify: `React/src/renderer/src/store.ts`, `React/src/renderer/src/selection.ts`, `React/src/renderer/src/Detail/Scope.ts`, `React/src/renderer/src/Detail/DetailPane.tsx`, `React/src/renderer/src/Detail/ContainerView.tsx`, `React/src/renderer/src/Detail/Table/TableView.tsx`, `React/src/renderer/src/Detail/Table/pipeline.ts`, `React/src/renderer/src/Sidebar/Sidebar.tsx`, `React/src/renderer/src/Sidebar/sidebarDnd.tsx`, `React/src/renderer/src/Sidebar/sidebarDndModel.ts`, `React/src/renderer/src/MarkdownPM/connections/index.ts`
- Test: `React/src/renderer/src/selection.test.ts`, `React/src/renderer/src/Sidebar/sidebarDndModel.test.ts`, `React/src/renderer/src/Detail/Table/pipeline.test.ts`

**Interfaces — Consumes:** Tasks 1-4. Move every renderer/store consumer from `vaults`/`PageTypeNode`/`'pageType'` to `collections`/`CollectionNode`/`'collection'` + recursive `SetNode.sets`.

- [ ] **Step 1: Update failing tests** — `selection.test.ts` + `sidebarDndModel.test.ts`: Collection→nested-Sets fixtures; depth-1 Set selectable, depth-2+ expand-only; cross-Set reparent updates `parent_id`/path. `pipeline.test.ts`: view source is a Collection/Set (not vault/pageType).
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — `store.ts`/`selection.ts`/`Scope.ts`: node-kind handling `'pageType'`→drop, `'vault'`→`'collection'`. `DetailPane.tsx`: drop vault case; `'collection'` + `'set'` cases. `ContainerView.tsx`: accept `CollectionNode`. `TableView.tsx`/`pipeline.ts`: source kind = collection/set. `Sidebar.tsx`/`sidebarDnd.tsx`/`sidebarDndModel.ts`: recursive Set render + reparent. `connections/index.ts`: container resolution across the 2-tier tree.
- [ ] **Step 4: Run, verify pass** (full `npm test`).
- [ ] **Step 5: Commit** — `feat(react): 2-tier renderer/store/view — Collection container + recursive Set tree`

### Task 6: Contract — remove the deprecated 3-tier shapes

**Files:** Modify `React/src/shared/types.ts`, `React/src/shared/schemas.ts`, `React/src/main/paths.ts`, `React/src/main/readNexus.ts` (drop the `vaults` alias write); Test: full suite.

- [ ] **Step 1:** grep `src` for `pageType|PageTypeNode|\bvaults\b|_pagetype|vault_order|property_definitions|collection_id` → confirm only definitions remain.
- [ ] **Step 2: Implement** — delete `PageTypeNode`, `NexusTree.vaults`, `'pageType'` from `NodeKind`, `pageType` from `SidecarKind` + `_pagetype.json` from `SIDECAR_FILENAME`, the `property_definitions`/`collection_id`/`vault_order` deprecated aliases, and the `vaults` alias write in `readNexus`.
- [ ] **Step 3: Run, verify pass** (full `npm test`); `npm run typecheck` clean.
- [ ] **Step 4: Commit** — `refactor(react): remove deprecated 3-tier shapes (PageTypeNode, vaults, _pagetype)`

### Task 7: Manual verification fixture

- [ ] **Step 1:** Convert `~/test` to new format (open once in Swift — its migrator converts `_pagetype.json`→`_pagecollection.json` + old middle `_pagecollection.json`→`_pageset.json` with a `.nexus/migration-backup-*`; or script the rename). Verify `find ~/test -name '_pagetype.json'` is empty.
- [ ] **Step 2:** `cd <worktree>/React && npm run build && env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` — confirm Collections + nested Sets + pages render (blank-sidebar bug gone). Screenshot.

---

## Phase 2 — Adopter + Adopted→ULID (both builds)

### Task 8: Swift — assert the ULID-on-disk invariant (reference; no behavior change)

**Files:** Test `PommoraTests/PageStamperTests.swift` (extend) — on `main`.

- [ ] **Step 1:** Add a test: load a frontmatter-less page, run the index-build stamp path, reload, assert persisted `id` is a ULID (no `adopted-` prefix). Add a second: simulate save failure, assert the in-memory id stays the deterministic `adopted-<hash>` (stable across two loads).
- [ ] **Step 2:** Run via builder agent: `xcodebuild test -only-testing:PommoraTests/PageStamperTests` — verify count > 0, green.
- [ ] **Step 3: Commit (main)** — `test(swift): assert adopted-id never persists + deterministic fallback on failed write`

### Task 9: React — order-write leak guard

**Files:** Modify `React/src/main/crud/reorder.ts`; Test `React/src/main/crud/reorder.test.ts`.

- [ ] **Step 1: Failing test** — `setStateOrder`/`setChildOrder` with `['<ulid>','adopted-deadbeef','<ulid2>']` persists only the two ULIDs.
- [ ] **Step 2-4:** `ids.filter(id => !id.startsWith('adopted-'))` before persist; green.
- [ ] **Step 5: Commit** — `fix(react): never persist adopted- placeholder ids into order arrays`

### Task 10: React — stamp-on-open adopter

**Files:**
- Create: `React/src/main/adopt.ts`; Modify: `React/src/main/index.ts` (`adoptNexus` hook); reuse `ids.ts` `newId`, `io/pageFile.ts` `mergeFrontmatter`, `crud/folderEntity.ts` sidecar writer.
- Test: `React/src/main/adopt.test.ts`

**Interfaces — Produces:** `stampAdopted(root): Promise<{stamped:number}>` — walks the tree **parents-before-children** (so a child's `parent_id` points at the parent's freshly-minted ULID, not its old placeholder); for any entity whose id starts with `adopted-`, mints a ULID and persists it (page → `id` into frontmatter via `mergeFrontmatter`, foreign keys preserved; folder → write/patch its sidecar with the ULID, healing `parent_id` from folder position). Idempotent; honors `excluded_folders`; skips `.`/`_` folders. **Scope: ULID stamping only — NOT Swift's full shape-classifier `NexusAdopter`; reuse existing atomic writers, don't clone its complexity.**

- [ ] **Step 1: Failing tests** — raw (sidecar-less) fixture: after `stampAdopted`, no `adopted-` ids remain; every folder has a sidecar ULID; a child Set's `parent_id` equals its parent's new ULID; a page's foreign frontmatter key survived; second run is a no-op; an `excluded_folders` entry is untouched.
- [ ] **Step 2: Run, verify fail.**
- [ ] **Step 3: Implement** — `adopt.ts` (parents-first depth-first stamp via existing writers); wire into `adoptNexus()` **after** `openSession(path)` and **before** `openSessionIndex(path)` so the index builds over ULIDs.
- [ ] **Step 4: Run, verify pass** (adopt suite + full `npm test`).
- [ ] **Step 5: Commit** — `feat(react): stamp-on-open adopter — mint ULIDs + sidecars for un-adopted entities (matches Swift)`

---

## Phase 3 — Config-Layer Alignment

Make a Swift nexus open in React with accent, labels, profile, homepage, and sections intact. (`tier-config.json` task dropped — tier labels come from `settings.labels`, handled in Task 11.) Casing per Global Constraints.

### Task 11: Settings reads — accent, structured labels, saved-config

**Files:** Modify `React/src/main/readNexus.ts` (settings + saved-config reads), `React/src/shared/types.ts` (`NexusLabels` shape + `DEFAULT_LABELS`, accent value set), renderer label/accent consumers; Test `readNexus.test.ts`.

**Interfaces — Produces:**
- accent: read `settings.accent_color` (values `red/orange/yellow/green/blue/purple/pink/gray`; absent/null = system).
- `NexusLabels` (structured): `{ sidebarSections:{areas,topics,pages}, pageCollection:{singular,plural}, pageSet:{singular,plural}, project:{singular,plural}, agendaTask:{singular,plural}, agendaEvent:{singular,plural} }` read from `settings.labels.{sidebar_sections,page_collection,page_set,project,agenda_task,agenda_event}`. "Sub-Set" = `"Sub-"+pageSet.singular` (derived). Tier labels come from here (Areas/Topics = `sidebar_sections`; Project = `project`).
- saved-config: read `savedConfig.items: [{key,label}]` (was `{labels:{…}}`), map by `key` (`homepage`/`calendar`/`recents`); preserve `schemaVersion` on write.

- [ ] **Step 1: Failing tests** — `accent_color:"blue"`→`'blue'`, `{}`→system; a Swift `labels` blob parses to the structured shape with Swift defaults on missing keys (section `pages` default `"Collections"`); a `{schemaVersion,items:[{key:"homepage",label:"Home"}]}` resolves Homepage's label to `"Home"`.
- [ ] **Step 2-4:** Implement the three reads; update every renderer site reading `labels.vaults`/`labels.collection`/`labels.set`/`accent` to the new shapes. Green.
- [ ] **Step 5: Commit** — `feat(react): settings reads aligned — accent_color, structured SettingsLabels, saved-config items[]`

### Task 12: Config-file reads — sidebar-sections + nexus.json identity

**Files:** Modify `React/src/main/readNexus.ts` (sections + identity reads) + `paths.ts` if needed; Test `readNexus.test.ts`.

**Interfaces:** sidebar-sections (camelCase) = `{sections:[{id,label,collectionIDs:string[]}]}` (was `vaultIDs`). nexus.json (camelCase) = `{schemaVersion,id,createdAt}` — read `id`+`createdAt`; stop reading `description`/`photo` here (moved to Task 13).

- [ ] **Step 1: Failing tests** — a section `{id,label,collectionIDs:["c1"]}` claims collection `c1`; nexus `{schemaVersion,id,createdAt}` sets `id`+`createdAt` and absence of description/photo doesn't blank the header.
- [ ] **Step 2-4:** Read/write `collectionIDs`; update the `userSections` partition; read camelCase identity. Green.
- [ ] **Step 5: Commit** — `feat(react): config-file reads aligned — sidebar collectionIDs + nexus.json camelCase identity`

### Task 13: Profile pic + subtitle — parity with Swift (read + write + render)

**Files:** Modify `React/src/main/readNexus.ts` (profile read), `React/src/main/mutate.ts` (`setProfileImage`/`setProfileSubtitle` reusing the `nexus-asset://` + asset-copy plumbing), the nexus-header renderer; Test `readNexus.test.ts` + a mutate test.

**Interfaces:** profile image = `settings.profile_image` (nexus-relative path into `.nexus/assets/<nexusID>/`); subtitle = `settings.profile_subtitle` (≤30 chars). React stops reading `description`/`photo` from `nexus.json`.

- [ ] **Step 1: Failing tests** — settings `{profile_image, profile_subtitle}` → tree exposes both; `setProfileImage` copies the file under `.nexus/assets/<nexusID>/` and writes the nexus-relative path to `settings.profile_image` (other settings keys preserved); `setProfileSubtitle` writes `settings.profile_subtitle`, enforces ≤30 chars.
- [ ] **Step 2-4:** Implement read + the two write ops (reuse banner asset-copy + `nexus-asset://` serving); render the profile pic + subtitle in the nexus header to match Swift. Green.
- [ ] **Step 5: Commit** — `feat(react): nexus profile pic + subtitle from settings (parity with Swift)`

### Task 14: homepage.json — preserve Swift's full shape on banner edits

**Files:** Modify the homepage `setBanner` writer in `React/src/main/mutate.ts`; Test a mutate test.

**Interfaces:** homepage.json (camelCase) = `{schemaVersion, icon?, banner?, blocks: ContextBlock[], modified_at}`. React edits only `banner`, round-trips the rest.

- [ ] **Step 1: Failing test** — write a homepage.json with `blocks:[{…}]`+`icon`; call homepage `setBanner`; assert `blocks`+`icon`+`schemaVersion` survive, only `banner` changed.
- [ ] **Step 2-4:** Ensure the writer is read-merge-write (`mutateJson` spread), never a full overwrite. Green.
- [ ] **Step 5: Commit** — `fix(react): preserve homepage blocks/icon/schemaVersion when setting banner`

### Task 15: Integration verification

- [ ] **Step 1:** Full `npm test` green (≥511, adjusted).
- [ ] **Step 2:** Launch React on a **Swift-managed** nexus (real one, or `~/test` post-conversion): confirm Collections/Sets render, accent applies, custom tier/entity labels show, profile pic + subtitle render, homepage banner + blocks survive a banner change, user sidebar sections resolve. Screenshot.
- [ ] **Step 3:** Reverse check: after React edits (create page, set profile pic, reorder), reopen in Swift — no data loss, no re-migration churn.

---

## Self-Review

- **Spec coverage:** Phase 1 ↔ the 3-tier→2-tier port (read/walk/schema/types/CRUD/IPC/index/renderer/store/view + contract), now covering the previously-missed `io/walk.ts`, `Scope.ts`, `selection.ts`, `store.ts`, `sidebarDnd.tsx`, `TableView.tsx`/`pipeline.ts`, `connections/index.ts`, `contextMenu.ts`, `shared/mutate.ts`, and their tests. Phase 2 ↔ Adopted→ULID + stamp-on-open (parents-first). Phase 3 ↔ accent, labels, saved-config, sidebar-sections, nexus identity, profile pic, homepage. No migrator (no React-only nexuses). No tier-config reader (redundant).
- **Green commits:** expand-migrate-contract keeps every Phase-1 commit compiling + `npm test` green despite the atomic TS type rename.
- **Type consistency:** `properties` (not `property_definitions`); `parent_id` (not type_id/vault_id/collection_id); index `parent_collection_id`/`parent_set_id`; `collections` (not `vaults`).
- **Casing:** snake_case for settings + sidecars + frontmatter; camelCase for nexus/homepage/saved-config/sidebar-sections.
- **Resolved risks:** tier-config redundancy (dropped); compile-window (expand-migrate-contract); coverage gap (missed files added); adopter parent-before-child ordering (specified).

---

## Execution State — Phase 2 complete (Tasks 8–10 shipped; at the Phase 2 checkpoint)

**Phase 2 done.** Adopted→ULID is closed on both builds.
- **T8 (Swift, `main` `ca9372b`):** `PageStamperTests` now asserts the index-build stamp path persists a real ULID (no `adopted-` on disk) and that a failed write keeps the deterministic `adopted-<hash>` id, stable across reloads. Suite = 5 tests, green via builder agent.
- **T9 (React, `pommora-react` `1626b46`):** `reorder.ts` strips `adopted-` ids at both persistence points (`setStateOrder` + `setContainerOrder`, so `setChildOrder` inherits it) via a shared `persistable()` helper — a transient placeholder can never land in an order array.
- **T10 (React, `pommora-react` `340e196`):** new `src/main/adopt.ts` `stampAdopted(root)` — a parents-before-children FS walk that mints a ULID for every un-adopted entity (raw folder → `_pagecollection.json` at root / `_pageset.json` nested with healed `parent_id`; page → `id` into frontmatter via `mergeFrontmatter`, foreign keys preserved). Idempotent (checks ids on disk, mode-independent), honors `excluded_folders`, skips `.`/`_`/Agenda folders. Wired into `index.ts adoptNexus()` after `openSession`, before `openSessionIndex`, best-effort try/catch. Gate: 522 tests / 64 files, typecheck clean.

**Design notes for Phase 3 / future:**
- The adopter heals `parent_id` **only at mint time** — already-adopted folders are left byte-identical (idempotency). Harmless because `readNexus` derives parent from folder position at runtime and never reads stored `parent_id`; the stored value exists purely for Swift parity + is write-only React-side.
- The adopter does **not** create `.nexus/nexus.json` identity. So a *truly raw* folder (no `nexus.json`) gets sidecars stamped on disk, but `readNexus` stays in raw mode (`sidecarMode=false`) and ignores them. This is fine for the real use case (React opens Swift nexuses, which have identity → `sidecarMode=true` → stamped sidecars are read; and a foreign folder dropped *into* an adopted nexus is read correctly). Pure-raw folders are the "open once in Swift first" dev path. If React ever needs to adopt a bare folder standalone, identity-creation would belong here or in Task 12.

---

### (historical) Execution State — post-compact handoff (Phase 1: 6 / 7 done — Task 7 = checkpoint)

**Read this whole section before resuming. Everything below is verified against committed code.**

### Where the work lives
- **React work → the worktree:** `/Users/nathantaichman/The Studio/Projects/Pommora-react-worktree`, branch **`pommora-react`** (off `main`). All Tasks 1–7, 9, 10 commit here. `node_modules` is already installed (Node ABI for the Vitest gate).
- **Swift + this plan + shared truth → main repo:** `/Users/nathantaichman/The Studio/Projects/Project Pommora` on `main`. Task 8 (Swift) commits here. **This plan doc is in main's working tree, UNCOMMITTED** — consider committing it to `main` so it isn't lost on a branch switch.
- **Gate (run in `<worktree>/React`):** `npm test` (= `vitest run`, ~2s) **and** `npm run typecheck` (node+web). Both must be green to commit. Baseline started at 511; now **514** (3 tests added).
- **Commits so far (pommora-react):** `33ec775` (T1) → `652f9f1` (T2) → `be15dcf` (T3) → `66fa5c0` (T4) → `a1a7ac8` (T5) → `b8e33ff` (T6). Working tree clean. Baseline now **516 tests / 63 files**; typecheck (node+web) clean.

### The non-negotiable strategy: expand-migrate-contract
There are **two** coupling failure modes — both bit during execution, both must be respected:
1. **Type coupling (compile-time):** renaming/removing a `types.ts` member breaks every consumer at once → `npm test` won't compile. Fix: add new shapes *alongside* old (T1 did this), migrate consumers, delete old (T6).
2. **Data coupling (runtime):** tests that run the *real* `readNexus` (index/build, sessionIndex, mutate round-trips) break when the tree's output changes, even when types compile. T2 first *flipped* the read and broke 6 tests; the fix is the **dual-walk** — `readNexus` emits BOTH legacy `vaults` (via `legacyRead*`) AND new `collections`, side by side, until consumers migrate. T6 removes the legacy walk.

### Conventions locked in (keep consistent)
- **Swift keys:** schema under `properties` (NOT `property_definitions`) on the Collection; Set parent = `parent_id` (NOT type_id/vault_id/collection_id); top order = `collection_order`.
- **Casing:** snake_case for `settings.json` + `_page*.json` sidecars + page frontmatter; **camelCase** for `nexus.json`/`homepage.json`/`saved-config.json`/`sidebar-sections.json`/`tier-config.json`.
- **`tier-config.json` is NOT read** (dropped — Swift renders tier labels from `settings.labels`, verified). Don't build a reader.
- **`io/walk.ts` needs NO changes** (false positive — generic `.md` lister; the depth cap lived in `readNexus`'s `collectMdDeep`, now legacy-only).
- **Index `SCHEMA_VERSION = 15`**, deliberately ≠ Swift's 16 (safe rebuild churn on cross-open, no silent foreign-schema query).
- Per-task: TDD-ish (adjust test → impl → both gates green → commit). **Stage explicit files** (never `git add -A` — parallel-session rule). Commit trailer: `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.
- Execution mode = **inline with checkpoints at phase boundaries** (Nathan's choice). Pause + report after Task 7 (Phase 1 checkpoint), Task 10 (Phase 2), Task 15 (Phase 3).

### Nathan's ratified decisions
Full port (read+write+index+renderer); **stamp-on-open adopter** matching Swift (Task 10); **no old-format migrator** (no React-only nexuses); **fold config gaps in** (Phase 3); **add the profile pic feature** to React (Task 13, real read+write+render, not just a key-repoint).

### DONE: Task 5 (`a1a7ac8`) — renderer + store + view flipped to 2-tier
Renderer now consumes `collections`/`CollectionNode`/recursive `SetNode.sets`. Added `{kind:'set';id;path}` to `SelectionState` + `SelectTarget` (depth-1 Sets selectable; depth-1-ness is a render-position check, never stored); deeper Sub-Sets are expand-only. Set drag-drop generalized to reparent across any Collection/Set with a cycle guard (`setContainerOf` + `isSelfOrDescendant`). **Deviations from plan (verified):** `pipeline.ts`/`pipeline.test.ts` needed NO change (ViewRow-only, zero node coupling); removed `SetNode.selectable` (depth-1 Sets ARE selectable — the stored `false` was a lie); added `'set'` to `BannerOwnerKind` (main's `setBanner` is generic over `SIDECAR_FILENAME[kind]`, so a Set banner round-trips into `_pageset.json`). Section header temporarily binds `tree.labels.collection` (singular) — **Task 11** reshapes labels to singular/plural and supplies the proper plural.

### DONE: Task 6 (`b8e33ff`) — contract: all 3-tier shapes removed
Deleted the legacy walk + every 3-tier symbol (see commit body). `NexusTree.collections` + `UserSection.collections` now required. Six test files remapped to Collection→recursive-Set (5 via parallel sonnet agents, mutate.test.ts the big one — all reviewed, assertions meaningful not weakened). Contract grep clean (only Model A columns `parent_collection_id`/`page_collection_id` + the legit Agenda `property_definitions` remain). **Note for a future cleanup (out of scope):** `ChildOrderKey` still lists `'collection_order'` though collections are top-level now — harmless vestige.

### NEXT: Task 7 — manual verify (Phase 1 CHECKPOINT — needs Nathan)
`~/test` is currently OLD format (`_pagetype.json`) — convert it (open once in Swift, or script the rename) so `find ~/test -name _pagetype.json` is empty. Launch: `cd <worktree>/React && npm run build && env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` (ELECTRON_RUN_AS_NODE MUST be unset). Confirm Collections + nested Sets + pages render. Screenshot. **Post-functional UIX review is mandatory** before Phase-1 closeout. (Original spec retained below.)

### Task 7 — manual verify (original spec)
`~/test` is currently OLD format (`_pagetype.json`) — convert it (open once in Swift, or script the rename) so `find ~/test -name _pagetype.json` is empty. Launch: `cd <worktree>/React && npm run build && env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` (ELECTRON_RUN_AS_NODE MUST be unset). Confirm Collections + nested Sets + pages render. Screenshot. **Post-functional UIX review is mandatory** before Phase-1 closeout.

### Phase 2 (Tasks 8–10) and Phase 3 (Tasks 11–15)
Specs are in the Task sections above. Key reminders: T8 is Swift on `main`, run via the **builder agent** (`xcodebuild test -only-testing:PommoraTests/PageStamperTests`, verify count > 0). T9 = one-line `adopted-` filter in `reorder.ts`. T10 = new `src/main/adopt.ts` (`stampAdopted`, parents-before-children, reuse existing writers, hook in `index.ts` `adoptNexus` after `openSession` before `openSessionIndex`). T11 reshapes `NexusLabels` (flat → `{singular,plural}` pairs + nested `sidebar_sections`). T13 reuses the `nexus-asset://` + asset-copy plumbing. T14 must be read-merge-write (preserve homepage `blocks`/`icon`/`schemaVersion`).

### Source-of-truth specs
`//.claude//Features//PageCollections.md` + `PageSets.md` (target model); `//.claude//Features//Architecture.md` (on-disk). The cornerstone holds: open the file and verify before asserting.
