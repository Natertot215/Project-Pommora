## Views UIX Fixes — Sequenced

Tackled one-by-one; perfect each before the next. **Division of labor (carry through all fixes):** the views **dropdown** creates + switches views and switches *type*; the settings **Layout pane** owns the active view's *detailed* settings; **type is the only control shared by both** (Table/Gallery reachable from each → both write `SavedView.type`).

Figma (toolbar area + dropdown): https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora---Swift?node-id=474-9432 · read off Nathan's LIVE desktop selection (the node-URL doesn't resolve via MCP); treat sizing/spacing as DIRECTION, not exact.

**Sequence (locked).** Next session does the cross-view UIX that applies to BOTH renderers — the **menus + banners** — including the toolbar `»` overflow (the headline task). Then build out **Gallery** (after Fix 2). Then re-do the **grouping + sorting** UIX (rudimentary + incomplete today, many issues). **Fix 3** (the Layout-pane rework) lands LAST — only after BOTH Table + Gallery are visually perfect.

> ⚠️ **Toolbar, Views button, and banner chrome are in ACTIVE FLUX — nothing in the toolbar/banner sections below is settled truth for the future.** Two days of toolbar/banner work have left us unable to concretely map dependencies: we don't know how the toolbar truly behaves in relation to views, the Views button, and the toolbar-wide right-click menu; we don't know whether the banner's edge-to-edge bleed interacts with the toolbar; and we don't know how the methods used to make the Views button look correct affect the rest of the toolbar. The Views dropdown only **"looks" good** *right now* — we do not know **at what cost**, nor whether it was reached through the **best (or even correct) methods**. It carries known quirks (it follows into the inspector when toggled — Apple-native apps don't) and assumed-but-unmapped side effects on the rest of the toolbar. Treat every toolbar/banner claim below as a current-state observation or a working theory, **never as a foundation to build on.** **Next priorities here:** finish the remaining UIX-fixes log → identify + remove the toolbar-wide "Icon / Icon + Text" menu → resolve the underlying toolbar uncertainties — *before* resuming Views/grouping. (Context: the toolbar/banner cost is a live motivator for the parallel React + TS rebuild exploration.)

### Fix 1 — Views dropdown internals — DONE (toolbar host/sizing REOPENED, see flux note above)

Dropdown redesigned: fixed-width single-icon **views button** (icon = active view's icon, default `rectangle.3.group`); rows = display-icon + name + a right chevron opening a **type submenu** (flies right); right-click → Rename / **Edit Icon** (the real `IconPicker`, flies left) / Duplicate / Delete; "New View" footer. The active row is clean (grey highlight + blue focus ring removed). `ViewsDropdownButton` / `ViewsPanel` / `ViewsPanelRow`. The dropdown's *internals* are done; the *toolbar hosting + sizing* around it are the unsettled part.

**Toolbar host (current working approach, not closed truth):** the buttons glued together and the views button leaked into the inspector when the `.toolbar` was attached to `inspectorContent`; moving it onto the detail column (via the `NavigationSplitView`, commit `bb6817a`) cleared *that* symptom. This is the right default *today*, but the explanation is a working theory and the move did not resolve the open unknowns below.

### Toolbar cluster — CURRENT STATE + open unknowns (NOT finalized)

**What's in code as of HEAD** (read off the source, not assumed): `.toolbar { }` is hosted on the **detail column** of the `NavigationSplitView`; it emits two trailing items — a standalone icon-only **Views pill** (shown only on container views) and a `.primaryAction` **settings·nav·inspector trio** — each its own `.glassEffect(.regular.interactive(), in: .capsule)` with `.sharedBackgroundVisibility(.hidden)`, plus a `.navigation` back/forward group and a flexible `ToolbarSpacer`. `.toolbarBackground(.hidden, for: .windowToolbar)` on the body. No `WindowToolbarConfigurator`, no `allowsDisplayModeCustomization`. Baseline-and-teardown commits `ced9dd3` / `3a70f14` / `70fe2b1` / `fc613ca`; the toolbar-glyph DRY extraction is `b958cbd`; the trio/Views split is `65dc04d`.

**Working theories (visual-only, NOT future-proof — do not build on these):**
- The `»`-overflow that folded the cluster on macOS 26 cleared when the toolbar moved off the split-view root onto the detail column. The *explanation* offered then — `.primaryAction` anchoring leading-relative to its host, so on the root it measured against the narrow sidebar budget — fit the observed behavior but was **never independently proven**; treat it as a plausible model, not a fact.
- The "squished" Views button traced to `.buttonStyle(.plain)` stripping default toolbar sizing; removing it (not adding frames) restored system-owned height. Well-supported, but, like everything here, not stress-tested against the unknowns below.
- SDK ceiling (read against `MacOSX26.5.sdk`): no trailing action placement (`topBarTrailing` unavailable on macOS), no `ToolbarSpacer` custom width — which is why the cluster uses two custom glass capsules rather than native spacing. The earlier `NSGlassContainerView` attribution was refuted (it's a private *event-handling* subview, not a layout mechanism).

**Open unknowns (why this whole area is flagged in flux):**
- **Inspector adoption.** Both items sit in the trailing region the inspector adopts wholesale, so toggling the inspector folds the Views pill (and trio) *into* the inspector's toolbar segment — a position Apple-native apps don't use. The split into two items keeps the trio from condensing, but it did NOT stop the adoption; excluding the pill was attempted and **failed**. Cause not understood.
- **Unknown blast radius.** The methods used to make the Views button visually correct (the two-item split, the glass capsules, `.sharedBackgroundVisibility`) are *assumed* to affect the rest of the toolbar, but **how is unknown** — we can't currently map which chrome choice causes which symptom.
- **Banner interaction.** The container banner bleeds edge-to-edge under the toolbar via `backgroundExtensionEffect()`; whether that contributes to any toolbar issue is **unknown and untested**.

### Fix 1b — Column / page-row "Edit Icon" → IconPicker popover — NEEDS NATHAN'S PICK

Replace the screen-takeover (`IconPickerSheet`) with the left-flying `IconPicker` popover (the approach used in the views dropdown). Open question — WHICH rows: table/gallery page rows (routed via `ViewSurface` → the global `.sheet`; rows need a per-row anchor, more involved) or sidebar entity rows (Vaults / Areas / Topics / Projects / Sets). (Property rows in Edit Properties already use `iconPickerPopover`.)

### Fix 2 — Banner + revised titles — IN PROGRESS

Current working point on `main` (Nathan set it manually — the baseline; nothing is "fixed" beyond it):

- Detail title → **22pt** (`.title` bold) via new `PUI.DetailHeader` tokens.
- When a banner is set, the title **overlays** it at the bottom-leading corner; plain chrome above the content otherwise (`ViewSurface.headerRegion`).
- Banner **bleeds edge-to-edge under the sidebar + inspector + toolbar** via Apple's `backgroundExtensionEffect()` (macOS 26 Liquid Glass; the Landmarks-sample pattern) — this REPLACED the original plan (window `.titlebarAppearsTransparent` + `.fullSizeContentView`). **Unknown:** whether this under-toolbar bleed interacts with the toolbar chrome problems (see flux note up top) — untested.
- Banner height **140 → 180** (`ContainerBannerView`).
- The title-contrast **stroke was explored (a Core Text inside-stroke) then DROPPED** — the current title is a plain `Label`.

**Pending Fix-2 polish:** the title text baseline should sit on the icon's bottom edge — a plain `Label` centers them, floating the text slightly high — not yet applied.

### Fix 3 — Layout pane revision + type dual-write — QUEUED (lands after BOTH views are visually perfect)

- Settings → Layout pane becomes format-dependent: **Layout Format** row (Table/Gallery); **Table** → Hide Column Borders, Hide Page Icon; **Gallery** → Card Size, Hide Property Titles, Hide Page Icon; **both** → Open In (per-view).
- New `SavedView` fields: `hideColumnBorders`, `hidePageIcon`, `hidePropertyTitles`, per-view `openIn` (today `openIn` lives on `PageType`).
- Type changeable from BOTH the dropdown submenu and this pane → single source of truth on `SavedView.type`.
- Order: the grouping + sorting UIX rework comes FIRST; Fix 3 is the final pass.

### Cleanup / bookkeeping

- **Toolbar-wide "Icon Only / Icon + Text" right-click menu — UNRESOLVED (the crux to kill).** Right-clicking *anywhere* in the toolbar region — the Views pill, the trio, back/forward, the sidebar toggle, AND the empty title-bar space — surfaces a display-mode menu offering "Icon Only" / "Icon + Text". It is NOT scoped to the Views button. **Mechanism unconfirmed.** An exhaustive grep of the Swift sources (06-14) found **no app code that creates it** — no `.contextMenu`, no `Menu`, no `Display As`, no `allowsDisplayModeCustomization`, no `secondaryClickMenu` in the toolbar/Views path; the Views button is a plain icon-only `Button` + `.popover`. Two untested hypotheses remain: (a) the macOS-native NSToolbar display-mode menu that AppKit auto-attaches to any materialized toolbar; (b) an app-level menu leaking toolbar-wide. **Settle which with a live right-click test before any removal attempt — do not assert either as fact.** An `allowsDisplayModeCustomization = false` attempt (set via a window accessor) did NOT suppress it and was reverted.
- **Views-button display toggle (icon vs icon + view name) — DEFERRED (a distinct feature, not the bug above).** Nathan's actually-requested feature: a right-click on the Views button *only* offering "Display as Icon Only" / "Display as Icon + Title", persisted via `viewsButtonStyle` — spec at `// Planning//06-12-Views-V2-Plan.md`. Two builds (`020a663`, then a 06-14 retry) both leaked their `.contextMenu` toolbar-wide and were pulled (`e82bee8`); the dormant `views_button_style` persistence was removed in the teardown (`3a70f14`). Stays deferred until the menu mechanism above is understood — the feature can't be cleanly scoped to one toolbar item while a single-item menu still spans the whole toolbar.
- `.savedView` `SidebarSheet.IconTarget` case may be dead (views Edit Icon moved to the popover) — verify + remove.
- Glass rendering / flyout directions / banner bleed / toolbar placement are NOT CI-verifiable — each needs Nathan's physical pass; CI only guarantees compile + tests green.
