## PagePreviewWindow — V9 Real-Window Rebuild

> **COMPLETE — shipped at v0.4.0 (2026-06-10, 987 tests green).** Executed with live screenshot-verified iteration on The Nexus; the inspector pivoted mid-execution from a styled preview pane to mounting the REAL `FrontmatterInspector` (compact scale, dual-domain meta removal). Deviations from plan: the P0 spike folded into live verification; `windowResizeBehavior(.disabled)` was removed (it froze all resizing); the hairline alignment landed naturally via the 46pt title bar + flush cards instead of a nudge. Record → `History.md` § "v0.4.0".

Replaces the V8 in-window glass card (`PreviewStack` overlay) with a real `WindowGroup`-created window. Drafted 2026-06-10 from Nathan's rulings + four research reports (SwiftUI window scenes, `.inspector` mechanics, AppKit child windows, Mail-compose survey). Supersedes the V8 primitive in `PagesV2.md` §P5.

### Locked decisions (Nathan, 2026-06-10)

1. **Proper SwiftUI `WindowGroup`** — SwiftUI creates the real window; an AppKit pass restricts it. NOT a hand-rolled AppKit window/panel (that is the named fallback only if the spike fails).
2. **Visually identical to a separate Mail/Notes window** — standard `windowBackground` material, system shadow/corners/hairlines/fonts. Zero glass, zero custom card styling. One substitution: two capsule buttons (✕ close top-left, inspector toggle top-right) where traffic lights would be.
3. **A real window in the hand, invisible to the system**: drags/resizes/focuses like any window; Cmd-W closes; but no traffic lights, no Dock minimize, no Window-menu entry, no Cmd-` cycling, no Mission Control card, never floats over other apps, moves with + stays above the main window (child attachment), closes with the main window and on Nexus switch.
4. **"Fullscreen" = promote**: native fullscreen disabled at every level; the fullscreen shortcut (Ctrl-Cmd-F) and titlebar-strip double-click (zoom) on a focused preview route to Open-in-main-pane (flush → select in main window → close preview). No Escape-to-close (real windows don't).
5. **Tables keep double-click to open**; sidebar stays single-click. Routing per `open_in` unchanged.
6. **Focus on open** — the preview becomes key immediately, like any opened window.
7. **System-default placement; fresh defaults every open** — no cascade logic, no per-page frame memory, `.restorationBehavior(.disabled)`.
8. **Inspector defaults open; toggling widens/shrinks the window** by the inspector width — the body column never squeezes.
9. **Figma sizes dropped** (475/685 were drawing conventions). Sizes are tunable constants: default ≈720×540 inspector-open (body ≈510), min ≈420×360. Tuned on sight in P1.
10. **Lock model preserved**: opens locked; unlock reveals Open; re-lock flushes. Title/icon inline editing preserved.
11. **Chrome locks (Nathan, 2026-06-10)**: (a) the two capsule buttons are **Liquid Glass** — per the Figma `Window/Button` component (glass capsule + soft drop shadow `0 8 20 @ 12%`, 36×26, 10pt semibold glyph) — the one sanctioned glass on an otherwise standard-material window; (b) the header row IS the **title bar** — ✕ capsule · page icon + inline-editable title · inspector capsule — and doubles as the native drag strip; (c) **uniform-distance dividers** per the P5 transcript spec: header and footer hairlines share one rail inset (separator ends align with the capsules' horizontal bounds, equal gap each end), and the header's vertical rhythm is equal padding above and below the title row (`headerVPad` top == title→separator).

### Research constraints (verified, with sources in session transcript)

- `WindowGroup(id:for: PageRef.self)` dedupes per value (re-open focuses existing). `dismissWindow(id:)` closes ALL of the group — the Nexus-switch close-all. Custom close uses `dismiss()` from the root.
- `.windowStyle(.hiddenTitleBar)` keeps all standard window behavior (background, shadow, resize, top-strip drag); traffic lights are then hidden via AppKit (`standardWindowButton(_:)?.isHidden`). `.plain` is rejected: drops the standard background; shadow/resize undocumented.
- Window menu + Cmd-` exclusion REQUIRE AppKit: `isExcludedFromWindowsMenu = true` + `collectionBehavior` `.ignoresCycle`. Also set `.transient` (no Mission Control entry), `.fullScreenNone`, `tabbingMode = .disallowed`. Children do NOT inherit collectionBehavior — set on the child.
- `NSWindow.addChildWindow(_:ordered: .above)`: child rides parent moves (window-server-side), stays above parent always, drags free without detaching, hides with parent minimize/app hide. Parent close does NOT close children → explicit close via parent `willCloseNotification`. Known hazard: reset `firstResponder` before detaching a focused child.
- `.inspector` does NOT widen the window natively (squeezes content) → P0 spike picks the widen mechanism: (a) macOS 26 synchronized content-driven window resize, or (b) manual animated `setFrame` ± inspectorWidth with the inspector animation suppressed via transaction. `inspectorColumnWidth(210)` fixed inside the closure; `interactiveDismissDisabled` to block divider-collapse.
- View modifiers (macOS 15+): `.windowMinimizeBehavior(.disabled)`, `.windowFullScreenBehavior(.disabled)`, `.windowResizeBehavior(.disabled)` (kills zoom). Scene: `.commandsRemoved()`, `.windowBackgroundDragBehavior(.enabled)`, macOS 26 `.windowResizeAnchor(.topLeading)` for the widen animation.
- Mail-compose finding: Tahoe Mail keeps traffic lights; the two-button idiom is iPadOS 26's window-control language. Pommora's design is a deliberate novel idiom on the Mac — mechanism fully supported.

### Architecture

- **Scene** (`PommoraApp`): `WindowGroup("Page Preview", id: "page-preview", for: PageRef.self)` → `PagePreviewWindowRoot`. Scene modifiers per above. `PageRef` is already `Codable + Hashable` (built for this).
- **Env bootstrap**: root reads `AppGlobals.current` (NexusEnvironment publishes itself for standalone scenes) → `.injectNexusEnvironment(env)`; nil env or nil ref → self-dismiss.
- **`PagePreviewContent`**: port of `PagePreviewCard`'s data layer (load/resolve via `PageRef.resolve`, `PageEditorViewModel` + saver, rename/icon commits, lock, flush-on-close/promote) with the window layout: header rail / hairline / `MarkdownPMEditor` / footer, `.inspector { PagePreviewInspector }`. Drops: drag/resize gestures, clamp math, grip, glass, z-order.
- **`PreviewWindowConfigurator`** (`NSViewRepresentable`, runs once per window on `viewDidMoveToWindow`): hide 3 standard buttons; `isExcludedFromWindowsMenu`; `tabbingMode = .disallowed`; `collectionBehavior = [.transient, .ignoresCycle, .fullScreenNone]`; attach as child of the main window (`identifier` prefix `"main"`); observe parent `willClose` → close self; surface the `NSWindow` for the widen mechanism + zoom interception.
- **`PageOpenRouter`** (rehomed from `PreviewStack`): `destination(for:page:currentSelection:)` + `routeOpen` overloads taking an `openPreview: (PageRef) -> Void` closure (testable; call sites pass `{ openWindow(id: "page-preview", value: $0) }`). Conflict guard (`.suppressed`) unchanged.
- **Call sites**: SidebarView, PageTypeDetailView, PageCollectionDetailView, ComponentLibraryView → router/`openWindow`. ContentView: overlay block removed; `rebuildEnvironment` → `dismissWindow(id: "page-preview")`. NexusEnvironment: `previewStack` property + inject line removed.
- **Deleted wholesale**: `PreviewStack.swift`, `PagePreviewCard.swift` (incl. `PreviewOverlayHost`). No dead code.
- **Metrics**: one `PreviewWindowMetrics` enum — defaultSize, minSize, inspectorWidth (210), capsule 36×26, rail inset, glyph 10pt semibold.
- **Component Library**: the glass capsule window-button is staged as a reusable (`WindowCapsuleButton`, mirroring the Figma `Window/Button` component) and pulled into the preview window — not inlined (Component Library hard rule). The P5 `capsuleControl` inline helper retires into it.

### Phases

- **P0 — Spike (throwaway scratch scene, no port).** Verify on this machine: (1) child-attach of a WindowGroup window — ordering survives SwiftUI scene updates, rides parent drag, hides with minimize; (2) traffic-light hiding sticks across scene re-renders (re-apply on `windowDidBecomeKey` if not); (3) the inspector widen mechanism — macOS 26 synchronized resize vs manual `setFrame`; (4) `dismissWindow(id:)` group close-all. Output: a findings note that locks the P1 mechanisms. If (1) fails irreparably → STOP, surface to Nathan with the AppKit-panel fallback proposal.
- **P1 — Window + chrome.** Scene + root + content + configurator + metrics; visual pass with Nathan against the Mail/Notes-window standard (live screenshots); size constants tuned. Lock/footer/title/icon behavior ported verbatim. Fullscreen/zoom → promote wiring.
- **P2 — Wiring + demolition.** PageOpenRouter rehome; four call sites; ContentView/NexusEnvironment cleanup; delete PreviewStack/PagePreviewCard; test surgery (PreviewStackTests → PageOpenRouterTests: 5 destination + 3 routeOpen spy tests survive; 6 card-stack tests die — system-owned now). Green commit via background builder (quirk #13), executed-count reconciled (991 → ≈988).
- **P3 — Docs.** CLAUDE.md "Pages open per…" bullet rewritten (no separate window scene → real WindowGroup child window); `Features/Pages.md` § Opening behavior; `History.md` V9 entry; this plan → `Superseded/` on completion.

### Verification idiom

Every phase ships as a clean-room-verified green commit (build + full `-only-testing:PommoraTests`, non-zero executed count, no SIGTRAP/hang signatures). P1's visual gate is Nathan-reviewed screenshots of the running window. Working-tree caveat (quirk #10) applies.

### Risks

| Risk | Mitigation |
| --- | --- |
| SwiftUI fights child-window ordering on scene updates | P0 spike first; fallback = AppKit-created panel hosting identical SwiftUI content (pixel-identical result) |
| Inspector widen double-animates | Spike picks ONE mechanism; transaction-suppress the other |
| Traffic-light hiding reset by SwiftUI re-render | Re-apply in `windowDidBecomeKey` (research-known pattern) |
| Restored preview windows orphaned at launch | `.restorationBehavior(.disabled)` + nil-ref self-dismiss |
| Main-window identifier lookup ("main" vs "main-AppWindow-1") | Prefix match, hoisted into one shared locator (also fixes the existing exact-match lookups at ContentView:245 + ComponentLibraryView:416) |
