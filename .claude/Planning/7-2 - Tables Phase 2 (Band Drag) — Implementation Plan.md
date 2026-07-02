# Tables Phase 2 (Band Drag) Implementation Plan — V2

> **Execution mode: IN-LINE via superpowers:executing-plans — no subagent implementers; the executing agent verifies each task itself.** Steps use checkbox (`- [ ]`) syntax.
> **Status: RATIFIED (07-02) — two adversarial rounds ran.** Round 1: 10 findings, all folded. Round 2 (fold verification): 9/10 folds verified resolved; 1 required edit (the liveView early-return guard, folded into T5) + the redundant convergence-clear removed; the two hardest folds (reparent order math, override survival) held under direct modeling; tokens + fixture sanity checks passed. Spec: `7-1 - Tables Next-Parts … Decision Log.md` §C (+ its 07-02 supersession note) + Nathan's 07-02 rulings (LOCKED → `History.md`, with reversal seams). Phase 3 (chips) is a separate plan.

**Goal:** Group bands (Set bands and property-value bands) drag vertically to reorder per-view, and Set bands reparent across Sets/the Collection root via the filesystem — the sidebar's insertion-line feel, the glyph as the drag surface.

**Architecture:** A pure band model first (band list + slot/cycle/order math over the FULL structural tree), then the pipeline's `group_order` read through `liveView`, then the gesture surface (frozen-snapshot insertion-line drag on the header glyph), then the two commit paths routed by the slot's IMPLIED PARENT (same parent → view-order write · changed parent → `moveSet` reparent with the order-leak guard). Esc-abort ships for ALL drag surfaces (C-5).

**Reconciled Model (Nathan 07-02, code-validated + review-corrected):**
- Band order is manual-only and view-owned (LOCKED): defaults derive (property = defined option order flattened; structural = fs `set_order` seed), the first drag snapshots an owned sequence that never re-derives. `reversed`/`configured` stay decode-only parity.
- **Structural → view-level `group_order: string[]`** (one flat set-id array, every nesting level). The config-level home fails because `decodeGroupConfig` drops structural extras; the top-level zod add exists for **type coercion** — `looseObject` already preserves the raw key untyped, and an uncoerced non-array would crash `orderGroups` (review F5).
- **Property → existing `group.order` + `order_mode: 'manual'`** (Swift-parity; first UI writer).
- **The slot's implied parent routes the commit (review HIGH-1):** a between-bands drop resolves to a parent + position (the sidebar's `setContainerOf` prior art). Implied parent == current parent → pure view reorder. Implied parent ≠ current parent (a drop past a nesting boundary, a middle-zone nest-into, a de-nest to root) → **reparent** (`moveSet`) + the view order carries the visual slot. A flat array alone can NEVER lift a child past its parent — the router is what makes the insertion line honest.
- **Order math runs on the FULL structural id set — never the visible flatten (review HIGH-2):** collapsed subtrees' ids must survive every write; `structuralOrderAfterDrop` merges into the prior `group_order` + the complete tree ids and only MOVES the dragged id. The visible flatten is hit-testing only.
- **Reparent = filesystem, order = view (C-4).** `moveSet` gets the destination's CURRENT fs child order (from `setTree` — fs-ordered by construction) + the moved id APPENDED; the drop slot persists only in `group_order`. (The sidebar's `nextOrder`-from-slot is correct there, wrong here.)
- **No "None" band (Nathan 07-02):** loose rows are non-entities, and property no-value rows get the IDENTICAL treatment — a flattened, header-less tail pinned LAST, exactly like structural loose rows. Code reality: `TableView.tsx` already header-skips every `kind: 'ungrouped'` group, so the GroupHeader "None" glyph branch is DEAD code (removed in T1); the `empty_placement` read in `group.ts` dies (a 'top' value could hoist header-less floating rows — always bottom now; the field stays decode-only parity like `reversed`/`configured`). **`UNGROUPED` is the one non-unique key — it never enters `flattenBands`, `allBandIds`, or any order array** (review LOW-1).
- **Band drag is legal regardless of row-sort count** (the log's flagged open decision, decided 07-02): band order is structural and orthogonal to row ordering — `canReorderWithin` gates ROW reorder only; rows inside a dragged band keep their sort.
- **The id→path map** (log grounded constraint): `ResolvedGroup` carries only `key` — commits resolve Set paths through an id→path map built from `source.sets` the `buildSetNames`/`buildSetIcons` way (Task 5 builds it beside them).
- **The GLYPH is the drag surface (C-6);** the twisty + "+" stop propagation **on pointerdown** (not just click) so they can never arm a pending band gesture; a sub-`ACTIVATION` glyph press-release is a documented no-op (review MEDIUM-2).

## Global Constraints

- **ZERO styling regression** (fixed-track overflow model, full-bleed heading, dividers, sticky group headers — `Features/TableView.md`); Task 7 is a FULL functional CDP pass (Nathan 07-02): screenshots must prove reorder AND reparent work, not just the gesture chrome.
- **PommoraDND measurement discipline (C-2):** frozen snapshot at activation; scroll/tree-swap marks dirty → one lazy re-measure. **The BAND LIST is snapshot state too** — a tree swap mid-drag dirties both geometry and bands.
- **Test honesty (review F3/MEDIUM-1):** jsdom returns zero rects and lacks `setPointerCapture` — ALL slot/cycle/order math is tested at the pure-model level; jsdom gesture tests assert STATE only (mount/mute/clear/commit-callbacks) over explicitly stubbed `getBoundingClientRect` + pointer-capture; geometry truth lands in Task 7's CDP pass. No existing dnd-surface tests exist to extend.
- Every view persist routes `persistView` → `mergeOverrides`; **`group_order` MUST ride in `liveView`** (review F1 — otherwise any sibling persist folds the stale on-disk order back over a fresh drag; the `orderOverride` precedent is the pattern).
- TDD; each task an independent green commit (`npx vitest run` + `npm run typecheck`, exit codes UNMASKED); Biome auto-formats.

## File Structure

**Create:** `Table/bandDndModel.ts` + `.test.ts` · `Table/bandDnd.tsx` · `Table/bandOrder.ts` + `.test.ts`.
**Modify:** `shared/views.ts` (interface + coercing codec) · the pipeline's structural seam (`resolveView.ts`/`group.ts`) · `TableView.tsx` (liveView fold, override state, commits, mount) · `GroupHeader.tsx` (glyph handle) · `Table.css` (line + ghost, tokens only) · `tableDnd.tsx` + `sidebarDnd.tsx` (Esc) · docs at close (`TableView.md`, `Views.md`, `PommoraDND.md`).

---

### Task 1: `group_order` — schema, coercing codec, pipeline read through liveView

**Files:** Modify `shared/views.ts`; Create `Table/bandOrder.ts` + `.test.ts`; Modify the pipeline structural seam + `TableView.tsx`'s `liveView` memo; Modify `pipeline/group.ts` + `GroupHeader.tsx` (the no-"None"-band ruling).
**Interfaces — Produces:** `SavedView.group_order?: string[]` · codec is ELEMENT-FILTERING, never whole-array-catch (review F2): `z.array(z.unknown()).catch([]).transform((a) => a.filter((x): x is string => typeof x === 'string')).optional()` — one bad entry drops alone, the good ids survive (`decodeGroupConfig`'s own `.filter` precedent) · `orderGroups(groups: ResolvedGroup[], groupOrder: string[] | undefined): ResolvedGroup[]` — recursive: reorders `structural-set` siblings at every level (listed-first in array order, unlisted tail keeps fs order), `ungrouped` stays pinned last, non-structural groups untouched · `liveView` carries `group_order` (this task wires the READ; T5's override joins the same memo) · **no-"None"-band (Nathan 07-02):** `property()` always appends the no-value bucket LAST (the `empty_placement` read removed — decode parity only) + GroupHeader's dead `UNGROUPED` glyph branch deleted.

- [ ] **Step 1: Failing tests** — `bandOrder.test.ts`: top-level + nested reorder from one flat array; unlisted tail keeps fs order; ungrouped pinned; property groups untouched; undefined = identity. `views.test.ts` additions: `group_order` round-trips; **`['s1', 42, 's2']` decodes to `['s1','s2']`** (good ids survive a bad entry); a non-array `group_order` decodes to absent/empty (coercion, not crash). `group.test` addition: property grouping with `empty_placement: 'top'` still lands the no-value rows LAST.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** — interface + codec; `orderGroups`; wire at the structural seam reading `liveView.group_order`.
- [ ] **Step 4: Run full suite — PASS**; typecheck (unmasked).
- [ ] **Step 5: Commit** `feat(table): per-view group_order + always-bottom flattened no-value tail — coercing codec, every-level structural band order`.

### Task 2: The pure band model — full-tree math, parent-from-slot

**Files:** Create `Table/bandDndModel.ts` + `.test.ts`.
**Interfaces — Produces:**
`Band = { id: string; kind: 'set' | 'property'; depth: number; parentId: string | null; path?: string }`
· `flattenBands(groups, collapsed: Set<string>): Band[]` — VISIBLE band headers for hit-testing: takes the LIVE `collapsed` set (review F4 — `ResolvedGroup.isCollapsed` is a stale snapshot; the render reads live state), excludes collapsed subtrees' children, excludes `ungrouped`/None, structural + property kinds.
· `allStructuralIds(groups): string[]` — the FULL tree id set INCLUDING collapsed subtrees (review HIGH-2), fs/tree order; never contains `UNGROUPED`.
· `bandSlot(bands, measured: MeasuredRow[], y): { beforeId: string | null; impliedParentId: string | null; nestInto: string | null; lineY: number }` — between-slots resolve their IMPLIED PARENT from the neighboring bands' depths/parents (the `setContainerOf` idea); a set band's middle zone = `nestInto`.
· `canNest(draggedId, targetId, bands): boolean` — self/descendant guard (reuse `isSelfOrDescendant`'s logic shape).
· `structuralOrderAfterDrop(priorOrder: string[], fullTreeIds: string[], draggedId, beforeId): string[]` — merge-then-move: seed = priorOrder's ids (kept) + fullTreeIds not yet listed (appended in tree order); then MOVE draggedId before beforeId. Collapsed-sibling ids always survive (review HIGH-2's executed failure is the regression test).
· `propertyOrderAfterDrop(presentKeys, draggedKey, beforeKey): string[]`.
· `reparentFsOrder(destChildIds, movedId): string[]` — APPEND (C-4 guard, tested as such).

- [ ] **Step 1: Failing tests** — table-driven over a 2-level tree (A[A1,A2], B[B1]): flatten respects live collapse + excludes UNGROUPED; **HIGH-1 regression: a between-slot above A from A1's drag resolves impliedParentId = root (≠ A) — a parent change, not a reorder**; **HIGH-2 regression: dragging B above A while A is collapsed keeps A1/A2 in the output order** (`structuralOrderAfterDrop(['A','A2','A1','B'], fullIds, 'B', 'A')` preserves A2/A1); cycle guard blocks self + descendants; `reparentFsOrder` appends regardless of slot; property order-after-drop.
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): band-drag pure model — full-tree order math, parent-from-slot routing, cycle guard`.

### Task 3: Esc-abort for every drag surface (C-5)

**Files:** Modify `Table/tableDnd.tsx`, `Sidebar/sidebarDnd.tsx` — a window `keydown` Escape listener bound at drag activation → the existing cancel path (both currently handle only `pointercancel`; no dnd-surface tests exist — VERIFIED).
**Test scope (honest):** state-level only — new minimal jsdom tests that stub `getBoundingClientRect` (non-zero per-row rects) + `setPointerCapture`/`releasePointerCapture`, activate a drag, dispatch Escape, assert the drag state cleared and NO commit fired; Escape while idle = no-op, and the listener is detached after settle (no leak).

- [ ] **Step 1: Failing tests** (with the stub harness — this task BUILDS the shared stub helpers the later gesture tests reuse).
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement** (listeners join the existing add/remove sets in both surfaces).
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(dnd): Esc aborts an active drag on every surface`.

### Task 4: The band gesture surface

**Files:** Create `Table/bandDnd.tsx`; Modify `GroupHeader.tsx`, `TableView.tsx` (mount), `Table.css` (line + ghost — reuse `--drag-line` / `--state-ghost`; verify both tokens exist before use).
**Interfaces — Consumes:** Task 2 model, `ACTIVATION`, the snapshot discipline. **Produces:** press on the GLYPH → pending; past `ACTIVATION` → active: snapshot band-header rects + the band list ONCE (scroll/tree-swap dirties BOTH → one lazy re-measure); pointermove → `bandSlot` against the frozen snapshot → insertion line + portaled glyph ghost + source mute; middle-zone over a nestable set → nest highlight; Esc/`pointercancel` abort; release → `{ kind: 'reorder', beforeId } | { kind: 'reparent', targetParentId, beforeId }` **routed by impliedParent vs current parent** (HIGH-1) — the callback receives the classification, TableView never re-derives it. Twisty + "+" `stopPropagation` on POINTERDOWN; sub-`ACTIVATION` glyph release = no-op (documented).

- [ ] **Step 1: Failing tests** — jsdom STATE-ONLY over the Task 3 stub harness + a nested-set source in the gestures fixture: activation mounts the line element + mutes the source band; Escape clears everything, no commit; sub-threshold press then twisty click still toggles (pointerdown isolation); the commit callback receives `reparent` when the stubbed slot implies a parent change and `reorder` when not. (Line POSITION/geometry = Task 7 CDP, not asserted here.)
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): band drag gesture — glyph surface, insertion line, frozen snapshot`.

### Task 5: The commit paths — liveView fold + override survival

**Files:** Modify `TableView.tsx`.
**Interfaces — Consumes:** Tasks 1/2/4. **Produces:**
· `groupOrderOverride` state: **joins the `liveView` memo in THREE places (round-2 required edit): the early-return GUARD (`if (!orderOverride && !hiddenOverride && !groupOrderOverride) return view`), the merge branch (`group_order: groupOrderOverride ?? view.group_order`), and the dependency array.** A band-only drag is the COMMON case — with only the merge branch edited, the early return hands back the raw view, the band snaps back on render, and the next sibling persist writes the stale order to disk (the exact F1 clobber). The T5 regression test fails against a merge-branch-only implementation by design.
· **Reset discipline (review HIGH-3, round-2 verified):** `groupOrderOverride` resets on `[view.id]` ONLY — deliberately NOT in the `[source]` effect (the `moveSet`-triggered `load()` swaps `source` identity mid-flight; `key={source.id}` already remounts on real container switches, so no cross-container leak). First-save `view_default → view_<ulid>` reset is safe — the round-tripped view carries the saved order. No convergence-clear mechanism (the `orderOverride` precedent has none and survives fine).
· Structural reorder → override + `persistView({ group_order: structuralOrderAfterDrop(liveView.group_order ?? [], allStructuralIds(groups), …) })`.
· Property reorder → `persistView({ group: { ...view.group, order_mode: 'manual', order: propertyOrderAfterDrop(…) } })`.
· Reparent → `mutate({ op: 'moveSet', path, newParentPath, order: reparentFsOrder(destFsChildIds, movedId) })` (dest ids from `setTree` — fs order) **plus** the `group_order` write placing the id at the drop slot. Check `moveSet`'s name-collision behavior on reparent during implementation (flagged unread by review) — surface, don't guess.

- [ ] **Step 1: Failing tests** — jsdom (stub harness): reorder drop → `views.save` carries the full merged `group_order` (collapsed ids INCLUDED) and NO mutate; a collapse toggle right after a drag persists WITH the fresh band order (the F1 clobber regression); property drop → `group.order` + `order_mode: 'manual'`; reparent drop → `moveSet` with APPENDED fs order + a `group_order` carrying the slot; override survives a source-identity swap (HIGH-3 regression). (Loose/no-value rows have no band header at all post-T1 — nothing to arm; T2's `flattenBands` exclusion tests cover them at the model level.)
- [ ] **Step 2: Run — FAIL.**
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run full suite — PASS**; typecheck.
- [ ] **Step 5: Commit** `feat(table): band drop commits — liveView-folded group_order + order-leak-guarded reparent`.

### Task 6: Full gate + docs

- [ ] **Step 1:** `npx vitest run` + `npm run typecheck` — green, exit codes unmasked.
- [ ] **Step 2:** Docs: `Features/TableView.md` (band drag), `Features/Views.md` (`group_order`), `Features/PommoraDND.md` (the band surface + the band-list-is-snapshot-state extension of the measurement discipline). Bundle in the commit.
- [ ] **Step 3: Commit** `feat(table): Phase 2 docs reconciliation`.

### Task 7: CDP visual pass — FULL functional verification (Nathan, 07-02)

- [ ] **Step 1 — gesture chrome:** arm a Set-glyph drag, move (line + ghost + mute) — screenshot mid-drag; **Esc-abort** — screenshot the clean restore.
- [ ] **Step 2 — REORDER drop (view-write only):** drop a band into a new slot — before/after screenshots proving the order renders AND survives; verify the sidecar gained `group_order` and the sidebar did NOT change (fs-independence proof).
- [ ] **Step 3 — REPARENT round-trip:** nest one small Set into another (screenshot), move it back (screenshot); verify the folder moved on disk both times and the view order held the slots. **Disclosed caveat:** the return trip re-appends to the original parent's fs `set_order` tail — sidebar position may shift.
- [ ] **Step 4:** Styling-regression list (heading, dividers, sticky headers) against `TableView.md`; all screenshots to Nathan — the final verifier.

---

## Self-Review (V2)

**Round-1 findings folded:** F1 (liveView fold — T5 first bullet + global constraint) · F2 (element-filtering codec + survive-test — T1) · F3/MEDIUM-1 (test honesty re-scope + stub harness built in T3, reused T4/T5) · F4 (live `collapsed` into `flattenBands` — T2) · F5 (coercion justification restated — Reconciled Model) · HIGH-1 (parent-from-slot routing — model, T2 regression test, T4 commit classification) · HIGH-2 (full-tree ids + merge-then-move — T2 with the executed failure as a regression test) · HIGH-3 (override reset on `[view.id]` only + convergence — T5) · MEDIUM-2 (pointerdown isolation matrix — T4 test) · LOW-1 (UNGROUPED exclusion — T2).
**Spec coverage:** C-1 (T2/T4/T5) · C-2 (T4 snapshot, band list included) · C-3 (T1 + T5; view-level home per the locked History entry) · C-4 (T2 `reparentFsOrder` + T5, tested as append) · C-5 (T3 all surfaces; loose/None non-draggable) · C-6 (T4 glyph + pointerdown isolation).
**Deviations standing (disclosed):** nest-into = middle zone on a set band (no sidebar precedent for into-band; flagged for Nathan's Task 7 eyes) · reparent stays IN Phase 2 (the logic reviewer suggested deferring it; Nathan's ask makes it the headline — the three concentrated findings are individually folded instead).
