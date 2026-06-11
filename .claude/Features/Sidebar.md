### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Top-level groups — a heading-less pinned section at top, then **Contexts** (one section holding the three free-standing tiers), then Vaults — plus user-creatable vault sections after Vaults.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

Top-level groups, plus user sections:
- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents
- **Contexts** — one section headed "Contexts" holding three `square.grid.2x2` disclosure rows: Areas (tier 1) / Topics (tier 2) / Projects (tier 3). Each tier row expands to its entities as flat leaf rows.
- **Vaults** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages + Page Collections (UI label "Collection").
- **User sections** — user-created sibling sections after Vaults, each grouping Vaults the user moved into it (§ "User vault sections" below).

The **Contexts** section header is a fixed `Contexts` label. Its three tier rows read their labels from the renameable tier config — `Areas` / `Topics` from `SidebarSectionLabels`, `Projects` from the Project label pair. The Vaults section header default comes from `SidebarSectionLabels.defaults()` (`Vaults`); user-section labels rename inline.

Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section, not via a dedicated sidebar heading. The Calendar pin opens `CalendarDetailView` (Tasks list above, Events list below); right-click → "New Task" / "New Event" for quick capture.

```
[Sidebar]
  Homepage
  Calendar
  Recents
─ Contexts ─────────────────────
  ▾ Areas
      ◉ Personal       [color/symbol]
      ◉ Academics
      ◉ Work
  ▾ Topics
      CS 161
      Productivity
      Side Projects
  ▾ Projects
      Pommora
      "Atomic Habits"
─ Vaults ───────────────────────              ← default section header
  ▾ Assignments                            ← Page Type row (UI label: "Vault")
      📄 README                            ← Page directly in Page Type root
      ▾ Spring 2026                        ← Page Collection row (UI label: "Collection")
          📄 Essay 1
      ▾ Reports
          📄 2026 H1
  ▸ Notes
─ School ───────────────────────              ← user section (groups Vaults; navigation-only)
  ▸ Readings
```

No always-visible "+ New" buttons — creation is **right-click first**, complemented by **hover-only `+` buttons** on section/tier headings (visible on hover, hidden at rest). The fuller discoverability layer lands separately via quick-capture (Cmd+Shift+N / menu-bar; pre-v1).

##### Section grouping (sidecar-driven)

There are no wrapper folders on disk (see [[Architecture]]); the sidebar groups each root folder by its **per-kind sidecar filename** (the sidecars stay JSON):

- `_area.json` / `_topic.json` / `_project.json` (under `.nexus/areas` · `topics` · `projects`) → the **Contexts** section's Areas / Topics / Projects tier rows
- `_pagetype.json` → **Vaults** section (or the user section the vault was moved into)
- `_taskconfig.json` / `_eventconfig.json` (Tasks / Events singletons) → **no dedicated Agenda section**; their data surfaces through the Calendar pin entry

The sidecar is the **kind authority** — it, not the folder name, decides the grouping. The section headings are pure UI groupings with no on-disk counterpart. Folders without a recognized sidecar trigger the adopter on next launch — but only when there's something to migrate; fresh non-Pommora folders stay invisible to discovery.

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

Each entry's `key` is fixed in code; `label` is user-renamable via Settings → Saved Section.

- `homepage` opens the Homepage singleton (see [[Homepage]])
- `calendar` opens `CalendarDetailView` — Tasks list above, Events list below (see [[Agenda]]). Right-click the pin entry → "New Task" / "New Event" for quick capture. EventKit-mirrored entries appear once sync opt-in ships at v0.5.0.
- `recents` shows the NavDropdown's Recents store as a full-frame view; ships at v0.6.0 per [[NavDropdown]]

**User-pinning of arbitrary entities is post-v1** — section gets its "Saved" heading + "+" affordance then; the three defaults become movable / removable.

##### Contexts

One `Section` headed **"Contexts"** (a fixed label) holding exactly three `square.grid.2x2` **tier disclosure rows** — Areas, Topics, Projects — homogeneous siblings (quirk #8). The three tiers are free-standing: no containment, no parents, no cross-tier nesting (see [[Contexts]]).

- **Tier rows** are expand/collapse only. A tier row carries no selection tag — clicking anywhere toggles its disclosure. Its label reads from the tier config; creation is via the row's hover `+` or right-click "New <Tier>".
- **Entity rows** render as **flat leaf rows** inside the disclosure:
  - **Area rows** carry a `color` (the `AreaColor` palette — see [[Contexts]]) and optional `icon`.
  - **Topic rows** and **Project rows** are bare leaf rows (icon + title). Topics no longer inherit any parent indicator — the parent-Area tagging died with containment.

Per-tier drag-reorder (`.onMove`) persists sibling order to `.nexus/state.json` (`area_order` / `topic_order` / `project_order`). Clicking an entity opens its detail surface. Selection chrome stays at row-file level (§ "Selection language"); the tier rows mirror the proven `Section { … } header:` disclosure shape used by Vaults.

##### Vaults (default label)

Chevron-disclosure rows. **Each Page Type discloses both Pages (in the Page Type root) AND Page Collection sub-folders** as children. Each Page Collection discloses its Pages. Pages show their frontmatter `icon` if set, else the `doc.text` default; Page Collections use `folder`. The default UI label for Page Type rows is **"Vault"**; for Page Collection rows is "Collection" (both renameable via Settings).

Page Types don't display tagging (operational, not categorical). Clicking a Page Type opens its hierarchical Table; clicking a Page Collection opens a scoped view; clicking a Page routes per the vault's `open_in` mode — main detail pane (`window`, the default) or a PagePreview window (`compact`); see [[Pages]] § "Opening behavior".

##### User vault sections (navigation-only grouping)

User-creatable sections that group Vaults below the default Vaults section. Persisted at `.nexus/sidebar-sections.json`, owned by `SidebarSectionsManager` (mirrors the `SavedConfigManager` pattern: `load()` seeds + first-writes, `save()` writes atomically, failures land in `pendingError` for the sidebar toast).

- **Navigation-only** — grouping never moves a vault folder on disk; membership lives solely in the config.
- **Single-membership** — a vault sits in at most one user section; moving it strips it from every other section in the same config write.
- **Ungrouped vaults stay in the default Vaults section**; deleting a section ungroups its vaults back to it (no vault data touched).
- **Empty sections render header-only** — never a placeholder row (quirk #8: a `Section`'s rows stay homogeneous).
- **Dangling vault IDs** (vault deleted after grouping) stay in the config and skip-render; the config is not self-healed.
- **Render shape** — each user section is a sibling `Section(isExpanded:) { PageTypeRow… } header:` identical to the default Vaults section, reusing `PageTypeRow` unchanged.

Affordances: **"Add Section"** in the Vaults section-header context menu (stub-and-inline-rename via `CreateWithInlineEdit`); **"Move to Section" / "Remove from Section"** in a vault row's context menu (the menu appears once at least one section exists); **Rename Section / Delete Section** in the user-section header's context menu.

---

#### Creation affordance: right-click context menus, scoped by cursor location

Canonical creation pattern. No always-visible "+ New" buttons; right-click the relevant heading / row / area and a context menu's "New X" options auto-scope to that location's tier or container. Tier/section headings also expose a hover-only `+` complement — see below.

| Right-click target | Scoped creation options | Other context menu entries |
|---|---|---|
| Areas tier row | New Area | (toggles disclosure) |
| Topics tier row | New Topic | (toggles disclosure) |
| Projects tier row | New Project | (toggles disclosure) |
| Area row | New Area | Rename / Change Color / Change Icon / Delete |
| Topic row | New Topic | Rename / Change Icon / Delete |
| Project row | New Project | Rename / Change Icon / Delete |
| Vaults section heading | New Page Type | **Add Section** (new user section, inline-rename) |
| Page Type row | New Collection + New Page *(scoped to THIS Page Type)* | **Vault Settings…** (opens schema editor) / **Move to Section** (+ Remove from Section while grouped) / Rename / Change Icon / Delete |
| Page Collection row | New Page *(in THIS Collection)* | Rename / Delete |
| Page row | — | Rename / Delete |
| User section header | — | Rename Section / Delete Section (ungroups its vaults) |

Location scoping is load-bearing — right-clicking a Page Collection produces "New Page" that creates IN that Page Collection. The three tier rows each create only their own tier (no cross-tier creation — the tiers are independent). Matches Finder + Notion + Obsidian.

No Agenda menu rows in the sidebar at all — Agenda surfaces via the Calendar pin entry. Right-click the Calendar pin → "New Task" / "New Event" handles quick capture.

#### Discoverable creation: hover-icon "+" + quick-capture

Tier and section headings expose a **hover-only `+` button** as a discoverable complement, opening that tier/section's new flow. Keeps the sidebar visually quiet at rest while remaining discoverable.

Fuller global creation path lands via **quick-capture** (Cmd+Shift+N or menu-bar capture; pre-v1) — expected to absorb most CRUD entry traffic.

---

#### Selection language

- Fill: `Color(nsColor: .quaternarySystemFill)`, 6pt continuous corner radius, inset **11pt horizontal + 2pt vertical** (`.flat`); the `.disclosure` style drops the leading inset to 0 so the fill covers the chevron gutter
- Foreground: selected icon + text shift to `Color.accentColor`
- **Text** gets `.brightness(0.10)`; **icon** gets no brightness modifier
- Row content insets: **1pt vertical, 0 horizontal** (`.listRowInsets`)
- Icons use `.symbolRenderingMode(.monochrome)` so `.foregroundStyle(.accentColor)` applies
- Chrome is applied at each row file's body root via `.listRowBackground(SelectionChrome(...))`, deriving `isSelected` from `SelectionTag.X(entity.id).matches(selection)`. `SelectableRow` itself is pure content — no chrome. Implementation in `Pommora/Pommora/Sidebar/SidebarView.swift` + `Pommora/Pommora/Sidebar/ContextsSection.swift`.

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` or `.listRowInsets(EdgeInsets(...))`. Use for nesting/grouping.
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between chevron and `Label`. Only when the chevron is hand-rolled.
- **Icon-to-text gap inside a row** — internal to `Label`; controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }`. Outer `HStack(spacing:)` does NOT control this.
- **Chevron-column reservation across flat rows** — implicit from `DisclosureGroup` in a `.listStyle(.sidebar)` List. Only suppressible by hand-rolling expansion.

---

#### Section ordering

User-reorderable in v1.x (drag headings up/down). Initial-boot order is **Pinned (heading-less) / Contexts / Vaults / user sections** as shown above. Order persists per Nexus in `.nexus/state.json` (alongside other sidebar UI state).

---

#### Open until content lands

Hover treatment, keyboard navigation, focus-ring styling, row-density tuning, and Page-row icon hover behavior all resolve once real content lands. Captured intent: a third hovered state subtler than the selected fill.
