### Symbols

Registry of SF Symbol assignments across Pommora — what symbol goes where, by application. This is the source of truth: when a doc or feature mentions an icon for a sidebar row, toolbar button, default entity icon, etc., the canonical value lives here.

A future per-Nexus icon config mirrors this table — an in-app **Symbol Settings** surface that lets users override per-application defaults.

---

#### Defaults

| Application | Symbol |
|---|---|
| Pages | `doc.text` |
| Page Collections (UI label "Collection") | `book` (or per-Collection override at `_pagecollection.json.icon`) |
| Page Sets (UI label "Set") | `folder` (or per-Set override at `_pageset.json.icon`) |
| Areas | `rectangle.3.group` (or per-area override) |
| Topics | `folder` (or per-topic override) |
| Projects | `folder` (or per-project override) |
| Tasks | `checkmark.circle` (or per-task override) |
| Events | `calendar.badge.clock` (or per-event override) |
| Homepage (Pinned section) | `house` |
| Calendar (Pinned section) | `calendar` |
| Recents (Pinned section) | *(TBD — leave blank for now)* |
| Navigation trigger (toolbar) | `square.on.square` |
| Inspector toggle (toolbar) | `sidebar.trailing` |
| Sidebar toggle (toolbar) | *(system-provided by `NavigationSplitView`)* |
| Back / forward arrows (toolbar) | `chevron.left` / `chevron.right` |
| App-wide Settings scene (Cmd+,) | `gearshape` |

---

#### Conventions

- **Filled / outlined choice** follows Apple's HIG default for each symbol — outlined for nav, filled for status. Don't toggle unless there's a reason.
- **User-overridable per entity** — Pages, Page Collections, Page Sets, Areas, Topics, Projects, Tasks, and Events all carry an optional `icon` field on disk. The defaults above are fallbacks when the field is unset.
- **Per-property icons** — every property in a Type's schema can carry an icon; chosen via Pommora's native **`IconPicker`** (compact Liquid-Glass picker over the full SF Symbols catalog, with search + Saved/favorites).
- **No raw `Image(systemName:)` literals scattered across views** for entity defaults — wrap through a single resolver so this table is the only place to change a default.

---

#### Future in-app surface

A future per-Nexus icon config mirrors this table — a Symbol Settings surface that makes defaults user-editable per-Nexus, stored alongside the other per-Nexus config sidecars. The native `IconPicker` (already the per-property + per-entity icon chooser) supplies the editor UI. Until that ships, edits to defaults happen by editing this file plus the corresponding icon site in code.
