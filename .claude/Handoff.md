## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Handoff.md`; design system → `Features/Design.md` + `Features/Typography.md`.

### Where the project is

Two foundations are down; the UI is next.

- **Headless data layer — done** (branch `main`). Phases 0–7 + a 7-agent foundation review; **220 tests, typecheck + build green**, tests-only / no UI wired. The complete write/mutation side caught up to Swift (CRUD, properties, connections, SQLite index, Agenda). Full record: `Planning/Data-Layer-Handoff.md` + `…Build-Log.md`. Swift→React LOC ≈ 8,552 → 2,383 (~72%).
- **Design system — established, fully tokenized, live** (branch `design-system`). The Figma "Pommora - React" library is the source of design. The **token layer is complete**: `color` (solid spectrum + label tones + **backgrounds / fills / states / accent / separators**, mirrored from Figma), `typography` (`font` primitives + `text.*` composed ramp), the unified `chip` tint (incl. **red** — 11 colors), unified in `index.ts`; a `theme-vars.css.ts` bridge re-exports tokens as stable `var(--…)` so plain CSS references them. Icons = **Lucide** (`design-system/symbols/` + `Symbols.md`); glass = a **shared Material** (`materials/glass-material.ts` spread by `GlassSurface` / `GlassControls`, liquidGL "Tinted Lens"). A **data-driven, single-page showcase** (`design-system/showcase/`) is **live at https://pommora-design-system.vercel.app** (`npm run showcase` to dev; `build:showcase` → static `dist/`); its Materials section is a glass playground — 3 stacked photo surfaces with a lens you drag anywhere. Spec: `Features/Design.md` + `Features/Typography.md`.
- **App shell — designed, paused.** First-pass spec (window-drag fix + resizable / collapsible sidebar at 1440×900, Swift-matched sidebar sizing) is approved but unbuilt, awaiting a desktop GUI verification. Branch `app-shell` (empty placeholder).
- **Repo — consolidated into the Swift monorepo.** The React project lives in the `Project-Pommora` GitHub repo as a top-level `React/` folder (subtree, history preserved), alongside the Swift app. **Workflow:** the standalone `Pommora - React` repo is the working source; sync to the monorepo by cloning `main` + `git merge -X subtree=React react-src/design-system` + push (gate on "React/-only + fast-forward"). Vercel deploys the monorepo `React/`, so changes must be synced to go live. The Swift app moves into a sibling `Swift/` folder later (deferred — its branch had an active session).

### Lessons learned

- **Monorepo sync = subtree merge.** Standalone repo is upstream; the monorepo `React/` is a subtree synced via `git merge -X subtree=React react-src/design-system`. Always verify "React/-only + fast-forward" before pushing. Vercel deploys the monorepo — unsynced React work won't appear live.
- **vanilla-extract vars can't be read from plain CSS** — `createGlobalTheme` emits hashed names. Bridge via `globalStyle(':root', { vars: { '--name': token } })` (`theme-vars.css.ts`) to expose stable `var(--…)` — one source across `.ts` and `.css`.
- **Figma's 10-mode cap is hard** (`addMode` → "Limited to 10 modes only"). To add an 11th chip color (red), hand-build a gallery column with raw paints, not a mode. The Color collection's `defaultModeId` is also read-only.
- **Verify usages — fills AND strokes — before deleting a Figma variable.** A fills-only sweep left 12 stroke bindings on `label-on-color`, so deleting it left dangling refs. A claim is a hypothesis until checked.
- **The unified chip tint:** fill = base @ 60% · stroke = base @ 40% (2px; **1.5px** Checkbox) · text = `label-primary` + base @ 10%. Soft only. In `chip.css.ts`: one `tint(base)` `color-mix` formula → `chipColor.*`; the base `chip` **composes `text.control.emphasized`** (never re-states the ramp).
- **Gallery instances can carry local text-style overrides that survive a component edit** — verify Figma galleries at the *instance* level, not just the component; bind real type to a live style (never `NONE/MIXED`). SF Pro icon glyphs are size-only — never bind an Inter style or they tofu.
- **Keep design surfaces registry-shaped.** The showcase iterates `vars.color.solid`, `text`, `chipColor`, the `icons` map, and materials, so a new token / icon appears with no showcase edit.
- **JS/Electron config stays at the repo root** (`package.json`, lockfile, `tsconfig*`, `vite.config.ts`, `electron.vite.config.ts`, `node_modules`) — hard-expected by the toolchain. `out/` · `.vite` · `*.tsbuildinfo` · `.DS_Store` are gitignored cruft.
- (Data layer) Keep greenfield multi-agent stages sequential + self-verified green; `ELECTRON_RUN_AS_NODE=1` breaks GUI launches (strip it); CommonJS main/preload.

### Next session

1. **Design system → components** — the token layer is complete (color incl. backgrounds/fills/states/accent/separators, type, chip) + glass material + icons. Build the first real **components** (Label, Button, Menu, Menu Header, Separator) from tokens + materials into `design-system/components/` — they auto-appear in the showcase's "pending" list.
2. **Radius + spacing tokens** — formalize corners + spacing from Figma (currently ad-hoc literals — OKAY FOR NOW); then shadow / motion / z-index scales.
3. **App shell** — verify the paused first-pass on desktop, then build it (window drag, resizable / collapsible sidebar).
4. **Data layer → UI** (the long-standing UI-gated work): `mutate:*` / `index:*` IPC + preload bridge; incremental index upserts (+ `electron-rebuild` / `asarUnpack`); cascade orchestration. See `Planning/Data-Layer-Handoff.md`.

### Pending focuses

- **Monorepo working home — undecided.** Two copies exist (standalone repo + monorepo `React/`); pick one canonical and retire the other, or keep the standalone-upstream + sync workflow. For Vercel auto-deploy to reflect edits, work must reach the monorepo `main`.
- **Corners + spacing — OKAY FOR NOW (ad-hoc literals).** Radius (6–16px) + spacing are scattered in CSS, not tokenized — formalize as `radius` / `space` scales from Figma.
- **`surface.background` updated** — the window bg changed `#1C1C1F` → `#1A1A1B` (Figma `Background/bg-window`); now `vars.color.background.window`, driven via the `--bg-window` bridge var.
- **`red` is a chip color in code** (11 total) **and in the Figma gallery** — the Color collection is capped at 10 modes, so red is a hand-built **leftmost** gallery column (raw red tint), not a mode. `grey-default` is the `Default` chip color's source.
- **Glass — liquidGL "Tinted Lens" at zero tint** (blur 5 · brightness 90%), shared in `materials/glass-material.ts`, wired into `.surface-glass` / `Surface.tsx`. The selection lab was removed once chosen. `liquid-dom` shelved.
- **Custom domain** `pommora-design-system.com` not owned yet (showcase lives on the `.vercel.app` URL).
- **Contexts in `~/test`** — no `.nexus/` / contexts in the fixture, so the sidebar shows Vaults only; add a few Areas / Topics / Projects to exercise it.
- **Menu Heading icon is still 14pt** while its title is 13 / Semibold — decide whether the icon drops to 13 to match.
- **Sub-label → Caption/Standard (11) and Detail → Footnote/Emphasized (10)** were my calls — confirm or redirect.
- **Symbols.md `(Needs Editing)` rows** — Collection + Set both use `folder-closed`; `panel-left` + `square-dashed` queued but unassigned; confirm the Vault's `gallery-vertical-end → folder-open` transition. (`log-in` / `key-round` / `lock` / `square-plus` are now wired into the registry.)
- **Doc mirror** — `~/.claude/scripts/cross-file-mirroring` mirrors React docs → vault `Atlas/II. Projects/Pommora/II. React` (+ `Symbols.md` → `II. Features`); launchd watcher `com.nexus.claude-mirror` runs the React-aware script.

### Fix log

- **Glass lens default position** — measured the forest tile before the swatch/type rows grew (their labels populate after mount), so it landed ~163px high; fixed by re-measuring via a `ResizeObserver` until the first drag.
- `label-on-color` removal: first sweep was fills-only → 12 stroke bindings missed + the variable left dangling. Re-swept fills + strokes (12 vectors → `label-primary`), then deleted.
- Per-color cleanup: usage-check showed **all 55 in use** (lavender = accent, 100+ uses) → migrated (accent → semantic; gallery → modes; spectrum → solids) before deleting **54** tint variables.
- (Data layer) `SchemaTransaction` rollback hole + `.bak-` sweep (`d712999`); index `target_kind` = `area`/`topic`/`project`, not `context_tier` (`8309e20`).
