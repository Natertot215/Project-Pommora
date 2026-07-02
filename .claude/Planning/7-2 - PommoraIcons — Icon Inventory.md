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

#### Ratified Tabler Picks — Nathan

The immediate-register set, mapped to what each naturally replaces. Tabler ids as Nathan gave them — verify exact ids against `@tabler/icons-react` at registration (e.g. Tabler spells clock faces with digits).

| Tabler pick | Replaces (current) | Surface |
| --- | --- | --- |
| `plus` | `plus` | every add button |
| `check` | `check` (+ the MarkdownPM checkbox ✓ path) | status done · checkboxes · pickers |
| `x` | `x` | chip dismiss |
| `chevron-right` | `chevron-right` (+ the fold-chevron mask path) | twisties · menus · editor folds |
| `chevron-left` | `chevron-left` | toolbar Back · menu back-row |
| `chevron-up` / `chevron-down` | `chevron-up` / `chevron-down` | footer + accordion disclosure |
| `dots-vertical` | `ellipsis-vertical` | showcase Menu leaf |
| `adjustments-horizontal` | `sliders-horizontal` | toolbar Settings |
| `link` | `link` | Link (url) property type |
| `square-check` | `square-check` | Checkbox property type |
| `layout-dashboard` | `layout-dashboard` | ViewPane Layout |
| `eye` | `eye` | ViewPane Visibility |
| `eye-closed` | staged `eye-off` | Visibility hidden-state |
| `calendar-month` | `calendar` and/or `calendar-days` — **fork, see Gaps** | saved node · Date property type |
| `tag` | `tag` | showcase Chips leaf |
| `grip-vertical` | `grip-vertical` (+ the editor grip mask) | row/block drag grips |
| `grip-horizontal` | `grip-horizontal` | editor table column grip |
| `map` | `map` | toolbar Navigation |
| `clock-hour-three` | `clock` | Recents saved node |
| `layout-sidebar-right` | `panel-right` | toolbar Inspector |
| `circle-dashed` | `circle-dashed` | status upcoming · select placeholder |
| `layout-grid` | `layout-grid` | sidebar context-tier headers |
| `stack-2` | `layers` | ViewPane Group · showcase Glass leaf |
| `filter-2` | `list-filter` | ViewPane Filter |
| `arrows-up-down` | `arrow-up-down` | ViewPane Sort |

**Conditional**: Tabler `folder` + `folder-opened` replace `folder-closed`/`folder-open` — only after Nathan's custom CSS edits to them; hold Lucide's pair until those edits are ratified.

**Register-on-day-one, no assignment yet** (Nathan wants them in immediately; callsites TBD): `chevron-compact-up` · `chevron-compact-down` · `heart` · `dots`. Same census discipline applies later — unassigned entries are how the dead-7 happened.

#### Remaining Gaps — In-Use Icons Still Needing a Pick

Ordered by weight; these have no Tabler assignment yet:

1. `file-text` — **THE default page icon, heaviest icon in the app** (sidebar, table titles, autocomplete)
2. `square-dashed` — unselected state · profile placeholder · the DashIcon pending-glyph
3. `minus` — status in-progress (the status trio is otherwise covered)
4. `hash` — Number property type
5. `import` — File property type
6. `link-2` — Relation/Connections glyph — **fork**: Icons.md deliberately separates it from `link` (url); picking only `link` collapses the distinction. Needs its own glyph or an explicit merge call.
7. **Calendar fork** — one pick (`calendar-month`), two current slots: `calendar` (saved node) and `calendar-days` (Date & Time property type). One glyph for both, or split?
8. `server` — ViewPane Properties entry
9. `gallery-vertical-end` — sidebar Collection rows (no obvious 1:1 Tabler twin; deliberate choice needed)
10. `house` — Homepage saved node
11. `square-plus` — add-banner button
12. `log-out` — close-nexus button
13. Showcase trio — `palette` · `type` · `shapes` (lowest stakes)

**The dead 7** (`circle-x`, `copy`, `arrow-left-right`, `key-round`, `lock`, `log-in`, `panel-left`): no picks given — consistent with dropping at migration, pending the Nexus frontmatter grep.
