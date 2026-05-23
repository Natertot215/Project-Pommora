### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Five top-level groups — a heading-less pinned section at top, then Spaces, Topics, Items, Pages. Locked selection language from v0.0 carries forward.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

Five top-level groups (all labels renameable via Settings scaffold — Phase 7):
- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Items** (default label) — chevron-disclosure showing Item Types (UI label "Type"); each Type discloses Item Collections (UI label "Set")
- **Pages** (default label) — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages + Page Collections (UI label "Collection")

Items sits above Pages — quicker-capture entities ride higher in the visual hierarchy. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section, not via a dedicated sidebar heading. Calendar wires the Agenda data layer in a follow-up plan.

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
─ Items ────────────────────────
  ▾ Bookmarks                              ← Item Type row (UI label: "Type")
      Tech                                 ← Item Collection row (UI label: "Set")
  ▸ Books
─ Pages ────────────────────────
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

There are no wrapper folders on disk — Page Types, Item Types, and the Agenda singletons all live as siblings at the nexus root. The sidebar groups each root folder by reading its **per-kind sidecar filename**, not by inspecting a wrapper directory:

- Any root folder carrying `_pagetype.json` → grouped under the **Pages** section heading
- Any root folder carrying `_itemtype.json` → grouped under the **Items** section heading
- Root folders carrying `_taskconfig.json` (Tasks singleton) and `_eventconfig.json` (Events singleton) → **no dedicated Agenda section**; their data surfaces through the Calendar pin entry once Calendar UI lands

The section headings ("Pages" / "Items") are pure UI groupings with no on-disk counterpart. Folders without a recognized sidecar are unrecognized and trigger the adopter on next launch.

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
- `calendar` opens a calendar view over Agenda Tasks + Agenda Events + EventKit-mirrored entries (see [[Agenda]]); Calendar UI lands in a follow-up plan, data layer ships v0.3.0
- `recents` shows the NavDropdown's Recents store as a full-frame view; ships at v0.6.0 per [[NavDropdown]]

**User-pinning of arbitrary entities is post-v1** — section gets its "Saved" heading + "+" affordance then; the three defaults become movable / removable.

##### Spaces

Flat rows — no chevron, no children disclosure. Each Space carries a `color` (one of 9 Notion-palette colors) and optional `icon` (SF Symbol). Visual mode settable per Nexus via `tier-config.json.tagging_style`: `"color"` (dot, default), `"symbol"` (SF Symbol), `"both"`. Clicking opens its composed-blocks page.

##### Topics

Chevron-disclosure rows. Each Topic expands to show file-nested Projects (tier-3 Contexts) as leaf rows.

Topic rows carry **tagging indicators inherited from parent Space(s)**. Multi-Space Topics show multiple indicators side by side (e.g. blue + green dots for a Topic that belongs to both Personal and Work). Clicking a Topic or Project opens its composed-blocks page.

##### Items

Chevron-disclosure rows. **Each Item Type discloses its Item Collections** as children. The default UI label for Item Type rows is "Type"; for Item Collection rows is **"Set"** (both renameable via Settings).

Items themselves do **NOT** appear as leaves in the sidebar — they live in detail-pane Tables under their Item Type. Sidebar shows the structural / container view; detail pane shows the full data view.

Item Types don't display tagging (operational, not categorical). Clicking an Item Type opens its Items Table; clicking an Item Collection opens a scoped view.

##### Pages

Chevron-disclosure rows. **Each Page Type discloses both Pages (in the Page Type root) AND Page Collection sub-folders** as children. Each Page Collection discloses its Pages. Pages use the `doc.text` icon; Page Collections use `folder`. The default UI label for Page Type rows is **"Vault"**; for Page Collection rows is "Collection" (both renameable via Settings).

Page Types don't display tagging (operational, not categorical). Clicking a Page Type opens its hierarchical Table; clicking a Page Collection opens a scoped view; clicking a Page opens it in the main detail pane via the TextKit-2 editor (shipped v0.2.7.0).

---

#### Creation affordance: right-click context menus, scoped by cursor location

Canonical creation pattern. No always-visible "+ New" buttons; right-click the relevant heading / row / area and a context menu's "New X" options auto-scope to that location's parent. Section headings also expose a hover-only `+` complement — see below.

| Right-click target | Scoped creation options | Other context menu items |
|---|---|---|
| Spaces section area (empty / on heading) | New Space | — |
| Topics section area | New Topic | — |
| Items section area | New Item Type | — |
| Pages section area | New Page Type | — |
| Space row | New Space | Rename / Change Color / Change Icon / Delete |
| Topic row (when disclosed) | New Project *(in THIS Topic)* | Rename / Edit Parents / Change Icon / Delete |
| Project row | — | Rename / Change Icon / Delete |
| Item Type row | — *(no menu in v0.3.0 — stub row)* | — *(designed UI in follow-up plan)* |
| Item Collection row | — *(no menu in v0.3.0 — stub row)* | — *(designed UI in follow-up plan)* |
| Page Type row | New Collection + New Page *(scoped to THIS Page Type)* | **Page Type Settings…** (opens schema editor + sort + property visibility) / Rename / Change Icon / Delete |
| Page Collection row | New Page *(in THIS Collection)* | Rename / Delete |
| Page row | — | Rename / Delete (Page editor shipped v0.2.7.0) |

Location scoping is load-bearing — right-clicking on a Page Collection produces "New Page" that creates IN that Page Collection. Matches Finder + Notion + Obsidian.

No Agenda menu rows in the sidebar at all — Agenda surfaces via the Calendar pin entry; Agenda Task and Agenda Event creation runs through the Calendar UI when it lands.

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

User-reorderable in v1.x (drag headings up/down). Initial-boot order is **Pinned (heading-less) / Spaces / Topics / Items / Pages** as shown above. Order persists per Nexus in `.nexus/state.json` (alongside other sidebar UI state).

---

#### Inline-chevron experiment (Finder pattern)

Captured intent from v0.0 spike (not committed): hand-rolling chevron + member ForEach in Page Collection rows gives Finder-style flush-left flat rows. Verified in v0.0. Revisit once Page Type → Page Collection → Page chain is observed against real data.

---

#### Open until content lands

Hover treatment, keyboard navigation, focus-ring styling, row-density tuning, `tagging_style` default, and Page-row icon hover behavior — all resolve once real content lands. Captured intent: a third hovered state subtler than the selected fill.

---

> **v0.3.0 status:** The Pages-side ships fully designed per this spec — Page Type rows (labeled "Vault" by default), Page Collection rows, context menus, sheet wiring. The Items-side ships as minimal stubs: `ItemTypeRow` + `ItemCollectionRow` render as plain selectable rows (no context menus, no quick-actions). Click-through lands on a `ContentUnavailableView` placeholder; the Items table UI lands in a follow-up plan. Agenda has no sidebar section — Agenda Tasks + Agenda Events surface via the Calendar pin entry (data layer ships in v0.3.0; Calendar UI is a follow-up plan).
