## Deployment — Design-System Showcase (Vercel)

The component-library showcase deploys to Vercel from this repo. It builds the **showcase only** — a plain browser site — never the Electron app.

### What Goes Live

`design-system.html` → the data-driven showcase (`src/renderer/src/design-system/showcase/`): color tokens, the type ramp, chips, icons, glass materials, and a live accent picker. `vite build` emits it into `dist/`, served at `/`.

### How the Pointing Works (post-consolidation)

The repo was consolidated — the React app is now a **subfolder** of the `Project Pommora` monorepo (no more standalone React-at-root branch). The repo carries TWO vercel.json files so the deploy works under EITHER dashboard state:

- **Root `vercel.json`** — the self-sufficient path: builds with `cd React && npm run build:showcase`, output `React/dist`, plus the `/` → `/design-system.html` rewrite. This is what runs while the dashboard's Root Directory is still `.` (the pre-consolidation default) — no dashboard click required.
- **`React/vercel.json`** — the same pins relative to `React`. This one governs if/when the dashboard's **Root Directory** is set to `React` (Vercel reads vercel.json relative to the Root Directory, so only one of the two is ever read).

| Setting | Value |
|---|---|
| Git repository | `Natertot215/Project-Pommora` |
| Production branch | `main` |
| Root Directory | `.` works (root vercel.json) — `React` also works (React/vercel.json) |
| Build + output + rewrite | pinned in whichever vercel.json is read |

### If the Site Won't Update

1. Push `main` (every push to the production branch builds) — this is the whole deploy trigger.
2. Still stale? Vercel → **Settings → Git → Production Branch** must be `main` — the old deploy tracked the retired `react` branch, and that's a dashboard-only setting the repo can't fix.
3. If re-importing fresh: pick `Natertot215/Project-Pommora`; either Root Directory works per the table above.
4. Open the live URL and confirm the showcase renders.

### Domain

Unchanged: **https://pommora-design-system.vercel.app**. The custom domain `pommora-design-system.com` isn't owned yet — when it is, add it under **Settings → Domains** and point DNS at Vercel.

### Assets + Gotchas

- Glass-stage photos live in `React/public/surfaces/`; `vite build` copies `public/` into `dist/` automatically — no action.
- `better-sqlite3` (a dependency) installs from a prebuilt binary, so Vercel's Linux `npm install` won't native-compile it; the showcase bundle never imports it anyway.
- The showcase is decoupled from Electron — `build:showcase` is plain `vite build` (via `vite.config.ts`), not `electron-vite`.
