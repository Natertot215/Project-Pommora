## Mobile — Companion iOS App

Pommora's companion iPhone app: a phone-side client that reads and writes the **same nexus files** as the desktop app, kept in sync through iCloud. It is not a standalone product and never creates its own nexus — it depends on a desktop-synced nexus and edits it from a second device.

This folder holds the mobile-integration specs. Read this overview first; `MobileArchitecture.md` covers how the desktop build is reused, `NexusSync.md` the iCloud model, `FormFactor.md` the phone UX, `MobilePM.md` the touch editor, and `MobileResources.md` the concrete tooling. Provenance and the full decision trail live in `MobileDecisionLog.md`.

### The Core Decision

The mobile app is a **port, not a rewrite**. Pommora's renderer is already cleanly separated from its Node "main" process by a narrow typed IPC boundary, and the renderer never touches Node. That boundary is exactly where the mobile port cuts: the renderer is reused whole, and the main process is re-hosted on the phone's terms.

- **Framework — Capacitor.** The existing React renderer runs unchanged inside a native WebView shell — same components, same CSS, same CodeMirror editor. This is the architecture Obsidian's own mobile app uses (a web app plus CodeMirror in a Capacitor shell). React Native was rejected: it has no DOM or CSS, can't run the editor natively, and would rewrite the entire interface.
- **Sync — iCloud, no accounts.** The nexus lives in an iCloud Drive folder the desktop writes to; the phone reads and writes the same folder. Sync rides the user's Apple ID — there is no login and no account system. Full model in `NexusSync.md`.
- **Single-user, most-recent-wins.** Pommora is personal-first and used from one place at a time, so the sync model is deliberately most-recent-wins — no merge, no collaboration machinery.

### Division of Labor

Building the companion is well-scoped work, not research. The counterintuitive part: mechanical UI "porting" is nearly zero, because the interface ships as-is in the WebView. The real effort concentrates in three places.

- **Claude builds:** the renderer's UI ships almost untouched — the visual layer carries over verbatim, with a few host-boundary seams the exception (a `window.nexus` bridge shim, since Capacitor has no Electron `contextBridge`; asset-URL resolution, since image URLs hardcode an Electron-only scheme; native menus rebuilt as in-WebView surfaces; and a net-new mobile Vite config, since the existing standalone one builds only the showcase). Beyond that: re-host the main process as native filesystem access behind Capacitor plugins (most of it thin file-io wrappers), the native iCloud plugin and its sync hardening, and the mobile shell once the form factor is set.
- **Nathan owns:** the Apple platform ceremony — the **paid Apple Developer Program** (mandatory the moment iCloud is used; there is no free path for an iCloud app), Xcode, signing, the iCloud entitlement, and getting the app onto the phone. The least-friction install for a single user is **TestFlight internal** — no App Review, builds land instantly, with a trivial re-upload roughly every ninety days. Mechanical, but only the person holding the Apple ID and the device can do it.
- **The genuinely hard parts:** the phone form factor (real design, not porting), the sync edge-cases (evicted files, conflict copies), and the iOS known-container constraint. All named, and correctly small.

### Already Shipped — Desktop Pre-Paves

Cheap, behavior-preserving changes already on `main` that shrink the eventual port (all no-op or DRY on desktop; typecheck + build verified):

- **App build target** — `vite.config.app.ts` + `dev:app` / `build:app`: builds the renderer standalone (`dev:app` runs the real UI in any browser; `build:app` → `dist-app/` is Capacitor's `webDir`). Verified — 2,250 modules build clean.
- **`assetUrl.ts`** — one shared `nexus-asset://` image-URL helper (was 3 identical copies) so the mobile host swaps a single function.
- **`DEVICE_LOCAL_NEXUS_FILES`** (`paths.ts`) — names the four per-machine `.nexus` files so iCloud sync-exclusion references one constant (C-4c).
- **Editor input attributes** (MarkdownPM) — iOS soft-keyboard `autocapitalize` / `autocorrect` / `spellcheck` / `enterkeyhint`; inert on desktop.
- **`viewport-fit=cover` + `--safe-*` vars** — the safe-area tokens the drawers and Liquid-Glass bottom bar mount to; all `0px` on desktop.
- **`.shell` `100dvh`** — the shell tracks the live viewport (keyboard-safe on mobile; identical on desktop).
- **`dist-app/` gitignored** — the mobile build output stays out of commits.

### V1 Scope and Build Sequence

The phone is a **lean companion**, not a full authoring tool. Heavy structural authoring — schema design, view configuration, wrangling large multi-column tables — stays on the desktop, where a big screen and a pointer belong. The phone browses, reads, edits, and captures.

Build order:

1. The **sidebar / browse tree** ported to touch — the v1 path to reach any page.
2. General **CRUD** — create, rename, move, delete, and property edits.
3. **Page navigation and MarkdownPM editing** on touch.
4. **Quick Capture** — a lightweight create button and an Apple Shortcut.
5. The **inspector** surface reserved (its content is its own design pass).

### Deferred

- Container **views** (Table, Board, List, Cards, Gallery) and Context detail views — until the browse-and-edit core is done. With views deferred, the sidebar tree is the v1 way to reach a page.
- Any navigation beyond the sidebar (Pinned/Recents, history) — this waits until the desktop's own navigation surface is built, so the phone never gets ahead of the desktop.
- The inspector's tab content and its Claude-chat mechanism — the inspector is a substantial surface of its own and gets its own brainstorm; mobile only reserves the pane.

### Prospects

- Opening an arbitrary user-picked iCloud folder in place — an existing Obsidian vault, or a mobile-rooted folder the desktop then follows. Allowed later as an additive capability; the filesystem plugin's folder-resolution seam keeps it cheap. V1 uses the app-owned container.
- Mobile-only Liquid Glass on the bottom toolbar and simple buttons — a phone flourish the desktop doesn't carry; the reachability of iOS's system glass in a WebView is under research.
- A custom end-to-end sync service with real accounts — only if the product ever outgrows the Apple ecosystem; iCloud rides the Apple ID for free until then.
- Full native touch-editor polish beyond baseline usability.
- iPad-optimized layout, and Android — which would reopen the framework decision (Capacitor keeps it viable; iCloud does not).
