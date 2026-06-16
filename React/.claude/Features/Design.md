## Design System

The Pommora design system — the **code mirror of the Figma "Pommora - React" library**. Two-tier tokens (raw **primitives** → meaningful **semantic** aliases); components reference semantic tokens only. Lives in `src/renderer/src/design-system/`. Typography has its own spec: `Typography.md`.

### Source of truth

The **Figma "Pommora - React"** file is canonical for design *values*; this repo mirrors them as tokens. Values change in Figma first, then sync to the tokens here. The Figma file is also the visual reference for components.

### Tooling — established

- **vanilla-extract** (`@vanilla-extract/css` + `@vanilla-extract/vite-plugin`) — token files are `*.css.ts`; `createGlobalTheme(':root', …)` emits real CSS variables **and** a typed `vars` object (autocomplete; a mistyped token is a compile error). Plugin wired into the renderer Vite config.
- **Inter** (`@fontsource-variable/inter`) — variable font, family `Inter Variable`, covering Regular / Medium / Semibold / Bold; imported in `main.tsx` and set as the app font.
- Committed `404a1d7` (branch `design-system`).

### Folder

```
design-system/
├─ tokens/          the variables — edit here → propagates app-wide
│   ├─ color.css.ts        ← solid spectrum + label tones
│   ├─ typography.css.ts   ← font primitives + composed text styles
│   ├─ chip.css.ts         ← unified chip tint (fill/stroke/text recipe)
│   └─ index.ts            ← unified `vars` + `text` + chip exports
├─ symbols/         curated Lucide icon registry (index.tsx) + Symbols.md manifest
├─ materials/       glass-surface.tsx + glass-controls.tsx (the glass material)
├─ showcase/        the data-driven design-system site + draggable glass demo (`npm run showcase`)
└─ components/      reusable pieces (mirror the Figma components) — stubs
```

Rules: components reference **semantic tokens only** (never raw hex); one folder per component.

### Color — established (Figma)

#### Solid spectrum (11)

`red #FF453A · orange #FF9F0A · yellow #FFD60A · green #32D74B · light-blue #7EC8E3 · cyan #41959F · blue #0A84FF · purple #BF5AF2 · lavender #A78BCC · grey #8E8E93 · grey-default #48484A`. Authored in `color.css.ts` as `vars.color.solid.*`.

#### Chips — one mode-driven component + a unified tint

Chip color is a Figma **variable-mode picker**: the `Color` collection has **10 modes** (Blue, Green, Purple, Lavender, Cyan, Light Blue, Orange, Yellow, Grey, Default — **no red**), each holding a single `Base` (the solid, aliased). Selecting a mode recolors the whole chip. The **unified tint is the base at three opacities** — no custom colors, no lightening:

- **Fill** = base @ **60%** · **stroke** = base @ **40%** (2px; **1.5px** for Checkbox) · **text** = `label-primary` + base @ **10%** (near-white with a faint color tint).
- **Shapes:** Pill (text) and Select (icon-only) are **h20 pills** (radius 10); **Checkbox** is a **17×17 square** (radius 5.5) holding a checkmark.

Soft only — no Solid variant. The Figma showcase master shows a representative color (Blue); a chip's neutral fallback is the **Default** mode (Figma's collection default mode is read-only, so setting the master to Default just greys the showcase — the neutral default lives in the React component). In code (`chip.css.ts`): one `tint(base)` formula generates `chipColor.*` via `color-mix` — fill / stroke are the base at alpha, the text mixes 10% base into `label-primary`. Code includes **red** too (11 colors) — the 10-mode cap is a Figma-only limit.

#### Accent

Accent = **lavender**. Semantic tints: `accent-fill` (lavender @ 15%) + `accent-text` (lavender lightened). These replaced the old literal `lavender-fill` / `-text` across Buttons + Labels.

#### Labels

Text colors on `#F1F1F1`: `label-primary` 100% · `label-secondary` 65% · `label-tertiary` 35%. (Also in `Typography.md`.)

#### Backgrounds · Fills · States · Accent · Separators — tokenized

Mirrored from Figma into `color.css.ts` (`vars.color.*`):

- **Backgrounds** (`background.*`): `window #1A1A1B`, `primary #222225`, `secondary #252528`, `tertiary #333336`.
- **Fills** (`fill.*`): base `#71717A` at 22.5 / 15 / 10 / 6 / 4% — `primary` → `quinary` (overlay fills over a surface).
- **States** (`state.*`): `hover`, `selected`.
- **Accent** (`accent.*`): `base` (lavender), `fill` (lavender 15%), `text` (lavender lightened).
- **Separators** (`separator.*`): `line`, `border`, `segment`.

Per-color tint variables (`-fill` / `-soft` / `-text` / …) were **removed** — the unified chip tint + these semantic tokens replace them. `grey-default` is kept (the `Default` chip color's source).

### In code — established vs planned

- **Established:** `color.css.ts` → `vars.color.solid.*` (11 solids) + `label` / `background` / `fill` / `state` / `accent` / `separator` (mirrored from Figma); a `theme-vars.css.ts` bridge re-exports these as stable `var(--…)` names so plain CSS (showcase chrome) references them, not hardcoded values; `typography.css.ts` → `font` primitives + `text.*` composed styles; `chip.css.ts` → the unified chip tint (`chip` + `chipColor.*` incl. red + `chipCheckbox`); unified in `index.ts`. vanilla-extract + Inter wired; build + typecheck green. A **data-driven** showcase at `design-system/showcase/` (`npm run showcase`) — colors / type / chips / icons / materials each iterate their registry, so new entries appear with no showcase edit. It also builds to a static site (`npm run build:showcase` → `dist/`) with a repo-tracked `vercel.json`, **live at https://pommora-design-system.vercel.app**.
- **Planned:** a **radius** + **spacing** token scale — corners + spacing are currently ad-hoc literals (**OKAY FOR NOW**, to be formalized from Figma); plus shadow / motion / z-index scales.

### Components — stub

From the Figma library, **not yet built in React**: **Button · Label · Menu · Menu Header · Separator**. Each consumes semantic tokens; the **Chip** tint already ships (`chip.css.ts`) and the **icon** system is established (Lucide, above). Built one at a time into `design-system/components/`.

### Not yet established — stubs

- **Spacing scale** · **Radius scale** · **Shadow / elevation** · **Motion** (durations, easings) · **Z-index layers** — none built yet; **corners + spacing are OKAY FOR NOW (ad-hoc literals), to be formalized as tokens from Figma.**
- **Icon system — established (Lucide).** Curated registry at `design-system/symbols/` — `import { Icon } from '@renderer/design-system/symbols'` → `<Icon name="folder" size={15} />`. Driven by `design-system/symbols/Symbols.md`: add an icon's lucide.dev name there and it gets imported (only listed icons bundle — tree-shaken). SF Symbols stay the Figma design reference only; they can't ship on web.
- **Glass — established (Materials).** `design-system/materials/` — `glass-material.ts` holds the **shared** recipe (liquidGL "Tinted Lens" at zero tint: blur 5 · brightness 90%); `GlassSurface` + `GlassControls` both spread it (identical now, separable later). Import via the `materials/index.ts` barrel. `Surface` consumes `GlassSurface`; a draggable demo (glass over 3 photo surfaces — philly · forest · mac) lives in the showcase **Materials** section.
- **Theming light/dark + per-nexus accent** (from Settings) — `createThemeContract` is the seam.
