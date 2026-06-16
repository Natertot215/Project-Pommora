## Handoff — Pommora React

Lean current-state snapshot. Read first at session start. Deep docs: data layer → `Planning/Data-Layer-Handoff.md`; design system → `Features/Design.md` + `Features/Typography.md`.

### Where the project is

Two foundations are down; the UI is next.

- **Headless data layer — done** (branch `main`). Phases 0–7 + a 7-agent foundation review; **220 tests, typecheck + build green**, tests-only / no UI wired. The complete write/mutation side caught up to Swift (CRUD, properties, connections, SQLite index, Agenda). Full record: `Planning/Data-Layer-Handoff.md` + `…Build-Log.md`. Swift→React LOC ≈ 8,552 → 2,383 (~72%).
- **Design system — established this session** (branch `design-system`, `404a1d7` + Figma). The Figma "Pommora - React" library is the source of design and is now fully unified: typography ramp finalized **and wired to live text styles** across Menu Item / Menu Heading / Label / Button (+ Segmented) and every gallery card (menu titles → Callout · labels / buttons → Control Emphasized · Headline repurposed to 13 / Semibold for menu headers); **one mode-driven chip** with a unified tint; semantic accent; **per-color tint variables removed (54 deleted)**. The React token layer now carries `color` (solids + labels), `typography` (`font` + `text`), and the `chip` tint, unified in `index.ts`, plus a live showcase (`npm run showcase` → localhost). Icons are **Lucide**, curated via `design/icons/` + a `Symbols.md` manifest (add a name → it's imported). Spec: `Features/Design.md` + `Features/Typography.md`.
- **App shell — designed, paused.** First-pass spec (window-drag fix + resizable / collapsible sidebar at 1440×900, Swift-matched sidebar sizing) is approved but unbuilt, awaiting a desktop GUI verification. Branch `app-shell` (empty placeholder).

### Lessons learned

- **Verify usages — fills AND strokes — before deleting a Figma variable.** A fills-only sweep left 12 stroke bindings on `label-on-color`, so deleting it left dangling refs. Same lesson as the data layer's `target_kind`: a claim is a hypothesis until checked against the real thing.
- **Figma constraints are real:** variable modes cap at **10** per collection (Pro); `defaultModeId` is read-only (no reorder). The chip picker fit in exactly 10 modes; since `defaultModeId` is read-only, "a fresh chip = Default" belongs in the React component's default (setting the Figma master to Default just greys the showcase).
- **The unified chip tint:** fill = base @ 60% · stroke = base @ 40% (2px; **1.5px** Checkbox) · text = `label-primary` + base @ 10%. Soft only (no Solid). In code as `chip.css.ts` — one `tint(base)` `color-mix` formula → `chipColor.*`.
- **Gallery instances can carry local text-style overrides that survive a component edit.** After wiring the components, 4 menu-gallery instances kept stale overrides (raw / Body / Footnote) and had to be swept directly. Verify galleries at the *instance* level, not just the component — and bind real type text to a live style (never leave `NONE/MIXED`). SF Pro icon glyphs are the exception: size only, never bind an Inter style or they turn to tofu.
- (Data layer) Keep greenfield multi-agent stages sequential + self-verified green; `ELECTRON_RUN_AS_NODE=1` breaks GUI launches (strip it); CommonJS main/preload.

### Next session

1. **App shell** — verify the paused first-pass on desktop, then build it (the "general app functionality" pass: window drag, resizable / collapsible sidebar).
2. **Design system → code** — color (solids + labels), typography, and the chip tint are authored + showcased (`npm run showcase`). Remaining: accent / backgrounds / fills / states / separators tokens; then build the first real components (Button, Label, Menu) from the library.
3. **Data layer → UI** (the long-standing UI-gated work): `mutate:*` / `index:*` IPC + preload bridge; incremental index upserts (+ `electron-rebuild` / `asarUnpack`); cascade orchestration. See `Planning/Data-Layer-Handoff.md`.

### Pending focuses

- **Token import alias** — the existing `@renderer` alias covers tokens (`@renderer/design/tokens`); no separate `@/design` alias needed.
- **Glass / Surface** — Apple-Regular CSS default; `Surface` is the swappable seam; `--glass-radius` (12px) — eyeball window concentricity. `liquid-dom` shelved.
- **Contexts in `~/test`** — no `.nexus/` / contexts in the fixture, so the sidebar shows Vaults only; add a few Areas / Topics / Projects to exercise it.
- **`red` is in the solid spectrum but not a chip color** (excluded by design; the mode cap is 10). `grey-default` kept as the `Default` chip color's source.
- **Menu Heading icon is still 14pt** while its title is now 13 / Semibold — decide whether the icon drops to 13 to match (you scoped the 13pt change to menu *items*, which were already 13).
- **Sub-label → Caption/Standard (11) and Detail → Footnote/Emphasized (10)** were my calls (you specified only the primary title/label/content slots) — confirm or redirect.

### Fix log

- `label-on-color` removal: first sweep was fills-only → 12 stroke bindings missed + the variable left dangling. Re-swept fills + strokes (12 vectors → `label-primary`), then deleted.
- Per-color cleanup: usage-check first showed **all 55 in use** (lavender = accent, 100+ uses) → migrated (accent → semantic tokens; gallery → modes; spectrum → solids) before deleting **54** tint variables.
- (Data layer) `SchemaTransaction` rollback hole + `.bak-` sweep (`d712999`); index `target_kind` = `area`/`topic`/`project`, not `context_tier` (`8309e20`).
