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

| Type         | Icon                                      |
| ------------ | ----------------------------------------- |
| Number       | `hash`                                    |
| Checkbox     | `square-check`                            |
| Date & Time  | `calendar` (also the Calendar saved node) |
| Status       | `progress-check` (Tabler — the first opt-in)|
| Link         | `link`                                    |
| File         | `import`                                  |
| Context      | `layout-grid` (matches the sidebar tiers) |
| Select       | `send`                                    |
| Multi-Select | `tags`                                    |

**Link is the canonical name for the `url` type** — user-facing label and default new-property name ("New Link"). The on-disk type key stays `url`; only the name changed.

**Title** wears `text-align-justify` — the reserved heading column isn't a user property type, but its glyph lives beside the type map (`PropertyTypes.tsx`) so every surface renders it from one source. The reserved timestamp columns carry their own header glyphs: **Created** → `clock-plus`, **Modified** (`last_edited_time`) → `history`. Created has no PropertyType, so its glyph is set at the table header; Modified's rides the type map.

### View Types

The saved-view type roster and its grid glyphs (the ViewSettings 3×2 picker):

| Type     | Icon                                        |
| -------- | ------------------------------------------- |
| Table    | `table` — a plain 3×2 grid (also the view icon + button glyph) |
| Cards    | a custom 2×3 stretch-horizontal bar stack    |
| List     | a custom left-rail bar + four lines          |
| Gallery  | `layout-dashboard`                          |
| Calendar | `calendar-days`                             |
| Timeline | `chart-gantt`                               |

`table` is THE table glyph everywhere (view icon, view rows, the ViewDropdown button, and the grid's Table tile) — one glyph per concept, now a plain Lucide grid (the old rotated-Table custom caused sub-pixel aliasing). Cards + List are the two customs, registry-conforming SVG components sized to sit at the same height beside the Lucide glyphs.

### Misc

| Concept     | Icon     |
| ----------- | -------- |
| Connections | `link-2` |

`link-2` is the connections glyph — reserved for the `[[Title]]` connections surface. The Context property type wears `layout-grid` (matching the sidebar tiers), not `link-2`.
