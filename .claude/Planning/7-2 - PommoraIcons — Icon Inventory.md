## PommoraIcons — Icon Inventory

Scoping census for the Lucide→Tabler migration (PommoraIcons registry). Every icon callsite across Pommora + MarkdownPM, swept by three agents and hand-verified against the code. The app's full named-icon vocabulary is **49 names**: 38 registry entries + 11 stray Lucide components imported outside the seam. Three additional glyphs are Lucide *path data* baked into CSS/DOM, and 7 registry entries are dead in code.

#### The Three Populations

**1 — The Registry** (`design-system/symbols/index.tsx`, mirrored by `symbols/Symbols.md`): 38 icons keyed by lucide id, rendered via the `Icon` component (currentColor + size tokens — Tabler's React package speaks the same props dialect). ~85% of all renders route through it.

**2 — Strays** — direct `lucide-react` imports bypassing the seam (5 files). These must fold into the registry during the migration regardless of icon set:

| File | New-to-registry components | Registry duplicates also imported |
| --- | --- | --- |
| `Components/Detail/PropertyTypes.tsx:1` | Hash, SquareCheck, CalendarDays, Link, Import, Link2 | CircleDashed |
| `Components/Detail/ViewPane.tsx:2` ⚠ parallel session in flight | Server, Eye, LayoutDashboard, ListFilter | ChevronRight, Layers, ArrowUpDown |
| `Components/Detail/PropertiesPane.tsx:2` | — | ChevronRight, Plus |
| `design-system/components/menu/Menu.tsx:2` | — | ChevronLeft |
| `MarkdownPM/Tables/TableView.tsx:3` | GripHorizontal | GripVertical |

`eye-off` is staged in `Features/Icons.md` (Visibility hidden-state) but not in code yet — reserve it a slot.

**3 — Hidden Lucide DNA** — Lucide path data hardcoded outside any import; a Tabler pass must redraw these or route them through the registry, or the editor keeps Lucide shapes forever:

| Glyph | Where | Mechanism | Lucide source |
| --- | --- | --- | --- |
| Fold chevron | `MarkdownPM/Styles.css:6` (`--fold-chevron-mask`) | data-URI mask | `chevron-right` path (`m9 18 6-6-6-6`) |
| Block/quote/callout grip | `MarkdownPM/Styles.css:9` (`--grip-glyph`) | data-URI mask | `grip-vertical` circles |
| Checked checkbox ✓ | `MarkdownPM/editor/decorations.ts:59` | innerHTML SVG | `check` path (`M20 6 9 17l-5-5`) |

Genuinely custom, out of migration scope: the I-beam caret cursor (`Carets.css`), PickerMenu's frame SVG, edge-lens filter SVGs.

#### Registry Census (38)

| Icon | Role | Weight |
| --- | --- | --- |
| `check` | status done · checkboxes · pickers — everywhere | Heavy |
| `chevron-right` | twisties, menu nav, disclosure | Heavy |
| `chevron-down` / `chevron-up` | footer + accordion disclosure | Heavy |
| `chevron-left` | toolbar Back · menu back-row | Heavy |
| `plus` | every add button | Heavy |
| `x` | chip dismiss | Heavy |
| `file-text` | THE default page icon (sidebar, table title cells, autocomplete) | Heavy |
| `folder-closed` / `folder-open` | container/Set default, folder-aware swap | Heavy |
| `circle-dashed` | status upcoming · select placeholder · property type | Heavy |
| `square-dashed` | unselected state · profile placeholder · the `DashIcon` pending-glyph fallback | Heavy |
| `minus` | status in-progress | Medium |
| `grip-vertical` | table row drag grip | Medium |
| `gallery-vertical-end` | sidebar Collection rows (`Sidebar.tsx:307`) | Medium |
| `layout-grid` | sidebar context-tier headers (`Sidebar.tsx:326,343`) | Medium |
| `house` / `calendar` / `clock` | saved sidebar nodes — hardcoded in MAIN (`main/readNexus.ts:316-318`) | Medium |
| `map` | toolbar Navigation segment | Medium |
| `sliders-horizontal` | toolbar Settings segment | Medium |
| `panel-right` | toolbar Inspector segment | Medium |
| `square-plus` | add-banner button | Light |
| `log-out` | close-nexus + showcase sidebar reveal (flipped) | Light |
| `ellipsis-vertical` | showcase Menu leaf | Showcase-only |
| `palette` / `type` / `shapes` / `tag` / `layers`* | showcase leaf nav | Showcase-only |
| `circle-x`, `copy`, `arrow-left-right`, `key-round`, `lock`, `log-in`, `panel-left` | **UNUSED in code** — drop candidates | Dead |

*`layers` + `arrow-up-down` also appear in ViewPane's stray imports (Group/Sort entries).

Dead-entry caveat: frontmatter icons are open-vocabulary, so Nathan's real Nexus could reference these names even though code doesn't — grep the Nexus for the 7 before dropping.

#### Name Flow & Compat Constraints

- **Stored user data**: page frontmatter `icon` + Collection/Set sidecar `icon` are free strings (`z.string().optional()` — `shared/schemas.ts:23,87`), validated only at render via `asIconName` → unknown names silently fall back (`file-text` / `folder-closed`). A renamed vocabulary therefore *degrades gracefully* but loses user choices — PommoraIcons keys should stay a superset of current names, or carry an old→new alias map.
- **Main process speaks icon names** (`readNexus.ts` saved-node trio) — the vocabulary crosses IPC; keep main + registry in one change.
- **Hardcoded name maps**: `statusCycle.ts` STATUS_GROUP_GLYPH (`circle-dashed`/`minus`/`check`), Toolbar `Segmented` entries, showcase LEAVES.
- **IconPicker is a stub** (`Components/IconPicker.tsx` — "coming from Figma"): no user-facing catalog exists yet. Migrate BEFORE it ships and the picker enumerates PommoraIcons from day one.
- **Tests** use deliberately-unregistered strings (`star`, `box`, `circle`, `doc`) to prove open-vocab passthrough — no migration action.
- **Deps**: `lucide-react ^1.18.0` pinned; no `@tabler/*` installed yet.
- **Docs in sync**: `symbols/Symbols.md` (registry mirror) + `Features/Icons.md` (semantic assignments) update with the registry.

#### Decision Queue — Explicit-Replacement Review Order

Ordered by visibility so preference calls land where they're seen most. Per icon the call is: Tabler equivalent / keep Lucide / drop.

1. **Skeleton chrome** (every screen): the chevron quad · `plus` · `x` · `check` · `ellipsis-vertical` · `grip-vertical` + `grip-horizontal`
2. **Identity row icons** (sidebar + tables): `file-text` · `folder-closed`/`folder-open` · `gallery-vertical-end` · `layout-grid` · `house` · `calendar` · `clock`
3. **Status + property glyphs**: `circle-dashed` · `minus` · `square-dashed` · property types (`hash`, `square-check`, `calendar-days`, `link`, `import`, `link-2`)
4. **Toolbar + panes**: `map` · `sliders-horizontal` · `panel-right` · view-settings set (`server`, `eye` (+staged `eye-off`), `layout-dashboard`, `list-filter`, `layers`, `arrow-up-down`) · `square-plus` · `log-out`
5. **MarkdownPM DNA**: fold chevron · grip glyph · checkbox check — redrawn as Tabler paths (or registry-routed) so the editor matches the app
6. **Showcase-only** (lowest stakes): `palette` · `type` · `shapes` · `tag`
7. **The dead 7**: drop at migration unless the Nexus grep finds stored uses
