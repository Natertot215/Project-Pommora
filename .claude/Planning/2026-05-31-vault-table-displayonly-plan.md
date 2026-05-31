# Vault Table Display-Only Interim — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`. Steps use checkbox (`- [ ]`) syntax. Build/test via a **background** `builder` Agent (`-only-testing:PommoraTests`, quirks #13/#16) — never foreground `xcodebuild`. Per-green commits to `main`. Revert the GRDB `project.pbxproj` churn before each commit (quirk #6). Leave parallel-session docs (`Paradigm-Decisions.md` / `History.md` / `Relations-Redesign-Plan.md`) untouched (quirk #10). Swift 6 strict concurrency.

**Goal:** Make vault/type detail tables display-only for ordering (deferring vault-level structural reorder), while keeping collection/set tables fully reorderable — resolving the sidebar↔table conflation without building the per-view system yet.

**Architecture:** Pure removal of the vault/type tables' drag mechanics (verified isolated from inline editing). The views become display-only and mirror the sidebar's file-level order through the shared `@Observable` managers. Collection/set reorder + `DetailReorderPlanner` + `DetailRowDragPayload` are untouched. Dead `SessionRowOrdering` is deleted.

**Tech Stack:** SwiftUI (`Table`, `DisclosureTableRow`), Swift 6, Swift Testing, GRDB.

Decision/deferral record: `.claude/Planning/2026-05-31-vault-table-displayonly-interim.md`.

**TDD note:** This is a removal/cleanup, so the discipline is *"the full suite stays green + the test runner still bootstraps after each step; the kept collection-reorder tests still pass; obsolete vault-drag tests are retired"* — not RED-first (no new behavior is added). The load-bearing check is **bootstrap** (a pure-display `DisclosureTableRow` must still render without a launch crash — quirk #8/#16).

---

### Task 1: Make `PageTypeDetailView`'s table display-only

**Files:**
- Modify: `Pommora/Pommora/Detail/PageTypeDetailView.swift` — the `rows:` closure (~`:185-207`) + delete `handleDrop` (~`:238-257`) + `handleChildDrop` (~`:259-273`)

- [ ] **Step 1: Replace the drag-laden `rows:` block with pure display.**

Find (current, post-`fee6804`):
```swift
            ForEach(rows) { row in
                if let kids = row.children, !kids.isEmpty {
                    DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                        // Child Pages are drag sources too: each Collection's children
                        // get their own group-scoped drop zone so a Page reorders WITHIN
                        // its Collection (the drop offset is relative to `kids`).
                        ForEach(kids) { kid in
                            TableRow(kid)
                                .draggable(DetailRowDragPayload(rowID: kid.id))
                        }
                        .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                            handleChildDrop(parentRow: row, kids: kids, payloads: payloads, toOffset: offset)
                        }
                    }
                    .draggable(DetailRowDragPayload(rowID: row.id))
                } else {
                    TableRow(row)
                        .draggable(DetailRowDragPayload(rowID: row.id))
                }
            }
            .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                handleDrop(payloads: payloads, toOffset: offset)
            }
```

Replace with:
```swift
            // Display-only ordering (interim): vault-level reorder is deferred — vault
            // tables mirror the sidebar's file-level order via the shared managers.
            // Reorder lives in the sidebar (file-level) and in each collection's own view.
            // See Planning/2026-05-31-vault-table-displayonly-interim.md.
            ForEach(rows) { row in
                if let kids = row.children, !kids.isEmpty {
                    DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                        ForEach(kids) { kid in
                            TableRow(kid)
                        }
                    }
                } else {
                    TableRow(row)
                }
            }
```

- [ ] **Step 2: Delete the two now-unused private methods** `handleDrop(payloads:toOffset:)` and `handleChildDrop(parentRow:kids:payloads:toOffset:)`. (Leave `expandedBinding` + `expanded` — the disclosure collapse stays.)

- [ ] **Step 3: Verify (background `builder`).** Run `xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests`. Expected: compiles clean; runner **bootstraps** with a non-zero executed count (~1030); green except the known `PageEditorViewModelTests.debounceCoalescesRapidEdits` flake. (Confirms the pure-display `DisclosureTableRow` renders — no launch crash.)

- [ ] **Step 4: Commit.** Revert any `project.pbxproj` GRDB churn first; then:
```bash
git add Pommora/Pommora/Detail/PageTypeDetailView.swift
git commit -m "refactor(detail): Page Type table display-only for ordering (defer vault reorder)" \
  -m "Vault/Type tables mirror the sidebar file-level order; vault-level structural reorder is deferred to the per-view system. Collection reorder is unaffected. See Planning/2026-05-31-vault-table-displayonly-interim.md." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 2: Make `ItemTypeDetailView`'s table display-only (mirror of Task 1)

**Files:**
- Modify: `Pommora/Pommora/Detail/ItemTypeDetailView.swift` — the `rows:` closure (~`:222-244`) + delete `handleDrop` (~`:272-291`) + `handleChildDrop` (~`:293-307`)

- [ ] **Step 1: Replace the drag-laden `rows:` block with pure display.**

Find (current):
```swift
            ForEach(rows) { row in
                if let kids = row.children, !kids.isEmpty {
                    DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                        // Child Items are drag sources too ...
                        ForEach(kids) { kid in
                            TableRow(kid)
                                .draggable(DetailRowDragPayload(rowID: kid.id))
                        }
                        .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                            handleChildDrop(parentRow: row, kids: kids, payloads: payloads, toOffset: offset)
                        }
                    }
                    .draggable(DetailRowDragPayload(rowID: row.id))
                } else {
                    TableRow(row)
                        .draggable(DetailRowDragPayload(rowID: row.id))
                }
            }
            .dropDestination(for: DetailRowDragPayload.self) { offset, payloads in
                handleDrop(payloads: payloads, toOffset: offset)
            }
```
(The exact comment text may differ — match the structure: child `.draggable`, nested `.dropDestination`, parent `.draggable`, leaf `.draggable`, outer `.dropDestination`.)

Replace with:
```swift
            // Display-only ordering (interim) — see Task 1 / the interim design doc.
            ForEach(rows) { row in
                if let kids = row.children, !kids.isEmpty {
                    DisclosureTableRow(row, isExpanded: expandedBinding(for: row.id)) {
                        ForEach(kids) { kid in
                            TableRow(kid)
                        }
                    }
                } else {
                    TableRow(row)
                }
            }
```

- [ ] **Step 2: Delete** `handleDrop(payloads:toOffset:)` + `handleChildDrop(parentRow:kids:payloads:toOffset:)` from `ItemTypeDetailView`.

- [ ] **Step 3: Verify (background `builder`).** Same command + expectations as Task 1 Step 3.

- [ ] **Step 4: Commit.** Revert pbxproj churn; then:
```bash
git add Pommora/Pommora/Detail/ItemTypeDetailView.swift
git commit -m "refactor(detail): Item Type table display-only for ordering (defer vault reorder)" \
  -m "Mirror of the Page Type change. Item Set reorder is unaffected." \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 3: Delete dead `SessionRowOrdering` + fix stale comment + retire 2 vault tests

**Files:**
- Delete: `Pommora/Pommora/Detail/SessionRowOrdering.swift`
- Delete: `Pommora/PommoraTests/Detail/SessionRowOrderingTests.swift` (confirm path: `grep -rl "struct SessionRowOrderingTests\|SessionRowOrdering" Pommora/PommoraTests`)
- Modify: `Pommora/Pommora/Detail/DetailRowDragPayload.swift` (stale doc-comment ~`:7` referencing `SessionRowOrdering.move`)
- Modify: `Pommora/PommoraTests/Detail/DetailReorderPlannerTests.swift` (remove 2 cases + the now-unused `withChildren` helper)

- [ ] **Step 1: Confirm `SessionRowOrdering` has zero production callers**, then delete `SessionRowOrdering.swift` + `SessionRowOrderingTests.swift`. (Verified dead 2026-05-31 — only its own def, its tests, and the stale comment below reference it.)
```bash
grep -rn "SessionRowOrdering" Pommora/Pommora --include="*.swift"   # expect: only the file being deleted + the doc-comment in Step 2
```

- [ ] **Step 2: Fix the stale doc-comment** in `DetailRowDragPayload.swift` (~`:7`). Remove the line claiming the drop handler resolves position via `SessionRowOrdering.move`; replace with a short note that `DetailRowDragPayload` carries a row id for the collection/set detail-view reorder (`DetailReorderPlanner` + `reorderPages(in:)`/`reorderItems(in:)`).

- [ ] **Step 3: Remove the two vault-specific tests** from `DetailReorderPlannerTests.swift`: `childPageReorderWithinCollectionScopesToKids` and `topLevelDragStillKindSafeWithChildrenPresent` (these pinned the removed vault child-drop). Also remove the `fileprivate extension DetailRow { withChildren(_:) }` helper if it is now unused (it was added only for `topLevelDragStillKindSafeWithChildrenPresent`). KEEP all other cases (`homogeneousPagesDragToFront`, `dragPageInMixedRows`, `dragCollectionInMixedRows`, `noopDropReturnsNil`, `unknownIDReturnsNil`, `childItemReorderWithinSetScopesToKids`) — they cover the still-live collection flat-plan path.

- [ ] **Step 4: Verify (background `builder`).** `-only-testing:PommoraTests`. Expected: compiles (no dangling `SessionRowOrdering`/`withChildren` references); suite bootstraps; `DetailReorderPlannerTests` green with the kept cases; overall green except the known flake.

- [ ] **Step 5: Commit.** Revert pbxproj churn; then:
```bash
git add Pommora/Pommora/Detail/DetailRowDragPayload.swift Pommora/PommoraTests/Detail/DetailReorderPlannerTests.swift
git rm Pommora/Pommora/Detail/SessionRowOrdering.swift Pommora/PommoraTests/Detail/SessionRowOrderingTests.swift
git commit -m "chore(detail): remove dead SessionRowOrdering + retire vault-drag tests" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 4: Record the decision for future agents

**Files:**
- Modify: `Pommora/.claude/Guidelines/Paradigm-Decisions.md` (add a registry entry)
- Modify: `Pommora/.claude/Features/PageTypes.md` (note current state in the View types / View Settings area)

> ⚠️ **Parallel-session caveat (quirk #10):** `Paradigm-Decisions.md` currently carries *uncommitted parallel-session edits*. Do NOT bundle or revert them. **Step 1 below** must `git add -p`/stage only your own added hunk, or be deferred until the parallel edits are committed. `PageTypes.md` is NOT parallel-modified — safe to edit/commit normally.

- [ ] **Step 1 (Paradigm-Decisions):** Append a concise entry: *"Vault/Type detail tables are display-only for ordering (interim). SwiftUI `Table` can't do collapsible structural collection grouping + reliable nested reorder together; per-view `order` + the reorder engine are deferred to the view system (v0.5.0–v0.6.0). Collection/Set tables keep flat reorder; the sidebar owns file-level structural order. Full record: Planning/2026-05-31-vault-table-displayonly-interim.md."* — staging ONLY this hunk if the file still has parallel edits.

- [ ] **Step 2 (PageTypes.md):** In the View types / View Settings section, add one line: vault/type-level tables are display-only for ordering in the interim (mirror the sidebar's file order); per-view ordering/sort/group ship with the view system; collection/set tables reorder today.

- [ ] **Step 3: Commit (doc-only).**
```bash
git add Pommora/.claude/Features/PageTypes.md   # + Paradigm-Decisions.md ONLY if cleanly stageable
git commit -m "docs: record vault-table display-only interim decision" \
  -m "Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
```

---

### Task 5 (SEPARABLE — PENDING NATHAN'S CONFIRMATION): default order fallback → file/creation order

> Nathan asked vault tables to "default to what's on the file system, not alphabetical." The tables already *mirror the sidebar* (Tasks 1–2), so they're never independently alphabetical. This task only changes the **shared empty-state fallback** (when a container has no manual `page_order`/`item_order` yet) from alphabetical to a file-based order — affecting **both** sidebar and tables (they stay mirrored). **Do not start until Nathan confirms** (a) that he wants the fallback changed now vs deferred, and (b) what "file order" means.

**Files (anticipated):**
- Modify: `Pommora/Pommora/Ordering/OrderResolver.swift` (the `persistedOrder` nil/empty → alphabetical branch, ~`:37-39`)
- Test: `Pommora/PommoraTests/.../OrderResolverTests.swift` (or new)

- [ ] **Step 0 (PRECONDITION): confirm with Nathan** that "file order" = file **creation order** (oldest-first), and verify a stable creation-date source exists for Pages (`.md`) + Items (`.json`) — a frontmatter/`created` field, else `FileManager` `.creationDateKey`. If no stable source, surface that and reconsider (e.g., keep alphabetical, or use the on-disk write/enumeration order). **No code until this is answered.**
- [ ] **Step 1 (RED):** test that `OrderResolver.resolve` with an empty `persistedOrder` returns items in creation order, not alphabetical.
- [ ] **Step 2:** run the test, confirm it fails for the right reason.
- [ ] **Step 3:** change the fallback to sort by the confirmed creation-date source (passed in, to keep `OrderResolver` pure).
- [ ] **Step 4:** run the test (+ full suite) green via background `builder`.
- [ ] **Step 5:** commit.

---

### Self-review

- **Spec coverage:** Tasks 1–2 = remove vault drag (scope #1). Task 3 = delete dead `SessionRowOrdering` + retire 2 tests (scope #2, #3). Collection reorder + `DetailReorderPlanner` + `DetailRowDragPayload` explicitly untouched (scope #4). Task 5 = fallback order (scope #5, gated on confirm). Task 4 = documentation (scope #6). All covered.
- **No placeholders:** every removal shows the before/after; commands + commit messages are concrete. (Task 5 is intentionally gated, not a placeholder — it must not start until confirmed.)
- **Type/name consistency:** `handleDrop` / `handleChildDrop` / `DetailRowDragPayload` / `DetailReorderPlanner` / `expandedBinding` match the verified code. Kept vs removed tests named exactly.
- **Isolation (verified):** removing the drag does not touch `PropertyCellEditor`/`updatePageProperty`/`updateItemProperty`, cell rendering, selection, double-click-to-open (`.simultaneousGesture` on the Title cell), disclosure collapse, context menus, or relation warming.
