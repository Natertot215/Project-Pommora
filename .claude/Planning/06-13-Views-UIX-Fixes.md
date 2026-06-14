## Views UIX Fixes — Sequenced

Tackled one-by-one; perfect each before the next. **Division of labor (carry through all fixes):** the views **dropdown** creates + switches views and switches *type*; the settings **Layout pane** owns the active view's *detailed* settings; **type is the only control shared by both** (Table/Gallery reachable from each → both write `SavedView.type`).

Figma (toolbar area + dropdown): https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora---Swift?node-id=474-9432 · read off Nathan's LIVE desktop selection (the node-URL doesn't resolve via MCP); treat sizing/spacing as DIRECTION, not exact.

**Sequence (locked).** Next session does the cross-view UIX that applies to BOTH renderers — the **menus + banners** — including the toolbar `»` overflow (the headline task). Then build out **Gallery** (after Fix 2). Then re-do the **grouping + sorting** UIX (rudimentary + incomplete today, many issues). **Fix 3** (the Layout-pane rework) lands LAST — only after BOTH Table + Gallery are visually perfect.

### Fix 1 — Views dropdown + toolbar — DONE

Dropdown redesigned: fixed-width single-icon **views button** (icon = active view's icon, default `rectangle.3.group`); rows = display-icon + name + a right chevron opening a **type submenu** (flies right); right-click → Rename / **Edit Icon** (the real `IconPicker`, flies left) / Duplicate / Delete; "New View" footer. The active row is clean (grey highlight + blue focus ring removed). `ViewsDropdownButton` / `ViewsPanel` / `ViewsPanelRow`.

**Root cause (closed):** the buttons were gluing together and the views button was leaking into the inspector because the `.toolbar` was attached to `inspectorContent` — so the inspector owned the `primaryAction` context. Moved the toolbar onto the `NavigationSplitView` (commit `bb6817a`); recorded in `// Guidelines //Design.md`.

### Toolbar `»` overflow — CONFIRMED (host-anchoring)

macOS 26 folded the primary-action controls (views / settings / nav / inspector) into the `»` overflow menu. An all-opus investigation (code + the macOS 26.5 SDK + Apple docs, 06-14) plus the host-move fix + screenshots **confirmed the root cause:**

- **Host-anchoring (CONFIRMED).** `.primaryAction` is the **leading edge** on macOS (Apple doc, verbatim), and the `.toolbar` was attached to the `NavigationSplitView` **root** — so `.primaryAction` resolved to the **sidebar** (primary column), and the overflow pass measured the cluster against the *sidebar's* narrow width budget (~180–330pt), not the window. This explained the fold into `»`, the `ToolbarItemGroup` landing over the sidebar, and the overflow-even-maximized. (`.navigation` back/forward are immune — a non-overflow leading slot.) **Fix (shipped):** host the `.toolbar` on the **detail column** so `.primaryAction` leaves the narrow sidebar; the single-item cluster no longer overflows.
- **SDK ceiling (verified vs `MacOSX26.5.sdk`):** macOS has NO trailing action placement (`topBarTrailing` is `@available(macOS, unavailable)`); `visibilityPriority` / `topBarPinnedTrailing` / `toolbarOverflowMenu` are absent; `ToolbarSpacer` is present but has no custom-width sizing — so a tight gap between two *native* pills is impossible, which is why the cluster uses two custom `.glassEffect()` capsules.
- **REFUTED (confirmed false):** the earlier `NSGlassContainerView` attribution — a *private event-handling* toolbar subview (it swallows mouse clicks; workaround `.buttonStyle(.borderless)`), NOT a layout/overflow mechanism. Also ruled out: a merging second toolbar (none exists in the main tree) and the banner / `backgroundExtensionEffect` (the overflow predated it by ~17 days).

### Toolbar cluster — FINALIZED (06-14 teardown + review)

The primary-action cluster is conclusively done — two Liquid Glass capsules (**Views** pill | **settings·nav·inspector** trio) at a tight `PUI.Spacing.md` gap, hosted on the **detail column**, with `.sharedBackgroundVisibility(.hidden)` killing the "reaching" and **system-owned height** (the squish was caused by `.buttonStyle(.plain)` on the Views button stripping the default toolbar sizing — removing it was the fix). Baseline `ced9dd3`; teardown `3a70f14` (dead scaffolding) + `70fe2b1` (redundant `GlassEffectContainer` dropped, gap tokenized) + `fc613ca` (comment/doc truth-up). A full `bb6817a..HEAD` review came back merge-quality; its one DRY finding shipped as the `.toolbarGlyph(width:)` modifier + `PUI.Icon.toolbar*` tokens (`b958cbd`). Glass/height/host claims verified against `MacOSX26.5.sdk` and a live capture. Spec → `// Guidelines //Design.md` "Chrome animation" + "Liquid Glass continuity".

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

- **DONE (06-14, `3a70f14`)** — Dormant "Show View Title" persistence (`views_button_style` field + `OrderPersister.setViewsButtonStyle`) removed in the toolbar teardown; zero readers confirmed.
- `.savedView` `SidebarSheet.IconTarget` case may be dead (views Edit Icon moved to the popover) — verify + remove.
- Glass rendering / flyout directions / banner bleed / toolbar placement are NOT CI-verifiable — each needs Nathan's physical pass; CI only guarantees compile + tests green.
