## Views UIX Fixes — Sequenced

Tackled one-by-one; perfect each before the next. **Division of labor (carry through all fixes):** the views **dropdown** creates + switches views and switches *type*; the settings **Layout pane** owns the active view's *detailed* settings; **type is the only control shared by both** (Table/Gallery reachable from each → both write `SavedView.type`).

Figma (toolbar area + dropdown): https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora---Swift?node-id=474-9432 · Figma is read off Nathan's LIVE desktop selection (the node-URL doesn't resolve via MCP); treat sizing/spacing as DIRECTION, not exact.

### Fix 1 — Detach view controls + new dropdown — MOSTLY DONE, toolbar close-out pending

**Done (verify visually):**
- Dropdown redesign: fixed-width single-icon **views button** (icon = active view's icon, default `rectangle.3.group`); rows = display-icon + name + right chevron; active row clean (grey highlight + blue focus ring removed via `.focusEffectDisabled()`); **native Apple toolbar-glass popover background** (no hand-rolled `.chipDropdownPanel()` — toolbar-anchored popovers get auto-glass, WWDC25 #323); chevron → **type submenu flies right**; right-click → Rename / **Edit Icon (reuses real `IconPicker`, flies left)** / Duplicate / Delete; "New View" footer. `ViewsDropdownButton` / `ViewsPanel` / `ViewsPanelRow`.

**ROOT CAUSE found (Nathan): the toolbar was attached to `inspectorContent`, not the main view.** That made the inspector own the toolbar's `primaryAction` context — gluing the 4 buttons together AND surfacing the views button inside the inspector when opened. The whole "merging / reaching / can't-separate" saga (tried: bare `.glassEffect()` HStack → merged; `ToolbarSpacer(.fixed)` → separate but wide gap; `GlassEffectContainer` → morphs/reaches; `glassEffectUnion` → still reaches; per-capsule containers → still reaches) was fighting the inspector. **`.toolbar` moved onto `NavigationSplitView` (commit `bb6817a`).**

**Toolbar close-out (PENDING Nathan's visual after the move):**
- Confirm views button no longer inside the inspector.
- Confirm views capsule + 3-button capsule = two distinct pills, tight gap, no reach/merge. If still glued, standard separate `ToolbarItem`s (or a tight `HStack`) should now work — the inspector context is gone. Eventually adopt the **native toolbar pattern** (drop manual `.glassEffect()`; use `ToolbarItemGroup` + system glass + `ToolbarSpacer`).
- Tune the inter-capsule gap (currently ~8pt).
- Layout: views = its OWN segment; settings + nav + inspector = the other segment (right-most). `GlassEffectContainer` is a MORPH primitive — do NOT use it to *separate*.

### Fix 1b — Column / page-row "Edit Icon" → IconPicker popover — NEEDS NATHAN'S PICK

Replace the screen-takeover (`IconPickerSheet`) with the left-flying `IconPicker` popover (the approach Nathan liked in the views dropdown). Open question: WHICH rows —
- **table/gallery page rows** (right-click → Edit Icon, routed via `ViewSurface` → the global `.sheet`; rows are AppKit `NSOutlineView` cells → needs a per-row anchor, more involved), or
- **sidebar entity rows** (Vaults / Areas / Topics / Projects / Sets).
- (Property rows in Edit Properties already use `iconPickerPopover` — done.)

### Fix 2 — Banner backdrops the chrome — QUEUED

- Banner image extends into the toolbar + title-bar (full-bleed top), behind the detail title. Needs window `.titlebarAppearsTransparent` + `.fullSizeContentView` (today `.unified(showsTitle: false)`, banner sits below the toolbar).
- When a banner is present: the title text **+ its icon** get a 2pt outside stroke in the secondary-label color, for contrast over any image.
- Also perfects the top-region alignment.

### Fix 3 — Layout pane revision + type dual-write — QUEUED

- Settings → Layout pane becomes format-dependent (Figma photo 2): **Layout Format** row (Table/Gallery); **Table** → Hide Column Borders, Hide Page Icon; **Gallery** → Card Size, Hide Property Titles, Hide Page Icon; **both** → Open In (per-view).
- New `SavedView` fields: `hideColumnBorders`, `hidePageIcon`, `hidePropertyTitles`, per-view `openIn` (today `openIn` lives on `PageType`, not the view).
- Type changeable from BOTH the dropdown submenu and this pane → single source of truth on `SavedView.type`.

### Cleanup / bookkeeping

- Dormant "Show View Title" persistence (`views_button_style` field + `OrderPersister.setViewsButtonStyle`) now uncalled — remove in a persistence pass.
- `.savedView` `SidebarSheet.IconTarget` case may be dead now (views Edit Icon moved to the popover) — verify + remove.
- `main` is LOCAL-ONLY, far ahead of `origin/main`, NOT pushed.
- Glass rendering / flyout directions / gaps / reaching / banner are NOT CI-verifiable — each needs Nathan's physical pass; CI only guarantees compile + 1214 tests green.
