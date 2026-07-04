## Mobile — Architecture

How the desktop build is reused on the phone, and what has to be built new.

### The Port Cuts at the IPC Boundary

Pommora already splits into a Node "main" process that owns the filesystem and a React renderer that never touches Node, talking only through a narrow typed bridge. The renderer is verified free of any Node or Electron dependency — its UI runs unchanged in any host that provides the bridge, which is why the CSS and components carry over verbatim: it is the same web app in a native WebView. What does NOT come free is the host boundary itself — providing the bridge, resolving asset URLs, rebuilding native menus, and building the renderer for the WebView are net-new work, collected under *What Reuse Doesn't Cover* below. The mobile port reuses the renderer's UI whole and re-implements the main process's responsibilities natively behind the same bridge shape.

### The Native Contract

The renderer needs a small, well-defined surface from its host: read the nexus tree (structure only — page bodies and property values load lazily), read one page, read a container's values, run the single mutation entry point, and receive a change-push when files change on disk. Most of the desktop main process behind that surface is thin filesystem wrappers, trivial to re-host on a native file API. A minority is genuinely platform-specific — native menus, dialogs, the file-watcher — and is rebuilt for the phone. The domain layer beneath both (the property codec, validation, the mutation orchestrator) already lives in shared, platform-agnostic code and moves over untouched. The regeneratable SQLite index is off the read path and is dropped for the phone's first version.

### What Reuse Doesn't Cover

The renderer's UI is reused, but the host boundary is net-new — three seams the "keep the CSS" headline hides, plus a read-path restructure:

- **The `window.nexus` bridge.** The renderer reaches its host entirely through a `window.nexus` object; on the desktop that object is created by Electron's `contextBridge` in the preload. Capacitor has no `contextBridge` — it exposes native code through its own plugin registry — so a **web-side shim** must construct a `window.nexus`-shaped object backed by Capacitor plugin calls and the custom filesystem plugin. This is the port's first step, and it is real design, not a wrapper.
- **Native menus become in-WebView menus.** A chunk of the bridge is native context menus (the editor menu, and the table, cell, column, property, and option menus) built with Electron's menu API. iOS has no equivalent host, so each becomes an in-WebView menu surface. The action vocabularies survive — they live in shared code — but the rendering is rebuilt.
- **Asset URLs.** Banner and avatar images hardcode an Electron-served `nexus-asset://` scheme in a few renderer components. The WebView has no such handler, so the asset-URL prefix must be host-injected and the custom plugin registers the equivalent local scheme — a small but real renderer edit.
- **A staged read engine, not just a gate.** The desktop reader is one eager recursive walk, re-invoked by the watcher on every change. On iCloud that walk hits evicted stubs, and gating each file's download inside the eager walk would materialize the whole nexus on every launch and every remote change — the opposite of lazy. The mobile read path splits into a cheap structure-only pass plus lazy per-entity materialization, with the watcher decoupled from full re-walks. A read-engine workstream, not a one-line gate.

### The Shell — Capacitor

The renderer runs inside a Capacitor WebView. Capacitor consumes the renderer's existing Vite build output as its web assets, so the desktop's electron-vite build is left exactly as it is and Capacitor is added as a **second, parallel consumer of the same bundle** — no shared-Electron plugin, no merging of the two toolchains, just two independent consumers of one Vite output. The targets diverge in two places: the asset base path (the WebView's origin scheme needs it resolved), and the fact that the app renderer has **no standalone Vite config today** — its build lives only inside the electron-vite config, so the mobile target needs a net-new standalone Vite config mirroring it (React, vanilla-extract, the shared aliases, the app entry, the mobile base path). The repo's existing standalone Vite config builds only the design-system showcase, not the app.

Target the current Capacitor major line, which requires a recent Node and Xcode — a dependency-environment check to clear before starting, and a detail for `MobileResources.md` to carry rather than this doc.

### The Native Filesystem — Plugins Plus One Custom Plugin

Routine file access rides Capacitor's official Filesystem plugin, alongside a set of small official plugins for platform surfaces: keyboard, haptics, status bar, share, app lifecycle and deep links, and preferences (for small UI state only — never canonical data, which stays in files). A Files-app visibility flag is set so the nexus is readable by other tools on the phone, preserving the agent-legible promise.

The one piece with no off-the-shelf answer is **iCloud folder access**: no existing plugin gives persistent, writable, bookmark-backed folder access with iCloud stub-materialization. This is a small custom Capacitor plugin — on the order of a few hundred lines of Swift — exposing pick-or-resolve the nexus folder, read its tree recursively, write a file, and materialize an evicted file. Its internals are standard iOS document APIs: the folder picker and security-scoped bookmarks (or the app-owned ubiquity container), a metadata query plus the ubiquitous-item download call for materialization, and a file coordinator around reads and writes. Which internals apply follows the transport decision in `NexusSync.md`. Real-world precedent (an iOS Markdown app syncing an iCloud folder) exists to mirror.

Quick Capture's Apple Shortcut entry is likewise native Swift — App Intents has no turnkey plugin — but it's a small, self-contained surface.

### Dev Workflow

The phone build runs the renderer's Vite dev server over the local network, so edits hot-reload on a real device the same way the desktop does in dev. The WebView is inspectable from Safari's Web Inspector — the same DevTools surface as Electron. The Xcode round-trip (sync assets and native dependencies, open, sign, run) is the one native-toolchain step, and it's Nathan's; the code that fills it is Claude's.
