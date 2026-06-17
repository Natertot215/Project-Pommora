## Deployment — design-system showcase (Vercel)

The component-library showcase deploys to Vercel from this repo. It builds the **showcase only** — a plain browser site — never the Electron app.

### What goes live

`design-system.html` → the data-driven showcase (`src/renderer/src/design-system/showcase/`): color tokens, the type ramp, chips, icons, glass materials, and a live accent picker. `vite build` emits it into `dist/`, served at `/`.

### The one setting that changed

The repo was consolidated — the React app is now a **subfolder** of the `Project Pommora` monorepo (no more standalone React-at-root branch). So the setting that MUST change from the old deploy is the **Root Directory**.

| Setting | Value |
|---|---|
| Git repository | `Natertot215/Project-Pommora` |
| Production branch | `main` |
| **Root Directory** | **`React`**  ← the showcase lives here now (was `.`) |
| Framework preset | Vite |
| Build command | `npm run build:showcase`  (pinned in `React/vercel.json`) |
| Output directory | `dist`  (pinned in `React/vercel.json`) |
| Install command | `npm install`  (default) |

`React/vercel.json` already pins the framework, build command, output dir, and the `/` → `/design-system.html` rewrite — Vercel reads it **relative to the Root Directory**, so it's found once Root Directory = `React`.

### Bring it back live

1. Vercel → the project → **Settings → General → Root Directory** → set `React`, save.
2. **Settings → Git → Production Branch** → `main`.
3. If re-importing fresh instead: pick `Natertot215/Project-Pommora`, set **Root Directory = `React`** during import; Vite auto-detects.
4. **Deployments → Redeploy** — or just push `main` (every push to `main` builds).
5. Open the live URL and confirm the showcase renders.

### Domain

Unchanged: **https://pommora-design-system.vercel.app**. The custom domain `pommora-design-system.com` isn't owned yet — when it is, add it under **Settings → Domains** and point DNS at Vercel.

### Assets + gotchas

- Glass-stage photos live in `React/public/surfaces/`; `vite build` copies `public/` into `dist/` automatically — no action.
- `better-sqlite3` (a dependency) installs from a prebuilt binary, so Vercel's Linux `npm install` won't native-compile it; the showcase bundle never imports it anyway.
- The showcase is decoupled from Electron — `build:showcase` is plain `vite build` (via `vite.config.ts`), not `electron-vite`.
