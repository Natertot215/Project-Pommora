## PagesV2 — Items-Strip Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL — use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement task-by-task. Steps use checkbox (`- [ ]`) syntax. **Green per commit** (paradigm decision #4). Each phase ends with a builder-subagent verification (quirk #13: background Agent, `-only-testing:PommoraTests`, no UI tests, no window-focus grab) — confirm a **non-zero executed count** (quirk #1), not just `** TEST SUCCEEDED **`.

**Goal:** Strip the Items subsystem from Pommora so the codebase reads as though Pages were always the only operational entity — no item-named code, no dormant item frameworks — while landing a plain `PagePreview` window, a vault-level Compact/Window open-in toggle, and user-creatable sidebar sections.

**Architecture:** Page is the sole survivor; `Item*` code/index-tables/tests are deleted and every `item|page` shared seam collapses to page-only. The `EntityKind`/`SidebarSelection` enum-case removals are the compiler's exhaustiveness gate (P2). MarkdownPM's `{{ }}` capability is **renamed** to an item-free page-native chip-link (kept, gated off), not parked under its old identity. `Class` is dropped; the index rebuilds at schema v11 (no data migration).

**Tech Stack:** SwiftUI, Swift 6 strict concurrency + ExistentialAny, GRDB/SQLite, Yams, in-tree `MarkdownPM` (TextKit 2 + `swift-markdown`), Swift Testing (`@Suite`).

**Source of truth:** spec `// Planning//06-09-Items-Strip-Spec.md`; decision record `// Planning//06-09-Items-Pages-Collapse-Evaluation.md`. This plan was authored from an 8-cluster + adversarial-critic whole-codebase review.

**Revision V2 (stress-test-hardened, 2026-06-09).** A 10-region code-grounded verification pass (~187 claims; ~165 confirmed) corrected the items below: a non-existent MarkdownPM config field the P0 gate read from (CR-1), a static call to an injected `MainWindowRouter` instance in the P5 scene (CR-2), a mis-sequenced `ItemLinkOpener` delete (CR-3), a wrong `ItemWindow/` file count + two phantom filenames (CR-4), a P10 archival no-op against already-deleted docs (CR-5), an unverified settings-footer slot (CR-6, held for the Figma pass), and an unverified `NexusPaths` helper (CR-7). Plus enum-collapse → enum-deletion simplifications, four unnamed dead files, and an explicit no-trace allowlist. **CR-8 (added after the property-editor investigation):** P3 must MOVE `PropertyEditorRow` + `MultiSelectChips` out of `ItemWindow/` (not delete them) — they're generic and `FrontmatterInspector` consumes them at HEAD; deleting them red-breaks compile before P5. **P5 is now FINALIZED** — the Figma `PagePreview` design is captured and all OPENs resolved (lock=edit-gate, context-menu open, window-dismiss control, footer toggle); `FrontmatterInspector` is reused verbatim, so there is no property editor to rebuild.

**Revision V3 (review pass #2, 2026-06-09).** A 4-agent adversarial re-verification confirmed the plan sound (every P5 symbol exists with the stated shape; ordering holds; the `#15` keystone lockstep is fully mapped; plan↔spec aligned) and surfaced five hardening fixes, all folded in: (1) thread the CR-1 gate field through the `.pommora()` factory, not just the struct; (2) `SideKind` is in **4** files, not 5 — `PropertyTypePickerPane` has none (only an item `@Environment`); (3) `ViewSettingsPane` **already** has a pinned `footer:` slot — use it, don't extend (CR-6); (4) the P5 toggle extracts `liveVault` from `liveScope` via `if case .pageType`; (5) the no-trace gate adds a `Item[A-Z]` comment-scan (the allowlist is comment-blind). No new blockers.

**Revision V4 (operating contract, 2026-06-09).** Added the **Operating contract** section that binds every phase: (1) standing permission to STOP and ASK whenever a task would require guessing or isn't specified enough to avoid a revision; (2) **controller-verified completion** — the controller reads the diff + confirms the evidence first-hand, never trusting a subagent's "done"; (3) **flagged findings flow back** into this plan (re-version) AND into P10's doc-sweep list. Strengthened P10 to total Items erasure with exactly two permitted survivors (a one-line `CLAUDE.md` note + the `History.md` record). The plan is ratified and execution-ready.

**Revision V5 (pre-execution tightening, 2026-06-09).** A final code-grounded pass found the green-per-commit contract broken by deferring all test surgery to P8: at HEAD, `IndexUpdaterTests` calls the item methods P1 deletes (`upsertItemType`/`deleteItemType`/`upsertItem`), `ItemTypeDetailViewTests`/`ItemCollectionDetailViewTests` reference the views P1 deletes, `ConnectionScannerTests:10` asserts `{{Beta}}` scans to `.item` (P1 stops that scanning), ~20 suites reference enum cases P2 deletes, and `PommoraTests/Items/` references the managers P3 deletes — so the test target cannot COMPILE between P1 and P8 as previously sequenced (the P7 "HARD SEQUENCING RULE" had caught one instance of this class; the class is general). Fix: a **lockstep test-surgery rule** added to the verification idiom — every phase pulls the affected P8 test deletions/seam-edits forward into its own commit; P8 becomes the reconciliation checklist + relocations + new coverage, and explicitly runs after P5/P6. Also corrected two stale lines: the self-review note still said "extend `ViewSettingsPane` with a `footer:` slot" (V3 established the slot already exists), and the `ConnectionScannerTests` edit was mislabeled `.item→.chip` (decision #3 leaves no chip case at the connection layer — the `{{` assertions are deleted, landing in P1). **Same hole found production-side at dispatch:** P0's "app target NOT expected green until P5" exception would make P1–P4's green gates impossible — five app/test files call the renamed MarkdownPM slots at HEAD (`AutoCompleteWiring`, `MarkdownEditorConfig:38`, `PageEditorView:277`, `AutoCompleteWiringTests`, `ConnectionConfigWiringTests`). Fixed by P0 Step 7b: rename those call-site tokens in the same commit (labels only; P1/P5 delete the sites later) — every phase, P0 included, now gates on full green.

**Revision V6 (contract upgrade + CR-9, 2026-06-09).** Contract clause #1 is upgraded from standing permission to standing **obligation** by Nathan's direct instruction: anything flagged fuzzy or uncertain — by the controller, a subagent's report, or a verification result — halts the work until Nathan has answered directly; the controller does not resolve flagged ambiguity on his behalf. First application, **CR-9:** P1's working tree dropped the `ItemTypeManagerError` branch + overload from `PropertyEditorErrorMessage` while the type's `LocalizedError` extension still delegated into that mapper — the fallback recursed (`localizedDescription` ↔ `string(for:)`) until the test host crashed (1258 executed, 902 cascade failures from the one defect; the app build stayed green — type-safe but runtime-recursive, exactly the gap the test gate exists to catch). The V2 wording "removing the branch early is safe" was wrong. Resolved per Nathan's decision: **cut the loop on the error side** — delete the `LocalizedError` extension on `ItemTypeManagerError` in P1 (the enum stays until P3) and pull the item-side `ManagerErrorMessageTests` test forward into P1's lockstep surgery. Verified post-fix: **no user-reachable item-error path survives P1** — nothing constructs the item delete confirmations, and the item panes/windows are orphaned switch arms held only by enum exhaustiveness until P2 — so no item error message of any kind can surface; items no longer exist as a user-facing concept.

---

### Operating contract (binds every phase — read before dispatching any task)

**1. You MUST STOP and ASK whenever anything is flagged fuzzy or uncertain — this is an obligation, not merely a permission (directive 2026-06-09).** If a task would make you *guess*, if the specifics aren't pinned down enough that proceeding risks a revision Nathan wouldn't like, or if you hit an assumption this plan didn't anticipate — **halt and ask Nathan before writing code.** This binds the controller as much as the workers: a subagent's NEEDS_CONTEXT report, an anomaly in a verification result, or a diff that contradicts the plan halts the work until Nathan has answered directly — the controller does not resolve flagged ambiguity on Nathan's behalf. A question costs a minute; a wrong guess that ships costs a revision and erodes trust. The cornerstone governs absolutely: *you do NOT guess — you LOOK, you ASK.* This obligation is standing and unconditional across all phases.

**2. Controller-verified completion — never trust a subagent's "done."** Every task returns to the controller (you), who independently confirms it **before** marking the task complete or dispatching the next:
- **Read the actual diff**, not the agent's prose summary of it.
- **Confirm the build/test result first-hand:** a **non-zero executed test count** (quirk #1 — `** TEST SUCCEEDED **` with 0 tests run is a FAILURE, not a pass); the phase's specific green-gate evidence (the named grep returning clean, the asserted behavior); **no SIGTRAP on first selection** (quirk #15).
- **Confirm the commit contains only intended files** — revert incidental Yams/GRDB pbxproj reorders (quirk #6); never bundle parallel-session churn (quirk #10).
- A task is "green" only when **you have seen the evidence yourself**, not when an agent claims it. If the agent's report and the diff disagree, the diff wins — investigate.

**3. Flagged findings flow back into the plan AND into the doc list.** If implementing a task surfaces a wrong assumption, a missing prerequisite, a new dependency, or scope drift, you MUST, before dispatching the next task: **(a)** rewrite the affected later tasks in THIS plan and re-version it (CLAUDE.md hard rule — re-assess between green commits; the plan is the live theory of the work, only green commits are facts); and **(b)** record which spec / Feature / Guideline / `CLAUDE.md` docs the finding changes, appending them to P10's sweep checklist so nothing flagged survives only in a subagent transcript. A finding that isn't reflected back into the plan + docs is a finding lost.

---

### Decisions (resolved 2026-06-09)

All seven open decisions are ratified — reflected in the tasks below.

1. **`PageCollection.template_config` — dropped entirely.** No per-collection layout schema; `open_in` is vault-level on `PageType`. The 2 `CollectionTemplateConfigTests` page tests are deleted (P8).
2. **Open-in toggle — a segmented control at the bottom of the main settings pane.** A simple `Layout: Compact | Window` segmented `Picker` at the bottom of `StorageMenuRoot` (the settings dropdown), separated by a `Divider` above it, using Design.md padding discipline. Vault-scoped. No new `ViewSettingsRoute` case; no duplicate toggle in `PageTypeDetailView`.
3. **`{{ }}` collapses at the connection layer.** Connections use `[[` **only** — drop the `{{` regex from `ConnectionScanner`, collapse `ConnectionSyntax` to page-only, drop the chip arm from `AutoCompleteWiring`, no `{{` index rows. The chip-link **render design is retained, dormant, in MarkdownPM** (renamed page-native, gated off, NoOp resolver) so it can be re-enabled later — but the app wires no `{{` trigger.
4. **`{{ }}` click — moot** (collapsed). No `onChipLinkClick` wired; the dormant chip render reuses later if turned on.
5. **`Paradigm-Decisions.md` — append a superseding entry + mark #14/#15 superseded inline** (registry is append-only; chronology preserved).
6. **Band-3 sections — single-membership + inline-rename.** A vault sits in at most one user section; ungrouped vaults stay in the default Vaults section.
7. **Resolver — reuse `pageConnectionResolver`, rename `ConnectionResolver`.** Drop the separate `itemConnectionResolver` env key/@Entry; the renamed page resolver serves `[[` (fewer injection slots; quirk #15).

---

### Phase order & dependencies

`P0` (MarkdownPM rename, independent) · `P1` (collapse leaf item arms) → `P2` (remove enum spine = compiler gate) → `P4` (relocate survivors + `PageType.open_in`) → `P3` (delete item type bodies/managers/migration; `NexusEnvironment` keystone) → `P7` (schema v11) ; then `P5` (re-home chip-link app-side + build `PagePreview`) needs P0+P3+P4 ; `P6` (settings/labels) alongside P5 ; `P8` (test reconciliation + new coverage) after P5/P6 — the lockstep rule pulls most surgery into P1–P7, and P8's new tests exercise P5's routing + P6's labels ; `P9` (band-3, last build) after P5 ; `P10` (doc-sweep + archival) after P5/P8.

> Verification idiom (every phase): dispatch a **background builder Agent**: `xcodebuild build` then `xcodebuild test -only-testing:PommoraTests` on the Pommora scheme; report green/red + the executed test count. Never run xcodebuild in the foreground (quirk #13). Before each commit, revert incidental Yams/GRDB pbxproj package-reorder diffs (quirk #6). **Then the controller verifies first-hand per Operating Contract #2 — read the diff, confirm the executed-count + green-gate evidence yourself; an agent's "done" is not acceptance.**
>
> **Lockstep test surgery (V5 — binds every phase):** if a phase deletes or changes production code that any test file references, that phase pulls the affected P8 test deletions/seam-edits forward **into the same commit** — the test target must compile AND pass at every gate; a known-red interval is never acceptable. Tick pulled-forward items off in P8's checklist as you go; P8 is the master list and final reconciliation, not the only window the surgery may land in.

---

### Phase P0 — MarkdownPM chip-link rename (item-free, capability kept)

**Goal:** rename the entire `item*` link framework in the package to a generic `chipLink` family + add the off-by-default gate, so the chip-link **render design survives as a dormant, reusable capability with zero item tokens**. Package builds + package tests green before app-side seams depend on the new names. (Per decision #3, the *app* wires no `{{` trigger — this pipeline stays in the package, gated off + NoOp-resolved, for later reuse; only the connection layer collapses to `[[`.)

**Files (all under `External/MarkdownPM/Sources/MarkdownPM/` — note: repo-root level, NOT `Pommora/Pommora/External/…` as a prior draft stated):** `Parser/MarkdownToken.swift`, `Parser/MarkdownTokenizer.swift`, `Parser/MarkdownDetection.swift`, `Renderer/ItemChipMetrics.swift` (→ rename file `ChipLinkMetrics.swift`), `Renderer/MarkdownTextLayoutFragment.swift`, `Styling/MarkdownPMStyler+Links.swift`, `Styling/MarkdownPMStyler.swift`, `Styling/MarkdownPMStyler+TextStyling.swift`, `Services/MarkdownPMServices.swift`, `MarkdownPMConfiguration.swift` (add the gate field — CR-1), `TextView/NativeTextViewWrapper.swift`, `TextView/Coordinator/NativeTextViewCoordinator.swift` (+`+Restyling`/`+TextDelegate`/`+Services`), `TextView/NativeTextViewSelectionTypes.swift`; tests under `External/MarkdownPM/Tests/MarkdownPMTests/`.

- [ ] **Step 1 — Token + attr keys.** `MarkdownToken.swift`: `case .itemLink → .chipLink` (L26); attr keys `itemLinkTitle → chipLinkTitle` (raw `"ChipLinkTitle"`), `itemChipIcon → chipLinkIcon` (raw `"ChipLinkIcon"`) (L15–16). `MarkdownTextLayoutFragment.swift`: `itemChipBounds → chipLinkBounds` (raw `"ChipLinkBounds"`) (L21).
- [ ] **Step 2 — Tokenizer + detection.** `MarkdownTokenizer.swift`: `itemLinkRegex → chipLinkRegex` (L21), emission `.itemLink → .chipLink` (L121–128). `MarkdownDetection.swift`: `itemDepth → chipDepth` (L510/516–520), `.itemLink → .chipLink` (L416). Scrub item comments. **LEAVE** genuine bullet/heading list-item comments (L84–95/268).
- [ ] **Step 3 — Metrics file rename.** Rename `Renderer/ItemChipMetrics.swift → ChipLinkMetrics.swift`; `enum ItemChipMetrics → ChipLinkMetrics`; header-comment scrub. (Synchronized file group auto-includes — quirk #2; confirm no explicit pbxproj reference.)
- [ ] **Step 4 — Fragment draw.** `MarkdownTextLayoutFragment.swift`: `drawItemChips → drawChipLinks`, `itemChipRects → chipLinkRects`, `itemChipFont → chipLinkFont`, `itemChipRect(forSize:) → chipLinkRect(forSize:)` (L758/796/1131–1225); attribute reads use `chipLink*` keys; `ItemChipMetrics.* → ChipLinkMetrics.*` (L1191–1204). **LEAVE** L296 `-` list-item comment.
- [ ] **Step 5 — Styler + gate.** `MarkdownPMStyler+Links.swift`: `styleItemLinks → styleChipLinks` (L105), `.itemLink → .chipLink` (L107), `ctx.services.itemLinks → chipLinks` (L114), `ItemChipMetrics.size → ChipLinkMetrics.size` (L123), attr stamps → `chipLink*` (L130–132/168).
  - **Step 5a (CR-1) — CREATE the gate field first.** Verified: `MarkdownPMLinkConfig.renderChipLinksAsChips` does **not** exist — `MarkdownPMConfiguration.swift:33-95` is a flat struct with no chip field, and `LinkStyle` (`MarkdownPMTheme.swift:371`) is colors-only. Add `public var renderChipLinksAsChips: Bool = false` directly to `MarkdownPMConfiguration` (NO new nested type — Simplicity-first), and thread it through `MarkdownPMConfiguration.init` (≈L54+) with a `= false` default. **Also thread it through the `.pommora()` factory** in `Pages/MarkdownEditorConfig.swift` (add `renderChipLinksAsChips: Bool = false` param + `config.renderChipLinksAsChips = …` assignment) — otherwise the factory always builds `.default` (false) and the gate is invisible/un-toggleable. The two call sites (`PageEditorView` L459, `ItemWindowRenderer` L275 — latter deleted in P3) keep compiling via the default.
  - **Step 5b — wire the guard.** Guard the kern-trick chip-draw branch (≈L120-160) with `ctx.configuration.renderChipLinksAsChips`; when `false`, fall through to the plain-link branch (L162-179 → `.link` + `.chipLinkTitle`). `MarkdownPMStyler.swift`: call site `styleItemLinks → styleChipLinks` (L256, KEEP the call), `.itemLink` filters → `.chipLink` (L457/498). `MarkdownPMStyler+TextStyling.swift`: `.itemLink → .chipLink` (L65).
- [ ] **Step 6 — Services + coordinator + selection.** `MarkdownPMServices.swift`: `services.itemLinks → chipLinks` (L249), init param + assignment (L257/264). `NativeTextViewWrapper.swift`: `onItemLinkClick → onChipLinkClick` (L72/102/119/421). Coordinator chain (`+Restyling`/`+TextDelegate`/`+Services`): `onItemLinkClick → onChipLinkClick`, `itemLinkTokens → chipLinkTokens`, `InlineTokenContext.itemLink → .chipLink`, `isItemLinkActive → isChipLinkActive`, `.itemLinkTitle` reads → `.chipLinkTitle`, local `itemTitle → chipTitle`. **LEAVE** `NSMenuItem item.tag` locals (`+Services` L121–122). `NativeTextViewSelectionTypes.swift`: `InlineSelectionKind.itemLink → .chipLink` (L38).
- [ ] **Step 7 — Package tests.** Rename `ItemLinkTokenizerTests.swift → ChipLinkTokenizerTests.swift` (`@Suite` + struct + `.itemLink → .chipLink`). `ConnectionStylerResolutionTests`: `itemLinks: → chipLinks:`, chip attr asserts → `chipLink*`; **keep a chip-on variant** flipping `renderChipLinksAsChips = true` so chip-bounds coverage survives. `InlineSelectionDetectorTests`: `.itemLink → .chipLink` + func renames. `InputTransformCorpusTests`: `itemLinkAutoPair → chipLinkAutoPair`.
- [ ] **Step 7b (V5) — App-side call-site renames (labels only; keeps the app target green).** Verified at HEAD: five app/test files reference the renamed slots — `Connections/AutoCompleteWiring.swift` (`.itemLink` L21/30/35/43), `Pages/MarkdownEditorConfig.swift` (`config.services.itemLinks` L38), `Pages/PageEditorView.swift` (`onItemLinkClick:` L277), `PommoraTests/Connections/AutoCompleteWiringTests.swift` (`.itemLink` L36/44/62/72), `PommoraTests/Connections/ConnectionConfigWiringTests.swift` (`services.itemLinks` L10/67/69). Rename the tokens in place (`.itemLink → .chipLink`, `services.itemLinks → services.chipLinks`, `onItemLinkClick: → onChipLinkClick:`) — zero behavior change; P1/P5 delete these sites later. Re-grep before editing (quirk #10: parallel-session churn).
- [ ] **Step 8 — Verify + commit.** Builder Agent: `swift build` of MarkdownPM + `swift test` (renamed suites); confirm non-zero executed count (quirk #1). With Step 7b the app target stays green — also verify `xcodebuild build` + `-only-testing:PommoraTests` (background builder, quirk #13). Commit: `refactor(markdownpm): rename item-link framework to page-native chip-link + gate off`.

**Green gate:** MarkdownPM package builds + its renamed suites pass (non-zero count).

---

### Phase P1 — Collapse leaf item arms (no type deletions yet)

**Goal:** drop every item arm from kept files + delete pure-item leaf VIEW files, so P2's enum-spine removal hits a clean exhaustiveness gate. Item types/managers + enum cases still exist.

**Files & actions:**

- [ ] **Detail leaf deletes:** delete `Detail/ItemTypeDetailView.swift`, `Detail/ItemCollectionDetailView.swift`.
- [ ] **Sidebar strip (quirk #8):** delete `Sidebar/ItemTypeRow.swift`, `Sidebar/ItemCollectionRow.swift`; remove `struct ItemsSection` from `SidebarView.swift` (L510–573) + its List-body call (L45–51); drop the item arms from the **three discrete** confirmation methods (D-1 — not one range): `confirmationTitle` (L115–120), `confirmationMessage` (L135–140), `confirmationButtons` (L218–235); drop `cascadeUnlinkTier` `itemContentManager.unlinkTier` (L246); L134 `"All Pages and Items inside" → "All Pages inside"`. The List now holds only homogeneous Sections (Saved/Spaces/Topics/Vaults) — do NOT introduce a flat-leaf/disclosure mix.
- [ ] **Detail seam-edits (collapse to `.page`/`.collection`):** `PageTypeDetailView.swift` + `PageCollectionDetailView.swift` (rows/contentKind/handleDoubleTap/handleDrop/menuItems/parent/propertyValue/commitRename item arms + the `presentItemAction` call + Phase-6 stub comments); `PropertyCellEditor.swift` (L7–8 doc + L374 `"Use the Item Window inspector…"` string → page-native); `DetailRowDragPayload.swift` L5 comment.
- [ ] **ViewSettings seam-edits (managers still exist → safe):** **`SideKind` lives in FOUR files** (verified) — `StorageMenuRoot` (L196), `PropertiesListPane` (L95), `PropertyVisibilityPane` (L231), `EditPropertyPane` (L597) — each an identical `private enum SideKind { pages, items }`. **Simplification #2 — DELETE the enum, don't collapse it:** once `items` is gone it's a single-case dead discriminator; remove `SideKind` from each of the four and inline the page path (DRY + delete-more). **`PropertyTypePickerPane` has NO `SideKind`** (do not look for one) — but it DOES carry an `@Environment(ItemTypeManager)` declarer (L29). **Drop the `@Environment(ItemTypeManager)` declarer from all five panes** (the four above + `PropertyTypePickerPane`). `ViewSettingsButton` drop the `itemTypeManager` stored param + fix the `ContentView` call site; `PropertyEditorErrorMessage` drop the `ItemTypeManagerError` branch (L22–24) + overload (L58–69) **together with the `LocalizedError` extension on `ItemTypeManagerError` and the item-side `ManagerErrorMessageTests` test (CR-9 — all four pieces in one lockstep edit)**. The earlier "removing the branch early is safe" claim was wrong: the extension delegates into the mapper, so dropping the branch alone sends `localizedDescription` into the fallback, which recurses back into the extension until the process crashes — type-safe but runtime-recursive. The enum itself still dies in P3 with the manager.
- [ ] **Properties — explicit dead-file deletes (verification confirmed zero live consumers — §5b):** delete `SchemaConflictDetector.swift` + `SchemaConflictDialog.swift` (confirmed zero external refs), `TypeSettingsSheet.swift` (sole caller `ItemTypeRow.swift:86`, deleted above), and `MoveStripConfirmationDialog.swift` (confirmed zero live instantiations). Then: `ContextDisplayResolver` L45 drop `.item/.itemType/.itemCollection` icon arm; `PerTypeSchemaService`/`ContextValueEditor`/`ContextPicker`/`ContextChip`/`PropertyChip` doc-scrub.
- [ ] **Index seam-edits (tables stay until P7):** `IndexUpdater` 6 item methods + `reconcile/activate/reactivate` ternaries → page-only; `IndexBuilder` item snapshot structs + `collect/insert` item funcs + `clearAllTables`/`insertTierContextLinks`/`insertConnections` item blocks.
- [ ] **Connections seam-edits (collapse `{{` to `[[`-only — decision #3):** `ConnectionScanner` **delete the `itemRegex` + its `.item` dict slot entirely** (no `{{` scanning); `ConnectionCascade` delete `.item` rewrite arm (`Item.load`); `ConnectionFileLocator` delete `.item` `locate`/`idMatches` arms; `AutoCompleteWiring` **delete the chip/`itemLink` arm** + `queryKind` collapse to `.page`; `AutoCompleteWindow` comment scrub. (The MarkdownPM chipLink render pipeline stays dormant per P0; it just gets no connection-layer trigger.) **P1→P2 handoff (explicit):** here P1 stops *emitting* `ConnectionSyntax.item` (scanner) but the enum **case itself is removed in P2** (`ConnectionTitle.swift:11-15` is 2-case); `ConnectionScannerTests` is rewritten **here, not P8** (V5) — **delete the `{{Beta}}` → `.item` assertion (L10) and assert `{{ }}` is NOT scanned** (deleting an assertion compiles fine while the case still exists; there is no `.item→.chip` rename — decision #3 leaves no chip case at the connection layer).
- [ ] **Lockstep test surgery (V5 — verified couplings at HEAD):** in this same commit, delete `Detail/ItemTypeDetailViewTests` + `Detail/ItemCollectionDetailViewTests` (reference the views deleted above); seam-edit `Index/IndexUpdaterTests` + `Index/IndexBuilderTests` to drop the tests calling the deleted item methods/snapshot funcs (`upsertItemType`/`deleteItemType`/`upsertItem`/item collect-insert — the item-*table*-existence asserts survive until P7); `ConnectionScannerTests` per the bullet above. Tick each off in P8's list.
- [ ] **NavDropdown seam-edits:** `NavDropdownButton` drop `openItemWindow` helper + `.item` arm; `BackForwardButtons` drop `case .item` + `lookupItem` helper + `presentItemAction` call; `EntityRow` drop `.item/.itemType/.set` icon+label arms; `RecentsManager` drop `.itemType/.set`; `NexusState` drop `itemTypeOrder` + `item_type_order` key.
- [ ] **CRITIC-ADDED — `Nexus/AdoptionPreviewView.swift` (production view, was missed):** drop `summaryStat itemTypeMigrationCount` + `labels.itemType.singular` (L107–108); the `itemTypeMigrations` ForEach (L281); `itemTypeMigrationCount` computed incl. `wrapperKind == .items` (L431–434); `.itemType/.itemCollection` icon arm (L457) + label arms (L467–468); L167 `"Pages/Items/Agenda" → "Pages/Agenda"`; L13 doc. It consumes `PropertyIDMigration.itemTypeMigrations` (P3) + `SettingsLabels.itemType` (P6) + `AdoptedSidecarKind.itemType` (P3) — **must drop in lockstep** or it compile-breaks.
- [ ] **Verify + commit.** Builder Agent green with item enum cases + types still defined. If the compiler couples P1↔P2 (an enum case can't survive with all arms gone), fold P1+P2 into one green checkpoint. Commit: `refactor(pages): drop item arms from shared call sites (pre-enum-gate)`.

**Green gate:** build green with item enums/types still defined; test target compiles + passes after the lockstep surgery (no red interval).

---

### Phase P2 — Remove the enum spine (compiler exhaustiveness gate)

**Goal:** delete the item enum cases — the keystone that forces any missed seam to surface as a build error.

**Files & actions:**

- [ ] `IndexQuery.swift`: `EntityKind` (L658–661) drop `item/itemType/itemCollection`; `TargetRef` (L711–719) drop `itemType/itemCollection`; `resolveEntities` items SELECT block (L65–67); `entityContainer .item` case (L182–211); **drop the `kind` param entirely** from `resolveUniqueEntity`/`resolveUniqueTitle`/`resolvePageByIDOrTitle`/`titleExists`/`titleCandidates` (page-native simplification, L301/316/332/346/359); `kindTableMap` item keys — **note this dict is duplicated at L97–108 AND L390–406; simplification #5: hoist to one `nonisolated static let` and reuse** (removes a copy-paste hazard mid-strip); `FilterBuilder.targetSQL`/`targetEntityKind` (L496–509); `entityKindToOwningTypeKind`/`entityKindFromString` (L611–632).
- [ ] `ConnectionTitle.swift`: **collapse `ConnectionSyntax` to page-only** — drop the second (`item`) case (decision #3). **Simplification #4 — once single-case, DELETE the enum entirely** and inline `"page"` / `.page` at its call sites (it becomes a constant; `targetKind` always returns `"page"`, `AutoCompleteWiring.queryKind` always `.page`).
- [ ] `SidebarSelection.swift`: drop `case itemType/itemCollection` (L14–15) + `resolvedIcon` arms; `SidebarLookupBundle.itemType` field (L53) + every constructor arg; delete `resolveItemType`/`resolveItemCollection` (L115–128); `init?(stateRef:)` item arms (L144–146); `init?(tag:)` item arms (L169–170); `SelectionTag.itemType/.itemCollection` (L187–188) + `matches`/`init?` arms (L212–213).
- [ ] `SidebarConfirmation.swift`: drop `deleteItemType/deleteItemCollection` + id arms. `SidebarSheet.swift`: `IconTarget` drop `.itemType/.itemCollection/.item` + id arms. `IconPickerSheet.swift`: drop `.itemType/.itemCollection/.item` arms (currentIcon/save) + `@Environment(ItemTypeManager/ItemContentManager)` declarers.
- [ ] `DetailRow.swift`: `Kind` drop `.item/.itemCollection`; update `kindLabel` + `stateRef`. `DetailReorderPlanner.swift`: drop `.item/.itemCollection` from `Kind` + init arms.
- [ ] `SidebarDetailView.swift`: drop `.itemType/.itemCollection` switch arms; drop `@Environment(ItemTypeManager/ItemContentManager)`; delete the `.onAppear AppGlobals.presentItemAction` builder block (L130–152: `ItemLocationResolver`/`ItemRef`/`openWindow id:item-window`); KEEP `@Environment(\.openWindow)` (reused for page-preview in P5). **Quirk #10:** this single open-path call site is the coordination point with the parallel NSPanel session.
- [ ] `EntityStateRef.swift`: drop `Kind .item/.itemType/.set` + `init?(sidebarSelection:)` item arms (L56–57). Old `state.json` item kinds decode as `typedKind == nil` and skip (clean-slate safe).
- [ ] `ViewSettingsScope.swift`: drop `itemType/itemCollection` cases. `ViewSettingsRoute.swift`: drop `itemTemplate` case + `paneTitle` arm. `ViewSettingsPopover.swift`: drop item `rootContent` + `itemTemplate` destination arms. Delete `ViewSettings/ItemTemplatePane.swift` (now orphaned).
- [ ] `Validation/NexusContext.swift`: drop `lookupItemType` slot (L18) + `ItemType.find` resolver (L56) — KEEP the `@MainActor @escaping () -> NexusContext` snapshot-closure pattern for Pages (quirk #5). `NameCollisionValidator`: drop item branch. (Both resolve once `ItemType` is gone in P3 — same green window.)
- [ ] `Detail/ContentItem.swift`: **DELETE** (currently dual-case `.page`/`.item`; the item arm goes dormant after P1, leaving a single-case wrapper). **Simplification #3 — inline, don't just delete:** have the detail views return `[PageMeta]` directly instead of `[ContentItem.page(...)]`, removing the wrapper layer entirely.
- [ ] **Lockstep test surgery (V5):** ~20 test files reference the enum cases this phase deletes (grep `SidebarSelection\.itemType|ViewSettingsScope\.itemType|EntityKind\.item|\.itemCollection` over `PommoraTests` and trust the live result over this list) — seam-edit the mixed suites (e.g. `ViewSettingsScopeMappingTests`, `DetailReorderPlannerTests`, the Settings label suites) and early-delete the pure-item suites whose subjects die in P3 anyway (e.g. `ItemRefTests`, `ItemFormatMigrationTests`, `NewItemSheetTests`) in this same commit. Tick each off in P8's list.
- [ ] **Verify + commit.** Builder Agent: first hard compiler gate. `xcodebuild test` must confirm the host app bootstraps (quirk #16) and the sidebar outline diffs without crashing (quirk #8). Commit: `refactor(pages): remove item enum spine (compiler gate green)`.

**Green gate:** build green with item enum cases gone; host app bootstraps; outline stable.

---

### Phase P4 — Relocate survivors + add `PageType.open_in`

**Goal:** move the three page-used types out of the doomed `Items/LayoutArchetype.swift` and add `open_in` to `PageType`, so the symbols exist when `Items/` is deleted in P3. (P4 lands inside the P3 window, before the `LayoutArchetype.swift` delete.)

**Files:** Create `Pommora/Pommora/Vaults/PageDisplay.swift`; modify `Pommora/Pommora/Vaults/PageType.swift`; delete `Pommora/Pommora/Vaults/PageTemplateConfig.swift`; verify `Pommora/Pommora/Detail/Columns/PropertyCellDisplay.swift`; modify `Pommora/Pommora/DesignSystem/PUI.swift`.

- [ ] **Step 1 — Create `Vaults/PageDisplay.swift`** with the relocated types (internal; doc-strings page-native):

```swift
// Page-native display config relocated from the deleted Items/LayoutArchetype.swift.
enum OpenInMode: String, Codable, Sendable, CaseIterable {
    case compact   // opens the page in the PagePreview window
    case window    // opens the page in the main detail pane (was .fullPage)
}

enum PropertyDisplay: String, Codable, Sendable { /* …relocated verbatim… */ }
enum DisplayTreatment: Sendable { /* …relocated verbatim… */ }

extension PropertyDisplay {
    func treatment(for /* …existing signature… */) -> DisplayTreatment { /* …relocated verbatim… */ }
}
```

  (Copy the real `PropertyDisplay`/`DisplayTreatment`/`treatment(for:)` bodies from `Items/LayoutArchetype.swift`; rename `OpenInMode` cases `.preview → .compact` (raw `"compact"`), `.fullPage`(raw `full_page`)`→ .window` (raw `"window"`).)
- [ ] **Step 2 — `PageType.swift`:** remove `templateConfig` prop (L34) + CodingKey `template_config` (L43) + its init/decode/encode; add:

```swift
var openIn: OpenInMode?
// in CodingKeys: case openIn = "open_in"
// decode:  openIn = try c.decodeIfPresent(OpenInMode.self, forKey: .openIn)
// encode:  try c.encodeIfPresent(openIn, forKey: .openIn)
```

  Fix the `ItemType`-parity doc-strings (L5/25/32) and `find(id:)` doc (L109–111, drop the `ItemTypeManager` ref).
- [ ] **Step 3 — Delete `Vaults/PageTemplateConfig.swift`** (held only `layout`/`defaultBody`/`openIn`; `open_in` now on `PageType`, the rest dropped — open-decision #1).
- [ ] **Step 4 — Delete from `Items/LayoutArchetype.swift`** (the file is deleted in P3, but confirm these have no other consumer now): `LayoutArchetype`, `PropertyLayoutMode`, `PromotedProperty`.
- [ ] **Step 5 — `DesignSystem/PUI.swift`:** delete `enum ItemWindow { width/height }` (L86–95) + its MARK header (dead once the scene goes in P5; `PagePreview` is resizable — do not revive under a renamed enum).
- [ ] **Step 6 — Verify + commit.** Builder Agent green: `PageType` decodes `open_in`; `PropertyCellDisplay` resolves `PropertyDisplay`/`DisplayTreatment` from `PageDisplay.swift`. Commit: `refactor(vaults): relocate page display types + add PageType.open_in`.

**Green gate:** build green; no `LayoutArchetype`/`PromotedProperty`/`PropertyLayoutMode` symbol survives outside the about-to-delete file.

---

### Phase P3 — Delete item type bodies, managers, migration, `NexusEnvironment` keystone

**Goal:** with no references left, delete the item types/managers/validators/migration and strip the `NexusEnvironment` keystone (quirk #15 lockstep).

**Files & actions:**

- [ ] **Delete `Items/`** entirely: `ItemType`, `ItemTypeManager`, `ItemContentManager`, `ItemContentManager+CRUD` (`ItemCRUDError`), `ItemCollection`, `ItemParent`, `TemplateResolver`, and `LayoutArchetype.swift` (after P4 relocated its survivors).
- [ ] **`ItemWindow/` — MOVE two generic files out, THEN delete the rest (CR-4 + CR-8).** Currently 11 files, NOT 13 (the previously-listed `ItemWindowPresenter.swift` + `ItemWindowSceneRoot.swift` **do not exist** — consolidated by the parallel NSPanel refactor; the folder churns under that session, quirk #10). Enumerate via `ls Pommora/Pommora/ItemWindow/` and re-confirm before acting.
  - **CR-8 (verified — would break compile if missed): two files are generic and have a LIVE page-side consumer NOW** (`Pages/FrontmatterInspector.swift` uses both at HEAD `caa236b`). **MOVE, do not delete:** `PropertyEditorRow.swift → Properties/PropertyEditorRow.swift` (the sole per-type editor `switch` in the codebase — text/number/checkbox/date/select/multiSelect/relation/url/status/file; zero item coupling — takes only `PropertyDefinition` + `PropertyValue` binding) and `MultiSelectChips.swift → Properties/Chips/MultiSelectChips.swift` (generic `[String]` chip UI that `PropertyEditorRow.multiSelectEditor` depends on). Same-module move (no import edits — quirk #2 auto-includes); scrub item tokens from their header comments for no-trace. **If P3 deletes these without moving, `FrontmatterInspector` red-breaks immediately — this is independent of P5.**
  - **DELETE the remaining 9** (genuinely item-coupled, no other consumer): `FloatingItemPanel`, `ItemInspector`, `ItemWindowHost`, `ItemWindowLayouts`, `ItemWindowPanelManager`, `ItemWindowRenderer`, `ItemWindowViewModel`, `ItemWindowZoneConfig`, `PropertyFieldBar` (the pinned-chip-bar — no page equivalent).
- [ ] **Delete `Content/`:** `Item.swift`, `ItemFrontmatter.swift`, `ItemRef.swift` (+ `ItemLocationResolver`), `KindStamp.swift`. **Seam-edit** `TierRelationCarrying.swift` (drop `ItemFrontmatter` conformance, keep Page). **Seam-edit** `PageFrontmatter.swift`: drop `KindStamp.decodeKind` + **stop writing `Class`** (foreign frontmatter still preserves any external `Class` by value).
- [ ] **Delete `Validation/`:** `ItemValidator`, `ItemTypeValidator`, `ItemCollectionValidator`. (**CR-3 — `Connections/ItemLinkOpener.swift` is NOT deleted here.** It has a live consumer — `PageEditorView.onItemLinkClick` (L277–288) — not stripped until P5 Step 1. Deleting it in P3 red-breaks compile. Moved to P5 Step 1, adjacent to its consumer.)
- [ ] **`NexusEnvironment.swift` KEYSTONE STRIP (quirk #15):** remove stored props `itemTypeManager`/`itemContentManager`/`itemWindowPanelManager`/`itemConnectionResolver`; their construction/wiring/snapshot blocks; `AppGlobals.publish` item params; the `itemTypeMgr.loadAll` Task; the `.environment(...)` injects. Per open-decision #7, **reuse `pageConnectionResolver`** (drop the separate `itemConnectionResolver` slot). **Quirk #10:** `itemWindowPanelManager` served the floating window — coordinate removal with the parallel session; don't bundle its churn.
- [ ] **`ConnectionResolver.swift` (decision #7):** drop the `@Entry itemConnectionResolver` env key entirely; reuse `pageConnectionResolver` for `[[`. `PommoraConnectionResolver` is `kind: .page`-only (drop the `kind` param). **Rename** the resolver type/symbols to a page-native name (no `item`/`kind` framing) per no-trace.
- [ ] **Nexus migration deletes:** delete `ItemFormatMigration.swift`; `NexusManager.runFormatMigration` + `migratedItems` OR-fold + item-migration prose. `PropertyIDMigration.swift`: drop `itemTypeMigrations`/`scanItemType`/`applyItemType`/`enumerateItemMembers`/`.itemType` `TypeMigration` case/`itemTypesScanned` → PageType-only.
- [ ] **`NexusAdopter.swift` (heavy):** drop `AdoptedSidecarKind .itemType/.itemCollection`; `WrapperKind .items` + the `"Items"` name classification; delete `stampClassPass`/`stampOneFile`/`classifyClassStamp`/`ClassStampRead` + the autoTag call (Class dropped); delete `sweepStrayJSONItems`/`isStrayItemJSONCandidate` + its call; item sidecar writers; contentSniff doc simplify. Folder sidecar = sole kind authority.
- [ ] **`AtomicIO`:** `AtomicYAMLMarkdown` delete both `setStampKey` overloads + the `Yams.Node("Class")` write; `frontmatterScalar(at:forKey:)` — **re-grep**: delete if Class-classify was its only non-test caller, else keep generic (open item (b)). `NexusPaths` delete `itemTypeSidecarFilename`/`itemCollectionSidecarFilename` + the 5 item path helpers + L205 Class comment. `Filesystem.swift`/`Nexus.swift` doc-scrub.
- [ ] **`Ordering/OrderPersister.swift`:** delete `setItemTypeOrder`/`setItemCollectionOrder`/`setItemOrder`(×2)/`mutateItemType`/`mutateItemCollection`.
- [ ] **Lockstep test surgery (V5):** the suites referencing the types/managers deleted here cannot survive this commit — delete the remaining `PommoraTests/Items/` pure-item suites and the outside-`Items/` suites whose subjects die here (per P8's deletion lists: `ItemFileTests`, `KindStampTests`, `ItemValidatorTests`, `ClassStampPassTests`, etc.), and seam-edit the mixed suites that construct `ItemType`/call the deleted managers. **Relocate before deleting** (P8's relocation bullet): `PropertyEditorRowTests → PommoraTests/Properties/` rides along with the CR-8 source move. Tick each off in P8's list.
- [ ] **Verify + commit.** Builder Agent: `grep` confirms NO surviving `@Environment(ItemTypeManager/ItemContentManager)` declarer AND env props gone (first selection must not SIGTRAP — quirk #15); host app bootstraps (quirk #16). Commit: `refactor(pages): delete item types/managers/migration; strip NexusEnvironment keystone`.

**Green gate:** build + test green; no item managers, no `Class` write, no SIGTRAP on first selection.

---

### Phase P7 — SQLite schema v11 (delete-and-rebuild, no migration)

**Goal:** drop the item DDL so the index is page-only; bump the version so existing DBs delete-and-rebuild on open.

**Files:** `Index/IndexSchema.swift`, `Index/PommoraIndex.swift`.

- [ ] `IndexSchema.swift`: delete `itemTypesDDL`/`itemCollectionsDDL`/`itemsDDL` constants + their `apply()` calls; delete item index lines (`idx_items_*`, `idx_item_collections_*`); fix connections DDL comments (`'page'|'item'` → page-only; `surface → 'page_body'`).
- [ ] `PommoraIndex.swift`: bump `currentSchemaVersion 10 → 11` (L85) with a doc note (item tables dropped; connections/context_links item rows orphaned; existing DBs delete+recreate page-only). No logic change to `open(at:)`.
- [ ] Connections table keeps its columns but page-only (`source_kind`/`target_kind` always `"page"`, `surface "page_body"`).
- [ ] **Verify + commit.** Builder Agent: fresh DB builds page-only; an existing v10 DB deletes+rebuilds on open. Commit: `refactor(index): schema v11 — drop item tables (delete-and-rebuild)`.

**Green gate:** build + test green. **Lockstep test surgery (V5 — supersedes the prior "accept a red interval" option, which is no longer permitted):** `IndexBuilderTests` asserts item-table existence (L89/142/147/246/269/274/276); dropping the DDL makes those asserts fail. Seam-edit those asserts (plus any remaining item rows in `PommoraIndexTests`) **in this same commit** — P7 is then independently green-gateable like every other phase. Tick the pulled-forward edits off in P8's list.

---

### Phase P5 — Re-home chip-link app-side + build `PagePreview`

**Goal:** point the app's `{{ }}` path at the renamed MarkdownPM slots, delete the Item Window scene + `AppGlobals` bridge + auto-open scaffold, and build the new `PagePreview` surface + open-routing + the open-in toggle.

**Depends on:** P0 (renamed slots), P3 (item types gone), P4 (`OpenInMode` relocated).

**Files:** `Pages/MarkdownEditorConfig.swift`, `Pages/PageEditorView.swift`, `Pages/AppGlobals.swift`, `ContentView.swift`, `PommoraApp.swift`, create `Window/PagePreviewScene.swift`, delete `Window/PreviewWindow.swift`, `Vaults/PageType.swift` (+`PageTypeManager`), `Detail/PageTypeDetailView.swift`, `ViewSettings/StorageMenuRoot.swift`, `Sidebar/` page-row tap site, `ComponentLibrary/ComponentLibraryView.swift`.

#### PagePreview — Figma design (received 2026-06-09)

The Figma design is in; the STOP/WAIT gate is lifted for the *spec*, and the build proceeds once the three OPEN items below are answered. **Window shell:** rounded-rect panel, **475×475** collapsed (no-inspector); **Liquid Glass *menu* background** (the menu-glass material, consistent with the inspector's menu-BG hairline-card treatment shipped at `2220121`); resizable. The inspector, when toggled, adds a right pane and widens the window.

**Header band.** Leading: a capsule **window-dismiss (close) control** (closes the preview panel). Then the page **icon** (icon selector) + **Title** at `.title3`, both **inline-editable** (TextField → filename rename, per filename=title; icon via the existing icon selector). Trailing: the **inspector-toggle** capsule (a plain inspector show/hide — it does NOT transform). Vertical rhythm: `padding(top→title)` **equals** `padding(title→separator)`. The header **separator** is a hairline **inset to the capsule buttons' horizontal bounds** — NOT full-bleed; a small gap/affordance sits at each end where the separator stops short of the window edge.

**Body.** The page's `MarkdownPMEditor`, **slightly inset** ("reduced") to read as a preview. **Lock-gated editing:** the preview opens **locked = read-only**; the **Lock is the edit trigger** — unlocking makes the body **fully editable + live-saving** (same save path as the main `PageEditorView` editor). (Supersedes the prior always-`isEditable:false` model: `isEditable` binds to `!isLocked`.)

**Footer band.** Bottom-left: a **non-navigable breadcrumb** — `.footnote` emphasized weight, `.secondary` color — the context path ("Label > Label"). Bottom-**right**: the **Lock symbol** — the lock/unlock toggle that gates body editing (locked by default). The inspector button is unaffected (no transform).

**Open / Lock via context menu.** **Right-clicking the body area OR the title area** shows a context menu with **"Lock / Unlock"** and **"Open Page"**. "Open Page" routes to the full detail pane (`router.requestOpen(to: .page(page))` — CR-2 — + dismiss the preview). There is **no** "open" toolbar button; promotion-to-full is a context-menu command only.

**Inspector (toggled open).** Top: a **menufield** of the **three context layers** (`tier1`/`tier2`/`tier3`); the **middle** context row aligns exactly with the header separator of the main window; fill = `.quaternaryLabel`. Below it, a **separate menufield** for **page properties** — add properties from the page's schema and assign values, **reusing the existing Item-Window property-assignment UX** ("that functionality works well" — Nathan).

> **✅ P5↔P3 property-editor — RESOLVED (investigated 2026-06-09).** Good news: the page-native property editor **already exists and is ~complete** — `Pages/FrontmatterInspector.swift` (built in the ItemsV2 Phase A work) is a full Form-based editor with a debounced (300ms) save VM, all property types, tier rows, and error resilience. It saves via `FrontmatterInspectorViewModel.flushNow() → onSave → PageContentManager.updatePageFrontmatter → AtomicYAMLMarkdown.write`. **PagePreview reuses `FrontmatterInspector` VERBATIM — there is NO property editor to re-implement.** The only seam is the two generic files `PropertyEditorRow` + `MultiSelectChips`, which `FrontmatterInspector` already depends on at HEAD and which P3 must **move** (not delete) — handled in P3 above (CR-8). The shared pickers `ContextValueEditor`/`ContextPicker`/`ChipDropdown`/`DateTimePicker` already live in `Properties/` (no item coupling, reused as-is). The item-side `ItemInspector`/`ItemWindowViewModel` (pinned-chip + session-surface "Add property" logic) are correctly deleted — Pages render the full schema, no "Add" menu, no chip bar.

- [ ] **Step 1 — Editor config + view re-home.** `MarkdownEditorConfig.swift`: **drop the `itemResolver` param** (L33) — `config.services.chipLinks` stays at its NoOp default, so `{{` renders inert (decision #3, no app trigger). `PageEditorView.swift`: delete the `onItemLinkClick:` closure (L277–288, `ItemLinkOpener`/`presentItemAction`) **and delete `Connections/ItemLinkOpener.swift` here (CR-3, moved from P3)** — the closure is its only consumer; strip both in one commit. Drop `@Environment(\.itemConnectionResolver)` (L45) — reuse the renamed page resolver (decision #7); drop the L462 resolver arg. KEEP the `[[ ]]` `onLinkClick` path (L263–276) as the sole page link path. No `onChipLinkClick` wired (decision #4).
- [ ] **Step 2 — `AppGlobals.swift`:** delete `itemContentManager`/`itemTypeManager` statics (L23/25); the Item Window bridge block (L63–77: `itemWindow`, `presentItemAction`); `publish(...)` item params (L43–55). Coordinate the `publish` signature with `NexusEnvironment.init` in one commit.
- [ ] **Step 3 — `ContentView.swift`:** delete the `#if DEBUG -autoOpenItemWindow` `.task` block (L223–255); the `env.itemTypeManager/itemContentManager` reads in `primaryActionCapsule` (L94/100/108) + the inspector toolbar `SidebarLookupBundle` (L179).
- [ ] **Step 4 — `PommoraApp.swift`:** delete `UtilityWindow("Item", id: "item-window")` (L61–74). Add the page-preview scene (quirk #10: single owner; if the parallel session already converted the scene, replace whatever form exists):

```swift
WindowGroup(id: "page-preview", for: PageRef.self) { $ref in
    PagePreviewScene(ref: ref).environment(nexusManager)
}
.defaultSize(width: 475, height: 475)   // collapsed (no inspector); inspector widens it
.windowResizability(.contentMinSize)
```

- [ ] **Step 5 — Create `Window/PagePreviewScene.swift`** to the Figma design above. Build against the **verified live symbols** (the prior placeholder snippet had two fabricated calls — corrected here). The concrete Swift is written once OPEN-1/2/3 are answered; the load-bearing structure:
  - **Data load** (`.task(id: ref)`): `ref.resolve(vaultManager:contentManager:)` → `page`/`vault`; body via `PageFile.loadLenient(from: page.url, nexusRoot: contentManager.nexus.rootURL)?.body`. (CR-7 / build-time: verify the real `PageRef.resolve` signature, `PageMeta.id`/`.url`, and `PageFile.loadLenient` before relying on them.)
  - **Editor + lock state:** hold `@State private var isLocked = true` (preview opens locked). `MarkdownPMEditor(text:configuration:.pommora(verticalInset:0), fontName:"SF Pro Text", fontSize:15, documentId:page.id, isEditable: !isLocked)`. When unlocked, the body needs a real `Binding`/save path (not `.constant`) wired to the page-content save the main `PageEditorView` uses. The bottom-right Lock glyph toggles `isLocked`.
  - **Inspector:** `.inspector(isPresented:)` bound to a separate inspector-toggle `@State` (NOT `.constant(true)`, NOT coupled to the lock), hosting **`FrontmatterInspector(page:vault:index:…)` reused verbatim** — it already provides the full property editor (per-type rows via the now-`Properties/`-resident `PropertyEditorRow`, tier rows, debounced save). `index:` = `contentManager.indexUpdater?.index`; `relationDisplay:` from the env `ContextDisplayResolver`. The Figma inspector spec (3-context menufield with the middle row aligned to the header separator, `.quaternaryLabel` fill; separate properties menufield) is a **visual/layout pass over `FrontmatterInspector`'s existing Form sections** — restyle, do not rebuild.
  - **Context menu (`.contextMenu` on the body + title areas):** "Lock / Unlock" toggles `isLocked`; "Open Page" calls the open action below.
  - **CR-2 (verified) — `MainWindowRouter` is an injected instance, NOT static.** Add `@Environment(MainWindowRouter.self) private var router`; the open action is `router.requestOpen(to: .page(page)); dismissWindow()` (`.page(PageMeta)` is a confirmed real `SidebarSelection` case — `SidebarSelection.swift:13`). Fired from the context-menu **"Open Page"** command — there is no open toolbar button.
  - Apply the quirk-#16 XCTest guard if any launch-time restoration touches permissions.
- [ ] **Step 6 — Delete `Window/PreviewWindow.swift`** (zero live consumers; `PagePreview` does not reuse it).
- [ ] **Step 7 — `PageType.open_in` persistence + toggle.** **CR-7 (build-time):** verify `NexusPaths.vaultMetadataURL(forTitle:in:)` exists with that exact signature before writing `setOpenIn` — the path-helper family is confirmed present, but match the real name/shape. Add to `PageTypeManager`:

```swift
func setOpenIn(_ mode: OpenInMode, forVault typeID: String) async throws {
    guard let i = types.firstIndex(where: { $0.id == typeID }) else { return }
    var updated = types[i]
    updated.openIn = mode
    updated.modifiedAt = Date()
    try updated.save(to: NexusPaths.vaultMetadataURL(forTitle: updated.title, in: nexus))
    types[i] = updated
    // no SQLite upsert — open_in is not indexed
}
```

  In `StorageMenuRoot.swift` (decision #2): `SideKind` is already deleted (P1 simplification #2) + item arms stripped, then add the open-in segmented control. **CR-6 RESOLVED (Figma 2026-06-09):** the control sits in a **pinned footer at the bottom of the settings pane**, below a trailing `Divider`, **right-aligned** — a compact inline `Compact | Window` segmented control (the pane's `Edit Properties / Templates / Layout` rows sit above; the footer is a fixed band, not part of the scrolling content). **`ViewSettingsPane` ALREADY exposes a pinned `@ViewBuilder footer:` slot** (verified `DesignSystem/ViewSettingsPane.swift:28-45`, pinning at L74-79) — **render the control in that existing slot; no extension needed.** Control shape: a `Layout:` segmented `Picker`:

```swift
Divider()
Picker("Layout", selection: Binding(
    get: { liveVault.openIn ?? .window },
    set: { mode in Task { try? await pageTypeManager.setOpenIn(mode, forVault: liveVault.id) } }
)) {
    Text("Compact").tag(OpenInMode.compact)
    Text("Window").tag(OpenInMode.window)
}
.pickerStyle(.segmented)
// padding per Design.md
```

  Vault-scoped (shown for a vault's settings). **Note (verified):** `StorageMenuRoot` exposes `liveScope: ViewSettingsScope`, not a bare `liveVault` — extract the vault via `if case .pageType(let liveVault) = liveScope { … }` (the snippet's `liveVault` is shorthand for that). Labels `"Compact"`/`"Window"` are structural, NOT user-renameable. **No duplicate toggle in `PageTypeDetailView`** (decision #2 — single location).
- [ ] **Step 8 — Open-routing branch** at the sidebar page-row tap (where `selection = .page(p)` is set):

```swift
switch vault.openIn ?? .window {
case .window:  selection = .page(p)                                   // in-pane (existing render)
case .compact: openWindow(id: "page-preview", value: PageRef(/* page:in:vault: */))
}
```

  `SidebarDetailView`'s `.page` case stays the `.window` render.
- [ ] **Step 9 — `ComponentLibraryView.swift`:** delete the "Item Window" `WindowLaunchRow` + `WindowStubSheet` + `showingItemWindow`; rewrite the "Page Preview" row prose + rewire to `openWindow(id: "page-preview")`. **`Properties/Chips/ItemChip.swift` → rename to `ChipLinkView` (page-native), KEEP** (Nathan's call — retain as a staged Component-Library asset, trace-free, unused for now); rename the `ItemChipShowcase` gallery section + entry to the `ChipLinkView` name rather than deleting it.
- [ ] **Step 10 — Verify + commit.** Builder Agent green. Manual smoke (note for executor): a `.compact` vault page-tap opens `PagePreview` **locked/read-only**; the bottom-right Lock toggles editability and edits live-save; right-click → "Open Page" routes to the detail pane + dismisses; the inspector toggle shows/hides independently; a `.window` vault renders in-pane. `grep` confirms no `"item-window"` literal survives. Commit: `feat(pages): PagePreview window + vault open-in toggle; remove Item Window scene`.

**Green gate:** build + test green; open-in routing works both ways; no `item-window` scene id.

---

### Phase P6 — Strip item vocabulary from Settings + peripheral docs (alongside P5)

**Files:** `Settings/SettingsLabels.swift`, `Settings/Settings.swift`, `Agenda/AgendaTaskManager.swift` + `AgendaEventManager.swift`, `Properties/Chips/*`, `Properties/PinnedManager.swift`.

- [ ] `SettingsLabels.swift`: remove `itemType`/`itemCollection` `LabelPair` (L7–8) + CodingKeys `item_type`/`item_collection` (L17–18) + default seeds (L29–30). `SidebarSectionLabels`: remove `var items` (L48) + CodingKey + init param/assignment + the custom `init(from:)` `items` decode (L83) + default `items: "Items"` (L60); keep `pages` required.
- [ ] `Settings.swift`: delete the v1→v2 migrate block rewriting `sidebarSections.items "Types"→"Items"` (L131–139); keep the version scaffold + later steps.
- [ ] Agenda doc-comments (DRY across both manager files): `ItemCRUDError.duplicateTitle → PageCRUDError`; `"Pages, Items, and Agenda" → "Pages and Agenda"`; drop the `"Items) there is no container"` parenthetical.
- [ ] `ContextChip`/`PropertyChip` doc-scrub (Item Window → `FrontmatterInspector`/`PagePreview`); `PinnedManager` doc `'"page"/"item"' → '"page"'`.
- [ ] **Verify + commit.** Builder Agent green; add the `SettingsLabels` decode-tolerance test in P8 (a legacy `settings.json` with `item_type`/`item_collection` keys still loads). Commit: `refactor(settings): drop item labels + migration (decode-tolerant)`.

---

### Phase P8 — Test reconciliation + new coverage (after P5/P6)

**Goal:** the master test checklist. Under the V5 lockstep rule, most of the deletions/seam-edits below land pulled-forward inside P1/P2/P3/P7 — here the controller **verifies every line is ticked**, finishes any remainder, relocates the two mis-filed page tests, and adds the new coverage (which exercises P5's routing + P6's labels, hence the after-P5/P6 ordering). Honor quirk #1 (run by real `@Suite`/type token; verify non-zero counts).

- [ ] **Delete pure-item suites in `PommoraTests/Items/`** (real type tokens; note suite-string≠type for `ItemCollectionFile`/`ItemTypeFile`/`ParentItemTypeLookup`): `ClearTemplateConfigTests`, `ItemCollectionPinningTests`, `ItemCollectionTests`, `ItemContentManagerTests`, `ItemMarkdownTransitionTests`, `ItemReorderPersistenceTests`, `ItemTemplateConfigTests`, `ItemTypeManagerSchemaCRUDTests`, `ItemTypeManagerTests`, `ItemTypeSingularCodableTests`, `ItemTypeTests`, `ItemValidatorCapTests`, `ItemWindow{Layouts,Partition,Reorder,ViewModel,ZoneConfig}Tests`, `LayoutArchetypeTests`, `MoveItemTests`, `ParentItemTypeLookupTests`, `PromotedEntriesTests`, `PromotedForFieldTests`, `PromotedPropertyTests`, `RenameItemReturnTests`, `TemplateResolverTests`, `UpdateTemplateConfigTests`.
- [ ] **Relocate out of `Items/`:** `PropertyEditorRowTests.swift → PommoraTests/Properties/` (no item dep — mis-filed). Seam-edit + relocate `CollectionTemplateConfigTests.swift → Vaults/` (strip the 4 item tests; reconcile the 2 page tests against post-strip `PageCollection`/`PageType` — gated by open-decision #1; if `PageCollection.template_config` is dropped, delete those 2).
- [ ] **Delete pure-item suites outside `Items/`:** `Content/ItemFileTests`, `Content/ItemRefTests`, `Content/KindStampTests`, `Detail/ItemTypeDetailViewTests`, `Detail/ItemCollectionDetailViewTests`, `Validation/ItemValidatorTests`, `Connections/ItemLinkNavigationTests`, `Nexus/ClassStampPassTests`, `Nexus/ItemFormatMigrationTests`, `Sidebar/Sheets/NewItemSheetTests`, `ViewSettings/ItemTemplateRouteTests`, `ViewSettings/ArchetypePickerTests`, `ViewSettings/TemplateEditorTests`, `Properties/TypeSettingsSheetTests`, `Vaults/PageTemplateConfigTests`.
- [ ] **Seam-edit the critic-flagged mixed suites** (drop item arms, keep page coverage): `Index/{IndexUpdaterTests,IndexBuilderTests,IndexQueryTests,ConnectionQueryTests,TierRelationsEmitTests,IndexParentUpsertCascadeTests,CollectionIconSetterTests,CollectionIconTests,PommoraIndexTests}`; `Connections/{ConnectionCascadeTests,ConnectionLiveRefreshTests,ConnectionScannerTests(`{{` assertions deleted in P1 — no `.chip` rename),ConnectionConfigWiringTests,ConnectionResolverTests,AutoCompleteWiringTests}`; `Nexus/{AutoTagOrphanCleanupTests,DefaultViewMigrationTests,LoadAllIndexSyncTests(keep page-side quirk #14, drop item-side),PropertyIDMigrationTests,NexusAdopterAutoTagTests,NexusManagerLaunchIntegrationTests(✓ DELETED in P1 — misclassified as mixed: all 3 tests were item-migration-premised with no page coverage; the migration→forceRebuild join + Class relocation it mirrored die in P3; page-side launch-tail coverage is P8 new-coverage work),IndexUpdaterWiringTests,NexusManagerIndexTests,NexusAdopterTests,ContentSniffTests}`; `AtomicIO/NexusPathsTests` (drop `itemTypeSidecarFilename` asserts L42–43/266); `Vaults/{CollectionTypeIDReconcileTests,ResolvedPropertiesTests,SidecarVersionTests,PageCollectionViewsTests,ManagerErrorMessageTests(✓ item test dropped in P1 — CR-9),MemberFileStripResilienceTests}`; `Content/{NexusWideUniquenessTests,RelationCommitRoutingTests,UnlinkTierTests(drop item MARK),PageItemIconSetterTests(drop 2 item tests + RENAME file/suite/struct → PageIconSetterTests)}`; `Properties/{ReorderPropertyParityTests,DefaultSortConfigTests}`; `CRUD/ManagerCreateReturnContractTests`; `Detail/DetailReorderPlannerTests`; `Validation/NameCollisionTests` (drop item arm if present); `NavDropdown/RecentsManagerTests` (rewrite `.item/.itemType` records → `.page/.pageType`); `Settings/{SettingsTests,SettingsManagerTests,UILabelThreadingTests}`; `ViewSettings/ViewSettingsScopeMappingTests` (drop 2 item-scope tests).
- [ ] **Support:** delete `Support/TempNexus+Items.swift` after porting `UnlinkTierTests` off `itemTypeRoot`; KEEP `Support/TempNexus.swift` (115 consumers). Remove the now-empty `PommoraTests/Items/` folder.
- [ ] **VERIFY-SAFE (do not touch — only generic `removeItem`/cosmetic tokens):** `AppStateTests`, `DisplayAsDefaultTests`, `FilesystemTrashTests`, `DetailRowDragPayloadTests`, `AttachmentCascadeTests` (confirm only `FileManager.*Item`).
- [ ] **Add new coverage** (TDD — write failing first):
  - `PommoraTests/Vaults/PageOpenInTests.swift` — `PageType.open_in` round-trips through Codable + defaults to `nil` (treated as `.window`).
  - `PommoraTests/Settings/SettingsLabelsDecodeToleranceTests.swift` — a `settings.json` carrying legacy `item_type`/`item_collection`/`items` keys still decodes.
  - `PommoraTests/ViewSettings/OpenInToggleTests.swift` — the Compact/Window leaf writes `setOpenIn` (replaces `ItemTemplateRouteTests`).
  - `PommoraTests/Pages/PagePreviewRoutingTests.swift` — vault `open_in == .compact` routes to the page-preview window value; `== .window` sets `.page` selection.
- [ ] **Verify + commit.** Builder Agent: `xcodebuild test` green; `PommoraTests` compiles with zero item-domain references; each renamed suite run by its real token shows a non-zero executed count (quirk #1). Commit: `test(pages): strip item suites, seam-edit mixed, add open-in/PagePreview coverage`.

**Green gate:** full test target green; zero item references; new suites execute non-zero.

---

### Phase P9 — Band 3: user sidebar sections (last build)

**Goal:** persisted user-creatable sidebar sections grouping Vaults — navigation-only, no on-disk vault move. Reuse the `SavedConfig` manager pattern verbatim.

**Files:** create `Configuration/SidebarSectionsConfig.swift` + `Configuration/SidebarSectionsManager.swift`; modify `AtomicIO/NexusPaths.swift`, `Nexus/NexusEnvironment.swift`, `Sidebar/SidebarView.swift`, `Sidebar/PageTypeRow.swift` context menu.

- [ ] **Step 1 — Config + manager** (mirror `SavedConfig`/`SavedConfigManager` verbatim):

```swift
struct SidebarSectionsConfig: Codable, Sendable {
    struct Section: Codable, Sendable, Identifiable { let id: String; var label: String; var vaultIDs: [String] }
    var sections: [Section] = []
}
```

  `SidebarSectionsManager` mirroring `SavedConfigManager.swift` — `init(nexus:)`, `load()` via `AtomicJSON.decode` with `defaultSeed` + first-write, `save()` via `AtomicJSON.write`, `@Observable pendingError`. Add `NexusPaths.sidebarSectionsURL(in:) -> .nexus/sidebar-sections.json`. (Quirk #16: guard `load()` if it touches permissions at launch.)
- [ ] **Step 2 — Register on `NexusEnvironment`** (quirk #15): one stored property + one `.environment(...)` line in `.injectNexusEnvironment(_:)`.
- [ ] **Step 3 — Render** (quirk #8 — homogeneous rows only): each user section a sibling `Section(isExpanded:) { ForEach(vaultIDs → PageType) { PageTypeRow(...) } } header: { SectionHeader(...) }` — identical shape to `VaultsSection`, reusing `PageTypeRow(pageType:selection:editingID:justCreatedID:presentedSheet:confirmingDelete:nexus:index:)`. **Empty sections render NOTHING** (never a leaf placeholder mixed with disclosure rows).
- [ ] **Step 4 — Affordances:** "Add Section" `Button` in the Vaults `SectionHeader .contextMenu`; "Move to Section" `Button` in `PageTypeRow .contextMenu` writing the `vaultID` into the chosen section (single-membership — open-decision #6); inline-rename via the existing `CreateWithInlineEdit.run` + `DefaultTitleResolver`.
- [ ] **Step 5 — Verify + commit.** Builder Agent: `xcodebuild test` confirms the outline bootstraps (quirk #8) with a user section present + an empty one. Commit: `feat(sidebar): user-creatable sections grouping vaults`.

**Green gate:** build + test green; outline stable with populated + empty user sections.

---

### Phase P10 — No-trace doc sweep + plan archival (the closer)

**Goal — total erasure, two exceptions.** Every doc must read **as if Items never existed** and Pages were always the only operational entity beside Agenda. Delete the Items feature doc entirely; reframe every other doc around Pages; drop all Item vocabulary, diagrams, schema rows, and wikilinks. **The ONLY two places "Items" may survive in the entire repo are:** (1) a **single one-line historical note in `CLAUDE.md`** (that an Items layer existed and was collapsed into Pages — pointer to History), and (2) the **`History.md` record** (the collapse entry + the superseded ItemsV2 entries, append-only). Anywhere else — Features, PRD, Architecture, Domain-Model, Framework, Guidelines, code comments, this plan's siblings — a surviving "Item" is a defect the final grep gate must catch. This is the last phase; it is not optional polish — it is the no-trace guarantee made real.

- [ ] **Apply the accumulated flag-list (Operating Contract #3).** Before sweeping, gather every "this finding changes doc X" note accrued across P0–P9 and fold each into the relevant doc rewrite below — nothing flagged mid-implementation may be left only in a transcript.
- [ ] **Delete `.claude/Features/Items.md`;** repoint or remove every `[[Items]]` wikilink. **Build a per-link repoint matrix first** — verification found ~22 `[[Items]]`/`[[Item …]]` wikilinks across 7 Feature files (Collections, Pages, Prospects, Properties, Agenda, PageTypes, Connections, + Domain-Model/Architecture/History); enumerate each with `grep -rn '\[\[Item' .claude/` and decide repoint-`[[Pages]]`-or-drop per link. Missing one leaves a dangling wikilink in the final docs.
- [ ] **Heavy one-entity rewrites:** `Domain-Model.md`, `Architecture.md` (table count 11→8; schema v11 delete-and-rebuild; drop Class stamp + `_itemtype`/`_itemcollection` + `ItemTypeManager`/`ItemContentManager` rows), `PommoraPRD.md` (drop item DDL + recount; one operational entity; drop Item Window/Class/`{{` item product vocab), `Connections.md` (`[[` sole page-link path; `{{` re-homed page-native chip-link gated off; drop Item Chip/Item Window), `Properties.md` (drop Item Type Settings + `_itemtype` schema-carrier; pinned_properties → Prospect), `Sidebar.md` (drop Items section; recast shape; band-3 note; rewrite the quirk-#8 mirror clause), `NavDropdown.md`.
- [ ] **Seam-edit docs:** `Prospects.md` (delete Item Templates + legacy-Item-JSON-migration; reframe Item↔Page promotion; keep the pinned-property prospect item-free), `QuickCapture.md` (retarget capture to Page), `PageTypes.md` (document `open_in`; drop ItemType symmetry + `PageTemplateConfig`), `Pages.md` (document the open-in model + `PagePreview`), `Agenda.md`.
- [ ] **Guidelines:** `Symbols.md`, `CRUD-Patterns.md` (rewrite the PreviewWindow rule → `PagePreview`; drop the `ItemContentManager` arm), `Markdown.md`, `Paradigm-Decisions.md` (**append** a superseding entry + mark #14/#15 superseded inline — open-decision #5; do not falsify chronology).
- [ ] **`History.md`:** add a top collapse entry (survivor=Page; Item* deleted; Class dropped; `[[` declassed; `{{` re-homed gated-off; `PageType.open_in`; `PagePreview` built / `PreviewWindow` eliminated; schema v10→v11; no migration); cross-note prior ItemsV2 entries as superseded.
- [ ] **`Framework.md`:** drop Items-side roadmap rows; replace the "Item UIX — Item Window" slot with `PagePreview` + open-in + band-3 work.
- [ ] **`CLAUDE.md` (heavy):** one-entity rewrite (drop the Items operational layer, the symmetric-code paragraph, the Vault/Collection vs Type/Set divergence, the Class-stamp clause, the Item Window bullet → detail-pane vs `PagePreview`). Quirks: #8 → post-strip homogeneous-sections rule; #14 drop `ItemTypeManager.loadAll`; #15 drop the `ItemTypeManager/ItemContentManager` example; #5 drop `ItemContentManager`. Update the Document Map (Items.md deleted). **KEEP exactly ONE one-line historical note** (e.g. *"Items were a separate operational entity until the 2026-06 collapse into Pages — see History.md"*) — this is one of the only two permitted surviving "Items" mentions in the repo.
- [ ] **Archival (CR-5 — mostly a no-op now):** the three ItemsV2 plan files (`06-07-ItemsV2-Plan-V3.md`, `06-07-ItemsV2-Spec-V5.md`, `06-03-ItemsV2-Implemented.md`) were **already deleted in HEAD `caa236b`** — git history preserves them; **no `Superseded/` relocation needed.** Reconcile against actual `git status` at execution (working tree may still show `06-07-ItemsV2-Plan-V3.md` as modified). `Planning/README.md`: note the ItemsV2 plans were superseded by PagesV2 (commit ref). **Do NOT "fix the false MarkdownPM-untouched line" — that line does not exist in the current README** (phantom claim, removed).
- [ ] **Low-severity residue** (kept page code): scrub stale `ItemType`/`_itemtype` doc-comments in `Vaults/PageCollection.swift` L4, `PropertyDefinition.swift` L3–4/128/166, `SavedView.swift` L4–5, `BuiltInContextLinkProperties.swift` L33.
- [ ] **Verify + commit.** Run the codified no-trace gate (allowlist explicit, not prose) across `.claude/` AND `Pommora/`:
  ```
  grep -rniE '\bitem' .claude/ Pommora/ External/MarkdownPM/ \
    | grep -vE 'FileManager|removeItem|copyItem|moveItem|NSMenuItem|GridItem|SavedConfig\.Item|<Item|\b(for|let|var) +item\b|History\.md|Superseded/|list.item'
  ```
  (V5: `External/MarkdownPM/` added to the scanned paths — the gate's prose always claimed MarkdownPM item-free but the codified grep missed it; `list.item` excludes the package's genuine bullet/heading list-item comments.)
  must return only (a) append-only `History.md` entries (marked superseded) and (b) the **single** permitted `CLAUDE.md` historical-note line — **any other hit is a defect.** **The allowlist is comment-blind** (a stray `// Item Window` comment near kept code would slip it) — so ALSO run a `PascalCase`-token scan to catch comment residue: `grep -rn 'Item[A-Z]' Pommora/Pommora` must return zero hits (the `EntityKind`/`SidebarSelection` compiler gate in P2 catches `.item` enum cases; this scan catches `ItemType`/`ItemWindow`/etc. in comments). Commit: `docs: no-trace sweep — one-entity model; archive ItemsV2 plans`.

**Green gate (no-trace, final):** the grep verification in `no_trace_verification` passes — production source, on-disk schema, MarkdownPM, tests, and docs all item-free except the enumerated generic survivors (`FileManager.*Item`, `NSMenuItem`, `GridItem`, `SavedConfig.Item`, loop vars) and append-only history.

---

### Self-review notes

- **Spec coverage:** every spec section maps to a phase — strip (P1–P3, P7, P8), `[[` declass + `{{` rename (P0, P2, P5), `Class` drop (P3), `PagePreview` (Figma design captured in P5) + open-in + lock→open inspector-button transform (P4, P5), band-3 (P9), QuickCapture (spec-only, P10 doc), closeout (P8 tests, P10 docs). No pinned-property tasks (correctly absent — Prospect).
- **P5 design resolved 2026-06-09:** top-left = window-dismiss; Lock = edit gate (default locked, unlock→editable+live-save); inspector toggle unchanged; "Open Page"/"Lock-Unlock" via right-click context menu; lock glyph bottom-right. CR-6 RESOLVED — open-in segmented control sits in a pinned, right-aligned footer below a trailing `Divider`, rendered in `ViewSettingsPane`'s **existing** pinned `footer:` slot (verified L28-45/74-79 — no extension needed). **P5↔P3 property editor RESOLVED** — `FrontmatterInspector` is reused verbatim (no re-implementation); P3 MOVES `PropertyEditorRow` + `MultiSelectChips` to `Properties/` rather than deleting them (CR-8). **No remaining P5 OPENs — P5 is spec-complete and ready to build.**
- **Critic gaps folded in:** `AdoptionPreviewView` (P1) + the ~25 under-mapped test files (P8 seam-edit list).
- **Type consistency:** `OpenInMode { .compact, .window }`, `chipLink*` family names, `setOpenIn(_:forVault:)`, `PagePreviewScene`, `SidebarSectionsConfig` used consistently across P0/P4/P5/P8/P9.
- **Open decisions** (7) carry recommendations; the write→stress-test→revise loop ratifies them.
