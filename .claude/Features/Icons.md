## Icons

Pommora's standard semantic icons — the canonical glyph for each pane, property type, and recurring concept. Icons come from **Lucide** (named here by their lucide.dev id), curated in the registry behind `design-system/symbols` (mirrored by `symbols/Symbols.md`); this doc names the assignment, the code holds the maps. **Tabler (`@tabler/icons-react`) stays installed as a second source we can pull from** — a per-icon opt-in through the same seam (see Symbols.md), not the default. Anything without an assigned glyph falls back to **`DashIcon`** (the dashed-square placeholder) until a symbol is chosen — a placeholder is intentional, not a gap to fill arbitrarily.

### Sizing

- **Content / leading icons** (pane rows, property-type rows) render at **16px** — a touch larger than their label, matching the row-icon convention.
- **Affordance icons on subline rows** (the back-row `‹` chevron, the footer `+`) render at **12px**, sized down to sit with the 10px subline type.

### View Settings Panes

The six settings rows (`ViewPane` → `ENTRIES`):

| Pane       | Icon               |
| ---------- | ------------------ |
| Properties | `server`           |
| Visibility | `eye` → `eye-off` when hidden |
| Layout     | `layout-dashboard` |
| Group      | `layers`           |
| Filter     | `list-filter`      |
| Sort       | `arrow-up-down`    |

`eye-off` is the hidden-state variant, registered for the Visibility pane's per-property toggles.

### Property Types

The type glyphs, shown in the type picker and on each property row. Label + icon + the creatable set are one source — `PropertyTypes.tsx` → `PROPERTY_TYPES` (rendered via `PropertyTypeIcon`):

| Type          | Icon            |
| ------------- | --------------- |
| Number        | `hash`          |
| Checkbox      | `square-check`  |
| Date & Time   | `calendar` (also the Calendar saved node) |
| Status        | `circle-dashed` |
| Link          | `link`          |
| File          | `import`        |
| Relation      | `link-2` (see Misc) |
| Select        | *pending → `DashIcon`* |
| Multi-Select  | *pending → `DashIcon`* |

**Link is the canonical name for the `url` type** — user-facing label and default new-property name ("New Link"). The on-disk type key stays `url`; only the name changed.

### Misc

| Concept     | Icon     |
| ----------- | -------- |
| Connections | `link-2` |

`link-2` is the connection/relation glyph — applied to the `relation` property type, reserved for the wider connections surface.
