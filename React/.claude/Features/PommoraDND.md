## Drag and Drop — PommoraDND

Pommora's drag-and-drop is an **in-house engine, PommoraDND**, built to replace `@dnd-kit/*`. It owns the interaction layer the way `MarkdownPM` owns the editor layer — leaning on the external library first to learn the problem, then rebuilding a leaner equivalent scoped to our reality (Chromium-only via Electron, React-only, a known set of surfaces). It lives behind a **thin seam** so the engine is swappable without touching callers. This doc is the durable spec of the system.

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

### Sidebar tree (the app's chosen behavior)

The sidebar adopts a **bespoke** position-aware behavior — the **"sidebar"** treatment — rather than the sort engines above, because its drop feel is an Apple-style **insertion line**, not displacement: the line marks the exact drop, the picked-up row stays **muted in place**, and a ghost rides the cursor (rendered through a portal, to escape the glass `backdrop-filter` containing block that would otherwise capture a `fixed` element). **Every entity is draggable and reorders within its parent heading** — pages (within a folder; also reparent across folders), collections (within a vault), sets (within a collection), vaults, and the three context tiers; the code-fixed Saved pins are the only inert rows. Because nothing displaces, rows never move mid-drag — so it hit-tests **live** row rects (no frozen snapshot) and derives all structure (kinds, paths, depths, parent, each parent's ordered child ids + the top-level groups) from the tree through a pure, unit-tested model (`Sidebar/sidebarDndModel.ts`). A drop resolves to one of three **commits**, each routed to its store/IPC action: `movePage` (page move + `page_order`), `reorderChildren` (`collection_order` / `set_order` on the parent's sidecar), or `reorderTop` (`vault_order` / `{tier}_order` in `.nexus/state.json`). It superseded the old container-only `useTreeMove`, which was removed (the sidebar was its only consumer).

### Verification harness

The **Interaction Lab** (`design-system/interactions/`, served via `npm run showcase` → `interactions.html`) exercises every surface — list, grid, table, recursive tree, cross-list board — with a live "feel" control (duration + easing) shared across all of them. It is the design-system verification surface, **separate from the app**: a green lab does not mean the app consumes the engine. **The sidebar tree is adopted** (its own behavior, above); the main list / view rows remain a later, deliberate integration.

### Relationship to dnd-kit

`@dnd-kit/*` has been **fully replaced and uninstalled** — PommoraDND is the drag engine, with no `@dnd-kit` dependency or import anywhere. It is **not** a 1:1 port — it deliberately drops generality we don't need (the framework-agnostic core, three input sensors, four collision strategies, the modifier pipeline, SSR guards, continuous re-measuring) and adds improvements dnd-kit lacks (pointer capture, hysteresis, no mid-drag array churn, a frame-accurate commit).

Shared types (`Box` / `DropState` / `DragItem` / `DragNotify` / `Modifier`), the tuning constants, and the pure helpers (`toBox`, `px`) live in `shared.ts`, consumed by both `engine.tsx` and `group.tsx`. The two engines' drag-state and commit machinery stay separate — they model genuinely different interactions (in-place transform vs portal overlay), so only the shared primitives are hoisted.

### Constraints, auto-scroll, accessibility (built)

Each is an inline option or an automatic behavior, exercised in the Lab:

- **Constraints & modifiers** — `axis` lock, `bounds` clamp (window / list-extent), a `modifiers` escape hatch (folded left-to-right like dnd-kit's `applyModifiers`), `swap` mode (exchange active+over, commit with `arraySwap`), and **async drop rejection** (`canReorder` may return a `Promise`; the item holds lifted in the `pending` state until the verdict resolves). The Constraints Lab surface toggles each.
- **Auto-scroll** (`autoscroll.ts`) — an rAF loop scrolls the nearest scrollable ancestor when the pointer nears an edge, with an ease-in ramp (dnd-kit uses a non-frame-synced `setInterval` + linear) and limit-awareness (no churn at a maxed edge). The container's scroll delta is compensated into the lifted item + collision so the drag stays accurate as content scrolls; non-active items don't double-compensate (their shift is a frozen-rect difference). Scope simplification: nearest ancestor only, not the page/window.
- **Keyboard + screen-reader** (`keyboard.ts`, `a11y.ts`) — Space/Enter lifts, arrow keys move (a geometric next-slot getter that covers list/row/grid), Space/Enter/Tab drops, Esc cancels; an assertive ARIA live region announces pick-up/move/drop/cancel with position ("item 3 of 8"), a hidden instructions element is wired via `aria-describedby`, and focus is restored to the item on drop. Items are focusable (`tabIndex`); the handle role is `button` by default, settable to `null` so table rows keep `<tr>` semantics.

### Mobile-readiness invariants

Desktop-first, but the sensor and collision layers keep a future touch UX viable: `touch-action: none` on draggables, delay+tolerance activation, a non-passive `touchmove` hedge, clean `pointercancel` handling, a separable keyboard sensor, and collision math that never bakes in hit-target sizes.

### Known minor issue

Under aggressive drag-then-drop, one or two gap items can show a sub-perceptible snap at the commit (in-flight transition timing + sub-pixel rounding between the transform end-position and the natural post-reorder slot). Mitigated via the `transitionend` commit; Nathan admits the residual is truly only noticeable if you’re explicitly trying to recreate it and already know what you’re looking for — he’s accepted as inconsequential.
