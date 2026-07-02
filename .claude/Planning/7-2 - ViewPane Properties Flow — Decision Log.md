## ViewPane Properties Flow — Decision Log

### Frame

- **Purpose:** Rebuild the ViewPane's Properties pane into the full assign surface — Nathan's Figma mockup is canonical as revised in-session: assigned properties on top (chevron → editor), an "All Properties" registry disclosure (sidebar-style left chevron) with per-row `+` promotion, drag across the two groups for assign/unassign, a nexus-wide cosmetic property order, a 350px height cap with the shared scroll-edge fade, and a top-right circle-plus create.
- **Core Value:** One surface where a Collection's schema is composed from the nexus registry — see everything, promote what fits, remove without destroying.
- **Success Criteria:** From any Collection/Set table: open Settings → Properties, see assigned + all-registry properties, assign by `+` or drag, unassign by drag-out (values survive, re-assign restores), reorder the registry list and see that order in every collection's menu.

### Sources

- `React/src/renderer/src/Components/Detail/PropertiesPane.tsx` — the LIVE pane: list → type picker → per-property editor (rename/icon/delete); routes to `window.nexus.schema.*`. This feature extends it, not replaces it.
- `React/src/renderer/src/Components/Detail/ViewPane.tsx` — mounts PropertiesPane in PaneSlider slot B (`minWidth/minHeight 245` — Nathan's live tweak, uncommitted; he re-tuned from 225 mid-session).
- `React/src/renderer/src/Components/Detail/PaneSlider.tsx` — two-slot push/back with animated width+height from ResizeObserver-measured slots; has `minHeight`, no max/scroll yet.
- `React/src/main/io/propertiesRegistry.ts` — registry store: `.nexus/properties.json` = `Record<propId, PropertyDefinition>` (UNORDERED — the nexus order config is net-new).
- [[History]] 07-01 PropertiesV2 — ratified: Remove = **unassign, non-destructive** ("values sit in frontmatter as foreign data, restored by re-assigning"); global Delete = `.trash` snapshot + atomic fan-out strip (IPC-exposed, UI deferred to this plan); Create validates names registry-wide, Assign is unvalidated/idempotent; `schema:*` IPC kept its names re-backed by registry+assignment ops.
- `Planning/7-1 - PropertiesV2 Data Layer — Implementation Plan.md` — the shipped data layer + its deferred "Plan 2" list: assign-existing surface, Remove-vs-Delete labels, global-clash nudge, **Max Properties question**.
- `Planning/6-28 - Table Views Part 3 — View Settings.md` — the ViewPane spec: pane nav, current Properties increment, pending "rich editor" items (per-type options, change-type confirm, duplicate, drag-reorder).
- Nathan's Figma mockup (in-chat, 07-02) — layout truth as REVISED in-session: back header w/ top-right circle-plus · assigned rows w/ chevrons · "All Properties" tertiary disclosure (left chevron) · registry rows w/ `+`. (The mockup's footer `+ New Property` row is superseded by A-9.)
- `React/src/renderer/src/Sidebar/Sidebar.css` §nav mask (lines ~40-48) — the Apple scroll-edge fade (`--edge-fade` 22px) to hoist for A-6.

### Decisions

#### A — Surface & Layout

- **A-1:** [confirmed] Extends the existing `PropertiesPane` in place — the list/type/edit sub-nav and `schema:*` IPC routing stay; this adds the All Properties section, drag, order, the height cap, and the header/menu revisions (the old footer create-row goes, per A-9).
- **A-2:** [confirmed] Assigned properties render on top at the standard menu tone (label-control), each with a trailing chevron into the per-property editor. The assigned list shows the Collection's assignment-array order.
- **A-3:** [confirmed] "All Properties" is a disclosure row — size-footnote emphasized, label-tertiary, **chevron on the LEFT like the sidebar's twisties** — revealing with the Reveal unfold AND the ViewPane's height-resize animating IN-SYNC (one beat, the PaneSlider discipline); its rows render dimmer with a trailing `+`.
- **A-4:** [confirmed] "All Properties" lists only UNASSIGNED registry properties — an assigned property never appears in both groups.
- **A-5:** [confirmed] `+` on a registry row assigns it to the Collection, appending to the BOTTOM of the assigned list.
- **A-6:** [confirmed] The ViewPane gets a 350px max height; past it the pane scrolls internally, with the **sidebar's Apple scroll-edge fade HOISTED to a shared recipe** (`Sidebar.css` §nav mask, `--edge-fade` 22px) so one knob tunes both surfaces. Implementation seam: a `maxHeight` prop on PaneSlider (clamp the animated viewport height) + `overflow-y: auto` + the shared edge mask on the slot.
- **A-7:** [confirmed] The "fade-reveal" = the pane SLIDE. Today only root→Properties slides (PaneSlider's two slots); PropertiesPane's internal list→editor/type-picker are instant state swaps. Nathan: the slide must be **DRY-ed to every pane push at every depth** — one shared nav-stack mechanism that every pane rides automatically, never per-window wiring; the New-Property type picker rides it too. PaneSlider generalizes from two slots to an N-level push/back stack (same width+height-on-the-beat animation).
- **A-8:** [confirmed — REVISED] The property editor's header becomes `‹ {Name}` + a trailing **⋮ (ellipsis-vertical)**; ⋮ pops a NATIVE dropdown carrying **Remove AND Delete** — Delete is deliberately reachable ONLY inside the property's own pane (never from the list). The footer "Delete Property" row is removed. Delete keeps the ratified confirm-gate + `.trash` recovery snapshot; it purges Remove-caches (D-6) and saves nothing restorable in-app.
- **A-9:** [confirmed] **`+ New Property` moves to the list header's top-right as a `circle-plus` icon** (mirroring the editor's top-right ⋮ slot); the footer row + its divider are gone. Pressing it SLIDES into the type picker (A-7). A newly created property **appends to the BOTTOM of the nexus order** AND is auto-assigned to the current Collection (the existing `schema:add` = create+assign), landing at the assigned group's bottom.
- **A-10:** [confirmed] Right-clicking an assigned property row pops a native menu: **Rename · Remove**. Rename triggers IN-LINE renaming of the row via a NET-NEW property rename channel: a `renamingPropertyId` store slot + a property-aware inline-input variant routing to `schema:rename(containerPath, propId, name)`. Review-verified (MAJOR-1): RenamableTitle CANNOT be generalized — it is path-keyed and its submit routes to the filesystem `rename` op (`MutableKind` has no property, properties have no path); only its input/commit UX pattern is copied. [confirmed] All-Properties rows get Rename only (Remove is meaningless unassigned).

#### B — Nexus Property Order

- **B-1:** [confirmed] A nexus-wide, purely cosmetic property order — it only governs how registry properties list in every collection's menu; dragging within All Properties rewrites it.
- **B-2:** [confirmed] It persists INSIDE `.nexus/properties.json` — the shape grows to `{ order: string[], defs: Record<propId, def> }`, with a lenient-read branch treating the legacy bare-Record shape as `{ order: [], defs }`. (Nathan signed; the sibling-file option → Considered & Rejected.)
- **B-3:** [confirmed] The order array is element-filtered on read (unknown ids dropped, missing ids appended) — the `group_order` codec precedent — so registry create/delete never corrupts it. (Rode the signed B-2 presentation.)

#### C — Drag Semantics

- **C-1:** [confirmed] Drag within All Properties → reorders the nexus order (B-1).
- **C-2:** [confirmed] Drag a registry row INTO the assigned group → assigns to the Collection (the ratified idempotent assign) at the dropped slot in the assignment array.
- **C-3:** [confirmed — REOPENS a ratified call] Remove (drag-out or the editor's ⋮ menu) now **strips the property's values from every member page's frontmatter AND caches them restorably**; re-assigning the property to that Collection restores the cached values to the pages that held them. Provenance: the PropertiesV2 V1 log had "Clear Values" + archive-on-delete; the V2 review cut Clear Values ("model is Remove + Delete only") and shipped Remove as leave-in-frontmatter — Nathan reverses that here: no dormant foreign values on pages. **Delete saves nothing** (the `.trash` recovery snapshot stays as plumbing, but there's no in-app restore). Supersedes [[History]] 07-01's "values sit in frontmatter" and `Features/Properties.md` §Lifecycle — both restate on ship (D-6).
- **C-4:** [confirmed] The remove-drag does NOT drop where released: the All Properties area highlights as the target, and the row lands at its natural nexus-order slot.
- **C-5:** [confirmed] The assigned group is drag-reorderable within itself — that IS the Collection's property order (the existing `schema:reorder` assignment op).
- **C-6:** [confirmed] The cache is a `property_cache` block in the Collection's own sidecar: `{ [propId]: { removed_at, values: { [pageId]: rawOnDiskValue } } }` — Nathan signed approach 1 (see Approaches; alternates → Considered & Rejected).

#### E — Sweep Findings (don't-forget)

- **E-1:** [confirmed] **The renderer can't see the registry today** — the tree carries only each Collection's joined schema. The All Properties list needs every def + the nexus order: `NexusTree` gains `registry` (ordered `PropertyDefinition[]`, order applied main-side) — `readNexus` already loads the registry, so exposure is one join away, and watcher pushes keep the pane live. (Rejected: a separate fetch-on-open IPC — goes stale the moment another surface writes.)
- **E-2:** [confirmed] IPC additions: `assign(collectionPath, propId)` (exists in `crud/assignment.ts`, needs preload exposure), a registry-order write, and `schema:delete`'s implementation grows strip+cache (same signature — the pane keeps calling it). Restore rides assign's implementation (assign checks the sidecar cache). Ride-alongs: `schema:add` also appends the new id to the nexus order; `createProperty`'s unique-name validation comes OUT (D-3); global `deleteProperty` is already IPC-exposed via `property:delete`. Naming reconciliation (review MINOR-2): `schema:delete`'s user-facing label flips Delete→Remove and its body gains strip+cache — the word *Delete* now means `property:delete` only; blast radius is one caller (the pane's own row). Inline rename COMMITS through `schema:rename` but needs its own store channel (A-10 — net-new, not a RenamableTitle reuse).
- **E-3:** [confirmed] Remove and Restore are each ONE `SchemaTransaction` (the Delete machinery): strip/restore every member page + sidecar write atomically — no partial state on failure.
- **E-4:** [confirmed] The 350px cap makes the pane a SCROLL CONTAINER under an active drag: the DnD snapshot must dirty on scroll (bandDnd's `markSnapshotDirty` precedent) and a release OUTSIDE the dropdown must neither drop nor dismiss the dropdown (suppress the dismiss for drag releases). Esc aborts, house standard. Drop classification is REGION-OWNED by the two group rects (the bandSlot precedent): a slot in the assigned region persists collection order (or assigns), the All-Properties region persists nexus order (or unassigns) — one gesture surface, two persistence targets, disambiguated by region alone.
- **E-8:** [confirmed] The Reveal-mid-slide height contention has ONE arbiter: PaneSlider's single transitioned viewport height. A disclosure unfolding changes the slot's measured height → the ResizeObserver retargets the same height transition mid-flight (native CSS retargeting); "in-sync" (A-3) = both pinned to ONE duration token — the pane's beat (`duration.base`, 280ms): the in-pane disclosure overrides Reveal's default `duration.disclosure` (180ms — round-2 caught the mismatch; sidebar Reveals keep 180) so the unfold and the resize land as one beat, sharing `easing.standard`.
- **E-5:** [confirmed] Reserved properties (`isReservedPropertyId`) are excluded from BOTH groups, as the assigned list already does.
- **E-6:** [confirmed] Idempotency: Remove when not assigned = no-op (never overwrite an existing cache block with emptiness); assign when assigned = no-op (ratified); registry writes stay on the serialized mutation chain.
- **E-7:** [confirmed] Cache lifecycle closes cleanly under approach 1: collection deleted → cache dies with its sidecar; page deleted/moved-out → entry dropped at restore; Delete purges blocks (D-6).

#### D — Adjacencies (enter as decisions)

- **D-1:** [confirmed — REVISED] Delete IS in this build's UI, gated to the editor pane's ⋮ menu alongside Remove (A-8) — a property can't be deleted without entering its pane.
- **D-2:** [confirmed] **Max Properties: KILLED.** Nathan challenged its value; Claude's case against: no perf boundary at human-scale counts, the 350px scroll + Visibility pane absorb the UI pressure, and a cap manufactures limit-states (disabled +, bounce, messaging) for a wall nobody legitimately hits. Uncapped, zero code.
- **D-3:** [confirmed — Nathan overruled] **Duplicate names are ALLOWED for now — a FLAT policy across BOTH write paths**: the unique-name clash comes out of `createProperty` AND out of `editProperty`'s `validateName` (rename), or create-twice/rename-into-collision behave inconsistently (round-2 catch). IDs make duplicates mechanically safe; the flattening removed most legitimate need. Recorded in `Features/Properties.md` as a known quirk on ship. The clash nudge stays cut.
- **D-4:** [confirmed] Reconciliation on ship: `6-28 View Settings` spec §Properties, `Features/Properties.md` (assign surface + §Lifecycle Remove row — now FALSE per C-3), [[History]] 07-01's Remove sentence (restate, don't amend), and Handoff's Pending Focuses entry; the 6-28 minHeight (200) vs code (245, Nathan's live tweak) reconciles and the tweak gets committed.
- **D-5:** [confirmed] Sets route through the ancestor Collection's schema (existing `schemaCollection` resolution) — unchanged by this feature.
- **D-6:** [confirmed] Delete's fan-out must ALSO purge any Remove-cache entries for that property (wherever C-6 lands) — a cache the def no longer exists for is corrupt state.

### Approaches (resolved — Nathan signed the recommendations)

#### The Remove cache (C-6) — where stripped values live

1. **Collection-sidecar cache block (RECOMMENDED):** the Collection's own sidecar gains `property_cache: { [propId]: { removed_at, values: { [pageId]: rawOnDiskValue } } }`. Remove = one SchemaTransaction (the machinery Delete already uses): strip each member page's key + write the block + unassign. Re-assign = restore to pages still members (by id via the walk), stale page-ids dropped element-filter-style, block cleared. Why: the cache lives NEXT TO the schema it belongs to — travels with the collection on move/export/sync, no new file, no page residue, agent finds it in the obvious place; sidecar zod already rides unknown keys. This is Nathan's "keep it in the sidecar" instinct minus the redundant `disabled` marker — the cache block's presence IS the removed-but-restorable state.
2. **Central `.nexus/propertyCache.json`:** same shape keyed by collection. One file, but it detaches the cache from the collection it describes (a collection export/move loses its restore data) and adds a write-contention surface.
3. **Per-page `properties_archive` frontmatter block:** values move to an archive sub-map on each page — travels perfectly with pages, but pages keep carrying the data (against Nathan's "frontmatter wouldn't stay") and the "which pages" answer is scattered.

Nathan's raw idea — assignment entries marked `disabled` instead of removed — can't satisfy the strip requirement alone (a marker doesn't clear frontmatter); folded into option 1 as the cache-block-presence signal.

**Cache edges (don't-forget):** page joins collection while removed → nothing to restore ✓ natural; page deleted → entry dropped at restore; page moved out → entry dropped (values don't follow it out); Remove→re-add→Remove overwrites the block; Delete purges blocks everywhere (D-6); values stored as raw on-disk encodings (encoding-stable) — and restore RECONCILES each value against the def's CURRENT state — NET-NEW per-value logic, no existing primitive to ride (round-2: `dropConflictingValues` is all-or-nothing, `assignProperty` never touches values): each cached value whose select/status option no longer exists, or whose def type changed since caching, is dropped PER-VALUE; conforming values restore; the cache block clears either way. Restore never plants a value the current schema can't validate.

#### The nexus order (B-2) — where it lives

1. **Inside `.nexus/properties.json` (RECOMMENDED):** shape grows to `{ order: string[], defs: Record<propId, def> }` — one file owns the registry AND how it lists; the file is one day old, so the shape change is nearly free (one lenient-read migration branch: bare-Record reads as `{order: [], defs}`).
2. **Sibling `.nexus/propertyOrder.json`** (the folds pattern): zero registry churn, but splits one concept across two files.

### Core (must-have)

- All Properties disclosure (unassigned registry rows, tertiary tone, Reveal animation) + `+` promote appending to assigned.
- Nexus order config: persisted, element-filtered, applied to every collection's All Properties list; drag-to-reorder within the group.
- Drag assign (registry → assigned slot), drag reorder (assigned within itself = collection order), drag unassign (assigned → registry, area-highlight + natural-slot snap).
- The Remove cache (C-3/C-6): strip-on-remove, restore-on-reassign — Remove without it destroys data.
- The DRY nav-stack slide: every pane push at every depth rides the one shared slide (root → Properties → editor/type-picker); no per-window wiring.
- The editor's `‹ Name  ⋮` header — native menu: Remove · Delete (Delete pane-gated, confirm-gated).
- The list header's top-right `circle-plus` create (slides to the type picker; new prop appends to the nexus order).
- Row right-click menu (Rename · Remove) + shared in-line rename.
- 350px pane cap + internal scroll with the hoisted sidebar scroll-edge fade (one shared recipe, one knob).

#### Prospects (allowed later, not now)

- Rich per-property editor (per-type options/status groups, formats, change-type confirm, duplicate) — the 6-28 pending list; separate arc. **Nathan (07-02): the full Status, Multi-Select, and Select PropertyPanes are DESIGN-READY in Figma — first in line once this plan ships; pull the Figma designs when building.**

#### Out of Scope

- Visibility / Layout / Group / Filter / Sort panes — sibling ViewPane items, own arcs.
- Agenda's separate `property_definitions` — deliberately untouched (ratified).

#### Considered & Rejected

- **Max Properties cap** — no value uncapped lacks; manufactures limit-states (D-2).
- **Create-time clash nudge** — obsoleted by the visible All Properties list (D-3).
- **Registry-wide unique-name validation** — Nathan dropped it (IDs make duplicates mechanically safe; flattening removed the need); ships as a Properties.md known quirk (D-3).
- **Footer `+ New Property` row + divider** — replaced by the header's top-right circle-plus (A-9).
- **One flat checkmarked list** (no assigned/all split) — loses the two-zone drag semantics and the mockup's hierarchy; the mockup is canonical.
- **Central `.nexus/propertyCache.json`** — detaches restore data from the collection it describes.
- **Per-page `properties_archive`** — keeps values in frontmatter, which Remove exists to prevent.
- **`disabled` markers on assignments** — a marker can't strip frontmatter; the cache block's presence carries the same state.
- **Fetch-on-open registry IPC** — goes stale against watcher-pushed tree updates; the tree carries it instead (E-1).

#### Lessons

- A ratified decision log entry is not immune to the user's newer intent — when Nathan's ask contradicts the record, surface the exact provenance (V1's "Clear Values," cut in V2 review) and reopen it explicitly rather than "correcting" him or silently complying.
