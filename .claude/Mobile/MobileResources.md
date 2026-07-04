## Mobile — Resources

The concrete tools, libraries, and references for the companion build — what to use, what to write, what to avoid. Version numbers are the current target lines, not endorsements; the decisions are the durable part.

### The Shell and Build

- **Capacitor** (current major line) — the native WebView shell. It consumes the renderer's existing Vite output as its web assets, so electron-vite is left untouched and Capacitor is added as a second, parallel consumer. Not `@capacitor-community/electron`, which would make Capacitor own the Electron build — abandoned and wrong-shaped. One hard gate: the current Capacitor major needs a recent Node and Xcode — verify the toolchain first.
- **Shared bundle** — the whole integration is `webDir` pointing at the renderer's build output. The app renderer has no standalone Vite config today (its build lives inside the electron-vite config), so the mobile target needs a **net-new standalone Vite config** mirroring the electron-vite renderer block — React, vanilla-extract, the `@shared`/`@renderer` aliases, the app entry HTML, and the mobile base path. The repo's existing standalone `vite.config.ts` builds only the design-system showcase, not the app. Monorepo write-ups exist for a Capacitor app beside a web app; no single template does electron-vite-plus-Capacitor, and none is needed.
- **Dev workflow** — point the WebView at the Vite dev server over the LAN for hot-reload on a real device; inspect the WebView from Safari's Web Inspector. The Xcode round-trip (sync, open, sign, run) is the native step.

### Native Filesystem and iCloud

- **`@capacitor/filesystem`** (official) — routine reads and writes. Day-one requirement: enable the Files-app sharing flags so the nexus is user-visible and agent-legible, not trapped in a private sandbox.
- **The iCloud plugin — write our own.** No existing plugin gives persistent, writable, bookmark-backed folder access with iCloud stub-materialization: the maintained pickers are read-only and one-shot, and the one plugin with the right bookmark model is abandoned. It is a small custom Capacitor plugin (a few hundred lines of Swift) exposing resolve-folder, read-tree, write-file, and materialize. The app-owned ubiquity container is the v1 resolver; the folder-picker-plus-bookmark path is the Prospect resolver behind the same seam (NexusSync.md).
  - **References to mirror:** an iOS Markdown-notes app that syncs an iCloud folder (fsnotes) for the real sync shape; a canonical iOS-directory-bookmark write-up for the picker path; a deep iCloud-documents guide for stub detection and materialization. A dead proof-of-concept shows the bookmark round-trip structurally.
  - **The gotcha:** iOS bookmarks use `.minimalBookmark`, not macOS's `.withSecurityScope` — copying macOS sample code here is the classic mistake.

### The Editor on Touch

- **No turnkey CM6 mobile toolbar exists** — compose it: a keyboard-accessory bar positioned by tracking the visual viewport (a small hook handles the riding math), with buttons calling CodeMirror commands (an existing package supplies the command set).
- **`@capacitor/keyboard`** (official) — set resize mode to `none` and disable the plugin's own scroll so the editor owns its layout; use it to hide the OS accessory bar so only ours shows.
- **CM6 input tuning** — set autocapitalize/autocorrect/spellcheck on the editable via content attributes (the editor defaults them off), knowing iOS text assistance is only partly reliable inside a syntax-rewriting editor. Target a recent `@codemirror/view` for the accumulated iOS selection and keyboard fixes, and audit that no style rule suppresses native selection.
- **Reference:** Atomic Editor — an Obsidian-style inline-preview CM6 editor with explicit iOS scroll and selection hardening, the closest thing to copy from. No open-source CM6-inside-Capacitor exemplar exists; the WebView wiring is assembled from the Keyboard docs plus the viewport hook.

### The Mobile Shell UI

- **Swipe drawer** — a maintained two-sided edge-swipe primitive (`@luciodale/swipe-bar`, zero-dependency, overlay-or-push) or a DIY build on a gesture library plus Pommora's own motion source. Vaul, the obvious pick, is now unmaintained — avoid it for a surface used daily.
- **Touch drag-to-reorder** — `@dnd-kit` with its TouchSensor and a delay-activation constraint gives long-press-then-drag so a plain swipe still scrolls; lift its official sortable-tree example rather than the stale wrapper package, and keep `touch-action: manipulation` on draggable rows.
- **Safe-area** — pure CSS on iOS: the viewport-cover meta plus the inset environment variables, with `@capacitor/status-bar` for the bar style. A community safe-area plugin is only needed if Android is ever added.

### Liquid Glass

- **The bottom bar → native overlay.** A Capacitor native-navigation plugin renders a real iOS 26 system Liquid Glass tab/tool bar over the WebView (cactuslab's native-navigation, packaged as `@capgo/capacitor-native-navigation`, exposes a `glass: liquidGlass` option; `stay-liquid` is a forkable proof-of-concept). The only route to authentic system glass without private APIs. Reserve the bar's height as a safe-area inset; native taps bridge to the router.
- **Loose buttons → in the WebView** on Pommora's existing `@samasante/liquid-glass` Controls material. It refracts through an element `filter` (not only the Chromium-only backdrop path) and ships Safari workarounds — but it also sets a `backdrop-filter: url()` WebKit may not honor, so **verify on-device and keep a flat-fill fallback** before relying on in-WebView glass. Keep glassed elements small and few to avoid scroll-time filter cost.
- **Rejected:** real system glass directly from web CSS (the private `-apple-visual-effect` property) — it works but is private API and an App Store rejection.

### Native Integrations

- **Apple Shortcut / App Intents** for Quick Capture — native Swift, no turnkey plugin. Home-screen quick actions have a community plugin; the modern App Intents system is a small hand-written intent that talks to the bridge.

### Distribution

- **The paid Apple Developer Program is mandatory** — the iCloud capability is blocked on free personal teams, so the free 7-day sideload (and AltStore-style auto-refresh) is off the table the moment the app syncs via iCloud.
- **TestFlight internal is the solo-user path** — no App Review, builds install from the TestFlight app, and the only upkeep is a trivial re-upload roughly every ninety days (scriptable). Ad-hoc is the alternative for a full year between touches, at the cost of UDID and certificate management; the App Store is overkill for a personal tool.
