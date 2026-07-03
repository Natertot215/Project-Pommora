## Symbols — PommoraIcons, the curated icon set

Pommora's icons are **PommoraIcons** — a mixed registry behind one seam (`index.tsx`): **Tabler** ([tabler.io/icons](https://tabler.io/icons)) is the default set rendered at the 1.75-stroke registry default, a handful of ratified **Lucide** keeps stay at their library look, and **customs** are first-party SVGs in the same slot shape. This file is the request list and mirrors the registry — add a name + purpose here, then import and register it in `index.tsx`. Only listed icons ship in the bundle. Keys are Pommora's own vocabulary; a key renames when its glyph changes identity (`square-plus` → `circle-plus`), never for library spelling.

**To use one in code:** `import { Icon } from '@renderer/design-system/symbols'` → `<Icon name="folder-closed" size={15} />`. `strokeWidth` is normalized across sources by the seam.

| Name | Source | Used for |
|---|---|---|
| `house` | Tabler `home` | Homepage |
| `calendar` | Tabler `calendar-month` | Calendar · Date & Time property type (THE calendar glyph) |
| `clock` | Tabler `clock-hour-3` | Recents |
| `gallery-vertical-end` | **Lucide keep** | Collection rows |
| `folder-closed` | **Lucide keep** | Collection/Set closed |
| `folder-open` | **Lucide keep** | Collection/Set open |
| `file-text` | Tabler | Page (THE default page icon) |
| `layout-grid` | **Lucide keep** | Context tiers (Area / Topic / Project) |
| `check` | Tabler | Checkbox chip · status Done glyph |
| `circle-dashed` | Tabler | Select chip placeholder · status Upcoming · Status property type |
| `minus` | Tabler | Status In-Progress glyph |
| `sliders-horizontal` | Tabler `adjustments-horizontal` | Trio Button, Settings |
| `chevron-left` / `chevron-right` / `chevron-up` / `chevron-down` | **Lucide keep** — THE house chevron (Tabler's draws smaller in the same box) | Twisties · menus · disclosure · toolbar Back/Forward |
| `chevron-compact-up` / `chevron-compact-down` | Tabler | Registered, unassigned |
| `map` | Tabler | Trio Button, Navigation |
| `x` | Tabler | Chip dismiss |
| `plus` | Tabler | Add buttons |
| `square-plus` | **Lucide keep** | Add Banner |
| `circle-plus` | Tabler | Registered, unassigned |
| `ellipsis-vertical` | **Lucide keep** — pairs with the Lucide chevrons in pane headers (Tabler's dots draw denser) | Property editor ⋮ · Menu leaf (showcase) |
| `dots` | Tabler | Registered, unassigned |
| `tag` | Tabler | Chips leaf (showcase) |
| `panel-right` | Tabler `layout-sidebar-right` | Trio Button, Inspector toggle |
| `square-dashed` | **Custom** (`SquareDashed.tsx`) | Unselected state · profile placeholder |
| `copy` | Tabler | Registered, unassigned (future duplicate actions) |
| `arrow-up-down` | Tabler `arrows-up-down` | ViewPane Sort |
| `log-out` | **Lucide keep** | Sidebar collapse/expand (flipped = collapse, normal = expand) |
| `heart` | Tabler | Registered, unassigned |
| `hash` | Tabler | Number property type |
| `square-check` | Tabler | Checkbox property type |
| `import` | Tabler `file-import` | File property type |
| `link` | **Lucide keep** | Link (url) property type |
| `link-2` | **Lucide keep** | Context/Relation property type · Connections |
| `server` | Tabler | ViewPane Properties |
| `eye` / `eye-off` | Tabler `eye` / `eye-closed` | ViewPane Visibility (shown / hidden) |
| `layout-dashboard` | Tabler | ViewPane Layout |
| `list-filter` | Tabler `filter-2` | ViewPane Filter |
| `layers` | Tabler `stack-2` | ViewPane Group · Glass leaf (showcase) |
| `grip-vertical` / `grip-horizontal` | Tabler | Drag grips (table rows · editor table columns/rows) |
| `palette` | Tabler | Colors leaf (showcase) |
| `type` | Tabler `typography` | Typography leaf (showcase) |
| `shapes` | Tabler `triangle-square-circle` | Icons leaf (showcase) |

Dropped at the Tabler migration (unused in code, unreferenced in the Nexus): `circle-x` · `arrow-left-right` · `key-round` · `lock` · `log-in` · `panel-left`.
