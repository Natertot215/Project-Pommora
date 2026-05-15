### React Distribution

electron-vite for the dev loop + electron-builder for packaging. `@electron/notarize` wraps Apple's `notarytool`. MAS sandbox details (constraints identical to a SwiftUI MAS build).

> **Status:** Reference. Swift uses Sparkle 2.x + TestFlight for Mac per `PommoraPRD.md` "Distribution" section.

---

#### Distribution

- **Build tooling:** `electron-vite` for the dev loop (Vite-first, HMR for the main process) + `electron-builder` for packaging. Alternative: Electron Forge 7+ (official, all-in-one, first-party feature parity). Both production-grade.
- **Native module rebuild:** `@electron/rebuild` (renamed successor to electron-rebuild) handles ABI compatibility for `better-sqlite3`. Forge auto-runs it via `install-app-deps`. Mark `better-sqlite3` as external in Vite config so the `.node` binary isn't bundled.
- **Auto-update:** `electron-updater` with GitHub Releases is the path of least resistance (free, reliable, no infra). MAS apps use Apple's mechanism — Pommora doesn't ship its own updates in that case.
- **Code signing + notarization:** `@electron/notarize` wraps Apple's `notarytool` (post-altool deprecation). Required entitlements: `com.apple.security.cs.allow-jit`. Hardened runtime mandatory.
- **MAS sandbox:** disables certain Electron modules and forces `contextIsolation: true`, `sandbox: true`, `nodeIntegration: false`. All renderer↔main IPC goes through `contextBridge.exposeInMainWorld` + `ipcRenderer.invoke`/`ipcMain.handle`. Filesystem requires `com.apple.security.files.user-selected.read-write` — same constraint as a SwiftUI MAS build; gives scoped access to user-picked nexus folders only.
- **Crash reporting:** `@sentry/electron` is the de-facto standard; hooks into Crashpad for native crashes including renderer/main/utility processes.
