## Build & Run Gotchas

Hard-won environment/toolchain traps. Add entries when a mistake is worth never repeating.

### Running the GUI

- **`ELECTRON_RUN_AS_NODE` must be unset.** This environment exports `ELECTRON_RUN_AS_NODE=1`, which makes the Electron binary run as plain Node — `require('electron')` then returns a path string and the app crashes with `Cannot read properties of undefined (reading 'handle')` plus a `Node.js vX` trailer. Always launch with it stripped:
  `env -u ELECTRON_RUN_AS_NODE TEST_NEXUS_PATH="$HOME/test" ./node_modules/.bin/electron .` (after `npm run build`).
- **`electron-vite dev` mis-launches here** for the same reason (it inherits the env). Prefer building + running the binary directly for a visual check; use `env -u ELECTRON_RUN_AS_NODE … npm run dev` if HMR is needed.
- **Electron binary may be missing after install** — if `node_modules/electron/path.txt` is absent (postinstall skipped), run `node node_modules/electron/install.js` to download it.
- **Don't auto-launch the GUI from an agent** — verify headlessly (`npm run typecheck && npm run build && npx vitest run`). Only launch when a human will look.

### Toolchain

- **CommonJS main/preload** — the package is intentionally NOT `type: module`. Electron's `require('electron')` fails on ESM named imports (`does not provide an export named 'BrowserWindow'`); CJS fixes it and lets the preload stay sandboxed. electron-vite then emits `out/preload/index.js` (referenced from `main/index.ts`).
- **Version pins: Vite 7 + `@vitejs/plugin-react` 5.** Newer plugin-react majors require Vite 8, which electron-vite 5 doesn't peer-support yet. Keep the pin until electron-vite supports Vite 8.
- **TS 6 deprecated `baseUrl`** — use `paths` with `./`-relative targets (no `baseUrl`).
- **Renderer CSS side-effect imports** need `/// <reference types="vite/client" />` (in `src/renderer/src/env.d.ts`).
- **vanilla-extract `*.css.ts` files may ONLY export serializable values** (styles, `styleVariants`, vars). It serializes every export into a virtual CSS module, so exporting a plain **function** throws `serializeVanillaModule` / `stringifyExports` and breaks `build` + `build:showcase`. **typecheck + vitest don't run that serialization**, so it passes the test gate and fails only at build. Put shared helpers (e.g. the chip `tint` recipe) in a plain `.ts` beside the `.css.ts` (`chip-tint.ts`).
- **Verify the gate with `&&`; don't `| tail` the final step.** A `;`-chained gate or `cmd | tail` masks the real exit code (tail exits 0 even when `cmd` failed). Run `typecheck && vitest run && build && build:showcase` and confirm `✓ built in` on every step — exit 0 alone is not proof.

### Glass / Liquid Glass

- **Apple Liquid Glass over an opaque dark surface reads dark, edge-defined** — not a white-tinted, brightened panel. Presence comes from the two-part edge (bright top specular rim + dark containment edge), low blur (≤ ~6px), minimal saturation. A `brightness()` lift or white fill over flat dark = "too bright / too frosty". The body stays near the main tone.
- **`liquid-dom` (WebGPU) is shelved** — most authentic (real GPU refraction of live DOM) but requires Chrome's experimental `canvas-draw-element` flag (HTML-in-Canvas) and composing the app inside its `LiquidCanvas` scene graph (invasive). Revisit when the API ships unflagged. The current glass is CSS (`.surface-glass` — do not entangle it with app logic; it's the swappable `Surface` seam).
- **`liquid-glass-react`** is installed but reserved for floating chrome (toolbar pills/popovers) — it's content-sized/centered and can't be a full-height pane.
