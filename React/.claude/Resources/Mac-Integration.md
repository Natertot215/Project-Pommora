## macOS Integration — Electron Ceilings

Where pure Electron lands on each macOS integration surface. Reference for the deferred OS-integration frontier — it saves re-research. (The native menu bar, Phase 2, is already shipped and sits in the first-party tier.)

### First-party (no companion bundle)

- **App menu bar + keyboard shortcuts** — `Menu.setApplicationMenu`, role-based items. (Shipped.)
- **Deep links** (`pommora://…`) — `app.setAsDefaultProtocolClient` + `open-url` + `Info.plist` `CFBundleURLTypes`; needs a single-instance lock.
- **Basic notifications** — HTML5 `Notification` → `UNUserNotification` (categories / actions need native work).
- **Dark mode** — `nativeTheme` + `prefers-color-scheme`.
- **Tray icon** — works (popup is an HTML window, heavier than a native MenuBarExtra).

### Companion Swift bundle required (ships separately)

- **QuickLook** `.md` preview (Finder spacebar) · **Share Extension** (receive shares — impossible in pure Electron) · **Spotlight at depth** (beyond `electron-spotlight`).

### Hard ceiling (no clean path)

- **Finder file-promise drag-out** — temp-file workarounds only.
- **Sidebar vibrancy** — `vibrancy: 'sidebar'` flickers on resize / bleeds through DOM (~80% right).
- **Accessibility for power users** — Chromium ARIA→AX gaps; no Dynamic Type.
- **Spaces-aware window restoration** — `electron-window-state` persists size / position only.

These are structural to the Electron path: ship companion Swift bundles for QuickLook / Share, or accept the ceiling.
