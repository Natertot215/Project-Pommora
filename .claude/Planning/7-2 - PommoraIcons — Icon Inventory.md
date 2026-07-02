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

The immediate-register set, mapped to what each naturally replaces. Tabler ids as Nathan gave them — verify exact ids against `@tabler/icons-react` at registration (e.g. Tabler spells clock faces with digits, and its hash glyph may be `hash` rather than `hashtag`).

**Stroke**: every Tabler registration renders at **1.75** stroke (Tabler ships 2 by default) — a PommoraIcons registry default, set once at the seam, not per-callsite.

**Sizing**: mechanically identical across libraries — both draw on the 24×24 grid, both React packages take the same `size`/`stroke` props and follow `currentColor`, so the seam's `1em`/size-token mechanism carries over untouched. Optical density differs per-glyph (Tabler tends to fill its grid slightly fuller); the 1.75 stroke is the compensator, final judgment by eyeball at build.

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
| `minus` | `minus` | status in-progress |
| `hashtag` | `hash` | Number property type |
| `circle-plus` | `square-plus` — shape shift, square→circle | add-banner button |
| `copy` | registry `copy` (uncalled today — kept registered for future duplicate actions) | — |
| `file-text` | `file-text` — verified, same id in Tabler | THE default page icon |
| `file-import` | `import` — bare `import` doesn't exist in Tabler; `file-import` verified | File property type |

**Keep Lucide** — Nathan's ratified keeps; PommoraIcons is officially a mixed registry:

- `gallery-vertical-end` — Collection rows (reviewed the four Tabler candidates; Lucide's wins)
- `folder-closed` / `folder-open` — stays Lucide (supersedes the earlier plan of Tabler `folder`/`folder-opened` behind custom CSS edits — that plan is dropped)
- `log-out` — the sidebar in-out toggle (collapse renders flipped, expand plain — App.tsx; the census's "logout button" label was wrong, this is the sidebar affordance)

**First-party custom glyphs**: `square-dashed` gets drawn in-house (no Tabler counterpart chosen; Nathan's call — "create our own"). Registry consequence: PommoraIcons hosts custom SVG components alongside `@tabler` ones in the same slot shape (24 viewBox · currentColor · the 1.75 stroke default), so a custom glyph is indistinguishable from a library one at the callsite.

**Register-on-day-one, no assignment yet** (Nathan wants them in immediately; callsites TBD): `chevron-compact-up` · `chevron-compact-down` · `heart` · `dots`. Same census discipline applies later — unassigned entries are how the dead-7 happened.

#### Remaining Gaps — In-Use Icons Still Needing a Pick

Nathan's blanket call: **"the rest can be Tabler."** Everything below defaults to its Tabler equivalent, exact ids resolved against the installed package at registry build (likely renames: `house`→`home`, `type`→`typography`; `server` and `palette` should carry over; `shapes` needs a nearest-fit call):

- `server` (ViewPane Properties) · `house` (Homepage saved node) · showcase trio (`palette` · `type` · `shapes`)

Only two genuinely open calls remain — both semantic, not library:

1. `link-2` — Relation/Connections glyph — **fork**: Icons.md deliberately separates it from `link` (url); picking only `link` collapses the distinction. Needs its own Tabler glyph or an explicit merge call.
2. **Calendar fork** — one pick (`calendar-month`), two current slots: `calendar` (saved node) and `calendar-days` (Date & Time property type). One glyph for both, or split?

**The dead 6** (`circle-x`, `arrow-left-right`, `key-round`, `lock`, `log-in`, `panel-left`): no picks given — consistent with dropping at migration, pending the Nexus frontmatter grep. (`copy` was in this set until Nathan's pick rescued it.)
