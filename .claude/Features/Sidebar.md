### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Four top-level groups — a heading-less pinned (Saved) section at top, then Spaces, Topics, Vaults — replacing the earlier three-heading model. Locked selection language from v0.0 carries forward unchanged.

This doc covers structural shape + selection chrome + creation affordances. Per-entity routing rules live in `Domain-Model.md`; full SwiftUI implementation patterns + per-entity CRUD UI live in `// Planning//Contexts-Vaults-spec.md`.

---

#### Layout

```
[Sidebar]
  Homepage
  Calendar
  Recents
─ Spaces ───────────────────────
  ◉ Personal       [color/symbol]
  ◉ Academics
  ◉ Work
─ Topics ───────────────────────
  ▾ Academics      [tagged: red]
      CS 161
      Linear Algebra
  ▾ Productivity   [tagged: blue + green]   ← multi-Space topic
      GTD method
      Time-blocking
  ▸ Side Projects  [tagged: blue]
─ Vaults ───────────────────────
  ▾ Documents
      📄 README                    ← Page directly in vault root
      ▾ Assignments
          📄 History WS
          📄 Math WS
      ▾ Reports
          📄 2026 H1
─ ...
```

No always-visible "+ New" buttons — creation is **right-click first**, complemented by **hover-only `+` buttons** on section headings (visible on hover, hidden at rest). The fuller discoverability layer lands separately via quick-capture (Cmd+Shift+N / menu-bar; pre-v1).

---

#### Section-by-section

##### Pinned (top — no heading)

Three fixed entries — `Homepage`, `Calendar`, `Recents` — render at the very top of the sidebar **without a heading**. The underlying `Section` wrapper persists structurally (for the future user-pinning feature; **"Saved" becomes the section identifier for pinned pages once that ships**) but no text label appears above the rows.

Stored in `.nexus/saved-config.json`:

```json
{
  "schemaVersion": 1,
  "items": [
    { "key": "homepage", "label": "Homepage" },
    { "key": "calendar", "label": "Calendar" },
    { "key": "recents",  "label": "Recents" }
  ]
}
```

Each item's `key` is fixed in code; `label` is user-renamable via Settings → Saved Section.

- `homepage` opens the Homepage singleton entity (see `Homepage.md`)
- `calendar` opens a calendar view over Agenda items + EventKit-mirrored system events (see `Agenda.md`)
- `recents` shows recently-opened tabs (lightweight v1 if tab state tracking is available, placeholder otherwise)

**User-pinning of arbitrary entities to this section is the planned post-v1 enhancement** — at which point the section gets its "Saved" heading and a "+" affordance for pinning, and the three default entries become movable / removable.

##### Spaces

Flat rows — no chevron, no children disclosure. "Spaces are items, not folders" in the sidebar.

Each Space carries a `color` (one of 9 Notion-palette colors) and optional `icon` (SF Symbol). The row shows the color and/or icon as a visual indicator. The visual mode is settable per Nexus via `tier-config.json.tagging_style`:

- `"color"` — colored dot (default)
- `"symbol"` — SF Symbol icon
- `"both"` — both shown side by side

Clicking a Space opens its composed-blocks page in the main pane.

##### Topics

Chevron-disclosure rows. Each Topic expands to show its file-nested Sub-topics as leaf rows.

Topic rows carry **tagging indicators inherited from their parent Space(s)**. Multi-Space Topics show multiple indicators side by side (e.g. blue + green dots for a Topic that belongs to both Personal and Work). The tagging visual respects the `tagging_style` setting above.

Clicking a Topic opens its composed-blocks page. Clicking a Sub-topic opens its composed-blocks page.

##### Vaults

Chevron-disclosure rows. **Each Vault discloses both Pages (directly in the vault root) AND Collection sub-folders** as children. Each Collection in turn discloses its Pages as children. Pages render with the `doc.text` icon; Collections render with the `folder` icon.

Items, Agenda items, and Events do **NOT** appear in the sidebar — they live exclusively in the detail-pane Tables (`VaultDetailView` and `CollectionDetailView`). The sidebar tree shows the **structural / Page-shaped** view; the detail pane shows the **data view** with all content types.

Vaults don't display tagging — they're operational, not categorical. Clicking a Vault opens its default detail view (hierarchical Table over its Collections + content). Clicking a Collection opens a view scoped to that Collection. Clicking a Page is a no-op until the Markdown editor lands (v0.2.7); structurally visible in the sidebar but not openable yet.

---

#### Creation affordance: right-click context menus, scoped by cursor location

The canonical creation pattern across the sidebar. No always-visible "+ New" buttons; the user right-clicks the relevant heading / row / area and gets a context menu whose "New X" options auto-scope to that location's parent. Section headings also expose a hover-only `+` complement — see "Discoverable creation" below.

| Right-click target | Scoped creation options | Other context menu items |
|---|---|---|
| Spaces section area (empty / on heading) | New Space | — |
| Topics section area | New Topic | — |
| Vaults section area | New Vault | — |
| Space row | New Space | Rename / Change Color / Change Icon / Delete |
| Topic row (when disclosed) | New Sub-topic *(in THIS Topic)* | Rename / Edit Parents / Change Icon / Delete |
| Sub-topic row | — | Rename / Change Icon / Delete |
| Vault row | New Vault + New Collection + New Page *(scoped to THIS Vault)* | Rename / Change Icon / Delete |
| Collection row | New Page *(in THIS Collection)* | Rename / Delete |
| Page row | — | Rename / Delete (Page editor coming v0.2.7) |

The location scoping is load-bearing UX — right-clicking on a specific Collection produces "New Page" that creates IN that Collection, not at the section level. This pattern matches macOS Finder (right-click in a folder → "New Folder" creates a sibling there) and Notion / Obsidian sidebar conventions.

#### Discoverable creation: hover-icon "+" + quick-capture

Section headings expose a **hover-only `+` button** (visible on hover, hidden by default) as a discoverable complement to the right-click pattern. Clicking it opens the same creation flow as the section's primary right-click target ("+ on Spaces" → New Space; "+ on Topics" → New Topic; "+ on Vaults" → New Vault). The hover-only treatment keeps the sidebar visually quiet at rest while remaining discoverable for users unfamiliar with right-click conventions.

The fuller global creation path lands later via **quick-capture** (Cmd+Shift+N or menu-bar capture; before v1) — quick-capture is expected to absorb most CRUD entry traffic across the app, not just sidebar entry.

---

#### Selection language (locked from v0.0)

- Fill: `Color.gray.opacity(0.10)`, 6pt continuous corner radius, inset **10.5pt horizontal + 2pt vertical** from row edges
- Foreground: selected icon + text shift to `Color.accentColor`
- **Text** gets `.brightness(0.10)` to lift the accent over the fill; **icon** gets no brightness modifier
- Row content padding: **4pt leading, 0 trailing, 2pt vertical**
- Icons use `.symbolRenderingMode(.monochrome)` so `.foregroundStyle(.accentColor)` applies
- Implementation in `Pommora/Pommora/Sidebar/SidebarView.swift` — custom `SelectableRow` with `SelectionTag` enum binding (was `String?` in v0.0)

Rationale and trade-offs (NSTableView ignoring SwiftUI tint, brightness-composition consistency across `Section` vs `DisclosureGroup` vs direct-`List`, fill-not-desaturating-on-window-unfocus) — preserved from the original Sidebar.md spec; see git history if relevant.

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` on the row, or `.listRowInsets(EdgeInsets(...))`. Use for nesting/grouping (Page rows inside a Collection, Sub-topics inside a Topic disclosure)
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between the chevron view and the `Label`. Only applies when the chevron is hand-rolled (not when SwiftUI's `DisclosureGroup` renders it internally)
- **Icon-to-text gap inside a row** — internal to `Label`, controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }` instead of `Label`. `HStack(spacing:)` on the outer row does NOT control this
- **Chevron-column reservation across flat rows** — implicit, triggered by `DisclosureGroup`'s presence in a `.listStyle(.sidebar)` List. Not directly user-controllable; only suppressible by dropping `DisclosureGroup` and hand-rolling expansion

---

#### Section ordering

User-reorderable in v1.x (drag headings up/down). Initial-boot order is **Pinned (heading-less) / Spaces / Topics / Vaults** as shown above. Order persists per Nexus in `.nexus/state.json` (alongside other sidebar UI state).

---

#### Inline-chevron experiment (Finder pattern)

Captured intent from v0.0 spike (not committed): hand-rolling chevron + member ForEach in Vault Collection rows (dropping `DisclosureGroup` for that section) gives Finder-style flush-left flat rows. Verified working in v0.0. Revisit after the v0.2 Pages-under-Vaults disclosure has been observed against real data — the deeper Vault → Collection → Page chain may want flush-left treatment to manage indentation density.

---

#### Open until content lands

Hover treatment, keyboard navigation, focus-ring styling, row-density tuning, `tagging_style` default, and Page-row icon hover behavior — all resolve once real content is in the sidebar and Tahoe rendering can be observed. Captured intent (not commitment): a third hovered state subtler than the selected fill.
