## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Handoff.md`; design system → `Features/Design.md` + `Features/Typography.md`.

### Where the project is

Two foundations are down; the UI is next.

- **Headless data layer — done** (branch `main`). Phases 0–7 + a 7-agent foundation review; **220 tests, typecheck + build green**, tests-only / no UI wired. The complete write/mutation side caught up to Swift (CRUD, properties, connections, SQLite index, Agenda). Full record: `Planning/Data-Layer-Handoff.md` + `…Build-Log.md`. Swift→React LOC ≈ 8,552 → 2,383 (~72%).
- **Design system — established this session** (branch `design-system`, `404a1d7` + Figma). The Figma "Pommora - React" library is the source of design and is now fully unified: typography ramp finalized **and wired to live text styles** across Menu Item / Menu Heading / Label / Button (+ Segmented) and every gallery card (menu titles → Callout · labels / buttons → Control Emphasized · Headline repurposed to 13 / Semibold for menu headers); **one mode-driven chip** with a unified tint; semantic accent; **per-color tint variables removed (54 deleted)**. The React token layer now carries `color` (solids + labels), `typography` (`font` + `text`), and the `chip` tint, unified in `index.ts`, plus a live showcase (`npm run showcase` → localhost). Icons are **Lucide** (curated `design-system/symbols/` registry + `Symbols.md`); glass is a **Material** (`design-system/materials/` — `GlassSurface` / `GlassControls`, liquidGL "Tinted Lens"). The whole layer lives under `src/renderer/src/design-system/` (`tokens` · `symbols` · `materials` · `showcase` · `components`); the showcase is **data-driven** — each section iterates its registry. Localhost: `npm run showcase` → the design system (single page); it builds to a static site (`npm run build:showcase` → `dist/`) with a repo-tracked `vercel.json`, **live at https://pommora-design-system.vercel.app** (a `/` rewrite serves it). Spec: `Features/Design.md` + `Features/Typography.md`.
- **App shell — designed, paused.** First-pass spec (window-drag fix + resizable / collapsible sidebar at 1440×900, Swift-matched sidebar sizing) is approved but unbuilt, awaiting a desktop GUI verification. Branch `app-shell` (empty placeholder).
- **Repo — consolidating into the Swift monorepo.** The React project is merged into the `Project-Pommora` GitHub repo as a top-level `React/` folder (subtree, history preserved), alongside the Swift app. The standalone `Pommora - React` repo stays the working copy for now; the Swift app moves into a sibling `Swift/` folder later (deferred — its branch has an active multi-commit session, and moving the tree mid-flight would wreck that merge).

### Lessons learned

- **Verify usages — fills AND strokes — before deleting a Figma variable.** A fills-only sweep left 12 stroke bindings on `label-on-color`, so deleting it left dangling refs. Same lesson as the data layer's `target_kind`: a claim is a hypothesis until checked against the real thing.
- **Figma constraints are real:** variable modes cap at **10** per collection (Pro); `defaultModeId` is read-only (no reorder). The chip picker fit in exactly 10 modes; since `defaultModeId` is read-only, "a fresh chip = Default" belongs in the React component's default (setting the Figma master to Default just greys the showcase).
- **The unified chip tint:** fill = base @ 60% · stroke = base @ 40% (2px; **1.5px** Checkbox) · text = `label-primary` + base @ 10%. Soft only (no Solid). In code as `chip.css.ts` — one `tint(base)` `color-mix` formula → `chipColor.*`.
- **Gallery instances can carry local text-style overrides that survive a component edit.** After wiring the components, 4 menu-gallery instances kept stale overrides (raw / Body / Footnote) and had to be swept directly. Verify galleries at the *instance* level, not just the component — and bind real type text to a live style (never leave `NONE/MIXED`). SF Pro icon glyphs are the exception: size only, never bind an Inter style or they turn to tofu.
- **JS/Electron config stays at the repo root.** `package.json`, the lockfile, `tsconfig*`, `vite.config.ts`, `electron.vite.config.ts`, `node_modules` are hard-expected at root by npm / Vite / electron-vite / tsc — moving them into a subfolder breaks the toolchain (so there is no "Index" config folder). `out/` · `.vite` · `*.tsbuildinfo` · `.DS_Store` are gitignored cruft, safe to delete (all regenerated).
- **Keep design surfaces registry-shaped.** The showcase iterates `vars.color.solid`, `text`, `chipColor`, the `icons` map, and the materials, so adding a token / icon appears with no showcase edit. New surfaces should expose a registry to stay auto-listed.
- (Data layer) Keep greenfield multi-agent stages sequential + self-verified green; `ELECTRON_RUN_AS_NODE=1` breaks GUI launches (strip it); CommonJS main/preload.

### Next session

1. **App shell** — verify the paused first-pass on desktop, then build it (the "general app functionality" pass: window drag, resizable / collapsible sidebar).
2. **Design system → components** — tokens (color / type / chip), icons (Lucide), and the glass material are authored + shown in the data-driven showcase. Remaining: accent / backgrounds / fills / states / separators tokens; then build the first real **components** (Button, Label, Menu) from tokens + materials into `design-system/components/` (the showcase's "pending" list).
3. **Data layer → UI** (the long-standing UI-gated work): `mutate:*` / `index:*` IPC + preload bridge; incremental index upserts (+ `electron-rebuild` / `asarUnpack`); cascade orchestration. See `Planning/Data-Layer-Handoff.md`.

### Pending focuses

- **Token import alias** — the existing `@renderer` alias covers tokens (`@renderer/design-system/tokens`); no separate `@/design` alias needed.
- **Glass — decided: liquidGL "Tinted Lens" at zero tint** (blur 5 · brightness 90%, transparent), wired into `.surface-glass` / `Surface.tsx`. The selection lab was removed once the glass was chosen; a draggable demo (glass across 3 fields) now lives in the showcase **Materials** section. `liquid-dom` shelved.
- **Contexts in `~/test`** — no `.nexus/` / contexts in the fixture, so the sidebar shows Vaults only; add a few Areas / Topics / Projects to exercise it.
- **`red` is now a chip color in code** (11 total); Figma's mode picker stays at 10 (Pro cap), a Figma-only divergence. `grey-default` kept as the `Default` chip color's source.
- **Menu Heading icon is still 14pt** while its title is now 13 / Semibold — decide whether the icon drops to 13 to match (you scoped the 13pt change to menu *items*, which were already 13).
- **Sub-label → Caption/Standard (11) and Detail → Footnote/Emphasized (10)** were my calls (you specified only the primary title/label/content slots) — confirm or redirect.
- **Symbols.md `(Needs Editing)` rows** — Collection + Set both use `folder-closed`; `panel-left` + `square-dashed` are queued but unassigned. Every sidebar disclosure (Vault / Collection / Set) shows `folder-open` when expanded — confirm the Vault's `gallery-vertical-end → folder-open` transition reads right. Newly queued in `Symbols.md` but not yet wired into `index.tsx`: `log-in` (create inverse), `key-round`, `lock` (needs edits), `square-plus`.
- **Doc mirror** — `~/.claude/scripts/cross-file-mirroring` now mirrors React docs → vault `Atlas/II. Projects/Pommora/II. React` (+ `Symbols.md` → `II. Features`); seeded via `--once`. The launchd watcher (`com.nexus.claude-mirror`) was restarted last session to run the React-aware script.
- **Vercel hosting — live** at https://pommora-design-system.vercel.app (root dir `React/`, branch `main`; auto-redeploys on push to the monorepo). Custom domain `pommora-design-system.com` not owned yet.
- **Monorepo working home — undecided.** After the `React/` subtree lands on `main`, the project exists in two places (the standalone repo + the monorepo `React/`). Pick one as canonical and retire the other before resuming React feature work.

### Fix log

- `label-on-color` removal: first sweep was fills-only → 12 stroke bindings missed + the variable left dangling. Re-swept fills + strokes (12 vectors → `label-primary`), then deleted.
- Per-color cleanup: usage-check first showed **all 55 in use** (lavender = accent, 100+ uses) → migrated (accent → semantic tokens; gallery → modes; spectrum → solids) before deleting **54** tint variables.
- (Data layer) `SchemaTransaction` rollback hole + `.bak-` sweep (`d712999`); index `target_kind` = `area`/`topic`/`project`, not `context_tier` (`8309e20`).
