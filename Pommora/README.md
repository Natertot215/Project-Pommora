# Pommora — React

A React + TypeScript + Electron rebuild of Pommora (a simpler Notion that's also a more capable Obsidian). See the program roadmap in the Swift project's `// Planning // 06-14-React-Rebuild-Roadmap.md`; the current phase plan is in [`Planning/Phase-1-Window-Sidebar-Scaffold.md`](Planning/Phase-1-Window-Sidebar-Scaffold.md).

## Status

**Phase 1 — read-only walking skeleton:** a window + glass sidebar that reads a nexus folder from disk and renders its true structure. No function (selection / CRUD / drag / editor / writes) is wired yet.

## Scripts

```bash
npm run dev         # electron-vite dev (HMR)  — see env note below
npm run build       # bundle main + preload + renderer to out/
npm run typecheck   # tsc (node + web projects)
npm test            # vitest
```

## Running locally

The app reads a test nexus. Point it with `TEST_NEXUS_PATH` (defaults to `~/test`).

> **Gotcha — `ELECTRON_RUN_AS_NODE`.** If this variable is set in your shell/environment, the Electron binary runs as plain Node and the app crashes immediately (`require('electron')` returns a path string → `Cannot read properties of undefined`). Always launch with it unset:

```bash
# dev (HMR):
env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" npm run dev

# or run the built app directly (no dev server):
npm run build
env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .
```

## Architecture (Phase 1)

- **main/** — Node/Electron only. `readNexus.ts` walks the nexus (sidecar + structure-classification paths) → one immutable `NexusTree`; exposed via the `nexus:open` IPC.
- **preload/** — narrow `contextBridge` exposing only `window.nexus.open()`.
- **renderer/** — React. Zustand session store → recursive sidebar on a swappable glass `<Surface>`.
- **shared/** — the `NexusTree` cross-process contract.

CommonJS main/preload (not `type: module`) so Electron's `require('electron')` resolves cleanly and the preload can stay sandboxed. No SQLite — the single fs walk is the only read source.
