### Symbols

Registry of SF Symbol assignments across Pommora — what symbol goes where, by application. This is the source of truth: when a doc or feature mentions an icon for a sidebar row, toolbar button, default entity icon, etc., the canonical value lives here.

This file is also the spec for a future in-app **Symbol Settings** surface — once the table is mature, it gets mirrored into a Swift `IconConfig` struct (or similar) wired through the SwiftUI environment, letting users override per-application defaults.

---

#### Defaults

| Application | Symbol |
|---|---|
| Pages | `doc.text` |
| Collections | `folder` |
| Vaults | `book` (or per-vault override in `_vault.json.icon`) |
| Spaces | `rectangle.3.group` (or per-space override) |
| Topics | `folder` (or per-topic override) |
| Sub-topics  | `folder` (or per-sub-topic override) |
| Items| `tray` (or per-item override) |
| Tasks | `checkmark.circle` (or per-item override) |
| Homepage (Saved-section pin) | `house` |
| Calendar (Saved-section pin) | `calendar` |
| Recents (Saved-section pin) | *(TBD — leave blank for now)* |
| NavDropdown trigger (toolbar) | `square.on.square` |
| Inspector toggle (toolbar) | `sidebar.trailing` |
| Sidebar toggle (toolbar) | *(system-provided by `NavigationSplitView`)* |
| Back / forward arrows (toolbar) | `chevron.left` / `chevron.right` |
| Vault Settings | `gearshape` |

---

#### Conventions

- **Filled / outlined choice** follows Apple's HIG default for each symbol — outlined for nav, filled for status. Don't toggle unless there's a reason.
- **User-overridable per entity** — Pages, Items, Vaults, Collections, Spaces, Topics, Sub-topics, and Agenda items all carry an optional `icon: String?` field on disk. The defaults above are fallbacks when the field is unset.
- **Per-property icons** — every property in a Vault's schema can carry an icon (`PropertyDefinition.icon: String?`); chosen via `IconPickerField` (wraps the `xnth97/SymbolPicker` SPM dep behind Pommora's own sheet).
- **No raw `Image(systemName:)` literals scattered across views** for entity defaults — wrap through a single resolver so this table is the only place to change a default.

---

#### Future in-app surface

Once the Symbol Settings surface ships (post-v1 candidate), this table becomes user-editable per-Nexus. The Swift type is expected to land roughly like:

```swift
struct IconConfig: Codable {
    var page: String        // default "doc.text"
    var collection: String  // default "folder"
    var vault: String       // default "book"
    var space: String       // default "rectangle.3.group"
    // ... one field per row above
}
```

Stored at `.nexus/icon-config.json` alongside `tier-config.json` / `saved-config.json`. The `IconPickerField` surface (already used in Vault Settings for per-property icons) supplies the editor UI.

Until that ships, edits to defaults happen by editing this file + the corresponding `Image(systemName:)` site in code.
