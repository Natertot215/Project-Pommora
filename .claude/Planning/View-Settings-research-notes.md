### View Settings — Research Notes

> Captured 2026-05-25 from two parallel research agents. Feed these findings into the v0.3.1.x Storage View Redesign spec when it gets written.

#### Source

- **Notion UX teardown** — investigated open trigger, submenu reveal pattern, dismiss, animation, accessibility, mobile vs desktop, visual chrome.
- **SwiftUI / macOS Tahoe primitives** — investigated container choice (Menu vs Popover vs NSPopover), submenu navigation (NavigationStack inside popover), toolbar placement, SF Symbol HIG, hover/press states, dismiss behavior, keyboard nav. Used Context7 + Apple docs + WWDC25 sessions.

Full agent transcripts at `/private/tmp/claude-501/.../ac9b473b57fa48ffd.output` + `ae240bef611192b83.output` (transcripts ephemeral — extract digest below).

#### Locked decisions from this research

##### Container + placement

- **Container = SwiftUI `.popover(isPresented:)` on a `Button` inside a `ToolbarItem(.primaryAction)`**. NOT `Menu` (flat-only, no rich content). NOT `NSPopover` via representable (overkill).
- **WWDC25 #323 confirms toolbar-anchored popovers auto-inherit Liquid Glass** on Tahoe. Do NOT manually apply `.glassEffect()` / `.background(.regularMaterial)`. Let the system handle it. If shared-glass capsule grouping is unwanted, set `.sharedBackgroundVisibility(.hidden)` on the ToolbarItem.
- **Icon = `slider.horizontal.3`** (Apple HIG: per-view configurator, mirrors Photos library options / Music now-playing settings). NOT `gearshape` (reserved for app-wide Settings). NOT `line.3.horizontal.decrease.circle` (Mail filter / App Store sort — too specific).
- **Placement adjacent to Inspector toggle**, trailing edge. Use `ToolbarSpacer` to separate from preceding items.

##### Submenu navigation

- **Use `NavigationStack` inside the popover** for push/pop with back chevron + section title. WWDC25-validated pattern; mirrors Notion's exact UX. `@Environment(\.dismiss)` pops the stack; at root, dismisses the popover.
- **Alternatives ranked + rejected:**
  - DisclosureGroups — fine for 2-3 short editors but Filter rules grow unpredictably; popover resize is jittery.
  - Custom view-state switch with `.transition(.slide)` — reimplements what NavigationStack gives free.
  - Nested popovers — Apple avoids; spatially confusing on macOS.
- **Width: fixed `.frame(width: 280)` minimum**; height grows per-pane (NavigationStack animates the height transition).
- **Animation:** Notion uses ~180-220ms horizontal slide on push/pop with a subtle fade. Popover open is a brief scale-from-anchor + fade (~120ms). SwiftUI `.smooth(duration: 0.2)` matches.

##### Dismiss + keyboard

- **Outside-click dismisses the whole popover** (SwiftUI default — keep transient). Submenu pushes happen INSIDE the popover so the popover stays open through navigation.
- **ESC pops one level**, dismisses at root. Cmd+[ navigates back inside NavigationStack (automatic).
- **`.interactiveDismissDisabled(true)`** would make the popover non-transient — only needed if we want to require explicit dismiss.

##### Row states

- **Use `Button(action:) { HStack { ... } }.buttonStyle(.plain)` inside `List`/`Form`**. List rows give hover highlight + selection chrome for free via Liquid Glass — don't hand-roll `.onHover`.
- For non-list rows: `.buttonStyle(.borderless)` + `.contentShape(Rectangle())`.

##### Apple first-party references

- **Reminders' "Show More" sheet** (Sort By / Show / Group By) — closest first-party analog to what we're building.
- **Calendar's calendar-set picker** — popover with nested choices.
- **Numbers' table format menus** — Menu-style flat nav (we're going deeper, hence Popover).
- **Finder's "Show View Options"** — utility window, different pattern, not directly applicable.

#### Notion menu structure — adapted to Pommora

Source: Notion's "View settings" menu (post-2025 redesign, July 2025 — slider/equalizer icon replaced the older `•••` overflow).

```
View settings                                    [×]
─────────────────────────────────────────────────────
[⊞]   Table                                       ⓘ     ← view icon + editable name + info
─────────────────────────────────────────────────────
☰    Layout                              Table   >    ← v0.3.x: Table only; v0.5.0 unlocks
👁   Property visibility                     3   >    ← count badge
≡    Filter                                  2   >    ← count badge
↕    Sort                                    1   >    ← count badge
⊟    Group                                       >    ← OPEN Q: ship in v0.3.1.x or defer to v0.5.0?
─────────────────────────────────────────────────────
DATA SOURCE SETTINGS                                  ← subhead
☰    Edit properties                            >    ← schema-wide CRUD (deepest stack)
```

**Pommora-specific divergences:**

- **No `Source` row** — Notion's data-source decoupling doesn't apply to Pommora (the container IS the data source).
- **`Edit properties` lives inside this menu**, not as a separate toolbar button. Per locked decision: single consolidated configurator. (Original ask called for two separate buttons; user revised to consolidate.)
- **Property Visibility row UX = click-to-toggle with strikethrough** when muted. No eye icon. Drag handle on left for reorder.
- **Layout row in v0.3.x** = "Table" only, other rows disabled/checked. Forwards-compat slot for v0.5.0 board/list/cards/gallery.
- **No Conditional Color, Sub-items, Copy link to view, Automations, AI Autofill, Archived pages, More settings, Manage data sources, Lock views** — Notion-specific or deferred.

#### Storage model

Add to all 4 sidecars (`_pagetype.json`, `_pagecollection.json`, `_itemtype.json`, `_itemcollection.json`):

```json
"views": [
  {
    "id": "view_<ulid>",
    "name": "Table",
    "icon": "tablecells",
    "type": "table",
    "visible_properties": ["prop_<ulid>", "_status", ...],
    "hidden_properties": ["prop_<ulid>", ...],
    "sort": [{ "property": "prop_<ulid>", "direction": "asc" }],
    "filter": { "match": "all", "rules": [...] },
    "group": null
  }
]
```

- Single entry per container today. Multiple at v0.5.0 (saved view tabs).
- `schema_version` bump → idempotent migration creates default `views[0]` from current state.
- IndexUpdater paths unaffected — view config is presentation-only, not indexed.
- Each container is INDEPENDENT (decision locked): Page Type, Page Collection, Item Type, Item Collection each carry their own `views[]`. Configuring one doesn't change the other.

#### Detail-view chrome (everything BELOW the toolbar)

```
┌──────────────────────────────────────────────────┐
│ Collection                                       │   ← title only
│                                                  │
│ [table content]                                  │
└──────────────────────────────────────────────────┘
```

**No tabs row, no chip strip, no inline view-config.** All view interaction lives in the toolbar button. At v0.5.0, when saved views ship, a tabs row appears below the title — that's the only future visual change.

#### Recommended SwiftUI skeleton

```swift
// Toolbar attachment
.toolbar {
    ToolbarSpacer()
    ToolbarItem(placement: .primaryAction) {
        Button {
            showViewSettings = true
        } label: {
            Label("View Settings", systemImage: "slider.horizontal.3")
        }
        .popover(isPresented: $showViewSettings, arrowEdge: .top) {
            ViewSettingsPopover()
                .frame(width: 280)
        }
    }
}

// Popover content with submenu navigation
struct ViewSettingsPopover: View {
    @State private var path = NavigationPath()

    var body: some View {
        NavigationStack(path: $path) {
            List {
                NavigationLink("Layout",            value: Pane.layout)
                NavigationLink("Property visibility", value: Pane.properties)
                NavigationLink("Filter",            value: Pane.filter)
                NavigationLink("Sort",              value: Pane.sort)
                NavigationLink("Group",             value: Pane.group)
                Divider()
                NavigationLink("Edit properties",   value: Pane.editProperties)
            }
            .listStyle(.inset)
            .navigationDestination(for: Pane.self) { pane in
                pane.editor   // Each pane returns its own editor view
            }
        }
    }
}
```

Inside each `pane.editor`, use `@Environment(\.dismiss)` to pop back to the root list.

#### Delivery slices (Approach B — patch-series drip, user-picked)

| Ship | Scope | Standalone-green outcome |
|---|---|---|
| **v0.3.1** | Toolbar button + popover shell + NavigationStack scaffold + `views[]` storage + migration + Property Visibility pane + Layout pane (Table placeholder) | Button appears; show/hide/reorder properties works; deeper panes greyed pending |
| **v0.3.1.1** | Edit Properties pane (extract `PropertyEditor` from `VaultSettingsSheet` / `TypeSettingsSheet`; route from popover; backport into sheets) | Schema CRUD reachable from popover; sheets internally unified |
| **v0.3.1.2** | Sort pane | Sort rules editable from popover; column-header click syncs |
| **v0.3.1.3** | Filter pane | Filter rules editable; `IndexQuery` wired |
| **v0.3.1.4** | Group pane (or defer to v0.5.0) | Grouped Table-mode rendering — OPEN Q |

Semantic gripe noted but accepted: Framework.md calls patches "touch-ups," and these are feature work. User accepted the drip framing.

#### Open questions for the spec

1. **Group pane** — ship in v0.3.1.x at all, or defer to v0.5.0 (it's most useful for Board view which is v0.5.0)?
2. **Filter operators in v0.3.x** — minimum viable set? Suggest `equals` / `not-equals` / `contains` / `empty` / `not-empty`. OR-grouped filters deferred to v0.5.0+.
3. **View tabs row** — hide entirely until ≥2 views (recommended), or show a single "Table" tab placeholder now?
4. **Title placement** — keep large title at top of detail view, or move to window toolbar's title slot?

#### UIX rule lock — tables get NO vertical column borders

Forward-applies to ALL storage detail views + v0.5.0 view-type renderings. Notion-flat aesthetic (vs Finder's column-separated style). Implementation paths:

1. **NSViewRepresentable wrapping NSTableView** with `gridStyleMask` explicitly cleared + custom header background — preserves native sort/resize/selection at cost of bridging code. **Recommended.**
2. Custom flat Table in pure SwiftUI via `LazyVGrid` or `Grid` — full styling control but loses native column-resize handles + re-implements sort indicators.
3. NSTableView runtime appearance override — hacky `.background { NSViewIntrospectionView }` shim.

#### Sources cited by research agents

- WWDC25 Session 323 — "Build a SwiftUI app with the new design" (`developer.apple.com/videos/play/wwdc2025/323/`)
- Apple Developer docs — `popover(isPresented:attachmentAnchor:arrowEdge:content:)`, `interactiveDismissDisabled(_:)`, `Environment(\.dismiss)`, SF Symbols
- swiftwithmajid.com — "Glassifying toolbars in SwiftUI" (July 2025)
- Notion help — "Views, filters, sorts & groups", "Databases reimagined, what's changed"
- The Organized Notebook — "Notion's New UI Design Update (June 2025)"
- Simone Smerilli — "All the features of Notion databases"

#### Existing-code touch (when spec lands)

- **`PropertyChip` / `PropertyCheckbox` / `ChipDropdown`** (shipped 2026-05-25, `Pommora/Properties/Chips/`) — reused for property previews + value pickers inside Filter / Sort UIs.
- **`VaultSettingsSheet` / `TypeSettingsSheet`** — kept for sidebar right-click admin path; internals migrate to host extracted `PropertyEditor` component (shared with popover's Edit Properties pane).
- **`PropertyEditor`** — NEW extracted component; the per-property editor used in both surfaces.
- **`PropertiesPulldown`** — already removed; this design supersedes it for Pages.
- **`PropertyPanel`** — unchanged (host-agnostic; targets Item Window inspector).
- **`SchemaConflictDialog` / `PropertyIDMigration` / `DualRelationCoordinator` / `IndexUpdater`** — untouched; live below the UI layer.
