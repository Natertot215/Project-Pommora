### Mac OS Integration — React+Electron

Inventory of Mac OS integration surfaces and where pure Electron lands on each: first-party areas, companion-bundle territory, hard ceilings. Plus the "more moving parts" risk note for the runtime stack shape.

> **Status:** Reference. Most of these are reasons Pommora chose SwiftUI — see `// Features//Architecture.md` and `PommoraPRD.md` "Mac OS Integration" section.

---

#### First-party areas

Areas where pure Electron is **first-party** (no companion bundles needed):

- **App menu bar + keyboard shortcuts** — `Menu.setApplicationMenu` with role-based items (`appMenu`, `editMenu`, `windowMenu`); covers standard Mac shortcuts adequately.
- **Deep links** (`pommora://page/<id>`): `app.setAsDefaultProtocolClient` + `open-url` event + `Info.plist` `CFBundleURLTypes`. Single-instance lock required.
- **Basic notifications** — HTML5 `Notification` API maps to `UNUserNotification`; categories/actions need native module work.
- **Dark mode toggling** — `nativeTheme` + `prefers-color-scheme`.
- **Tray icon** — works; popup uses an HTML window (heavier than a native MenuBarExtra popover).

#### Companion Swift bundles

Areas requiring **companion Swift bundles** (out-of-process extensions Pommora ships separately):

- **QuickLook Preview Extension** — for `.md` preview via Finder spacebar
- **Share Extension** — for receiving shares from other apps
- **Spotlight at depth** — beyond what `electron-spotlight` exposes

#### Hard ceilings

Areas with a **hard ceiling** (no clean path):

- **Finder file-promise drag-out** — temp-file workarounds only
- **Sidebar vibrancy polish** — Chromium DOM bleed + resize flicker
- **Accessibility for power users** — Chromium ARIA gaps for `aria-activedescendant`, AX tree shape, focus rings; no Dynamic Type
- **Window state restoration with macOS Spaces** — `electron-window-state` persists size/position only; not Mission Control Spaces

---

#### Integration ceiling — full detail

The areas where pure Electron has a hard ceiling and "Mac-first cohesion" doesn't fully land:

- **QuickLook (.md preview via Finder spacebar):** no path in Electron without shipping a separate Swift bundle outside the app.
- **Share Extension** (receive shares from Safari / Mail / etc.): impossible in pure Electron ([Issue #31984](https://github.com/electron/electron/issues/31984) still open). Would require a sidecar Swift extension target.
- **CoreSpotlight (nexus-wide system search):** possible only via `electron-spotlight` (Objective-C native module), which is maintained by one person and requires a signed build to talk to `corespotlightd`. Fragile.
- **NSServices** ("New Pommora Page from Selection"): `Info.plist` registration works, but receiving selection requires native bridging the framework doesn't expose ([Issue #8394](https://github.com/electron/electron/issues/8394) still open).
- **Finder file-promise drag-out** (drag a Page from the sidebar to Finder writes the file at the drop location): broken for years; community workarounds write a temp file then call `startDrag`.
- **Sidebar vibrancy:** Electron exposes `vibrancy: 'sidebar'` on `BrowserWindow`, but it can flicker on resize and bleeds through DOM. Looks ~80% right; the remaining 20% is exactly what cohesion-sensitive users notice.
- **Accessibility (VoiceOver, Dynamic Type):** Chromium ARIA → AX bridge has documented gaps that surface for power users; Dynamic Type doesn't apply.

These are not feature blockers — Pommora can either ship companion Swift bundles for QuickLook / Share Extension (which partially defeats the cross-platform appeal of Electron) or accept the integration ceiling. The choice is structural to the React path.

---

#### Runtime stack — more moving parts

The runtime is a stack: Vite + Electron main + Electron renderer + Tailwind + better-sqlite3 (with native rebuild for the Electron ABI). Each component is well-trodden, but the surface area is larger than a single-process Swift app. For an agentic-implementation workflow, this trades a larger training corpus for more components to keep aligned across version bumps and platform updates.
