### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-11 — v0.4.1 Sets FINISHED, pending stress-testing)

**Sets shipped end-to-end on branch `sets`, merged to `main` as v0.4.1.** The third operational tier (Vault → Collection → Set (optional) → Pages) went spec → stress-tested plan → 11-task subagent execution (each task a green commit, every agent claim controller-verified with targeted test runs) → docs-as-fact rewrite. 1006 → 1058 tests green. Includes: `PageSet` + `_pageset.json`, dedicated `PageSetManager`, schema v14, depth-2 adoption, `ContainerIDHealer` ULID-collision hardening, sidebar Set rows (expandable, never selectable), set-aware connections/editor/preview write paths, strip-free in-vault moves + whole-Set moves, the renameable "Set" label. Record → `History.md` § "Sets"; spec → `Features/Sets.md`; decision → registry #19. **Status: feature-complete pending Nathan's hands-on stress-testing** — two live-test bugs (selection bleed, invisible new Set) and two code-review finds (set pages unselectable via sidebar lookup, `unlinkTier` nulling `page_set_id`) were fixed same-session; more may surface under real use.

#### Lessons Learned

- **An untagged row inside a tagged container INHERITS the container's `.tag`** — "no tag" ≠ non-selectable. Non-selectable rows need a distinct tag that resolves to no selection + `.selectionDisabled(true)` on the label row (not the container — traits propagate to generated child rows). Now in CLAUDE.md quirk #9.
- **`-only-testing` filters match the TYPE name, not the `@Suite` display string** — a mismatched filter silently no-ops to `TEST SUCCEEDED` with 0 tests. Always confirm non-zero executed counts from the canonical xcresult (console output also masks retry-flicker: a test can fail, pass on retry, and print SUCCEEDED).
- **Two ULIDs minted in the same millisecond tie on the timestamp prefix** — never assert creation order across quick successive creates; derive order baselines in tests.
- **`INSERT OR REPLACE` upserts make every omitted column a silent reset** — any call site that upserts a page without threading `page_set_id` erases set membership. When a row gains a column, grep every upsert call site, not just the happy path.
- **The controller-verifies-every-claim loop earns its cost**: this branch's verification caught a zero-test filter no-op, a Sendable-capture compile failure, a stale schema tripwire, a genuinely flaky order assertion, and a plan reference to a dialog that never existed.

#### Next Session (Nathan's standing direction)

**Views.** The full design pass for the v0.5.0 Views cluster (Board / List / Cards / Gallery, multi-saved-view tabs, per-view order/sort/Group By/columns, reorder engine). START FROM `Planning/06-11-Views-Spec.md` — the pre-design findings ledger (current SavedView/GroupConfig code facts, roadmap scope, Sets-derived requirements like the property-or-container `GroupConfig` reshape and structural-grouping defaults, platform notes). Also fold in the stress-test feedback from Nathan's v0.4.1 usage.

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (was undecided post-PreviewWindow-elimination; the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) live at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

- Sidebar set-row selection bleed — untagged rows inherited the collection's tag; fixed with `SelectionTag.set` + `selectionDisabled` (regression-tested).
- New Set invisible in collection view — view rendered only pages; Sets now render as `DisclosureTableRow` rows with pages as children (empty Set = visible leaf).
- Set pages unselectable via sidebar lookup — `resolvePage` now searches `pagesBySet` (regression-tested).
- `unlinkTier` cascade nulled `page_set_id` (INSERT OR REPLACE) + missed the `pagesBySet` cache — both now set-aware.

Outstanding (restored — wiped by the PagesV2 refresh, not yet fixed):

- **Column reorder broken** — drag-reordering table columns; folds into upcoming view-system work.
- **"Modified" not hideable** in the visibility settings.
- **Inline-edit lag** — property value inline edit has a noticeable update buffer.
- **Column layout not persisted** across sessions (+ property columns don't show icons); folds into upcoiming view-system work.
- **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
- **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
- **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **New property values aren't selectable until an app restart** — adding a value to a property doesn't refresh its picker live; the new option only appears after a relaunch.
- **Pinned-nav title staleness** — changing a page's title doesn't update its title in the pinned section of the nav dropdown until re-pinned (recents update fine, being constantly refreshed). Likely needs a file-watcher (possibly overkill, or naturally resolved once a watcher lands). Non-issue for now.
- **Collection reorder limits** (investigated — not a bug): a vault with one collection + no root pages can't reorder it (inherent SwiftUI `.onMove` — needs ≥2 items in the `ForEach`); and a collection can't be dragged past root Pages (an intentional v0.3.0 no-interleave guard in `PageTypeRow.reorder`, line ~317). Enhancement to allow interleaving collections + pages: drop the cross-set guard + add a mixed `reorderDisclosureItems` path that splits the result back into collection-order + page-order.
- **KNOWN ISSUE; NOTE TO FUTURE** - with the change from relation properties to contexnts, future implementation of tasks + events won't have a way to relate to contexts; we'd cross this bridge when we get there.

#### Sibling Project — React Rebuild (now in this repo under `React/`)

A React + TypeScript + Electron rebuild of Pommora lives in this repo as a top-level **`React/`** folder (subtree-merged, full history preserved) — a port of the same PRD/paradigm, not a new product. So far: the **headless data layer** is done (CRUD, properties, connections, SQLite index, Agenda; tests-green, no UI wired) and the **design system** is established (vanilla-extract tokens, Lucide icons, a liquidGL glass material, a data-driven showcase that also static-builds for hosting). App shell + data-layer→UI wiring come next. The Swift app moves into a sibling **`Swift/`** folder in a later coordinated pass. Full state → `React/.claude/Handoff.md`.
