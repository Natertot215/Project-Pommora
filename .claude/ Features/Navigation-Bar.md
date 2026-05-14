### Navigation Bar

Pommora's top-of-window strip — a **single horizontal plane** combining window chrome, page navigation, tab switching, and toolbar actions into one row. No separate tab bar below the title bar; no traditional address bar. Inspired by Safari's compact tab layout — the only Apple app that puts tabs and chrome in a single row alongside a persistent sidebar — adapted to a notes/database context where there's no URL to host.

The navigation bar is the structural framing of every Pommora window. Tabs live here, navigation controls live here, the inspector toggle lives here. The Pages canvas, the Spaces canvas, the Item windows — all sit beneath it.

---

#### Layout

```
[ ◯ ◯ ◯ ]  [≡]   [ ‹ › ]   ········· tabs ·········   [+]   [▢]
 traffic   side   back/      auto-distributed         new    inspector
 lights    bar    forward    tab strip                tab    toggle
```

Items, left to right:

- **Traffic lights** — macOS-provided window controls (close, minimize, zoom)
- **Sidebar toggle (`≡`)** — collapses or expands the primary sidebar; provided by the split-view container
- **Back / Forward (`‹ ›`)** — page-navigation arrows; always visible, always rendered (no-op until navigation history exists)
- **Tab strip** — fills the center; tabs auto-distribute available width
- **New tab (`+`)** — opens an empty tab; trailing edge, immediately before the inspector toggle
- **Inspector toggle (`▢`)** — toggles the pop-out inspector; trailing-most position

The window title itself is suppressed — the navigation bar replaces the macOS title-bar text entirely. Only the traffic-light buttons remain from the standard window chrome.

---

#### Tab strip

##### Width distribution

Tabs share the available strip width **equally**. Each tab is `availableWidth / tabCount` wide:

- 1 tab → 100% of strip
- 2 tabs → 50% each
- 3 tabs → ~33% each
- 8 tabs → ~12.5% each

No minimum width floor. No "stay-at-full-size-until-N" behavior. Pure even division. Tabs grow when others close, shrink when others open. The strip itself never scrolls — width is divided, not extended.

##### Visibility

The strip's visibility is **hover-gated**. Two modes the user can switch between (eventually a setting; for now a development toggle):

- **Hover-only** — tabs invisible by default; cursor entering the navigation bar fades them in; cursor leaving fades them out. The bar reads as nearly chrome-free when not in use.
- **Always-visible-with-fade** — tabs always present at reduced opacity (~35%); hover raises them to full opacity. Constant at-a-glance read of what's open.

The back/forward, new-tab, and inspector buttons are **always visible** regardless of mode — only the tab strip itself is hover-gated.

##### Tab states

Each tab renders in one of three states:

- **Inactive** — muted background, secondary text color
- **Active** — distinct background (accent-tinted), primary text color, weighted
- **Hover-active** — appears on per-tab hover; reveals the close button (`×`) at the trailing edge of the tab

Title text truncates with an ellipsis (`Untitl…`) when the tab is too narrow to fit the full filename.

##### Tab cap

Hard limit of **15 open tabs** in v0.1. The new-tab button (`+`) and `Cmd+T` are both disabled when the cap is reached — non-responsive, no notification.

Rationale: realistic usage is 3–8 tabs; 15 is a comfortable ceiling that working sessions rarely hit. The cap is provisional and revisited once usage patterns are observed.

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

`Cmd+T` is disabled at the 15-tab cap.

---

#### Persistence

Open tabs and the active-tab pointer **persist across launches**. State storage:

- **v0.1** — `@AppStorage` (UserDefaults). Sufficient for tab IDs and active index; lightweight.
- **v0.2+** — moves to `.pommora//state.json` inside the vault once the watcher + state layer ships. Cross-device sync becomes possible if the vault is cloud-synced.

Tab state survives quit/relaunch. Tab state is **per-window** — opening a second window starts with a single empty tab.

---

#### Button styling

All toolbar buttons render at **compact size** — smaller than SwiftUI's default — to produce the dense Safari-flavored row. Icons stay readable; the row reads as tight rather than padded. This proportion choice is the visual anchor for the whole "compact" feel.

---

#### Constraints

- Window title text is suppressed — the navigation bar replaces it entirely.
- The tab strip never scrolls in v0.1 — equal division only.
- The new-tab button is silently disabled at the 15-tab cap (no error message, no popup).
- Tab drag-to-reorder is not supported in v0.1.
- The back/forward buttons render but are no-ops until navigation history exists.
- Items don't get tabs — they open in their own popover Item window (see `Items.md`).
- Spaces and Pages both get tabs; Items do not.

---

#### Deferred — post-v0.1

##### Tab-overflow scrolling

When the 15-tab cap is eventually lifted, the strip transitions from equal-distribution to **horizontally scrollable**. Tabs hold at a comfortable minimum width (~120pt) and the strip itself scrolls past the visible area like a slider. The back/forward buttons stay pinned to the leading edge; the new-tab and inspector buttons stay pinned to the trailing edge. Only the tab strip middle scrolls.

Switching from "always-show-all-tabs" (equal division) to "scroll-when-too-many" (fixed minimum + scrollable) is the right complexity escalation — only build it if real usage shows the cap actually bites.

##### Tab drag-to-reorder

Reorder tabs by dragging within the strip. Standard browser pattern. Defer until users actually want it.

##### Tab tear-off to new window

Drag a tab out of the strip to open it in a new Pommora window. Heavier interaction work; defer until multi-window editing becomes a real workflow.

##### Back / forward navigation history

The `‹ ›` buttons currently render but no-op. Wiring them requires a per-tab navigation stack (history of which file/space/etc. each tab has previously shown). Build once tabs hold richer state than just "which file is open."

##### New-tab page content

The empty state for a new tab is undefined in v0.1 — main pane shows placeholder content. Likely future direction: a WKWebView-hosted **graph view** of all Pages and their wikilink relationships (Obsidian-style). Depends on the link layer (v0.5). Tracked in `Prospects.md`.

##### Visibility-mode setting

The hover-only vs always-visible-fade toggle becomes a user-facing preference when Settings ships in v0.12.

---

#### Why this exists

Most note-and-database apps use one of two top-bar conventions:

- **Obsidian / VS Code style** — title bar on top, separate tab bar below it, separate toolbar below that. Two or three rows of chrome before content begins.
- **Notion / Linear style** — minimal chrome, no tabs at all; navigation happens through the sidebar or breadcrumbs.

Pommora needs tabs (multi-document workflow is core) but also wants minimal chrome. Safari's compact-tab pattern — chrome and tabs sharing one row — is the only macOS reference point that solves both. Adopting it means:

- More vertical space for actual content (one row of chrome instead of two or three)
- Tabs are a first-class navigation surface, not a hidden affordance
- The sidebar stays usable alongside the tab strip, without competing for horizontal space — both can be present at once
- The whole window reads as visually compact and content-forward, matching Pommora's broader simplicity-first stance

The tradeoff: Safari's compact layout depends on an active-tab-as-address-bar trick that doesn't translate to a notes app. Pommora drops that trick (no URL field) and uses the freed center space purely for tabs. The result is a navigation bar that takes Safari's structural idea and applies it without browser-specific affordances.
