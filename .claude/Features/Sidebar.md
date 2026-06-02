### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Five top-level groups — a heading-less pinned section at top, then Spaces, Topics, Items, Vaults.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

Five top-level groups:
- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Items** — chevron-disclosure showing Item Types (UI label "Type"); each Type discloses Item Collections (UI label "Set").
- **Vaults** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages + Page Collections (UI label "Collection").

Section-header defaults come from `SidebarSectionLabels.defaults()`: `Spaces` / `Topics` / `Items` / `Vaults` (Items-side uses the operational word "Items", not the container-plural "Types"). All renameable via Settings.

The Items section sits above Vaults — quicker-capture entities ride higher in the visual hierarchy. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section, not via a dedicated sidebar heading. The Calendar pin opens `CalendarDetailView` (Tasks list above, Events list below); right-click → "New Task" / "New Event" for quick capture.

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
─ Items ────────────────────────              ← section header (Items-side default)
  ▾ Bookmarks                              ← Item Type row (UI label: "Type")
      Tech                                 ← Item Collection row (UI label: "Set")
  ▸ Books
─ Vaults ───────────────────────              ← section header (Pages-side default)
  ▾ Assignments                            ← Page Type row (UI label: "Vault")
      📄 README                            ← Page directly in Page Type root
      ▾ Spring 2026                        ← Page Collection row (UI label: "Collection")
          📄 Essay 1
      ▾ Reports
          📄 2026 H1
  ▸ Notes
```

No always-visible "+ New" buttons — creation is **right-click first**, complemented by **hover-only `+` buttons** on section headings (visible on hover, hidden at rest). The fuller discoverability layer lands separately via quick-capture (Cmd+Shift+N / menu-bar; pre-v1).

##### Section grouping (sidecar-driven)

There are no wrapper folders on disk (see [[Architecture]]); the sidebar groups each root folder by its **per-kind sidecar filename** (the sidecars stay JSON):

- `_pagetype.json` → **Vaults** section
- `_itemtype.json` → **Items** section
- `_taskconfig.json` / `_eventconfig.json` (Tasks / Events singletons) → **no dedicated Agenda section**; their data surfaces through the Calendar pin entry

The sidecar is the **kind authority** — it, not the content-file extension, decides the section. This matters now that both Pages and Items are `.md`: a Finder-built `.md` folder *without* a sidecar can't be told apart by extension, so it adopts as a Page Type by default; hand-building an Items folder requires dropping in `_itemtype.json`. The section headings are pure UI groupings with no on-disk counterpart. Folders without a recognized sidecar trigger the adopter on next launch — but only when there's something to migrate; fresh non-Pommora folders stay invisible to discovery.

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

- `homepage` opens the Homepage singleton (see [[Homepage]])
- `calendar` opens `CalendarDetailView` — Tasks list above, Events list below (see [[Agenda]]). Right-click the pin entry → "New Task" / "New Event" for quick capture. EventKit-mirrored entries appear once sync opt-in ships at v0.5.0.
- `recents` shows the NavDropdown's Recents store as a full-frame view; ships at v0.6.0 per [[NavDropdown]]

**User-pinning of arbitrary entities is post-v1** — section gets its "Saved" heading + "+" affordance then; the three defaults become movable / removable.

##### Spaces

Flat rows — no chevron, no children disclosure. Each Space carries a `color` (the `SpaceColor` palette — see [[Contexts]]) and optional `icon` (SF Symbol). Visual mode settable per Nexus via `tier-config.json.tagging_style`: `"color"` (dot, default), `"symbol"` (SF Symbol), `"both"`. Clicking opens its composed-blocks page.

##### Topics

Chevron-disclosure rows. Each Topic expands to show file-nested Projects (tier-3 Contexts) as leaf rows.

Topic rows carry **tagging indicators inherited from parent Space(s)**. Multi-Space Topics show multiple indicators side by side (e.g. blue + green dots for a Topic that belongs to both Personal and Work). Clicking a Topic or Project opens its composed-blocks page.

##### Items (Items-side; default label)

Chevron-disclosure rows. **Each Item Type discloses its Item Collections** as children. The default UI label for Item Type rows is "Type"; for Item Collection rows is **"Set"** (both renameable via Settings).

Items themselves do **NOT** appear as leaves in the sidebar — they live in detail-pane Tables under their Item Type. Sidebar shows the structural / container view; detail pane shows the full data view.

Item Types don't display tagging (operational, not categorical). Clicking an Item Type opens its Items Table; clicking an Item Collection opens a scoped view.

##### Vaults (Pages-side; default label)

Chevron-disclosure rows. **Each Page Type discloses both Pages (in the Page Type root) AND Page Collection sub-folders** as children. Each Page Collection discloses its Pages. Pages show their frontmatter `icon` if set, else the `doc.text` default; Page Collections use `folder`. The default UI label for Page Type rows is **"Vault"**; for Page Collection rows is "Collection" (both renameable via Settings).

Page Types don't display tagging (operational, not categorical). Clicking a Page Type opens its hierarchical Table; clicking a Page Collection opens a scoped view; clicking a Page opens it in the main detail pane via the TextKit-2 editor (shipped v0.2.7.0).

---

#### Creation affordance: right-click context menus, scoped by cursor location

Canonical creation pattern. No always-visible "+ New" buttons; right-click the relevant heading / row / area and a context menu's "New X" options auto-scope to that location's parent. Section headings also expose a hover-only `+` complement — see below.

| Right-click target | Scoped creation options | Other context menu items |
|---|---|---|
| Spaces section area (empty / on heading) | New Space | — |
| Topics section area | New Topic | — |
| Items section area (Items-side) | New Item Type | — |
| Vaults section area (Pages-side) | New Page Type | — |
| Space row | New Space | Rename / Change Color / Change Icon / Delete |
| Topic row (when disclosed) | New Project *(in THIS Topic)* | Rename / Edit Parents / Change Icon / Delete |
| Project row | — | Rename / Change Icon / Delete |
| Item Type row | New Set + New Item *(scoped to THIS Item Type)* | **Type Settings…** (opens schema editor) / Rename / Change Icon / Delete |
| Item Collection row | New Item *(in THIS Set)* | Rename / Delete |
| Page Type row | New Collection + New Page *(scoped to THIS Page Type)* | **Vault Settings…** (opens schema editor) / Rename / Change Icon / Delete |
| Page Collection row | New Page *(in THIS Collection)* | Rename / Delete |
| Page row | — | Rename / Delete (Page editor shipped v0.2.7.0) |

Location scoping is load-bearing — right-clicking on a Page Collection produces "New Page" that creates IN that Page Collection. Matches Finder + Notion + Obsidian.

No Agenda menu rows in the sidebar at all — Agenda surfaces via the Calendar pin entry. Right-click the Calendar pin → "New Task" / "New Event" handles quick capture.

#### Discoverable creation: hover-icon "+" + quick-capture

Section headings expose a **hover-only `+` button** as a discoverable complement, opening the section's default new sheet. Keeps the sidebar visually quiet at rest while remaining discoverable.

Fuller global creation path lands via **quick-capture** (Cmd+Shift+N or menu-bar capture; pre-v1) — expected to absorb most CRUD entry traffic.

---

#### Selection language

- Fill: `Color(nsColor: .quaternarySystemFill)`, 6pt continuous corner radius, inset **11pt horizontal + 2pt vertical** (`.flat`); the `.disclosure` style drops the leading inset to 0 so the fill covers the chevron gutter
- Foreground: selected icon + text shift to `Color.accentColor`
- **Text** gets `.brightness(0.10)`; **icon** gets no brightness modifier
- Row content insets: **1pt vertical, 0 horizontal** (`.listRowInsets`)
- Icons use `.symbolRenderingMode(.monochrome)` so `.foregroundStyle(.accentColor)` applies
- Chrome is applied at each row file's body root via `.listRowBackground(SelectionChrome(...))`, deriving `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. `SelectableRow` itself is pure content — no chrome. Implementation in `Pommora/Pommora/Sidebar/SidebarView.swift`.

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` or `.listRowInsets(EdgeInsets(...))`. Use for nesting/grouping.
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between chevron and `Label`. Only when the chevron is hand-rolled.
- **Icon-to-text gap inside a row** — internal to `Label`; controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }`. Outer `HStack(spacing:)` does NOT control this.
- **Chevron-column reservation across flat rows** — implicit from `DisclosureGroup` in a `.listStyle(.sidebar)` List. Only suppressible by hand-rolling expansion.

---

#### Section ordering

User-reorderable in v1.x (drag headings up/down). Initial-boot order is **Pinned (heading-less) / Spaces / Topics / Items / Vaults** as shown above. Order persists per Nexus in `.nexus/state.json` (alongside other sidebar UI state).

---

#### Open until content lands

Hover treatment, keyboard navigation, focus-ring styling, row-density tuning, `tagging_style` default, and Page-row icon hover behavior all resolve once real content lands. Captured intent: a third hovered state subtler than the selected fill.
