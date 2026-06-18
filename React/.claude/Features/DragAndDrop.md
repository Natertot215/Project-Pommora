## Drag and Drop — PommoraDND

Pommora's drag-and-drop is an **in-house engine, PommoraDND**, built to replace `@dnd-kit/*`. It owns the interaction layer the way `MarkdownPM` owns the editor layer — leaning on the external library first to learn the problem, then rebuilding a leaner equivalent scoped to our reality (Chromium-only via Electron, React-only, a known set of surfaces). It lives behind a **thin seam** so the engine is swappable without touching callers. The build plan, phase ladder, and the dnd-kit dissection that grounds it live at `Planning/PommoraDND-Research.md`; this doc is the durable spec of the system.

### The seam

Surfaces import **only** from `design-system/interactions/drag.tsx` — never `@dnd-kit` directly. That single boundary is what lets the engine be replaced internally:

- **`SortableZone`** — one sortable list. Standalone by default (list, grid, table, each tree level); pass `group` to make it a member of a `DragGroup` (cross-list).
- **`DragGroup`** — a set of zones that hand items between each other (the board), with a portal overlay.
- **`useDragItem(id)`** — wires a standalone item; spread the returned `handle` on the drag surface, `setNodeRef` on the element, `style` for the transform.
- **`useGroupedDragItem(id)`** — wires a `DragGroup` member item.
- **`reorder(items, activeId, overId)`** — the array commit helper a zone's `onReorder` applies.

`layout` (`'list' | 'grid' | 'table'`) is informational only — the engine is geometry-driven, so one displacement model serves all three.

### Core principles

The engine's behaviour is defined by a few load-bearing decisions, each chosen against how dnd-kit does it:

- **One pointer sensor.** A single Pointer-Events sensor with `setPointerCapture` handles mouse, trackpad, pen, and touch. There is no mouse/touch sensor split and no document-level listener fallback — capture routes move/up/cancel to the dragged element regardless of where the pointer goes.
- **Measure once, no array churn.** Item rects are measured at drag start (per zone, on first entry for cross-list) and frozen for the drag. The items array is never mutated mid-drag; collision runs against the frozen snapshot. The reorder commits exactly once, on drop.
- **Closest-centre collision with hysteresis.** The over-slot is the nearest item centre to the projected drag point; switching slots must clear a small pixel threshold, so a slot boundary doesn't flicker between two positions.
- **One strategy-agnostic shift.** Displacement is a rects-reflow: each non-dragged item moves to the slot it will occupy after the reorder. The same math covers vertical lists, horizontal rows, and 2-D wrapping grids — there is no per-layout strategy registry.
- **Decide, then animate.** On drop the accept/reject decision is made *first*, then a single animation moves the item to its true resting slot (the gap if accepted, its origin if rejected). The commit fires when that animation actually ends (`transitionend`, with a fallback timer), not on a blind timer — so items never settle and then snap. A rejected drop cannot animate into the gap and bounce back.

### Single-zone vs. cross-list

Two engines sit behind the seam, sharing types and the measure-once / decide-then-animate model:

- **Single-zone** (`engine.tsx`) — list, grid, table, and each tree level. The dragged item moves **in place** (transform follows the pointer); neighbours shift to open the gap. Used where the surface isn't clipped.
- **Cross-list** (`group.tsx`) — the board. A `DragGroup` owns the one active drag across its zones. The lifted card is hidden in its source column and rendered as a `position: fixed` **portal overlay** under the cursor (escaping any column clipping); every column shifts its items by one slot-pitch to show where the card would land. The move commits once via `onCommit(activeId, toZone, toIndex)`. Because columns are never mutated mid-drag, there is no duplicate-card race to guard against — the class of bug dnd-kit's live cross-container moves required defending against simply doesn't exist here.

### Verification harness

The **Interaction Lab** (`design-system/interactions/`, served via `npm run showcase` → `interactions.html`) exercises every surface — list, grid, table, recursive tree, cross-list board — with a live "feel" control (duration + easing) shared across all of them. It is the design-system verification surface, **separate from the app**: a green lab does not mean the app consumes the engine. Real-app adoption (sidebar tree, main list) is a later, deliberate integration.

### Relationship to dnd-kit

`@dnd-kit/*` remains installed while PommoraDND reaches feature parity in the Lab; it is removed at cutover. The engine is **not** a 1:1 reimplementation — it deliberately drops generality we don't need (the framework-agnostic core, three input sensors, four collision strategies, the modifier pipeline, SSR guards, continuous re-measuring) and adds improvements dnd-kit lacks (pointer capture, hysteresis, no mid-drag array churn, a frame-accurate commit). The full kept/simplified/dropped ledger is in `Planning/PommoraDND-Research.md`.

### Constraints, auto-scroll, accessibility (built)

Each is an inline option or an automatic behavior, exercised in the Lab:

- **Constraints & modifiers** — `axis` lock, `bounds` clamp (window / list-extent), a `modifiers` escape hatch (folded left-to-right like dnd-kit's `applyModifiers`), `swap` mode (exchange active+over, commit with `arraySwap`), and **async drop rejection** (`canReorder` may return a `Promise`; the item holds lifted in the `pending` state until the verdict resolves). The Constraints Lab surface toggles each.
- **Auto-scroll** (`autoscroll.ts`) — an rAF loop scrolls the nearest scrollable ancestor when the pointer nears an edge, with an ease-in ramp (dnd-kit uses a non-frame-synced `setInterval` + linear) and limit-awareness (no churn at a maxed edge). The container's scroll delta is compensated into the lifted item + collision so the drag stays accurate as content scrolls; non-active items don't double-compensate (their shift is a frozen-rect difference). Scope simplification: nearest ancestor only, not the page/window.
- **Keyboard + screen-reader** (`keyboard.ts`, `a11y.ts`) — Space/Enter lifts, arrow keys move (a geometric next-slot getter that covers list/row/grid), Space/Enter/Tab drops, Esc cancels; an assertive ARIA live region announces pick-up/move/drop/cancel with position ("item 3 of 8"), a hidden instructions element is wired via `aria-describedby`, and focus is restored to the item on drop. Items are focusable (`tabIndex`); the handle role is `button` by default, settable to `null` so table rows keep `<tr>` semantics.

### Deferred (don't design out)

- **Tree cross-level moves** — within-level reorder works today (each tree level is a standalone zone on the engine). Reparenting / indent-outdent across levels is **deferred**: it's pure drop-feel/semantics (indent threshold, drop indicator) that needs visual iteration, so it isn't built blind. Recommended approach when ready: flatten the tree to `{id, depth, parentId}` rows, reorder the flat list through the engine, project the new depth from the drop index + horizontal offset, and rebuild — dnd-kit's sortable-tree pattern; the flatten/project/rebuild functions are pure and testable.
- **Board keyboard access** — the cross-list board (`useGroupedDragItem`) is pointer-only; keyboard drag across columns is a later pass.

### Mobile-readiness invariants

Desktop-first, but the sensor and collision layers keep a future touch UX viable: `touch-action: none` on draggables, delay+tolerance activation, a non-passive `touchmove` hedge, clean `pointercancel` handling, a separable keyboard sensor, and collision math that never bakes in hit-target sizes.

### Known minor issue

Under aggressive drag-then-drop, one or two gap items can show a sub-perceptible snap at the commit (in-flight transition timing + sub-pixel rounding between the transform end-position and the natural post-reorder slot). Mitigated via the `transitionend` commit; the residual is accepted as inconsequential.
