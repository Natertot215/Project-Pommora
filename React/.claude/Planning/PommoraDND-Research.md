# PommoraDND — Research & Build Plan (V2)

Status: **V2 — review-certified; Phases 0–2 + 4 + 5 + 6 built, each adversarially reviewed + fixed.** Seam unify · single-zone engine · cross-list board · constraints (axis/bounds/modifiers/swap/async-reject) · auto-scroll · keyboard + ARIA — all in the Interaction Lab; typecheck + 298 tests green (12 new pure-fn tests). `@dnd-kit` is import-free across the codebase. **Phase 3 (tree cross-level reparenting)** deferred as a decision — within-level works; reparenting is pure drop-feel needing visual iteration (flatten+project+rebuild approach in `Features/DragAndDrop.md`). **Phase 7 (prune the `@dnd-kit` dep)** gated on proven parity — deps kept until Nathan visually verifies. **Live drag-feel visual verification pending across all phases** (the agent can't drive the GUI). Durable spec → `Features/DragAndDrop.md`.

A from-scratch drag-and-drop engine replacing `@dnd-kit/*`, behind a unified thin seam (`SortableZone` / `useDragItem`, later `useArea`). Scope is **full dnd-kit feature parity** — keyboard drag, screen-reader support, auto-scroll, the lot — trimmed later if unused, never up front. dnd-kit stays installed until PommoraDND reaches parity in the Interaction Lab, then it's removed.

Grounded in a line-by-line dissection of dnd-kit's readable dev source across all four packages, and revised against two adversarial reviews (technical grounding + logic/coverage).

> **Scope note:** this is a **design-system / Interaction-Lab effort**. The real app (sidebar tree, main list) adopts PommoraDND as a **separate, later integration** — "Lab green" does not mean "the app uses it." Surfaces in `interactions/` are demo-only today.

## The Size Reality

Real runtime surface is **~5,220 lines** (the ~10,400 earlier counted every dist variant + sourcemaps): core 3,991 / sortable 801 / utilities 361 / accessibility 70. Roughly **94% is generality we don't carry** — framework-agnostic core, three input sensors, four collision strategies, a composable modifier pipeline, SSR guards, continuous re-measuring.

**PommoraDND full-parity estimate: ~1,400–1,700 lines.** Per-phase budget below — estimates, not gates. Phase 1 carries the bulk of the engine and is the phase most likely to overrun; if it does, that's a signal to re-assess, not to compress.

## The Drop Model — Decide, Then Animate (corrected in V2)

This is the load-bearing design decision, and the one most easily gotten wrong.

**The win we keep:** the items array is **never mutated during the drag**. Items shift to open a gap via transforms only; the reorder is decided and applied at drop. This is what lets us drop dnd-kit's FLIP layer (`useDerivedTransform`), its mid-drag `measureDroppableContainers` churn, and the `disableTransforms` flag system.

**The bug we fix:** a naive "animate the item into the gap, *then* commit" optimistically slides the item home — so a **rejected** drop (validation, a disallowed cross-list move, an async veto) would settle the item and then snap it back. Ugly.

**The correct order (matches dnd-kit's actual ordering):**

1. During drag — transforms show the open gap. Array untouched.
2. On pointer-up — **run the accept/reject decision first.**
3. **Then** play **one** drop animation to the item's **true** resting rect:
   - **Accept** → animate the transform into the gap, then commit the new order (items re-render in new positions with zero transform → seamless).
   - **Reject** → animate the transform back to origin; the gap closes; **no commit.**

In the **single-zone** case both target rects (origin and gap slot) are already known from the drag-start measurement, so this needs no FLIP re-measure — just a target chosen by the decision. In the **cross-list** case the destination zone's slot rect is *not* in the origin zone's drag-start snapshot, so the controller measures the destination zone's rects on first cross-zone `over` (frozen per zone, not continuously) — this is the one place the frozen-snapshot model re-measures, and it's bounded to zone-entry. (Phase 2.)

**Async rejection** (a drop that must ask a server/validator): mirror dnd-kit's `cancelDrop` — hold the item **lifted in a pending state** until the decision resolves, then animate to the truthful target. Detail deferred to Phase 4; the engine reserves a `pending` drop state from Phase 1 so it isn't retrofitted.

## What Shrinks, and Why

Each lever is grounded in the dissection; corrections from review are folded in.

1. **One sensor, not three.** `MouseSensor` + `TouchSensor` are cross-browser shims over `AbstractPointerSensor`; Chromium's Pointer Events API unifies mouse/touch/pen (`pointerType` discriminates). A single `PointerSensor` (~100 lines) covers all three. **Enhancement:** `element.setPointerCapture(pointerId)` instead of `ownerDocument` listeners — dnd-kit explicitly *rejected* pointer capture (its code comment cites unmounted-target events), but its concern (pointer leaving the window / cross-origin iframes) is a **non-issue in Electron**, so capture is the cleaner choice for us. Keep the sensor's `setup()` seam for the mobile non-passive-`touchmove` hedge.

2. **A ref controller, not a reducer + per-move dispatch.** dnd-kit's reducer has 8 actions but `DragOver` is never dispatched (`over` is separate `useState` — confirmed). Drag-origin + active-id live in a ref; only re-render-driving values (`translate`, `over`, zone set, `dropState`) use `useState`. React 19 auto-batches → drop every `unstable_batchedUpdates`. Measure the active node synchronously at drag start → collapse the two-step init status to `active: boolean` (valid only because measurement is synchronous).

3. **No FLIP, no mid-drag array churn** — see the Drop Model above. (Precise framing: dnd-kit's FLIP handles mid-drag commits *and* external mid-drag array mutations *and* post-drop settling; our frozen-snapshot + decide-then-animate design removes all three triggers.)

4. **Two collision functions, not four.** Keep `closestCenter` (with a cheaper 1-D axis-projection variant for lists/tables) and `pointerWithin` (as a filter, for tree/board). **Replace `closestCorners`** — don't drop it: its only caller is the sortable keyboard coordinate getter, which Phase 6 needs as a directional-proximity function. **Drop `rectIntersection`** (Jaccard; no surface needs overlap-area scoring, and it returns empty mid-gap). **Correction:** `closestCenter` *can* return empty (zero droppables / none measured yet) — the engine handles a `null` first-collision everywhere, never assumes a hit. **Enhancement:** **hysteresis** on `over` (only switch if the new best beats current by 4–8px) to kill slot-boundary flicker — lands in **Phase 1** (it affects the very first list), not later; tie-break by **DOM order**, not float precision.

5. **One strategy-agnostic shift engine — via rects-reflow.** **Correction:** the naive neighbor-shift (`rects[to] - rects[index]`) is wrong for a **wrapping** grid (items reflowing across rows). Use dnd-kit's correct general formula — `arrayMove(rects, activeIndex, overIndex)[index]` minus the original rect — as **one function** (no strategy registry). This uniformly covers vertical lists, horizontal lists, fixed grids, **and** wrapping grids. `rectSwapping` stays a 4-line `swap?: boolean` fork.

6. **Inline modifiers, not a pipeline.** `axisLock: 'x' | 'y' | null` + `bounds: 'window' | 'parent' | null` resolved in one `computeTransform()`, plus a `modifiers?: Modifier[]` escape hatch for cross-list adjustments. `snapCenterToCursor` stays a standalone helper.

7. **rAF auto-scroll, not `setInterval`.** Frame-synced loop (dnd-kit's 5ms `setInterval` double-steps); nearest scroll container only; scroll-delta rect correction is mandatory. Defer multi-ancestor chains, sticky scroll-intent, layout-shift compensation — don't design them out.

8. **CSS-transition drop animation, not the WAAPI `AnimationManager`.** A `transition: transform` + `transitionend` cleanup replaces the ~130-line ghost-child + Web-Animations machinery, cancellable via class removal. **Enhancement:** `.toFixed(1)` transforms (Retina sharpness) instead of `Math.round`; `AbortController` to cancel a stale drop animation when a new drag starts.

## Architecture — Three Layers

Mirrors Pommora's design-token + component-registry pattern.

- **Aliases** — named tunable vocabulary: feel (duration/easing — shipped as `feel.tsx`), activation (distance/delay/tolerance), layout (`list`/`grid`/`table` — replaces dnd-kit's strategy objects), axis, collision mode, bounds, conditions (disabled, handle-only).
- **Behaviors** — hoisted verbs, one implementation each: `sortable`, `crossList`, `resizable`, `collapsible`, `selectable`.
- **Areas** — per-region composition referencing aliases + behaviors by name. **Deferred** until ~4 real consumers; until then composition is explicit props on `SortableZone`. Phase 7 formalizes the registry **only if** the consumer count justifies it — otherwise it stays deferred.

**The seam — one canonical signature, fixed in Phase 0.** Surfaces only ever import `SortableZone` / `useDragItem` (later `useArea`):

```
SortableZone({ id, items, layout?, collision?, feel?, swap?, group?, onReorder, children })
useDragItem(id) -> { setNodeRef, style, handle, isDragging }
```

- `layout` is the named alias (`'list' | 'grid' | 'table'`) — **not** a dnd-kit strategy object.
- `onReorder(activeId, overId)` is the single commit callback (replaces the sketch's `onReorder` and `drag.tsx`'s `onDragEnd` — one name, picked here).
- `group` opts a zone into cross-list (Phase 2); single zones omit it.
- A **single top-level controller** (`DndRoot` provider) owns the one active drag; zones and items register into it. There is never more than one active drag (only one pointer is down at a time). On `pointerdown` the controller resolves the **owning zone by DOM containment** (innermost registered zone containing the target) — not by `stopPropagation` between nested contexts, since there's one root listener, not nested ones. Pointer capture then routes all subsequent events to the captured element regardless of nesting.
- **Zones without a `group` confine their drag to themselves** — they never accept a foreign item. `group` is the explicit opt-in that lets sibling zones hand off (Phase 2). So unrelated zones mounted on the same page (sidebar tree + main list) share the controller without sharing drags.

## Resolved Decisions (were Open Questions in V1)

- **Q1 — nested re-entrancy:** one top-level `DndRoot` controller, single active drag; the controller resolves the owning zone by **DOM containment** (innermost wins), and the **activation-distance gate preserves the Tree row's click-to-toggle** (a click that never exceeds the distance threshold stays a toggle, never a drag — the sketch's `!isDragging` guard pattern). No per-sensor `dndKit` stamp needed. (Forces Phase 3; baked into the Phase-1 controller.)
- **Q5 — overlay vs in-place:** **in-place transform** for non-clipped surfaces (list/grid/table, Phase 1); **portal overlay** for tree + board (clipping + cross-container, Phases 2–3). Do **not** assume future virtualization forces overlay everywhere — revisit per surface if the real main list is virtualized.
- **Q6 — area-manifest timing:** **deferred** (explicit props until ~4 consumers).

## Still-Open (resolve during the named phase, not before)

- Keyboard interaction model — Space/Enter lift, arrows move, Esc cancel; whether Tab-to-drop stays. (Phase 6)
- Announcement copy — per-surface factory (`itemLabel` + "position N of M"). (Phase 6)
- Auto-scroll curve — linear vs ease-in²; acceleration + threshold defaults. (Phase 5)
- Async `cancelDrop` UX — exact pending-state visuals. (Phase 4)

## Mobile-Readiness Invariants

Desktop-first, but keep a future touch UX viable: `touch-action: none` on every draggable (dnd-kit's gap — not just the overlay); delay+tolerance activation alongside distance; the `setup()` non-passive-`touchmove` hedge; clean `pointercancel` end; keyboard sensor stays separable; collision keeps `pointerCoordinates: Coordinates | null` and never bakes hit-target sizes into the math (inflate the rect at registration); rAF auto-scroll.

## Lab Harness Work (prerequisites, not afterthoughts)

The Interaction Lab is the verifier — but today it has **no scroll containers and nothing focusable**. So these are explicit build items:

- **Before Phase 5:** add a constrained-height (`max-height` + `overflow:auto`) scrolling list/sidebar section to the Lab. Auto-scroll has nothing to verify against otherwise.
- **Before Phase 6:** give surfaces `tabIndex`/`role`/focus styling. Keyboard drag can't be verified on non-focusable rows.

## Build Phases

Each ships as a green commit, verified live in the Lab (`npm run showcase` → `interactions.html`) with the engine swapped under the seam. "Done" = the demo behaves identically to (or better than) the dnd-kit version for that surface.

| Phase | Scope | ~LOC | Verify against |
|---|---|---|---|
| **0 · Unify the seam** | Define the canonical `SortableZone`/`useDragItem` signature above. Migrate List/Grid/Table/Tree off `strategy=`/`onDragEnd=` onto it, and port **Board** off raw `DndContext`/`useDroppable` onto the (group-aware) seam — **all while still dnd-kit-backed**, so the later cutover is a pure internal swap. Add the engine's **outbound event bus** (onDragStart/Move/Over/End/Cancel) to the seam now. | ~120 | All surfaces (no behavior change) |
| **1 · Core engine** | `DndRoot` controller + zone-keyed store (registry even for one zone); single `PointerSensor` (capture, activation distance/delay/tolerance seams, `touch-action:none`, `pointercancel`); measure-once; `closestCenter` (+1-D) with null-handling + **hysteresis**; rects-reflow shift engine (list/grid/table, incl. wrapping grid); **decide-then-animate** CSS-transition drop with a reserved `pending` state; conditions (handle-only, disabled); static ARIA attrs on `useDragItem`; event bus emitting. | ~420 | List, Grid, Table |
| **2 · Cross-list + overlay** | Multi-zone handoff via the shared controller (`group`); **measure the destination zone's rects on first cross-zone `over`** (frozen per zone); portal `DragOverlay` + nullified-context isolation; `snapCenterToCursor`. Board collision = `pointerWithin` to pick the column, then `closestCenter` within it (covers empty-column + end-of-list drop — the role `closestCorners` played in the dnd-kit Board). | ~280 | Board |
| **3 · Tree / nested** | Nested zones under the controller; `pointerWithin` filter + `closestCenter` fallback; nested re-entrancy via `stopPropagation`; overlay (clipping + cross-level). | ~150 | Tree |
| **4 · Constraints / modifiers / async** | Inline `axisLock` + `bounds` + `modifiers?` escape hatch; `rectSwapping` as `swap?`; **async `cancelDrop`** (hold-lifted pending); DOM-order tie-break. | ~150 | All surfaces |
| **5 · Auto-scroll** | rAF loop, nearest container, scroll-delta rect correction. *(Prereq: scrolling Lab surface.)* | ~180 | Scrolling list / sidebar |
| **6 · Keyboard + ARIA** | `KeyboardSensor`; per-surface directional coordinate getters (the `closestCorners` replacement); assertive live region; unified visually-hidden instructions; `RestoreFocus`; position-in-list announcements. ARIA attrs already emitted since P1; the bus already exists. *(Prereq: focusable Lab surfaces.)* | ~300 | All surfaces, keyboard-only |
| **7 · Cutover (+ areas if justified)** | Remove `@dnd-kit/*`; delete the dnd-kit-backed `drag.tsx`. Formalize the alias config + behavior registry **only if** ≥4 real consumers exist; otherwise leave areas deferred. | ~120 | Full demo + app |

## Parity Checklist (kept / simplified / dropped)

**Keep (simplify where noted):** central drag store → ref + minimal `useState`; `over` as separate state; internal/public context split; per-item active-transform isolation; activation distance + delay + tolerance + bypass; `hasExceededDistance` (Euclidean + axial + x/y-only); `pointercancel`/`resize`/`visibilitychange`/Esc cancel; post-drag click + text-selection suppression; `closestCenter` (+1-D) + `pointerWithin` filter; rects-reflow shift engine; `arrayMove`; `rectSwapping` as `swap?`; decide-then-animate drop; portal overlay + nullified context + remount key (tree/board); `snapCenterToCursor`; inline `axisLock`/`bounds` + modifier escape hatch; scroll-delta rect correction; nearest-container auto-scroll; full keyboard drag + per-surface coordinate getters; assertive live region + hidden instructions + ARIA attrs + `RestoreFocus`; event-bus pattern; `useCachedNode` stale-node fallback; `Rect` scroll-aware concept → explicit `adjustRect(rect, delta)`; async `cancelDrop`.

**Add (enhancements over dnd-kit):** pointer capture; hysteresis + DOM-order tie-break; rAF auto-scroll + ease-in curve; microtask-flushed measuring; `.toFixed(1)` transforms; `AbortController` drop cancellation; `touch-action:none` on draggables; position-in-list announcements.

**Drop:** `MouseSensor`/`TouchSensor` classes; `rectIntersection`; strategy registry, FLIP (`useDerivedTransform`), mid-drag re-measure, `disableTransforms`; WAAPI `AnimationManager`; composable modifier pipeline; all SSR guards / `useIsomorphicLayoutEffect` / `canUseDOM` / `unstable_batchedUpdates`; `JSON.stringify` dep-array hacks; two-step init status; per-sensor `dndKit` stamp. **Replace (not drop):** `closestCorners` → directional-proximity getter (Phase 6). **Defer (don't delete):** multi-ancestor scroll, scroll-intent, layout-shift compensation, `scrollIntoViewIfNeeded`.

## Known Minor Issues (carry into the feature doc)

- **Drop micro-jerk under aggressive dragging.** After throwing an item up/down hard and dropping mid-motion, one or two gap items can show a sub-perceptible snap at the commit. Root cause is in-flight transition timing + sub-pixel (`.toFixed(1)`) rounding between the transform end-position and the natural post-reorder slot. Mitigated (commit waits on the lifted item's `transitionend`, not a blind timer); residual deemed inconsequential and accepted. One-liner for the feature doc, not a fix target.

## Disposition of the Phase-1 Sketch

`src/renderer/src/design-system/dnd/sortable.tsx` (188 lines) predates this research. Its core ideas — measure-once, closest-center, no mid-drag churn — are **validated**, but it has the **wrong drop ordering** (animate-then-commit) and a **single-zone store** that Phase 1 explicitly supersedes (zone-keyed controller). Treat it as a reference for the target shape; Phase 1 rebuilds against this plan rather than extending it. Delete the sketch at Phase 1 start.

## Manual Inspection & Approval Gate (Nathan)

The engine was built and reviewed without live visual verification (the agent can't drive the GUI). It is **not approved** until this gate is passed by manual inspection in the Lab (`npm run showcase` → `interactions.html`). Faithful surfaces should behave like dnd-kit; anything that doesn't is a **bug**, not a preference. Check each; note failures inline.

**Per-surface drag feel**
- [ ] **List** — drag a row up/down; neighbours open the gap smoothly; drop settles with no lurch (beyond the accepted micro-jerk).
- [ ] **Grid** — drag a cell; the 2-D reflow looks right; wrapping across rows lands correctly; drop is clean.
- [ ] **Table** — drag a row; columns stay aligned; no border doubling that reads as a glitch.
- [ ] **Tree** — drag within a level; the click-to-expand caret still toggles (drag vs click not confused); nested levels reorder.
- [ ] **Board** — drag a card within a column AND across columns; the lifted card rides the cursor (portal overlay), the gap preview shows the landing slot, the card commits once on drop (no duplicate, no live mid-drag jump).

**Drop + collision**
- [ ] Drop always settles the item exactly into its slot (the reorder is correct).
- [ ] No slot-boundary flicker when hovering between two items (hysteresis).
- [ ] Aggressive drag-then-drop: confirm the residual micro-jerk is still inconsequential (the one accepted issue).

**Constraints surface** (toggle each)
- [ ] **Swap** — items exchange (active↔over) instead of shifting; commit matches the preview.
- [ ] **Axis Y** — the lifted item can't wander horizontally.
- [ ] **Bounds** — the lifted item is clamped to the list extent.
- [ ] **Async-reject slot 0** — dropping into the first slot holds the item lifted (~300ms) then springs it home; other slots accept.

**Scrolling list**
- [ ] Drag a row toward the top/bottom edge → the container auto-scrolls (ease-in, faster nearer the edge).
- [ ] Scrolling stops at the list's top/bottom limit (no jitter pinned against a maxed edge).
- [ ] Collision stays accurate while auto-scrolling (the over-slot tracks newly-revealed rows); the lifted item stays under the cursor.

**Keyboard** (Tab to an item, then operate by keyboard — try List / Grid / Table / Tree)
- [ ] **Space/Enter** lifts (item parks on its slot, focus ring visible).
- [ ] **Arrow keys** move it slot-to-slot (Grid: up/down/left/right step to the adjacent cell).
- [ ] **Space/Enter/Tab** drops; **Esc** cancels (returns to origin).
- [ ] Focus returns to the item after drop/cancel.

**Screen reader** (VoiceOver ⌘F5, optional but recommended)
- [ ] On focus, the instructions are read ("press space to pick up…").
- [ ] Pick-up / move / drop / cancel are announced with position ("item 3 of 8").

**Sign-off**
- [ ] **APPROVED** — all of the above pass. → then prune the `@dnd-kit` dependency (Phase 7) and the engine is parity-proven.
- Failures / notes: _______________________________________________
