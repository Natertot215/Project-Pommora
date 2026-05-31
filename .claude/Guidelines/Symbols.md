### Symbols

Registry of SF Symbol assignments across Pommora — what symbol goes where, by application. This is the source of truth: when a doc or feature mentions an icon for a sidebar row, toolbar button, default entity icon, etc., the canonical value lives here.

This file is also the spec for a future in-app **Symbol Settings** surface — once the table is mature, it gets mirrored into a Swift `IconConfig` struct (or similar) wired through the SwiftUI environment, letting users override per-application defaults.

---

#### Defaults

| Application | Symbol |
|---|---|
| Pages | `doc.text` |
| Page Collections (UI label "Collection") | `folder` |
| Page Types (UI label "Vault") | `book` (or per-Type override at `_pagetype.json.icon`) |
| Item Types (UI label "Type") | `tray.full` (or per-Type override at `_itemtype.json.icon`) |
| Item Collections (UI label "Set") | `square.stack.3d.up` (or per-Collection override) |
| Items | `tray` (or per-item override) |
| Spaces | `rectangle.3.group` (or per-space override) |
| Topics | `folder` (or per-topic override) |
| Projects | `folder` (or per-project override) |
| Agenda Tasks | `checkmark.circle` (or per-task override) |
| Agenda Events | `calendar.badge.clock` (or per-event override) |
| Homepage (Pinned section) | `house` |
| Calendar (Pinned section) | `calendar` |
| Recents (Pinned section) | *(TBD — leave blank for now)* |
| NavDropdown trigger (toolbar) | `square.on.square` |
| Inspector toggle (toolbar) | `sidebar.trailing` |
| Sidebar toggle (toolbar) | *(system-provided by `NavigationSplitView`)* |
| Back / forward arrows (toolbar) | `chevron.left` / `chevron.right` |
| Page Type Settings / Item Type Settings | `gearshape` |
| App-wide Settings scene (Cmd+,) | `gearshape` |

---

#### Conventions

- **Filled / outlined choice** follows Apple's HIG default for each symbol — outlined for nav, filled for status. Don't toggle unless there's a reason.
- **User-overridable per entity** — Pages, Items, Page Types, Page Collections, Item Types, Item Collections, Spaces, Topics, Projects, Agenda Tasks, and Agenda Events all carry an optional `icon: String?` field on disk. The defaults above are fallbacks when the field is unset.
- **Per-property icons** — every property in a Type's schema can carry an icon (`PropertyDefinition.icon: String?`); chosen via Pommora's native **`IconPicker`** (compact Liquid-Glass picker over the full SF Symbols catalog, with search + Saved/favorites — replaced the `xnth97/SymbolPicker` SPM dep 2026-05-30).
- **No raw `Image(systemName:)` literals scattered across views** for entity defaults — wrap through a single resolver so this table is the only place to change a default.

---

#### Future in-app surface

Once the Symbol Settings surface ships (post-v1 candidate), this table becomes user-editable per-Nexus. The Swift type is expected to land roughly like:

```swift
struct IconConfig: Codable {
    var page: String            // default "doc.text"
    var pageCollection: String  // default "folder"
    var pageType: String        // default "book"
    var itemType: String        // default "tray.full"
    var itemCollection: String  // default "square.stack.3d.up"
    var item: String            // default "tray"
    var space: String           // default "rectangle.3.group"
    var topic: String           // default "folder"
    var project: String         // default "folder"
    var agendaTask: String      // default "checkmark.circle"
    var agendaEvent: String     // default "calendar.badge.clock"
    // ... one field per row above
}
```

Stored at `.nexus/icon-config.json` alongside `tier-config.json` / `saved-config.json` / `settings.json`. The `IconPickerField` surface (already used in per-Type Settings for per-property icons) supplies the editor UI. Post-v0.6.0, the IconConfig store may fold into `settings.json` since both carry per-Nexus UI customization — TBD when the surface ships.

Until that ships, edits to defaults happen by editing this file + the corresponding `Image(systemName:)` site in code.
