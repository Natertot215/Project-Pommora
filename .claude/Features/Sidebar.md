### Sidebar

Pommora's leading-edge navigation pane in the three-pane shell. Top-level groups — a heading-less pinned section at top, then **Contexts** (one section holding the three free-standing tiers), then Vaults — plus user-creatable vault sections after Vaults.

Per-entity routing rules → [[Domain-Model]]; CRUD UI patterns → `// Guidelines//CRUD-Patterns.md`.

---

#### Layout

Top-level groups, plus user sections:
- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents
- **Contexts** — one section headed "Contexts" holding three disclosure rows: Areas / Topics / Projects. Each tier row expands to its entities as flat leaf rows.
- **Vaults** — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages + Page Collections (UI label "Collection"); each Collection discloses Page Sets (UI label "Set") + Pages.
- **User sections** — user-created sibling sections after Vaults, each grouping Vaults the user moved into it (§ "User vault sections" below).

The **Contexts** section header is a fixed `Contexts` label. Its three tier rows read their labels from the renameable per-tier config. The Vaults section header default is `Vaults`; user-section labels rename inline.

Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section, not via a dedicated sidebar heading. The Calendar pin opens the Calendar detail surface (Tasks list above, Events list below); right-click → "New Task" / "New Event" for quick capture.

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
          ▾ Midterm Prep                   ← Page Set row (UI label: "Set"; expandable, never selectable)
              📄 Exam Review
          📄 Essay 1                       ← Page at Collection root
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

Three fixed entries — `Homepage`, `Calendar`, `Recents` — render at the top **without a heading**. The underlying section wrapper persists for the future user-pinning feature (gains the "Saved" header when that ships).

Persisted in a pinned-section sidecar under `.nexus/` — an ordered list of items, each with a code-fixed `key` and a user-renamable `label`. Labels rename via Settings → Saved Section.

- `homepage` opens the Homepage singleton (see [[Homepage]])
- `calendar` opens the Calendar detail surface — Tasks list above, Events list below (see [[Agenda]]). Right-click the pin entry → "New Task" / "New Event" for quick capture. EventKit-mirrored entries appear once sync opt-in ships.
- `recents` shows the NavDropdown's Recents store as a full-frame view (see [[NavDropdown]])

**User-pinning of arbitrary entities is post-v1** — section gets its "Saved" heading + "+" affordance then; the three defaults become movable / removable.

##### Contexts

One section headed **"Contexts"** (a fixed label) holding exactly three **tier disclosure rows** — Areas, Topics, Projects — as homogeneous siblings. The three tiers are free-standing: no containment, no parents, no cross-tier nesting (see [[Contexts]]).

- **Tier rows** are expand/collapse only. A tier row carries no selection — clicking anywhere toggles its disclosure. Its label reads from the tier config; creation is via the row's hover `+` or right-click "New <Tier>".
- **Entity rows** render as **flat leaf rows** inside the disclosure:
  - **Area rows** carry a color (the Area palette — see [[Contexts]]) and an optional icon.
  - **Topic rows** and **Project rows** are bare leaf rows (icon + title) — no parent indicator, since the tiers don't nest.

Per-tier drag-reorder persists sibling order per Nexus. Clicking an entity opens its detail surface. Selection chrome stays at row level (§ "Selection language"); the tier rows mirror the same disclosure shape used by Vaults.

##### Vaults (default label)

Chevron-disclosure rows. **Each Page Type discloses both Pages (in the Page Type root) AND Page Collection sub-folders** as children. Each Page Collection discloses its Page Sets + its Pages; each Page Set discloses its Pages. Pages show their frontmatter icon if set, else the default page glyph; Page Collections and Page Sets use a folder glyph (per-Set icon overridable). The default UI label for Page Type rows is **"Vault"**; for Page Collection rows "Collection"; for Page Set rows "Set" (all renameable via Settings).

**Page Set rows are expandable, never selectable** — no selection chrome; clicking toggles the disclosure only (Sets have no detail view). Drag-reorder inside a Collection's disclosure is **two-zone**: Sets reorder among Sets, Pages among Pages; cross-zone drags are rejected. Order persists parent-side — Set order on the Collection's sidecar, each Set's child Pages in that Set's own order.

Page Types don't display tagging (operational, not categorical). Clicking a Page Type opens its hierarchical Table; clicking a Page Collection opens a scoped view; clicking a Page routes per the vault's open-in mode — main detail pane (the default) or a preview window; see [[Pages]] § "Opening behavior".

##### User vault sections (navigation-only grouping)

User-creatable sections that group Vaults below the default Vaults section. Persisted in a sidebar-sections sidecar under `.nexus/`; writes are atomic and failures surface as a sidebar toast.

- **Navigation-only** — grouping never moves a vault folder on disk; membership lives solely in the config.
- **Single-membership** — a vault sits in at most one user section; moving it strips it from every other section in the same config write.
- **Ungrouped vaults stay in the default Vaults section**; deleting a section ungroups its vaults back to it (no vault data touched).
- **Empty sections render header-only** — never a placeholder row (a section's rows stay homogeneous; see § "Constraints").
- **Dangling vault IDs** (vault deleted after grouping) stay in the config and skip-render; the config is not self-healed.
- **Render shape** — each user section renders the identical disclosure shape as the default Vaults section, reusing the same Page-Type row.

Affordances: **"Add Section"** in the Vaults section-header context menu (stub then inline-rename); **"Move to Section" / "Remove from Section"** in a vault row's context menu (the menu appears once at least one section exists); **Rename Section / Delete Section** in the user-section header's context menu.

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
| Page Collection row | New Page + New Set *(in THIS Collection)* | Rename / Delete |
| Page Set row | New Page *(in THIS Set)* | Rename / Change Icon / Move to… (another Collection) / Delete (two modes — see [[Sets]]) |
| Page row | — | Rename / Delete |
| User section header | — | Rename Section / Delete Section (ungroups its vaults) |

Location scoping is load-bearing — right-clicking a Page Collection produces "New Page" that creates IN that Page Collection. The three tier rows each create only their own tier (no cross-tier creation — the tiers are independent). Matches Finder + Notion + Obsidian.

No Agenda menu rows in the sidebar at all — Agenda surfaces via the Calendar pin entry. Right-click the Calendar pin → "New Task" / "New Event" handles quick capture.

#### Discoverable creation: hover-icon "+" + quick-capture

Tier and section headings expose a **hover-only `+` button** as a discoverable complement, opening that tier/section's new flow. Keeps the sidebar visually quiet at rest while remaining discoverable.

Fuller global creation path lands via **quick-capture** (Cmd+Shift+N or menu-bar capture; pre-v1) — expected to absorb most CRUD entry traffic.

---

#### Selection language

Finder-style selection — a subtle quaternary-fill rounded pill at the row level. The fill is applied via the list-row background (not an in-content background), so it spans the full row including the disclosure-chevron gutter rather than stopping at the content's leading edge. On selection the row's icon and text shift to the accent color, and the text brightens slightly so the selected row reads as active without a heavy highlight.

---

#### Constraints

Two load-bearing rules govern the sidebar's structure; breaking either has regressed a launch crash in the list-diffing layer:

- **Selection chrome lives at row level, never in-content.** Each row derives its own selected state and applies the selection pill through the list-row background. Row content stays pure — it carries no chrome of its own. An untagged row inside a tagged container inherits that container's selection, so a deliberately non-selectable row (e.g. a Set row) needs its own distinct non-selecting tag plus selection explicitly disabled on its label.
- **Every section's rows stay homogeneous.** Don't mix flat-leaf rows and disclosure rows inside the same section, and don't substitute a placeholder leaf for an empty section (an empty user section renders header-only). The list coordinator can crash on that asymmetry.

---

#### Section ordering

Initial-boot order: Pinned (heading-less) / Contexts / Vaults / user sections. Order persists per Nexus.

