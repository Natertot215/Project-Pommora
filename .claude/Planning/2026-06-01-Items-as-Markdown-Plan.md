## Items as Markdown — Implementation Plan (v5, finalized — 4 review rounds, grep-verified)

> **For agentic workers:** REQUIRED SUB-SKILL — `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans`, task-by-task. Build/test ALWAYS via a background builder subagent (CLAUDE.md quirk #13). Trust `xcodebuild`, not SourceKit (quirk #3). `-only-testing:PommoraTests/<Struct>` matches the **struct** name (quirk #17) — confirm a non-zero executed count. **Prove every "all N sites" claim by grep.**

**Goal:** Convert Items from whole-`.json` to plain `.md` (YAML frontmatter + body), sharing Pages' `AtomicYAMLMarkdown` pipeline, with the rich capped description as the markdown body (Shape A); Items stay a distinct *form* of one entity-type.

**Architecture:** `ItemFrontmatter` carries structured fields (`id`/`icon`/`tier1-3`/`properties`/timestamps + a reserved `kind` stamp emitted as on-disk key `Class`); description = body. Kind authority = parent-folder sidecar; the `Class` stamp is non-authoritative and self-heals. Foreign frontmatter keys are **preserved by value (never culled) on every Item AND Page write path**. Rides the Phase-6 `ItemValidator` rewire. **Reads are format-agnostic (`.md`+legacy `.json`) and write/delete/rename resolve the actual on-disk extension during the transition** so live `.json` Items never vanish, double, or orphan before the migration normalizes them.

**Tech Stack:** Swift 6 (strict concurrency + ExistentialAny), SwiftUI/AppKit, Yams 5.4.0 (pinned, confirmed), GRDB, Swift Testing. Atomic writes via `Data.write(.atomic)` + `SchemaTransaction`.

---

### Locked decisions

1. **Items are plain `.md`** (never `.item.md`). Shape A: capped description = body, single source of truth, no frontmatter-description, no mirror.
2. **Reserved stamp = on-disk key `Class`** (`item`|`page`), Codable `var kind: KindStamp` with `case kind = "Class"`. UI-hidden, **non-authoritative**; folder sidecar wins.
3. **Char cap = 1000 markdown-SOURCE chars** (raw `.count` of the draft string; markup counts). **Provisional — "for now" per Nathan 2026-06-01 (was 250).** The LIVE cap is ALREADY bumped to 1000 (commit pending: `ItemWindow` counter `:217/:220/:482` + dead `ItemValidator.maxDescriptionLength:13` + ComponentLibrary summaries); Task 9 formalizes save-time enforcement + DRY-unifies the two literals (UI should reference `maxDescriptionLength`). Validated on save (Task 9), not silently clamped; foreign over-cap render-clamped + warned. Counter shows `/ 1000`; the `descriptionTooLong` message references characters.
4. **Foreign frontmatter PRESERVED by VALUE — no culls — on EVERY Item AND Page write path.** Caveat: Yams round-trips *by value*, reflowing flow→block style and **dropping comments/anchors** (content safe, exact styling/comments not). Covered: all Item write paths + all 8 full-`PageFrontmatter` re-serialization paths (File map).
5. **Kind = three-state** (folder authority): ABSENT → write from folder; AGREES → proceed; DISAGREES → relocate to a hidden `.unsorted` inbox (future-UI-surfaced; no silent self-heal). Homeless file → `.unsorted`. **Resolution OUT of `.unsorted` is deferred with that UI.**
6. **Stamp write = a YAML-level single-key set** (`setStampKey`: compose mapping → set/correct only the `Class` node → serialize), NOT a typed save (a typed save would synthesize+persist an `adopted-<hash>` id and inject ~7 keys). It is **value-preserving, not byte-identical** (same Yams reflow caveat as #4 — a foreign Page's flow-style/comments reflow once on first stamp). Adds only `Class`, every other key's value unchanged. One write max/file; idempotent run-2-vs-run-1.
7. **Cross-Type move** = existing strip-on-move: Type-scoped *schema properties* not in the destination are voided (correct — non-transferable), while non-Type-scoped *foreign/plugin frontmatter keys* ride along (via `preservingFrom: srcURL`); `Class` carried unchanged. No Item↔Page move exists (post-v1 Prospect); kind CHANGES only via the deferred `.unsorted`-resolution.
8. **Agenda stays JSON.** Item markdown-formatting restrictions DEFERRED to the Item Window redesign.

### Landmine map

- **Landmine 1 — full-`Item` serialization clobber: exactly 8 sites** (`grep 'AtomicJSON.decode(Item'` = 6, + 2 typed-stage moves = 8): ① `PageContentManager+CRUD.swift:653`(+:659) · ② `PropertyIDMigration.swift:495`(+:498, catch-log-continue; **inside `applyItemType` whose enumerator is Task 10's — carved out of Task 3d**) · ③ `DualRelationCoordinator.swift:348`(+:351, wrapped→silent) · ④ `ItemContentManager+CRUD.swift:587`(+:592, unwrapped→loud) · ⑤ `:642`(+:653 write) · ⑥ `ItemTypeManager.swift:1014`(+:1017, wrapped→silent) · ⑦ `ItemContentManager+CRUD.swift:347` typed-stage (moveItemBetweenCollections) · ⑧ `ItemContentManager+CRUD.swift:434` typed-stage (moveItemAcrossTypes). → **Task 3d** routes ①③④⑤⑥⑦⑧ through the preserving Item save; **② stays AtomicJSON-preserving until Task 10.** (`SchemaTransaction.stage<Codable>` JSON-encodes at [SchemaTransaction.swift:69](Pommora/Pommora/AtomicIO/SchemaTransaction.swift#L69).)
- **Landmine 2 — the stamp pass is net-new code.** → **Task 5**.
- **Landmine 3 — `contentSniff` regresses, sidecar-required Item Types** ([NexusAdopter.swift:545](Pommora/Pommora/Nexus/NexusAdopter.swift#L545)→:546; `tagDepth0IfMissing` early-returns if a sidecar exists, so exposure = a sidecar-less `.md` Item folder). → **Task 4**.
- **Landmine 4 — `loadLenient` unwired + the 7th read site.** `grep 'Item.load('` = **7** read sites; ALL must move to the lenient/dual loader: `ItemContentManager.swift:84,:122`; `IndexBuilder.swift:310`; `ItemWindow.swift:429`; **`ItemContentManager+CRUD.swift:734` (unlinkTier — was missed)**; `:784`/`:795` (locateItemFile title lookup). → **Task 3b**.

### File-structure map

**Modify**
- `AtomicIO/AtomicYAMLMarkdown.swift` — preserving `write` + preserving `encode` overload + shared envelope helper + YAML-level `setStampKey(at:value:)` (Tasks 1, 5).
- `Content/PageFrontmatter.swift` — `static modeledKeys` (Task 1, DONE) + `var kind: KindStamp` (`case kind="Class"`, default `.page`) (Task 2). `Content/Item.swift` → split into `ItemFrontmatter` (Task 3a), which is BORN with `var kind` (default `.item`) + its own `static modeledKeys` — NOT added to the current `Item` struct in Tasks 1/2. `ItemFrontmatter` **drops `description` from CodingKeys** (it's the body now; Item.swift:18 currently has it). On-disk `createdAt`/`modifiedAt` optional; **both `Item.load` AND `Item.loadLenient` backfill missing timestamps from file creation/modification dates** (NOT default-to-1970); composite `Item` keeps them non-optional (Task 3a).
- `Content/PageFile.swift` — `PageFile.save` → preserving write; extract shared `relativePath`/`shortHash` (Tasks 1, 3b).
- **Page foreign-key preservation (Task 1) — `PageFile.save` + ALL 8 full-`PageFrontmatter` encode/stage paths** (`grep 'AtomicYAMLMarkdown.encode('` = 7): `PageContentManager+CRUD.swift:388,:481,:631`; `PropertyIDMigration.swift:462`; `DualRelationCoordinator.swift:335`; `PageTypeManager.swift:1000`; **`ItemContentManager+CRUD.swift:567` (Page branch of stageBackRefClear — was missed)**. Move/in-place sites use `preservingFrom: <the URL they read from>`.
- `Content/Item.swift` read + write/delete/rename wiring (Task 3b): the 7 `Item.load` sites → lenient/dual; the 3 READ enumerators (`ItemContentManager.swift:82,:120`; `IndexBuilder.swift:307`) become `(ext=="md" || ext=="json")` dual-dispatch; write/delete/rename resolve the actual on-disk extension (see Task 3b).
- `AtomicIO/NexusPaths.swift:319` — `.json`→`.md` literal (the path *constructor* `itemFileURL`); add `unsortedDir` (Tasks 3c, 6).
- `AtomicIO/Filesystem.swift` — `moveToUnsorted(_:nexusRoot:)` sharing a `relocate` core with `moveToTrash` (:159) **incl. its out-of-nexus guard + standardizedFileURL** (Task 6).
- **5 WRITE-side filter flips `"json"`→`"md"`** (Task 3c): `ItemContentManager+CRUD.swift:583,792`; `ItemTypeManager.swift:1005`; `DualRelationCoordinator.swift:345`; `PageContentManager+CRUD.swift:649`. (`PropertyIDMigration.swift:609` → Task 10. The 3 read enumerators → dual, above.)
- 8 clobber sites (Landmine 1) → Task 3d (② carved out).
- `Nexus/NexusAdopter.swift` — `contentSniff` (Task 4); stamp pass + `adoptionExcludedSubFolderNames:240` (Task 5); `cleanupLegacyOrphans` call in `autoTagMissingSidecars` (Task 8).
- `Validation/ItemValidator.swift:20` + 6 CRUD entry points + `ItemWindow.swift:478` (Task 9).

**Create:** `Content/KindStamp.swift` (Task 2); test files per task. *(No new `ItemFile` type — reuse `Item.load`/`save`/`loadLenient` on the existing `Item`.)*

---

## Phase 1 — serialization core

### Task 1: Preserving codec (`write` + `encode` overload + `setStampKey`), Items AND Pages

**Files:** `AtomicIO/AtomicYAMLMarkdown.swift`; `Content/PageFile.swift`; the 8 Page encode/stage paths in the File map; `static modeledKeys` on both frontmatters. Test `PommoraTests/AtomicIO/FrontmatterPreservationTests.swift`.

**Why:** `encode` (called by `write`) re-serializes only `CodingKeys` ([AtomicYAMLMarkdown.swift:56-57](Pommora/Pommora/AtomicIO/AtomicYAMLMarkdown.swift#L56-L57)), dropping foreign keys. 65+ live Pages carry plugin frontmatter. Requirements: **(A)** stable key order; **(B)** a *cleared* modeled top-level key (`icon`/`modified_at`/`folded_headings`, all `encodeIfPresent` — [PageFrontmatter.swift:77,83,87-88](Pommora/Pommora/Content/PageFrontmatter.swift#L77)) actually clears.

- [ ] **Step 1: Failing test** — round-trip with a modeled key, a foreign key, a cleared modeled key (foreign survives, cleared gone, order stable across two saves); PLUS `setStampKey` on a frontmatter-less foreign file adds ONLY `Class:` (no id/tier/properties); PLUS a flow-style/comment fixture (assert value-preserved, accepting reflow).
- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement.** `static let modeledKeys = Set(CodingKeys.allCases.map(\.rawValue))` (`CaseIterable`). Order-preserving, clear-aware merge as BOTH `write(...preservingFrom:modeledKeys:)` and `encode(...preservingFrom:modeledKeys:) -> Data` sharing one envelope helper; plus the YAML-level single-key `setStampKey`:

```swift
private static func mergedData<T: Codable>(frontmatter: T, body: String, preservingFrom existing: URL?, modeledKeys: Set<String>) throws -> Data {
    let typedYAML = try YAMLEncoder().encode(frontmatter)
    guard let existing, let raw = try? String(contentsOf: existing, encoding: .utf8),
          let (fm, _) = try? split(raw), !fm.isEmpty,
          case let .mapping(existingMap)? = try? Yams.compose(yaml: fm),
          case let .mapping(typedMap)? = try? Yams.compose(yaml: typedYAML)
    else { return try envelope(typedYAML, body) }
    var merged = Yams.Node.Mapping([])                       // ([]) — no nullary init in Yams 5.4.0 (confirmed)
    for (k, v) in existingMap {
        guard let key = k.string else { merged[k] = v; continue }
        if modeledKeys.contains(key) { if let tv = typedMap[k] { merged[k] = tv } /* else cleared → drop */ }
        else { merged[k] = v }
    }
    for (k, v) in typedMap where merged[k] == nil { merged[k] = v }
    return try envelope(try Yams.serialize(node: .mapping(merged)), body)   // sortKeys:false (confirmed)
}
static func setStampKey(at url: URL, value: String) throws {            // value-preserving single-key set
    let (fm, body) = try split(try String(contentsOf: url, encoding: .utf8))
    var map: Yams.Node.Mapping = { if case let .mapping(m)? = try? Yams.compose(yaml: fm) { return m }; return .init([]) }()
    map["Class"] = Yams.Node(value)
    try envelope(try Yams.serialize(node: .mapping(map)), body).write(to: url, options: [.atomic])
}
```

Switch `PageFile.save` + ALL 8 Page paths onto the preserving variants (`preservingFrom:` = the URL each reads from; move sites :388/:481 use `page.url` loaded at :384; the in-place sites :567/:631/:335/:462/:1000 use their read URL).

> **VERIFY (loop, empirical):** confirm the envelope `fmText` ends in exactly one newline and contains no inner `---`/`...` markers. (Yams API otherwise confirmed against the 5.4.0 checkout.)

- [ ] **Step 4: Run, PASS** (+ rewrite any `PageFile` test asserting exact bytes — key order shifts).  - [ ] **Step 5: Commit** `feat(io): order-preserving foreign-key retention (Pages + Items) + value-preserving single-key stamp`

---

### Task 2: `KindStamp` + the `Class` Codable property (PageFrontmatter; Item side rides Task 3a)

**Files:** Create `Content/KindStamp.swift`; modify `PageFrontmatter` only; Test `KindStampTests`.

`enum KindStamp: String, Codable, Sendable, Equatable { case item, page }`. On `PageFrontmatter`: `var kind` (default `.page`), `case kind = "Class"` in `CodingKeys` (already `CaseIterable` per Task 1), `encode` **unconditional** (every typed Page save stamps `Class: page`) + `decodeIfPresent ?? .page`. Because `Class` joins `CodingKeys`, `PageFrontmatter.modeledKeys` now includes it — the stamp is a Pommora-owned *modeled* key, not foreign (so the preserving merge substitutes it, never treats it as a foreign pass-through). **Item-side `kind` is NOT added here** — `ItemFrontmatter` is born in Task 3a carrying `kind=.item`; adding it to the soon-to-be-split `Item` struct now would be double-work (Studio iteration rule). *(Re-assessment after Task 1: was "both frontmatters"; narrowed to PageFrontmatter to avoid churning `Item` twice.)*

- [ ] Steps: failing test (only item/page; typed Page save emits `Class: page`; decode w/o `Class` defaults to `.page`) → implement → update any existing Page test asserting an EXACT frontmatter key-set (now includes `Class`) → green → commit `feat(model): Class kind-stamp Codable property on PageFrontmatter`.

---

### Task 3 (ATOMIC — ONE green commit): Items → Markdown

> **Atomic:** model split + read/write/delete/rename transition handling + 7 clobber sites + filters are mutually dependent for a green tree. Implement+test each sub-step locally; run the FULL suite once; land ONE commit. Spike 3a's codec round-trip first.

- [ ] **3a — Model split (Shape A):** `ItemFrontmatter` (id/icon/tier1-3/properties/createdAt?/modifiedAt? + `kind=.item`); **drop `description` from CodingKeys** (it's the body). `Item` = composite (frontmatter + `description`=body + title), `createdAt`/`modifiedAt` **non-optional on the composite**. `Item.load`→`AtomicYAMLMarkdown.load(ItemFrontmatter.self,…)`, body→description; **backfill missing created_at/modified_at from the file's creation/mod dates in BOTH `Item.load` and `Item.loadLenient`** (not default-to-1970 — avoids the 1970 display at [ItemWindow.swift:272-274](Pommora/Pommora/ItemWindow/ItemWindow.swift#L272)). `Item.save(to: url)` → preserving `write(... preservingFrom: url, modeledKeys: ItemFrontmatter.modeledKeys)` (re-reads `url` if present — `renameItem` renames oldURL→newURL THEN saves to newURL, so preservation reads the post-rename file). Keep `relationIDs`/`setRelationIDs`. *(A foreign `.md` carrying a frontmatter `description:` key keeps it as a preserved foreign key, coexisting with the body — documented, harmless.)*
- [ ] **3b — Lenient loader + WIRE all 7 reads + format-agnostic reads + transition-safe write/delete/rename:** add `Item.loadLenient`. Replace strict `Item.load` at ALL 7 sites (`ItemContentManager.swift:84,:122`; `IndexBuilder.swift:310`; `ItemWindow.swift:429`; `ItemContentManager+CRUD.swift:734,:784,:795`). The 3 READ enumerators (`ItemContentManager.swift:82,:120`; `IndexBuilder.swift:307`) become `(ext=="md" || ext=="json")` with extension-dispatched load — so legacy `.json` Items stay visible AND indexed (no blackout, no de-index). **loadAll de-dups by id, preferring the `.md` twin** if both exist. **Write/delete/rename resolve the actual on-disk file** during transition: a helper `existingItemURL(title, in:)` returns the `.md` if present else the legacy `.json`; `updateItem`/`deleteItem`/`renameItem` operate on that real URL (so they don't write a new `.md` beside an un-deleted `.json`, trash a nonexistent `.md`, or rename a nonexistent `.md`). New Items always write `.md`.
- [ ] **3c — Path + WRITE-side filters:** `itemFileURL` `.json`→`.md` ([NexusPaths.swift:319](Pommora/Pommora/AtomicIO/NexusPaths.swift#L319)); flip the **5 write-side filters** (`+CRUD:583,792`; `ItemTypeManager:1005`; `DualRelationCoordinator:345`; `PageContentManager+CRUD:649`); keep `!hasPrefix("_")`. (Read enumerators are dual per 3b; `PropertyIDMigration:609` is Task 10's.)
- [ ] **3d — 7 clobber sites (② excluded):** route ①③④⑤⑥⑦⑧ through `Item.load`/preserving `Item.save` (or preserving `encode` for staged sites), `preservingFrom:` the read URL. Move sites ⑦/⑧ use `preservingFrom: srcURL` (deleted AFTER commit at :350/:454, so still present at stage time). **Site ② (`PropertyIDMigration:495/498`) is NOT converted here — it stays `AtomicJSON.decode`+preserving until Task 10** (its enumerator `:609` still yields `.json`). Move-foreign-key test: a source foreign key survives to the destination.
- [ ] **3e — Fixtures (writer AND filename):** real `.md` via `AtomicYAMLMarkdown.write` (a renamed-`.json` is malformed → false green). Named breakers: `ItemFileTests`, `ItemContentManagerTests` (:93/:97/:143/:224), `NexusPathsTests` (:321), `ItemTypeManagerSchemaCRUDTests` (Item1.json:66/Entry1.json:143), `PropertyIDMigrationTests` (keep dual-format).
- [ ] **Test:** round-trip (body==description, `Class: item`); `ItemBodySurvivesEditTests` over the 7 converted sites with a non-empty body (② asserts reports-not-throws + body intact under the still-JSON path); a legacy `.json` Item stays visible + indexed + survives updateItem/deleteItem/renameItem without orphan/double.
- [ ] **Commit** (one) `refactor(items): Items are Markdown — Shape A, transition-safe reads+writes, 7 sites, filters (atomic)`

---

### Task 4: Fix `contentSniff` — sidecar-required Item Types

**Files:** `Nexus/NexusAdopter.swift` (`contentSniff` 530-552; callers :426/:685; doc-comment :651-652). Test `ContentSniffTests`.

Collapse to `return hasMarkdown ? (.pageType,.markdownChildren) : (.pageType,.emptyFolderDefaultsToPages)`; remove `hasUserJSON`/`.jsonChildren`; fix the :651-652 doc-comment. **Document:** a Finder-built `.md` folder WITHOUT `_itemtype.json` adopts as a Page Type (contentSniff reads extensions, not frontmatter) — hand-adding Items requires the sidecar.

- [ ] Steps: tests + **rewrite the inverting `NexusAdopterTests.scanJSONContentSignalsItemType` + `NexusAdopterAutoTagTests.itemsSideTwoTiersOnly`** in this commit → implement → green → commit `fix(adoption): contentSniff Item-as-md, sidecar-required Item Types`.

---

### Task 5: Net-new launch `Class`-stamp pass (Landmine 2)

**Files:** `Nexus/NexusAdopter.swift`; `adoptionExcludedSubFolderNames:240`. Test `ClassStampPassTests`.

Walk folders whose kind = `recognizedSidecarsAt(...).first` (Notes/Ideas/**Metrics** carry `_itemtype.json` + stray `_pagecollection.json`; first-wins → `.itemType`; Metrics has no `.md` = no-op). Per content file: `Class` absent → `setStampKey` (value-preserving single key); agrees → leave; disagrees → `moveToUnsorted` (Task 6). **`setStampKey` now THROWS `AtomicYAMLMarkdownError.nonMappingFrontmatter`** (Task 1 review-driven guard) when a foreign file's frontmatter root isn't a key/value mapping — catch it and `moveToUnsorted` (a non-mapping-root file is homeless/abnormal; never clobber it). One write/file. **Runs at END of each top-level folder iteration — AFTER Task 8's `cleanupLegacyOrphans` + sidecar writes** (so `recognizedSidecarsAt` sees a clean single-kind set). No internal XCTest guard (upstream at `loadOnLaunch:80`; the two callers `openExisting:197`/`openPicked:257` are private, reachable only via the guarded launch or the modal picker — confirm no test calls them directly). Add `Pommora`, `worktrees` to `adoptionExcludedSubFolderNames:240`; `.unsorted` is dot-prefix-skipped. **~65 foreign Pages get a one-time value-preserving reflow on first launch.**

- [ ] Steps: tests (stampless→`Class: item` + foreign keys intact + no id injected; **run-2 == run-1**; `Class: page` in item folder → `.unsorted`; Metrics no-op; `Pommora/` skipped; flow-style foreign Page → value-preserved) → implement → green → commit `feat(adoption): per-file Class stamp pass (value-preserving single-key insert)`.

---

### Task 6: Hidden `.unsorted` inbox

**Files:** `AtomicIO/Filesystem.swift` (`moveToUnsorted(_:nexusRoot:)` + shared `relocate` core), `NexusPaths.swift` (`unsortedDir`). Test `UnsortedInboxTests`.

URL-signature `moveToUnsorted(_ source: URL, nexusRoot: URL)`; share a `relocate(source:under:relativeTo:)` core with `moveToTrash` **including its out-of-nexus guard + `standardizedFileURL`** ([Filesystem.swift:159](Pommora/Pommora/AtomicIO/Filesystem.swift#L159)); reuse `suffixedWithTimestamp` (:194). **Hidden `.unsorted`** — future-UI-surfaced; auto-excluded by `descendantFiles` ([Filesystem.swift:277-279](Pommora/Pommora/AtomicIO/Filesystem.swift#L277-L279)). Triggers: `Class` disagrees with folder kind, OR no Type-folder context up the chain. Resolution OUT deferred.

- [ ] Steps: test relocation DIRECTLY (incl. an out-of-nexus source rejected) → implement → green → commit `feat(adoption): hidden .unsorted inbox`.

---

### Task 7: Cross-Type move carries `Class`

**Files:** `ItemContentManager+CRUD.swift:394` (Item→Item) + `:434` (converted by Task 3d — do NOT re-convert); `PageContentManager+CRUD.swift:443`. Test `MoveClassStampTests`.

No Item↔Page move (post-v1). Item→Item strips Type-scoped schema props (correct) while foreign keys ride along; `.md` carries `Class: item`. `movePageAcrossTypes` carries `Class: page`. Resolution out of `.unsorted` deferred.

- [ ] Steps: test (Item→Item: `Class: item` survives + schema props stripped + a foreign key survives; symmetric Page) → implement → green → commit `feat(move): Class survives cross-Type move`.

---

### Task 8: Auto-tag self-heals co-located orphan sidecars

**Files:** `Nexus/NexusAdopter.swift` (`autoTagMissingSidecars` :663). Test `AutoTagOrphanCleanupTests`.

**Root cause (traced):** 12 inert depth-0 `_pagecollection.json` strays (dangling shared `type_id`, 2026-05-28) from a wrapper auto-tag→unwrap. `IndexBuilder` reads `_pagecollection.json` only at depth-1 ([:195](Pommora/Pommora/Index/IndexBuilder.swift#L195)); depth-0 keys off `_pagetype.json` ([:186](Pommora/Pommora/Index/IndexBuilder.swift#L186)) → safe to delete. `cleanupLegacyOrphans` (:1018) handles it but only runs in `apply(_:)` over `plan.alreadyFlat`, gated by `hasAnythingToAdopt` ([NexusManager.swift:328](Pommora/Pommora/Nexus/NexusManager.swift#L328)) — a flat nexus skips it forever. **Verify the 12 are all tier-2** (co-located with `_itemtype.json`); a tier-1 dual would resolve `.pageType` first and mis-stamp — assert out of scope or handle.

**Fix:** in `autoTagMissingSidecars` (runs unconditionally, [NexusManager:197/:257](Pommora/Pommora/Nexus/NexusManager.swift#L197)), after `walkDepth1(folder,…)` per top-level folder, add `cleanupLegacyOrphans(in: folder, fm: FileManager.default)` — BEFORE Task 5's stamp pass in the same iteration.

- [ ] Steps: failing test (folder with `_itemtype.json` + stray; run pass; stray gone, `_itemtype.json` survives, clean folder untouched, idempotent) → implement → green → commit `fix(adopter): auto-tag self-heals co-located orphan sidecars`. (Nathan handles the one-time live deletion.)

---

## Phase 2 — Phase-6 rider

### Task 9: Introduce save-time `ItemValidator` on all 6 CRUD entry points + the UI switch

**Files:** `Validation/ItemValidator.swift:20`; the 6 entry points (collection-scoped :86,:135,:164 carry `_ = itemType // Phase 6`; **the 3 Type-root variants :195,:231,:279 have NO placeholder — they use `itemType.id` directly**); `ItemWindow.swift:478` (`friendly(_:)`). Test `ItemValidatorTests`.

**`ItemValidator.validate` has ZERO production callers** — this **introduces save-time Item validation for the first time**. Schema from `itemType.properties`; repurpose `maxDescriptionLength` (already bumped to **1000**) to a **body-length** check (source chars) + DRY-unify the `ItemWindow` counter literal to reference the constant. Placeholder removal applies to the **3 collection-scoped** sites; wire `validate` into all **6**. Keep `ValidationError`'s case set stable OR update the exhaustive `friendly(_:)` switch ([:478](Pommora/Pommora/ItemWindow/ItemWindow.swift#L478), **zero callers today**) same-commit; **wire `friendly(_:)`** and verify `commitSave`'s catch covers each thrown domain (`ItemCRUDError` vs `ValidationError`). `descriptionTooLong` message → "…source/markdown characters." Scope: `updateItemProperty(:627)` value-validation is a follow-up.

- [ ] Steps: failing cap test (body>1000 throws on a collection-scoped AND a Type-root create) → retype + wire 6 + switch + `friendly()` + message → retype fixtures + cap coverage → green → commit `feat(validation): introduce ItemValidator save-time validation, body cap, 6 CRUD paths (Phase 6)`.

---

## Phase 3 — data migration (normalizes the transition; reads/writes already tolerate both)

### Task 10: One-shot `.json`→`.md` Item migration + format-agnostic `applyItemType`

**Files:** Create `ItemFormatMigration` (near-clone of `PropertyIDMigration`); **owns `PropertyIDMigration:609` + `applyItemType:493-507` + clobber-site ② (`:495/:498`)** — make all format-agnostic (enumerate `.json`+`.md`, dispatch by extension, re-stage in the file's own format). Test: interrupt-resume regression.

**Scale:** 2 user Items (empty) + ~73 `.md` Pages — skip `Pommora/`; `.unsorted` auto-skips. Build for 40+. Because reads/writes are already transition-safe (Task 3b), this is normalization, not a hard gate. **Safety:** per item, stage new `.md` + old `.json`→`.trash` in ONE `SchemaTransaction`; idempotence on FILE TRANSITION; same-volume rename (or copy-fsync-delete); report failures (don't throw).

**Transitional `.json` code introduced by Task 3 — RETIRE here once no `.json` Items remain (re-grep each; lines drifted post-Task-3 `6cae814`):**
- `Item.load` / `Item.save` legacy `.json` branches (the `AtomicJSON` read + `.json`-in-place write) → drop.
- `Item.dedupedPreferringMarkdown` (`Content/Item.swift`) + the 3 dual READ enumerators (`ItemContentManager` ×2, `IndexBuilder`) + the `locateItemFile` fallback: collapse `(.md || .json)` → `.md`-only.
- `existingItemURL(forTitle:in:)` (`ItemContentManager+CRUD.swift`): drop the legacy `.json` fallback.
- clobber-site ② (`PropertyIDMigration`, now ~`:496`) + its `enumerateItemMembers` `.json` filter → format-agnostic / `.md`.
- `NexusAdopter` content-sniff `.json`-item signal (~`:541`) → drop (coordinate with Task 4, which already makes a `.md` folder Item-Type-capable via sidecar). KEEP the file-date timestamp backfill (correct for adopted files — not transitional).

**Transition gap to CLOSE (Task 3 deliberate):** the 4 `.md`-only strip/back-ref-clear stagers (PageContentManager + ItemContentManager back-ref clears; ItemTypeManager + DualRelationCoordinator strips) SKIP a legacy `.json` Item that still holds a stripped property or a paired-relation back-ref during the transition window. Migrating every `.json`→`.md` removes the skip; FOLLOW migration with a reverse-ref reconcile / index rebuild so any ref drift accrued mid-window heals. *(Filter-count reconciliation from Task 3 review: the plan's "5 write filters" = 4 `.md`-only strippers + the dual `locateItemFile`.)*

**Decision (Nathan 2026-06-02): FULL migration + RETIRE the dual-format code.** Since retiring the safety net makes the migration a hard gate, the migration **auto-runs once at launch** (mandatory one-time normalization, mirroring `PropertyIDMigration`'s invocation) — NOT a declinable consent-gate (declinable + retire = a declined migration would hide `.json` Items, incoherent). An elaborate preview UI is deferred as separate UI work; a non-blocking "migrated N" notice is optional. Split into two green commits:

- [ ] **10a — Migration (data layer), KEEP dual-format code:** create `ItemFormatMigration` (near-clone of `PropertyIDMigration`, auto-runs at launch via the same hook; per-item `SchemaTransaction` stages new `.md` + `.json`→`.trash`; idempotent on file-transition; resumable/interrupt-safe; reports failures, doesn't throw) + convert clobber-② (`PropertyIDMigration`) + format-agnostic `applyItemType` (enumerate `.json`+`.md`, dispatch by extension). Tests: `.json` Item migrates to `.md` (id/props/body intact); idempotent; interrupt-resume regression; site ② format-agnostic. Commit `feat(migration): one-shot .json→.md Item normalization (auto-run at launch)`.
- [ ] **10b — Retire transitional `.json` code (the list above):** flip `Item.load`/`save` + the 3 dual READ enumerators + `dedupedPreferringMarkdown` + `locateItemFile` + the `existingItemURL` fallback → `.md`-only; drop the `NexusAdopter` content-sniff `.json`-item signal. KEEP the file-date timestamp backfill. Add a post-migration reverse-ref reconcile / index rebuild to close the `.md`-only-stripper transition gap. Convert `ItemMarkdownTransitionTests` (`.json`-interop) → migration-shape tests. XCTest-guard the launch migration (quirk #16). Commit `refactor(items): retire transitional .json dual-format code (Items are .md-only)`.

---

## Task 11: Documentation — SUBSTANTIAL, document-by-document pass

**First-class task.** Doc-impact analysis (2026-06-01): **28 docs → 3 substantial rewrites (+1 deleted), ~14 targeted, ~10 verify-clean.** Governing flip: *Items = plain `.md` (frontmatter + capped body); description = body (Shape A, 1000 source cap (provisional)); one `AtomicYAMLMarkdown` pipeline; folder-sidecar kind authority + non-authoritative `Class`; foreign keys preserved by value (comments/anchors not round-tripped) for Pages AND Items; Agenda STAYS JSON; filename=title.* Honor preserve-formatting.

- [ ] **11.1 — Substantial rewrites (3):** `Features/Items.md` (:3/:31/:39-40/:48/:50-51/:88/:95/:123) · `PommoraPRD.md` (:9/:34/:98-99 tree [sidecars stay JSON]/:237 `items.description`=body PROJECTION, DDL unchanged/:332/:448 + `Class`) · `Features/Architecture.md` (:13/:36-37/:83/:119/:124/:142/:172 + the gated migration).
- [ ] **11.2 — Targeted (~14):** `CLAUDE.md` (:9/:43/:81/:17 + #14 pointer) · `Framework.md` (:12 + **CREATE a Phase-6 anchor — "rides Phase 6" is orphaned**) · `History.md` (ADD newest-first) · `Pages.md` (:3/:5) · `PageTypes.md` (:271 sidecar-driven; move-restamp ONCE) · `Domain-Model.md` (:60/:86/:135) · `Properties.md` (:14/:102/:400 + **Items-vs-Agenda description asymmetry** [Items=body, Agenda=JSON field]; foreign-key preservation as schema authority, distinct from move-strip; :423-428 source-char cap) · `Prospects.md` (:37 promotion cheap; :39/:40 demote = body CLAMPED→truncation) · `Guidelines/Markdown.md` (**NOT Features/** — §2.1:68) · `CRUD-Patterns.md` (:101/:123-127 preserving merge-on-write) · `QuickCapture.md` (:22) · `Sidebar.md` (:57-63) · `Collections.md` · `Planning/2026-06-01-Architecture-Skeptic-Review.md` (rec #3 SUPERSEDED).
- [ ] **11.3 — Registry:** `Paradigm-Decisions.md` — ADD **#14** (Items→`.md` Shape A; one pipeline; folder authority + non-authoritative `Class`; three-state→hidden `.unsorted`; foreign keys preserved by value — a REVERSAL of the deleted Session-Context cull; 1000 source cap (provisional); Agenda JSON; cite #13). **FIX the "Note on numbering" (#1-#12 → #1-#13).** Only after Nathan's paradigm confirmation (step 4) + History.md first.
- [ ] **11.4 — CREATE `Planning/README.md`** (does NOT exist; Document Map references it + `Planning/Superseded/` danglingly).
- [ ] **11.5 — Verify-clean (~10):** `Resources.md`, `Handoff.md` (via `/handoff`), `PageEditor.md`, `Contexts.md`, `Homepage.md`, `NavDropdown.md`, `Agenda.md` (confirm JSON-contrast + description-stays-JSON), `Spaces.md`, `Design.md`, `Symbols.md`.
- [ ] **11.6 — Commit groups** (`docs(items-md): <group>`); #14 post-confirmation; leave parallel Wikilink docs untouched (quirk #10).

---

## Sequencing & discipline

- **Order:** 1 → 2 → **3 (atomic)** → 4 → **6 → 5** (the stamp pass calls `moveToUnsorted`; Task 6 lands first) → 7 → 8 → 9 → 10 → 11 (docs, concurrent). Re-assess between green commits (hard rule #13).
- **NexusAdopter (Tasks 4/5/8 share the file, distinct functions):** within each top-level folder iteration → tag sidecar → `cleanupLegacyOrphans` (Task 8) → stamp pass (Task 5).
- **No blackout / no orphan / no double:** Task 3b's dual reads keep `.json` Items visible+indexed; write/delete/rename resolve the real on-disk extension; loadAll de-dups by id preferring `.md`. Task 10 normalizes when run.
- **Atomic commit:** Task 3 only. Tests by **struct** name (quirks #1/#17); non-zero counts; background builder (quirk #13). Revert incidental SPM/pbxproj reorders (quirk #6). Never revert unattributed changes (quirk #10).
- **Cited line numbers are PRE-Task-1 and now drift.** Task 1 (commit `5f2ca3a`) shifted lines in `AtomicYAMLMarkdown.swift`, `PageFrontmatter.swift`, `PageFile.swift`, `PageContentManager+CRUD.swift`, `PropertyIDMigration.swift`, `DualRelationCoordinator.swift`, `PageTypeManager.swift`, `ItemContentManager+CRUD.swift`. Every later implementer RE-GREPS each site fresh and trusts the grep, never the cited `:line` (counts still hold; positions don't).

## Execution model

`superpowers:subagent-driven-development`: fresh subagent per task, each given THIS plan, returning `{ status, commit, surprises, changesNeededToOtherTasks, planEdits, newRisks }` the controller reviews + re-assesses against (hard rule #13). **Run code tasks sequentially — do NOT parallelize** (one Swift module, green-per-task, Task 3 atomic). **One concurrent track:** Task 11 docs. **Do NOT execute until approved + `bulletproof`.**

## Status

**v5 (finalized, grep-verified across 4 review rounds).** Round-4 (grep-mandated) fixes applied: the missed 7th `Item.load` read site `:734` wired; the missed 8th Page-preservation site `:567` added; the transition window closed on write/delete/rename (resolve actual on-disk extension + id-dedup), not just reads; clobber-site ② carved out of Task 3d (stays AtomicJSON until Task 10, with its enumerator); the phantom `ItemFile` type removed (reuse `Item.load`/`save`/`loadLenient`); timestamp backfill specified in BOTH load paths (no 1970); `setStampKey` reframed value-preserving (not byte-identical); `description` dropped from `ItemFrontmatter` CodingKeys; the `_ = itemType` placeholder count corrected to 3; `moveToUnsorted` out-of-nexus guard; decision #7 schema-props-vs-foreign-keys reconciled. **Convergence:** findings walked sites → mechanism → composition → exhaustive completeness; v5 closes the completeness tail. **Pending your approval** → then the three closers (chat-summary, Handoff update, post-compact resume prompt).
