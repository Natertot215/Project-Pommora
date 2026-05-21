### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Four top-level groups — a heading-less pinned (Saved) section at top, then Spaces, Topics, Vaults. Locked selection language from v0.0 carries forward.

Per-entity routing rules → `Domain-Model.md`; SwiftUI implementation + CRUD UI → `// Planning//Contexts-Vaults-spec.md`.

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

Three fixed entries — `Homepage`, `Calendar`, `Recents` — render at the top **without a heading**. The underlying `Section` wrapper persists for the future user-pinning feature (gains the "Saved" header when that ships).

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

- `homepage` opens the Homepage singleton (see `Homepage.md`)
- `calendar` opens a calendar view over Agenda items + EventKit-mirrored events (see `Agenda.md`)
- `recents` shows the NavDropdown's Recents store as a full-frame view; ships at v0.6.0 per `NavDropdown.md`

**User-pinning of arbitrary entities is post-v1** — section gets its "Saved" heading + "+" affordance then; the three defaults become movable / removable.

##### Spaces

Flat rows — no chevron, no children disclosure. Each Space carries a `color` (one of 9 Notion-palette colors) and optional `icon` (SF Symbol). Visual mode settable per Nexus via `tier-config.json.tagging_style`: `"color"` (dot, default), `"symbol"` (SF Symbol), `"both"`. Clicking opens its composed-blocks page.

##### Topics

Chevron-disclosure rows. Each Topic expands to show file-nested Sub-topics as leaf rows.

Topic rows carry **tagging indicators inherited from parent Space(s)**. Multi-Space Topics show multiple indicators side by side (e.g. blue + green dots for a Topic that belongs to both Personal and Work). Clicking a Topic or Sub-topic opens its composed-blocks page.

##### Vaults

Chevron-disclosure rows. **Each Vault discloses both Pages (in the vault root) AND Collection sub-folders** as children. Each Collection discloses its Pages. Pages use the `doc.text` icon; Collections use `folder`.

Items, Agenda items, and Events do **NOT** appear in the sidebar — they live in detail-pane Tables (`VaultDetailView` / `CollectionDetailView`). Sidebar shows the structural / Page-shaped view; detail pane shows the full data view.

Vaults don't display tagging (operational, not categorical). Clicking a Vault opens its hierarchical Table; Collection opens a scoped view; Page opens in the main detail pane via the TextKit-2 editor (shipped v0.2.7.0).

---

#### Creation affordance: right-click context menus, scoped by cursor location

Canonical creation pattern. No always-visible "+ New" buttons; right-click the relevant heading / row / area and a context menu's "New X" options auto-scope to that location's parent. Section headings also expose a hover-only `+` complement — see below.

| Right-click target | Scoped creation options | Other context menu items |
|---|---|---|
| Spaces section area (empty / on heading) | New Space | — |
| Topics section area | New Topic | — |
| Vaults section area | New Vault | — |
| Space row | New Space | Rename / Change Color / Change Icon / Delete |
| Topic row (when disclosed) | New Sub-topic *(in THIS Topic)* | Rename / Edit Parents / Change Icon / Delete |
| Sub-topic row | — | Rename / Change Icon / Delete |
| Vault row | New Vault + New Collection + New Page *(scoped to THIS Vault)* | **Vault Settings…** (v0.3.0; opens VaultSettingsSheet — schema editor + sort + property visibility) / Rename / Change Icon / Delete |
| Collection row | New Page *(in THIS Collection)* | Rename / Delete |
| Page row | — | Rename / Delete (Page editor shipped v0.2.7.0) |

Location scoping is load-bearing — right-clicking on a Collection produces "New Page" that creates IN that Collection. Matches Finder + Notion + Obsidian.

#### Discoverable creation: hover-icon "+" + quick-capture

Section headings expose a **hover-only `+` button** as a discoverable complement, opening the section's default new sheet. Keeps the sidebar visually quiet at rest while remaining discoverable.

Fuller global creation path lands via **quick-capture** (Cmd+Shift+N or menu-bar capture; pre-v1) — expected to absorb most CRUD entry traffic.

---

#### Selection language (locked from v0.0)

- Fill: `Color.gray.opacity(0.10)`, 6pt continuous corner radius, inset **10.5pt horizontal + 2pt vertical**
- Foreground: selected icon + text shift to `Color.accentColor`
- **Text** gets `.brightness(0.10)`; **icon** gets no brightness modifier
- Row content padding: **4pt leading, 0 trailing, 2pt vertical**
- Icons use `.symbolRenderingMode(.monochrome)` so `.foregroundStyle(.accentColor)` applies
- Implementation in `Pommora/Pommora/Sidebar/SidebarView.swift` — custom `SelectableRow` with `SelectionTag` enum binding

Rationale / trade-offs preserved in git history.

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` or `.listRowInsets(EdgeInsets(...))`. Use for nesting/grouping.
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between chevron and `Label`. Only when the chevron is hand-rolled.
- **Icon-to-text gap inside a row** — internal to `Label`; controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }`. Outer `HStack(spacing:)` does NOT control this.
- **Chevron-column reservation across flat rows** — implicit from `DisclosureGroup` in a `.listStyle(.sidebar)` List. Only suppressible by hand-rolling expansion.

---

#### Section ordering

User-reorderable in v1.x (drag headings up/down). Initial-boot order is **Pinned (heading-less) / Spaces / Topics / Vaults** as shown above. Order persists per Nexus in `.nexus/state.json` (alongside other sidebar UI state).

---

#### Inline-chevron experiment (Finder pattern)

Captured intent from v0.0 spike (not committed): hand-rolling chevron + member ForEach in Vault Collection rows gives Finder-style flush-left flat rows. Verified in v0.0. Revisit once Vault → Collection → Page chain is observed against real data.

---

#### Open until content lands

Hover treatment, keyboard navigation, focus-ring styling, row-density tuning, `tagging_style` default, and Page-row icon hover behavior — all resolve once real content lands. Captured intent: a third hovered state subtler than the selected fill.
