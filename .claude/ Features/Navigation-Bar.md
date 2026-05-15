### Navigation Bar

Pommora's top-of-window strip — a **single horizontal plane** combining window chrome, page navigation, tab switching, and toolbar actions into one row. No separate tab bar below the title bar. Inspired by Safari's compact tab layout adapted to a notes/database context (no URL field).

The navigation bar is the structural framing of every Pommora window. Tabs live here, navigation controls live here, the inspector toggle lives here. The Pages canvas, the Spaces canvas, the Item windows — all sit beneath it.

---

#### Layout

```
[ ◯ ◯ ◯ ]  [≡]   [ ‹ › ]   ········· tabs ·········   [+]   [▢]
 traffic   side   back/      auto-distributed         new    inspector
 lights    bar    forward    tab strip                tab    toggle
```

Left to right:

- **Traffic lights** — OS-rendered window controls
- **Sidebar toggle (`≡`)** — system-provided by `NavigationSplitView` (NSSplitView animation); Mail/Notes/Finder path
- **Back / Forward (`‹ ›`)** — page-navigation arrows; render in v0.1, no-op until navigation history exists
- **Tab strip** — fills the center; tabs auto-distribute available width
- **New tab (`+`)** — trailing edge, immediately before the inspector toggle
- **Inspector toggle (`▢`)** — trailing-most; `sidebar.trailing` SF Symbol, placed inside the `.inspector { … }` closure so it anchors to the inspector's segment of the unified toolbar

The window title is suppressed (`.windowToolbarStyle(.unified(showsTitle: false))`); the navigation bar replaces it entirely.

---

#### Tab strip

Tabs share the available strip width **equally** — `availableWidth / tabCount`. No minimum width floor; the strip itself never scrolls. Tabs grow when others close, shrink when others open.

Hard limit of **15 open tabs** in v0.1; `+` and `Cmd+T` silently disabled at the cap. Rationale: realistic usage is 3–8 tabs; 15 is a comfortable ceiling. Revisited once usage patterns are observed.

Title text truncates with an ellipsis when the tab is too narrow. Inactive vs active distinction and any hover treatment resolve once tabs render under Tahoe (see "Open until v0.1+").

---

#### Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New tab | `⌘T` |
| Close active tab | `⌘W` |
| Jump to tab N | `⌘1` … `⌘9` |
| Previous tab | `⌘⇧[` |
| Next tab | `⌘⇧]` |
| Toggle inspector | (from `InspectorCommands`, system default) |

---

#### Persistence

Open tabs and the active-tab pointer **persist across launches**. v0.1: `@AppStorage` (UserDefaults). v0.2+: moves to `.pommora//state.json` once the watcher + state layer ships. Tab state is **per-window**.

---

#### Constraints

- The tab strip never scrolls in v0.1 — equal division only.
- The new-tab button is silently disabled at the 15-tab cap.
- Tab drag-to-reorder is not supported in v0.1.
- Back/forward render but are no-ops until navigation history exists.
- Items don't get tabs — they open in their own popover Item window (see `Items.md`).

---

#### Open until v0.1+ lands content

Active/inactive tab visual treatment, hover behavior on the tab strip, button density, and any toolbar-row sizing (`.unified` vs `.unifiedCompact`, `.controlSize`, `.imageScale`) resolve once tabs render on Tahoe and there's a real reference to compare against Mail/Notes/Finder.

Post-v0.1 features parked: tab-overflow scrolling, drag-to-reorder, tear-off, back/forward history wiring, new-tab page content, hover-visibility user preference. Detail moves here when committed.
