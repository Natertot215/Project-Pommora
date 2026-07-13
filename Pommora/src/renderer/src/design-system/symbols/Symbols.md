## Symbols — curated icon set

Pommora's React icons come from **Lucide** ([lucide.dev/icons](https://lucide.dev/icons)) — the curated registry in `index.tsx`, mirrored by this file. Add a name + purpose here, then import the Lucide component and register it. Only listed icons ship in the bundle. Keys are the app's own vocabulary (mostly the lucide.dev name); a key renames when its glyph changes identity, never for library spelling.

**Tabler stays a second source we can pull from.** `@tabler/icons-react` remains installed — to use one, import its `Icon*` component and add the entry (it renders through the same seam; Lucide and Tabler both default to a stroke of 2, so they sit at the same weight with no override). Lucide is the default; Tabler is a per-icon opt-in. Custom `customGlyphs` svgs match that weight too.

**To use one in code:** `import { Icon } from '@renderer/design-system/symbols'` → `<Icon name="folder-closed" size={15} />`.

| Name | Used for |
|---|---|
| `house` | Homepage |
| `calendar` | Calendar saved node · Date & Time property type |
| `clock` | Recents |
| `gallery-vertical-end` | Collection rows |
| `folder-closed` / `folder-open` | Collection/Set closed / open |
| `file-text` | Page (the default page icon) |
| `layout-grid` | Context tiers (Area / Topic / Project) · Context property type |
| `check` | Checkbox chip · status Done glyph |
| `circle-dashed` | Select chip placeholder · status Upcoming · Status property type |
| `minus` | Status In-Progress glyph |
| `tags` | Multi-Select property type |
| `sliders-horizontal` | Trio Button, Settings |
| `chevron-left` / `chevron-right` / `chevron-up` / `chevron-down` | Twisties · menus · disclosure · toolbar Back/Forward |
| `map` | Trio Button, Navigation |
| `x` | Chip dismiss |
| `plus` | Add buttons |
| `square-plus` | Add Banner |
| `ellipsis-vertical` | Property editor ⋮ · Menu leaf (showcase) |
| `dots` | Registered, unassigned |
| `tag` | Chips leaf (showcase) |
| `send` | Select property type |
| `panel-right` | Trio Button, Inspector toggle |
| `square-dashed` | Unselected state · profile placeholder |
| `copy` | Registered, unassigned (future duplicate actions) |
| `arrow-up-down` | ViewPane Sort |
| `log-out` | Sidebar collapse/expand (flipped = collapse, normal = expand) |
| `heart` | Registered, unassigned |
| `hash` | Number property type |
| `square-check` | Checkbox property type |
| `import` | File property type |
| `link` | Link (url) property type |
| `link-2` | Context/Relation property type · Connections |
| `server` | ViewPane Properties |
| `eye` / `eye-off` | ViewPane Visibility (shown / hidden) |
| `layout-dashboard` | ViewPane Layout |
| `list-filter` | ViewPane Filter |
| `layers` | ViewPane Group · Glass leaf (showcase) |
| `grip-vertical` / `grip-horizontal` | Drag grips (table rows · editor table columns/rows) |
| `palette` | Colors leaf (showcase) |
| `scaling` | Block Scale row (per-tile zoom) |
| `type` | Typography leaf (showcase) |
| `shapes` | Icons leaf (showcase) |
| `lock` | View-config locks (Nathan-supplied solid glyph — custom, drawn in `customGlyphs`) |
