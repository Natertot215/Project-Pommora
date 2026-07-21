## PommoraDND

Pommora's drag-and-drop is an **in-house engine, PommoraDND**, built to replace `@dnd-kit/*`. It owns the interaction layer the way `MarkdownPM` owns the editor layer — leaning on the external library first to learn the problem, then rebuilding a leaner equivalent scoped to our reality (Chromium-only via Electron, React-only, a known set of surfaces). It lives behind a **thin seam** so the engine is swappable without touching callers. This doc is the durable spec of the system.

### The Seam

Surfaces import only from the interaction layer's **two shared entry points** — never `@dnd-kit` directly. That boundary is what lets the internals be replaced without touching callers.

**`design-system/interactions/gesture.ts`** is the raw-pointer primitive under the bespoke surfaces: `beginPointerGesture` owns the pending→active activation gate, the window listener set, pointer capture, Esc cancel (optionally swallowed so a parent pane doesn't also dismiss), teardown, and a per-gesture abort handle. Exactly one gesture can be live at a time — a begin while one is live is refused. Surfaces wire it through **`usePointerGesture()`**, which owns each consumer's side of the ritual — the live handle, the unmount abort, and the refusal rule (a refused begin never overwrites the live gesture's handle) — and returns whether the gesture started. Consumers: the table row drag, the band drag, the properties-pane reorder, and the grouping-list reorder.

**`design-system/interactions/drag.tsx`** is the sort-engine seam:

- **`SortableZone`** — one sortable list. Standalone by default (list, grid, table, each tree level); pass `group` to make it a member of a `DragGroup` (cross-list).
- **`DragGroup`** — a set of zones that hand items between each other (the board), with a portal overlay.
- **`useDragItem(id)`** — wires a standalone item; spread the returned `handle` on the drag surface, `setNodeRef` on the element, `style` for the transform.
- **`useGroupedDragItem(id)`** — wires a `DragGroup` member item.
- **`reorder(items, activeId, overId)`** — the array commit helper a zone's `onReorder` applies.

`layout` (`'list' | 'grid' | 'table'`) is informational only — the engine is geometry-driven, so one displacement model serves all three.

### Core Principles

The engine's behaviour is defined by a few load-bearing decisions, each chosen against how dnd-kit does it:

- **One pointer sensor.** A single Pointer-Events sensor with `setPointerCapture` handles mouse, trackpad, pen, and touch. There is no mouse/touch sensor split and no document-level listener fallback — capture routes move/up/cancel to the dragged element regardless of where the pointer goes.
- **Measure once, no array churn.** Item rects are measured at drag start (per zone, on first entry for cross-list) and frozen for the drag. The items array is never mutated mid-drag; collision runs against the frozen snapshot. The reorder commits exactly once, on drop.
- **Closest-centre collision with hysteresis.** The over-slot is the nearest item centre to the projected drag point; switching slots must clear a small pixel threshold, so a slot boundary doesn't flicker between two positions.
- **One strategy-agnostic shift.** Displacement is a rects-reflow: each non-dragged item moves to the slot it will occupy after the reorder. The same math covers vertical lists, horizontal rows, and 2-D wrapping grids — there is no per-layout strategy registry.
- **Decide, then animate.** On drop the accept/reject decision is made *first*, then a single animation moves the item to its true resting slot (the gap if accepted, its origin if rejected). The commit fires when that animation actually ends (`transitionend`, with a fallback timer), not on a blind timer — so items never settle and then snap. A rejected drop cannot animate into the gap and bounce back.

### Single-Zone vs. Cross-List

Two engines sit behind the seam, sharing types and the measure-once / decide-then-animate model:

- **Single-zone** (`engine.tsx`) — list, grid, table, and each tree level. The dragged item moves **in place** (transform follows the pointer); neighbours shift to open the gap. Used where the surface isn't clipped.
- **Cross-list** (`group.tsx`) — the board. A `DragGroup` owns the one active drag across its zones. The lifted card is hidden in its source column and rendered as a `position: fixed` **portal overlay** under the cursor (escaping any column clipping); every column shifts its items by one slot-pitch to show where the card would land. The move commits once via `onCommit(activeId, toZone, toIndex)`. Because columns are never mutated mid-drag, there is no duplicate-card race to guard against — the class of bug dnd-kit's live cross-container moves required defending against simply doesn't exist here.

### Sidebar Tree (The App's Chosen Behavior)

The sidebar adopts a **bespoke** position-aware behavior — the **"sidebar"** treatment — rather than the sort engines above, because its drop feel is an Apple-style **insertion line**, not displacement: the line marks the exact drop, the picked-up row stays **muted in place**, and a ghost rides the cursor (rendered through a portal, to escape the glass `backdrop-filter` containing block that would otherwise capture a `fixed` element). **Every entity is draggable and reorders within its parent heading** — pages (within a folder; also reparent across folders), collections (within a vault), sets (within a collection), vaults, and the three context tiers; the code-fixed Saved pins are the only inert rows. It hit-tests a **frozen geometry snapshot** taken at drag activation — invalidated by any scroll or a mid-drag tree swap, then lazily re-measured once on the next move — and derives all structure (kinds, paths, depths, parent, each parent's ordered child ids + the top-level groups) from the tree through a pure, unit-tested model (`Sidebar/sidebarDndModel.ts`). A drop resolves to one of three **commits**, each routed to its store/IPC action: `movePage` (page move + `page_order`), `reorderChildren` (`collection_order` / `set_order` on the parent's sidecar), or `reorderTop` (`vault_order` / `{tier}_order` in `.nexus/state.json`). Every structural commit lands **optimistically**: the moment the write returns, a pure tree transform (`treeMove.ts`) patches the in-memory tree so the row appears in its new home instantly, and the confirming re-walk follows — the watcher's self-write suppression keeps the whole op to exactly one walk (→ [[Architecture]] § File-watcher). It superseded the old container-only `useTreeMove`, which was removed (the sidebar was its only consumer).

The **table band surface** (`Table/bandDnd.tsx`) extends the same insertion-line treatment to the table's group headers: the **glyph** is the drag surface (the chevron and hover "+" isolate on pointerdown), the line + portal ghost are the chrome, a Set band's WHOLE region — header past its top zone plus its data rows — reads as one continuous **nest-into** highlight (cycle-guarded; root append lives past the measured content bottom), and all slot/parent/order math lives in a pure, unit-tested model (`Table/bandDndModel.ts`). A drop hands the caller a *classified* commit — reorder vs reparent, routed by the slot's implied parent against the dragged band's current parent — so the view never re-derives it. Its snapshot extends the measurement discipline one step: **the band list is snapshot state too** — a mid-drag tree swap goes stale together with the geometry, so both invalidate and re-measure as one. **Esc aborts an active drag on every surface** (sidebar, table rows, bands) through each gesture's existing cancel path.

**Measurement discipline — a root-caused don't-repeat.** The sidebar originally hit-tested **live** rects — `getBoundingClientRect` over every registered row on every `pointermove` — and lagged exactly like the table's row-drag had (the same O(rows) forced-layout storm, the "on every X" anti-pattern). The root cause wasn't the code; it was the **reasoning**: "nothing displaces, so rows never move mid-drag" was used to justify live reads, when that property is precisely what makes a frozen snapshot *safe* — the justification was inverted. The deeper failure: a **bespoke surface re-derived its own measurement policy** instead of inheriting the engine's "measure once" core principle — the principle lived in the engines, and the sidebar sat outside them. The rule, for every drag surface (engine-backed or bespoke): **layout is read at activation, never per move; a scroll or structural change invalidates the snapshot, and the next move re-measures once** (coalescing an event burst into one read). If a new surface believes it needs live geometry, that belief is the thing to interrogate first.

### Verification Harness

The **Interaction Lab** (`design-system/interactions/`, served via `npm run showcase` → `interactions.html`) exercises every surface — list, grid, table, recursive tree, cross-list board — with a live "feel" control (duration + easing) shared across all of them. It is the design-system verification surface, **separate from the app**: a green lab does not mean the app consumes the engine. **The sidebar tree is adopted** (its own behavior, above); the main list / view rows remain a later, deliberate integration.

### Relationship to dnd-kit

`@dnd-kit/*` has been **fully replaced and uninstalled** — PommoraDND is the drag engine, with no `@dnd-kit` dependency or import anywhere. It is **not** a 1:1 port — it deliberately drops generality we don't need (the framework-agnostic core, three input sensors, four collision strategies, the modifier pipeline, SSR guards, continuous re-measuring) and adds improvements dnd-kit lacks (pointer capture, hysteresis, no mid-drag array churn, a frame-accurate commit).

Shared types (`Box` / `DropState` / `DragItem` / `DragNotify` / `Modifier`), the tuning constants, and the pure helpers (`toBox`, `px`) live in `shared.ts`, consumed by both `engine.tsx` and `group.tsx`. The two engines' drag-state and commit machinery stay separate — they model genuinely different interactions (in-place transform vs portal overlay), so only the shared primitives are hoisted.

### Constraints & Accessibility (Built)

Each is an inline option or an automatic behavior, exercised in the Lab:

- **Constraints & modifiers** — `axis` lock, `bounds` clamp (window / list-extent), a `modifiers` escape hatch (folded left-to-right like dnd-kit's `applyModifiers`), `swap` mode (exchange active+over, commit with `arraySwap`), and **async drop rejection** (`canReorder` may return a `Promise`; the item holds lifted in the `pending` state until the verdict resolves). The Constraints Lab surface toggles each.
- **Keyboard + screen-reader** (`keyboard.ts`, `a11y.ts`) — Space/Enter lifts, arrow keys move (a geometric next-slot getter that covers list/row/grid), Space/Enter/Tab drops, Esc cancels; an assertive ARIA live region announces pick-up/move/drop/cancel with position ("item 3 of 8"), a hidden instructions element is wired via `aria-describedby`, and focus is restored to the item on drop. Items are focusable (`tabIndex`); the handle role is `button` by default, settable to `null` so table rows keep `<tr>` semantics.

#### II. Autoscroll

One app-wide primitive drives every drag's edge-scroll — `interactions/autoscroll.ts`, a **singleton rAF loop** each drag source feeds, replacing the per-surface copies that used to drift apart. A drag calls `startAutoScroll` at activation and stops via the **instance-scoped stopper** it returns (so a bystander surface's teardown can't halt a live drag); the loop scrolls **one fixed scroller resolved once at drag start**. That scroller is passed explicitly by the drags that fold the scroll delta into their own pointer math (the engine, SurfacePM) or that scroll a container `findScroller` can't derive (the CM editor's `scrollDOM`); otherwise the **axis-aware `findScroller`** walks to the nearest ancestor that scrolls in the needed axis. Axis-awareness is load-bearing — a vertical table drag must skip the x-only `.table-view` to reach `.detail-scroll`.

The loop reads the last pointer point every frame — so holding still at an edge keeps scrolling, the whole reason a loop owns the scroll rather than the pointer-move — ramps by edge proximity, and advances the scroller in **pixels-per-second × frame-delta** with sub-pixel accumulation, so the speed is identical on 60 Hz and ProMotion. Two feel behaviors ride on top: **distance-based acceleration** eases a scroll run in from a floor and climbs it to a ceiling with the *distance it has covered* (a longer drag-scroll goes slightly faster; the run resets when the pointer leaves the edge band, and the floor is deliberately non-zero — at zero the loop would scroll nothing, accumulate no distance, and stall), and **direction-intent** withholds a direction until the pointer has left that edge band once, so grabbing an item already pinned at an edge doesn't rocket the container. The tunables — edge band, base speed, proximity-ramp exponent, and the acceleration floor / ceiling / distance — are tokens in `interactions/autoscroll.css`, read off the **drag element** once at drag start and cached; a surface overrides any of them by setting the var on itself or an ancestor.

The module **owns a termination backstop** (blur / visibilitychange / pointercancel) that stops the *loop only* — each surface still aborts its own gesture — so a focus-steal can't strand a running loop, and a single frame's delta is clamped so an rAF stall can't teleport the scroll.

**Consumers** (all on the one loop; no second copy remains): the drag engine, SurfacePM tiles, the settings-pane reorder, the MarkdownPM block drag, the sidebar tree, and table row + band reorder. **Prospects** (not yet wired, each named with its real cost): MarkdownPM list drag (needs its own scroll re-measure path first), table column horizontal reorder, the GFM-table drag, and the grouping pane — plus the cross-list board, which is architecturally distinct: its zone resolves under the pointer per move, so it alone would need per-frame scroller resolution reintroduced, not the fixed-scroller model.

### Mobile-Readiness Invariants

Desktop-first, but the sensor and collision layers keep a future touch UX viable: `touch-action: none` on draggables, delay+tolerance activation, a non-passive `touchmove` hedge, clean `pointercancel` handling, a separable keyboard sensor, and collision math that never bakes in hit-target sizes.

### Known Minor Issue

Under aggressive drag-then-drop, one or two gap items can show a sub-perceptible snap at the commit (in-flight transition timing + sub-pixel rounding between the transform end-position and the natural post-reorder slot). Mitigated via the `transitionend` commit; Nathan admits the residual is truly only noticeable if you’re explicitly trying to recreate it and already know what you’re looking for — he’s accepted as inconsequential.
