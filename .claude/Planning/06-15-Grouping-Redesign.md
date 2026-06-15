## Grouping Redesign — Spec

> **Status: written, review-certified (V2).** Design ratified with Nathan via interview (2026-06-15); code claims grounded against source and a logic/coverage round folded in (V2). Pending Nathan's read before the implementation plan.

Redesigns the **Grouping** pane and grouping behavior. Item-sorting (ordering rows *within* a group) is a separate follow-up and is untouched here. Grouping orders the group **headers**; sorting orders the **items** — the pipeline already keeps these independent and this spec preserves that split. The Options chip-list in the pane reorders *group headers*, never items.

### Scope

- In: the Grouping pane UI, the per-type group-order model, date bucketing, the empty-group rule, and view-level manual reordering of group headers.
- Out (deferred): the Sort pane redesign (item ordering), grouping by tiers / multi-select, grouping by system dates, the "Relative" date bucket, and sub-groups.

### Decisions (interview, 2026-06-15)

- **"Grouping off" = the file-system / structural default** (Collection → Set). The toggle flips a view between `GroupConfig.structural` and `.property`; there is no new "flat" state to invent.
- **Groupable property types: Select, Status, Checkbox, user Date only.** Tiers (Area/Topic/Project) and Multi-Select are *not* groupable — they are multi-value, and excluding them keeps every group single-membership (one page → exactly one group).
- **Group order controls headers only.** Item order within a group is the separate Sort feature.
- **Per-type order modes:** Select = Default / Manual · Status = Ascending / Descending / Manual · Date = Ascending / Descending · Checkbox = On / Off. (Select intentionally omits Descending — "Default" *is* the schema order and "Manual" covers any custom arrangement; a flat option list with no categories has no semantic reverse.)
- **Manual** order is editable in two places: drag chips in the pane's Options area, and drag the group-header chip in the view itself. Value-group headers are draggable only in Manual mode.
- **Empty ("No [Property]") group:** a *Hide empty groups* toggle removes it; otherwise it is always placeable Top or Bottom (an axis independent of the order mode — in a fixed mode it is the only movable group, and only to the ends).
- **Group-by picker** expands inline under "Group By" (not a pushed screen).
- **Options area reuses the Edit-Properties option-reorder design**, minus the "Add" affordance (no schema editing from the grouping pane).

### On-disk schema

`GroupConfig` (unchanged shape) stays a tagged enum on `SavedView.group`: `.structural` (file-system default) · `.property(PropertyGrouping)` · `.flat`. The toggle uses `.structural` ⇄ `.property`. (`.flat` is a legacy case no live sidecar uses; treat as `.structural` on decode.)

`PropertyGrouping` is extended additively (every new key `decodeIfPresent`):

```
PropertyGrouping {
  propertyID:       String
  orderMode:        GroupOrderMode    // .configured | .reversed | .manual   (default .configured)
  order:            [String]?         // the manual arrangement of group keys (used when .manual)
  dateGranularity:  DateGranularity?  // .day | .week | .month | .year        (date grouping only)
  emptyPlacement:   EmptyPlacement    // .top | .bottom                       (default .bottom)
  hideEmptyGroups:  Bool              // default false
}
```

**Backward compatibility.** An existing sidecar `{property_id, order?}` decodes with `orderMode = .configured` and the documented defaults. A populated legacy `order` is **ignored** while `.configured` (so the view's group appearance is unchanged on upgrade) and becomes live only if the user switches the pane to Manual — their old arrangement is still there waiting.

One `GroupOrderMode` enum backs every type; the pane exposes a type-specific subset with type-specific labels — DRY, one resolver path:

| Type | Popout labels → `orderMode` |
| --- | --- |
| Select | Default → `.configured` · Manual → `.manual` |
| Status | Ascending → `.configured` · Descending → `.reversed` · Manual → `.manual` |
| Date | Ascending → `.configured` · Descending → `.reversed` |
| Checkbox | Off (unchecked-first) → `.configured` · On (checked-first) → `.reversed` |

`order` holds bare group-value keys (option values for Select/Status), reusing the existing `PropertyGrouping.order` override the resolver already honors (`GroupResolver.bucketOrder`).

### Grouping model (resolver)

Buckets are built for **present values only**, plus one **nil bucket** for items whose grouped property is unset (titled "No [Property]"). No empty schema-option groups are manufactured. *Exception: Checkbox — see its bullet.*

- **Select** — one group per option value. `.configured` = the property's schema option order; `.manual` = the `order` array.
- **Status** — one group **per option value** (e.g. 5 options → 5 groups, not the 3 status categories). `.configured` flattens to one ordered list: Upcoming options in their schema sequence, then In-progress options in their schema sequence, then Done options in their schema sequence (this is exactly `statusGroups.flatMap { $0.options }`). `.reversed` reverses that entire flat list. `.manual` ignores category structure and uses `order`. The pane's Options preview nests options under their 3 status-group labels in fixed modes and flattens to one list in Manual; the **view groups are per-option regardless**.
- **Checkbox** — the sole type with **no nil bucket**. The resolver maps `nil` (unset) to the **Unchecked** key at assignment time; the nil-bucket path is never entered. `.configured` = Unchecked-first, `.reversed` = Checked-first. `hideEmptyGroups` and `emptyPlacement` are inert for Checkbox.
- **Date** — bucket each date by `dateGranularity` into an ISO-formatted key (`2026-06` month, `2026-W24` ISO-8601 week [Monday start], `2026-06-15` day, `2026` year). Bucket assignment uses the **device's current calendar + timezone** (buckets are display-local, not UTC); year-boundary ISO weeks carry their ISO year. Keys are ISO-formatted, so lexicographic order = chronological: `.configured` = ascending (oldest first), `.reversed` = descending. **Present buckets only** (no empty/future buckets), so hide-empty is inert for dates.
- **Empty (nil) group** — `hideEmptyGroups` drops it; otherwise `emptyPlacement` pins it Top or Bottom. It is the only group movable in a fixed order mode. When `hideEmptyGroups` is on, the pane **hides** the "Empty group" row entirely; `emptyPlacement` keeps its stored value and re-applies the moment hide-empty is turned off.

**Stale `order` & schema changes.** This is the existing `bucketOrder` convention, made explicit: a key in `order` with no present items produces no bucket (a deleted/renamed option leaves no ghost group); an option-value present but absent from `order` is appended at the tail in schema order. The pane's Options list always shows *current* schema options only, and writes a fresh `order` from them on a Manual reorder — so stale keys self-clean on the next edit.

**Group-by property removed / type-changed.** If `propertyID` resolves to a missing or no-longer-groupable property at load, the resolver falls back to `.structural` for that view (no crash, no error). The pane opens with the toggle ON but Group By showing "None" so the user can re-pick; the stale `PropertyGrouping` is preserved on disk and restored if the property reappears.

`GroupResolver.bucketKey` gains the date-granularity case; `bucketOrder` gains `orderMode` + `emptyPlacement`. Multi-value types never reach the resolver — they are excluded at `ViewSettingsProperties.groupable`.

### The Grouping pane

Replaces today's `GroupPane.swift`. A pushed pane within the View Settings `NavigationStack` (the mockup's "‹ Settings" back affordance). Rows are contextual to the selected type:

```
Grouping        [toggle]          ← OFF: file-system/structural. ON: reveals Group By.
Group By        <Property> ⌄      ← inline-expand picker (groupable user props, schema order)
Date By         <Day|Week|…> ›    ← date grouping only; popout
Order           <mode> ›          ← popout; per-type label set above
──────────────────────────────
Options                           ← Select + Status only; chip+drag-handle list, NO Add
  ⬤ <value>            ≡          ← draggable in Manual; non-draggable preview in fixed
  …                               ← hidden entirely if the property has zero options
──────────────────────────────
Hide empty groups   [toggle]
Empty group         <Top|Bottom>  ← hidden while Hide empty groups is on
```

**States.** *Off* → Group By shows "None", view is structural. *On, nothing picked* → a **UI-only** intermediate: the picker auto-expands, disk stays `.structural`, and nothing is written until a property is actually selected (only a pick commits `.property(...)`). The last picked property is remembered so toggling back restores its `.property` value immediately. *On, picked* → Group By shows the property; the contextual rows + Options area appear.

### Interaction — manual reordering

- **In the pane:** Manual mode makes the Options chip list drag-reorderable; the drop writes the new arrangement to `PropertyGrouping.order`.
- **In the view:** Manual mode makes group-header chips drag-reorderable — the table's group disclosure rows (`ViewGroupHeaderCell` in `ViewOutlineTable`) and the gallery's section headers (`GalleryView.header`) — writing through to the same `order`.
  - **Affordance:** in Manual, header chips show a drag handle (≡, matching the Options list). In fixed modes the handle is absent and the reorder gesture is **not installed** (not merely suppressed). The "No [Property]" chip in a fixed mode shows a handle but only the top and bottom drop zones accept it; mid-list drops are rejected.
- **Structural / no property grouping:** unchanged — dragging a row uses the existing `RowDragCoordinator` page-drag (its `reorder` closure) that reorders pages in the owning container and mirrors the sidebar order.
- **Mutual exclusion.** The group-header drag target is installed **only** when `GroupConfig == .property` *and* `orderMode == .manual`; in every other state the page-drag is active. The two are never live together in one view.

### Reuse vs. build

- **Reuse:** `ViewSettingsPane` frame + `PaneHeader`; `SelectOptionsEditor` / `StatusGroupsEditor` as the Options-area base (drop the "Add" closure); `ChipDropdown` / popover pattern for the Order + Date By popouts; `RowDragCoordinator` (extended with a group-header target) for the view-level drag.
- **Build (stage in the Component Library first, per the design-source rule):** a settings Toggle row, a disclosure/popout row, and the grouping Options list.

### Phases

0. **Schema** — extend `PropertyGrouping` (orderMode, dateGranularity, emptyPlacement, hideEmptyGroups), backward-compatible decode (legacy `order` ignored until Manual), unit tests.
1. **Resolver** — date bucketing + `orderMode` + `emptyPlacement` + checkbox nil→Unchecked + property-missing fallback, unit tests.
2. **Grouping pane** — toggle, inline Group By picker, Order + Date By popouts, Options reorder list, empty controls; wired to schema.
3. **View-level Manual header drag** — table + gallery, writing `order`, mutually exclusive with page-drag; the existing structural page-drag integration test must stay green.
4. **Polish + mandatory post-functional UIX review.**

### Risks

- View-level group-header drag across `ViewOutlineTable` (NSOutlineView) and `GalleryView` is the heaviest piece and the main schedule risk.
- Backward-compatible decode of older `PropertyGrouping` sidecars must be proven (decodeIfPresent defaults; legacy `order` dormant under `.configured`).
- The structural page-drag → sidebar/container-order path must not regress when the grouped-Manual drag lands (enforced by the Phase 3 mutual-exclusion rule + the existing integration test).

### Deferred

Sort-pane (item ordering) redesign · grouping by tiers / multi-select (multi-membership) · grouping by Created / Edited time · the "Relative" date bucket · sub-groups.
