## Views UIX Fixes — Sequenced

Tackled one-by-one; perfect each before the next. **Division of labor (carry through all fixes):** the views **dropdown** creates + switches views and switches *type*; the settings **Layout pane** owns the active view's *detailed* settings; **type is the only control shared by both** (Table/Gallery reachable from each → both write `SavedView.type`).

Figma (toolbar area + dropdown): https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora---Swift?node-id=474-9432 · read off Nathan's LIVE desktop selection (the node-URL doesn't resolve via MCP); treat sizing/spacing as DIRECTION, not exact.

**Sequence (locked).** Next session does the cross-view UIX that applies to BOTH renderers — the **menus + banners** — including the toolbar `»` overflow (the headline task). Then build out **Gallery** (after Fix 2). Then re-do the **grouping + sorting** UIX (rudimentary + incomplete today, many issues). **Fix 3** (the Layout-pane rework) lands LAST — only after BOTH Table + Gallery are visually perfect.

### Fix 1 — Views dropdown + toolbar — DONE

Dropdown redesigned: fixed-width single-icon **views button** (icon = active view's icon, default `rectangle.3.group`); rows = display-icon + name + a right chevron opening a **type submenu** (flies right); right-click → Rename / **Edit Icon** (the real `IconPicker`, flies left) / Duplicate / Delete; "New View" footer. The active row is clean (grey highlight + blue focus ring removed). `ViewsDropdownButton` / `ViewsPanel` / `ViewsPanelRow`.

**Root cause (closed):** the buttons were gluing together and the views button was leaking into the inspector because the `.toolbar` was attached to `inspectorContent` — so the inspector owned the `primaryAction` context. Moved the toolbar onto the `NavigationSplitView` (commit `bb6817a`); recorded in `// Guidelines //Design.md`.

### Toolbar `»` overflow — leading hypothesis (UNCONFIRMED, pending screenshots)

macOS 26 folds the primary-action controls (views / settings / nav / inspector) into the `»` overflow menu. An all-opus investigation (code + the macOS 26.5 SDK + Apple docs, 06-14) produced a **leading hypothesis — NOT yet confirmed; we confirm via the host-move fix + screenshots before calling it the root cause:**

- **Host-anchoring (leading hypothesis).** `.primaryAction` is the **leading edge** on macOS (Apple doc, verbatim), and the `.toolbar` is attached to the `NavigationSplitView` **root** — so `.primaryAction` resolves to the **sidebar** (primary column), and the overflow pass would measure the cluster against the *sidebar's* narrow width budget (~180–330pt), not the window. That would explain the fold into `»`, the `ToolbarItemGroup` landing over the sidebar, and the overflow-even-maximized. (`.navigation` back/forward are immune — a non-overflow leading slot.)
- **Single-blob packing (suspected amplifier).** All four controls sit in one atomic `ToolbarItem(.primaryAction)` wrapping a custom `HStack`.
- **Empty-when-nil (suspected confound).** The capsule renders empty while `nexusEnvironment` is nil (`ContentView.swift:86`) — a zero/variable-size item biases toward overflow.
- **SDK ceiling (verified vs `MacOSX26.5.sdk`):** macOS has NO trailing action placement (`topBarTrailing` is `@available(macOS, unavailable)`); `visibilityPriority` / `topBarPinnedTrailing` / `toolbarOverflowMenu` are absent; `ToolbarSpacer` is present.
- **REFUTED (confirmed false):** the earlier `NSGlassContainerView` attribution — that's a *private event-handling* toolbar subview (it swallows mouse clicks; workaround `.buttonStyle(.borderless)`), NOT a layout/overflow mechanism. Also ruled out: a merging second toolbar (none exists in the main tree) and the banner / `backgroundExtensionEffect` (the overflow predates it by ~17 days).

**Test in progress:** host the `.toolbar` on the **detail** (so `.primaryAction` leaves the narrow sidebar column) + decompose the single item; keep the existing buttons + liquid-glass placement. Confirm via screenshots BEFORE establishing the root cause.

### Fix 1b — Column / page-row "Edit Icon" → IconPicker popover — NEEDS NATHAN'S PICK

Replace the screen-takeover (`IconPickerSheet`) with the left-flying `IconPicker` popover (the approach used in the views dropdown). Open question — WHICH rows: table/gallery page rows (routed via `ViewSurface` → the global `.sheet`; rows need a per-row anchor, more involved) or sidebar entity rows (Vaults / Areas / Topics / Projects / Sets). (Property rows in Edit Properties already use `iconPickerPopover`.)

### Fix 2 — Banner + revised titles — IN PROGRESS

Current working point on `main` (Nathan set it manually — the baseline; nothing is "fixed" beyond it):

- Detail title → **22pt** (`.title` bold) via new `PUI.DetailHeader` tokens.
- When a banner is set, the title **overlays** it at the bottom-leading corner; plain chrome above the content otherwise (`ViewSurface.headerRegion`).
- Banner **bleeds edge-to-edge under the sidebar + inspector** via Apple's `backgroundExtensionEffect()` (macOS 26 Liquid Glass; the Landmarks-sample pattern) — this REPLACED the original plan (window `.titlebarAppearsTransparent` + `.fullSizeContentView`).
- Banner height **140 → 180** (`ContainerBannerView`).
- The title-contrast **stroke was explored (a Core Text inside-stroke) then DROPPED** — the current title is a plain `Label`.

**Pending Fix-2 polish:** the title text baseline should sit on the icon's bottom edge — a plain `Label` centers them, floating the text slightly high — not yet applied.

### Fix 3 — Layout pane revision + type dual-write — QUEUED (lands after BOTH views are visually perfect)

- Settings → Layout pane becomes format-dependent: **Layout Format** row (Table/Gallery); **Table** → Hide Column Borders, Hide Page Icon; **Gallery** → Card Size, Hide Property Titles, Hide Page Icon; **both** → Open In (per-view).
- New `SavedView` fields: `hideColumnBorders`, `hidePageIcon`, `hidePropertyTitles`, per-view `openIn` (today `openIn` lives on `PageType`).
- Type changeable from BOTH the dropdown submenu and this pane → single source of truth on `SavedView.type`.
- Order: the grouping + sorting UIX rework comes FIRST; Fix 3 is the final pass.

### Cleanup / bookkeeping

- Dormant "Show View Title" persistence (`views_button_style` field + `OrderPersister.setViewsButtonStyle`) — remove in a persistence pass.
- `.savedView` `SidebarSheet.IconTarget` case may be dead (views Edit Icon moved to the popover) — verify + remove.
- Glass rendering / flyout directions / banner bleed / toolbar placement are NOT CI-verifiable — each needs Nathan's physical pass; CI only guarantees compile + tests green.
