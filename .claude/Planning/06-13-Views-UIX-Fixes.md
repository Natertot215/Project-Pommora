## Views UIX Fixes — Sequenced

Tackled one-by-one; perfect each before the next. **Division of labor (carry through all fixes):** the views **dropdown** creates + switches views and switches *type*; the settings **Layout pane** owns the active view's *detailed* settings; **type is the only control shared by both** (Table/Gallery reachable from each → both write `SavedView.type`).

Figma (toolbar area + dropdown): https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora---Swift?node-id=474-9432

### Fix 1 — Detach view controls + new dropdown — ACTIVE

- **Detach + gate.** Lift the views button (`ViewsDropdownButton`) + the view-settings/sliders button (`ViewSettingsButton`) out of ContentView's `ToolbarItem(.primaryAction)` into an in-content top-trailing overlay; **hidden** unless the selection is `.pageType` or `.collection`. Nav-dropdown + inspector stay global toolbar items. Removes the system "Icon & Text" toolbar toggle.
- **New dropdown.** Row = view icon (display-only) + name + right chevron; active view = row **highlight**. Left-click row → switch active view; chevron → **right-flyout type submenu** (Table / Gallery); right-click → **Rename · Edit Icon · Duplicate · Delete**; "+ New View" footer (defaults Table).
- **Edit Icon = menu picker**, not the full-screen `IconPickerSheet` takeover (for views).
- Keep the custom "Show View Title" toggle (no longer a toolbar item).

### Fix 2 — Banner backdrops the chrome — QUEUED

- Banner image extends into the toolbar + title-bar (full-bleed top), behind the detail title. Needs window `.titlebarAppearsTransparent` + `.fullSizeContentView` (today it's `.unified(showsTitle: false)`, banner below the toolbar).
- When a banner is present: title text **+ its icon** get a 2pt outside stroke in the secondary-label color, for contrast over any image.

### Fix 3 — Layout pane revision + type dual-write — QUEUED

- Settings → Layout pane becomes format-dependent: **Layout Format** row (Table/Gallery); **Table** → Hide Column Borders, Hide Page Icon; **Gallery** → Card Size, Hide Property Titles, Hide Page Icon; **both** → Open In (per-view).
- New `SavedView` fields: `hideColumnBorders`, `hidePageIcon`, `hidePropertyTitles`, per-view `openIn` (today `openIn` lives on `PageType`, not the view).
- Type changeable from BOTH the dropdown submenu and this pane → single source of truth on `SavedView.type`.
