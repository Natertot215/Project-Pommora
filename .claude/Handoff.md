### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-13 — v0.5.0 Views cluster MERGED to `main` `8b9d4a1`: reorder/resize/row-order fixed [a REAL bug, not build-disparity], Collections on the native table, old stack deleted, multi-agent merge-gate passed)

**Headline: `views-salvage` is merged into `main` (`8b9d4a1`).** The whole v0.5.0 Views cluster — native `NSOutlineView` table (`ViewOutlineTable`) in BOTH Vault + Collection detail views, gallery + covers/banners, sort/filter/group view-settings panes, views dropdown, shared view pipeline, SavedView v2 schema, and column reorder/resize + row-order persistence — is on `main`. Local only — **NOT pushed to origin** (main is 6 commits ahead of `origin/main`). Build + **1214 tests** green.

**The reorder bug was REAL — and the prior handoff got it wrong.** Last session this file concluded the "column reorder doesn't persist" report was *build-disparity* (a stale binary). **That was false.** When Nathan tested, it genuinely didn't persist. Root cause, proven by live instrumentation: **`NSOutlineView` does NOT post `columnDidMove` / `columnDidResize` notifications for user gestures**, so the notification-observer persist never fired. Fix: capture the gesture directly off `ColumnHeaderView.mouseDown` (after AppKit's synchronous modal tracking loop returns) → `persistLiveColumnOrder` / `persistLiveColumnWidths`. Rows had a second, distinct bug — `PageContentManager.loadAll` re-resolved from a STALE in-memory `pageOrder` snapshot on re-entry — fixed by re-reading `page_order` fresh from the sidecar (vault/collection/set). Verified on disk (in-app self-test), by an independent agent, and the full suite. This is the cornerstone's exact failure mode: I asserted "build-disparity" without proving the *gesture* path, and time was lost before the real fix.

**Then finished the table and ran the merge gate.** Collections swapped off the old hand-rolled `CustomTableView` onto the native `ViewOutlineTable` (mirroring the Vault wiring); the 1,358-line old stack deleted (kept SHARED `RowDragCoordinator` + `ViewSelectionModel`). A focused review, then a full multi-agent **merge-gate** over the ENTIRE `main...views-salvage` diff (7 subsystem reviewers + a cross-cutting **table↔gallery DRY** reviewer Nathan requested) returned **1 BLOCKER + bugs + DRY-share**, all applied + verified before merging. The blocker: a **gallery cross-group card drop corrupted on-disk row order** (it resolved dragged items only within the *target* group, then fell back to the whole group → wrote a wrong reorder) — the table did NOT have this bug; fixed to mirror the table's all-groups resolution. Nathan's table↔gallery DRY directive was applied (shared `PageIconGlyph`, `VisiblePropertyOrder` resolver, `cellValue` helper, unified drag id-source). Merge resolved its one conflict (`Handoff.md`, docs); zero code conflicts.

**Left off:** `main` = `8b9d4a1` (merged, **local-only**). Working tree clean except an untracked parallel-session doc (`.claude/Planning/06-13-React-Design-System.md`, left per quirk #10). Build + 1214 tests green.

#### Lessons Learned

- **"Build-disparity" is a LAST resort, proven — never a first explanation for "still broken."** The 2026-06-13 reorder bug was closed as build-disparity last session and it was a real code bug (NSOutlineView posts no column notifications). Build-disparity IS real (confirm the running binary maps to source: `pgrep -x Pommora` mtime vs the change's timestamp), but only assert it AFTER the code path is proven correct. A process-restart test proves *reload-honors-disk*, NOT that a *user gesture writes* — verify the actual user path end-to-end. **→ corrects this file's prior "reorder verified, was build-disparity" claim.**
- **`NSOutlineView` does not post `columnDidMove` / `columnDidResize` for user column gestures.** Capture reorder + resize off the header view's `mouseDown` (after `super.mouseDown`'s modal tracking loop), then persist. **→ candidate CLAUDE.md quirk.**
- **A second renderer must SHARE the data logic, not re-implement it.** The gallery shipped a cross-group-drop data-corruption bug the table didn't have, purely because it resolved dragged items differently — caught only by the merge-gate's cross-cutting table↔gallery reviewer. Layout-agnostic data / persistence / drag / ordering logic lives in ONE shared place; renderers stay thin. (Nathan's explicit directive: don't rebuild table behavior into the gallery.)
- **Commit the WIRING with the feature, not just the new files** (carried — the `e7719c0` ghost-chase where the call-site swap was unstaged).
- **Native-first** — wrap the AppKit control; disclosure/resize/reorder/keyboard come free. Reinforces [[project-views-custom-table-failed-use-appkit]].

#### Next Session

1. **Deferred `ViewSurface` extraction.** `PageTypeDetailView` and `PageCollectionDetailView` are ~85% byte-identical (a SCOPE-DRY, distinct from the table↔gallery DRY already done). The merge-gate confirmed extracting a shared `ViewSurface` container (owning the `content` render-switch + the shared scope-independent members, parameterized by `ViewItemScope` + the two real closures) is worthwhile. Held back from the merge as too large to rush at the boundary — give it a focused pass.
2. **Toolbar-area + menus UIX** (Nathan's pending item) — move the views/settings button out of the shared `NSToolbar` (it's why every toolbar button shows the "Icon & Text" toggle), the views-dropdown panel styling (quaternary-fill selection per Figma), menus interaction.
3. **Gallery polish** (Nathan's pending item) — visual + behavioral.
4. **Push `main` to origin** when Nathan's ready (currently local-only).

#### Pending Focuses

- **Deferred `ViewSurface` extraction** (Next Session #1) — confirmed worthwhile, held back from the merge.
- **Cell-edit reload perf** — the table runs a full `reloadData()` per single-cell edit (the reload signature keys on `modifiedAt`). Invisible at tens of rows; revisit with per-row `reloadItem(_:)` only if large vaults feel laggy.
- **Row-pill rendering — PENDING NATHAN'S DIRECTION (do NOT build without explicit confirmation):** darker alternating "pill" fill (the `.inset` system color isn't recolorable → needs a custom `NSTableRowView`; present 3–4 dark-fill options) + keep the pill rounding clipped to the viewport on horizontal scroll (default `.inset` flattens it past the viewport).
- **Physical-drag confirmation** (~10 sec, optional) — column reorder/resize + row order are verified on disk and by composition; one real trackpad drag → leave → return closes the last visual link.

#### Fix Log

**SHIPPED THIS SESSION (merged to `main` `8b9d4a1`):**
- ✅ **Column reorder + resize persist** — captured off `ColumnHeaderView.mouseDown` (NSOutlineView posts no column notifications). Real bug, NOT build-disparity. The dead notification-observer path was removed.
- ✅ **Row order persists across re-entry** — `loadAll` (vault/collection/set) re-reads `page_order` fresh from the canonical sidecar before resolving.
- ✅ **Collections on the native table** — `PageCollectionDetailView` → `ViewOutlineTable`; the 1,358-line hand-rolled stack (`CustomTableView`, `ColumnLayout`, `ColumnDragController`, `TableHeaderRow`, `TableGroupRow`, `TableRowView`, `RowDragGeometry`) + orphaned tests deleted; shared `RowDragCoordinator` + `ViewSelectionModel` kept.
- ✅ **Gallery cross-group drop corruption** (merge-gate BLOCKER) — resolved across ALL groups + guard-on-empty, mirroring the table; stops a wrong row-order write on a reachable gesture.
- ✅ **Banner Change/Remove menu** (+ live the dead `previousBanner` delete); **`showBanner` toggle now gates visibility**; **`_modified_at` ("Last edited") filtering works** (+2 tests).
- ✅ **table↔gallery DRY** — shared `PageIconGlyph` (fixes divergent icon rendering), `VisiblePropertyOrder` resolver, `cellValue` helper, unified `RowDragCoordinator` drag id-source, shared cover sentinel + active-view resolver; plus cleanup/simplify (loadAll fresh-order helper, `updateView` via `mutateViews`, `TableSelectionModel` → `ViewSelectionModel`).

**Carried (pre-existing, unrelated to the Views work):**
- **Inline-edit lag** — property-value inline edit has a noticeable commit buffer.
- **Stale property options** — newly-added Select/Status options aren't selectable until restart; needs a running-build repro to pin the picker path.
- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Agenda doc mismatches** — `AgendaEventManagerError._status` doc-vs-guard; description-cap (specs say 1000, validators enforce none).
- **Pinned-nav title staleness** on rename until re-pinned (likely a future file-watcher fix).
- **NOTE TO FUTURE** — relation properties are replaced by contexts, so future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Views spec-as-fact → `Features/Views.md` · per-entity specs → `Features/*.md`
