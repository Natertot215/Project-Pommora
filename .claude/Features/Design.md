## Design System

The Pommora design system — the **code mirror of the Figma "Pommora - React" library**. Two-tier tokens (raw **primitives** → meaningful **semantic** aliases); components reference semantic tokens only. Lives in `src/renderer/src/design/`. Typography has its own spec: `Typography.md`.

### Source of truth

The **Figma "Pommora - React"** file is canonical for design *values*; this repo mirrors them as tokens. Values change in Figma first, then sync to the tokens here. The Figma file is also the visual reference for components.

### Tooling — established

- **vanilla-extract** (`@vanilla-extract/css` + `@vanilla-extract/vite-plugin`) — token files are `*.css.ts`; `createGlobalTheme(':root', …)` emits real CSS variables **and** a typed `vars` object (autocomplete; a mistyped token is a compile error). Plugin wired into the renderer Vite config.
- **Inter** (`@fontsource-variable/inter`) — variable font, family `Inter Variable`, covering Regular / Medium / Semibold / Bold; imported in `main.tsx` and set as the app font.
- Committed `404a1d7` (branch `design-system`).

### Folder

```
design/
├─ tokens/          the variables — edit here → propagates app-wide
│   ├─ color.css.ts        ← solid spectrum
│   ├─ typography.css.ts   ← font primitives + composed text styles
│   └─ index.ts            ← unified `vars` + `text`
└─ components/      reusable pieces (mirror the Figma components) — stubs
```

Rules: components reference **semantic tokens only** (never raw hex); one folder per component.

### Color — established (Figma)

#### Solid spectrum (11)

`red #FF453A · orange #FF9F0A · yellow #FFD60A · green #32D74B · light-blue #7EC8E3 · cyan #41959F · blue #0A84FF · purple #BF5AF2 · lavender #A78BCC · grey #8E8E93 · grey-default #48484A`. Authored in `color.css.ts` as `vars.color.solid.*`.

#### Chips — one mode-driven component + a unified tint

Chip color is a Figma **variable-mode picker**: the `Color` collection has **10 modes** (Blue, Green, Purple, Lavender, Cyan, Light Blue, Orange, Yellow, Grey, Default — **no red**), each holding a single `Base` (the solid, aliased). Selecting a mode recolors the whole chip. The **unified tint is the base at three opacities** — no custom colors, no lightening:

- **Soft (default):** surface = base @ **60%** (Fill) · outline = base @ **25%** · label = `label-primary` + base @ **10%** (white with a faint color tint).
- **Solid:** surface = base @ **100%** · label = `label-primary` (white) · no outline.

The Figma showcase master shows a representative color (Blue); a chip's neutral fallback is the **Default** mode, applied as the React `Chip` component's default (Figma's collection default mode is read-only, and setting the master to Default greys the showcase). In code: surface + outline are the base at opacity; the label is `label-primary` mixed ~10% with the base (a `color-mix`). Pending.

#### Accent

Accent = **lavender**. Semantic tints: `accent-fill` (lavender @ 15%) + `accent-text` (lavender lightened). These replaced the old literal `lavender-fill` / `-text` across Buttons + Labels.

#### Labels

Text colors on `#F1F1F1`: `label-primary` 100% · `label-secondary` 65% · `label-tertiary` 35%. (Also in `Typography.md`.)

#### Backgrounds · Fills · States · Separators

- **Backgrounds:** `bg-window #1C1C1F`, `bg-primary`, `bg-secondary`, `bg-tertiary`, `bg-quaternary`, `bg-quinary`.
- **Fills:** base `#747480` at 22.5 / 15 / 10 / 6 / 4% (overlay fills, over a surface).
- **States:** `state-hover`, `state-selected`.
- **Separators:** `separator`, `border`, `segment`.

Per-color tint variables (`-fill` / `-soft` / `-text` / `-soft-border` / `-soft-text`) have been **removed** — the unified chip tint + the semantic tokens above replace them. `grey-default` is kept (it's the `Default` chip color's source).

### In code — established vs planned

- **Established:** `color.css.ts` → `vars.color.solid.*` (11 solids); `typography.css.ts` → `font` primitives + `text.*` composed styles (full ramp — see `Typography.md`); unified in `index.ts`. vanilla-extract + Inter wired; build green.
- **Planned:** the remaining color tokens (labels, accent, backgrounds, fills, states, separators) + the chip-tint rule, each as a `design/tokens/*.css.ts` file.

### Components — stub

From the Figma library, **not yet built in React**: **Button · Label · Chip · Menu · Menu Header · Separator** (+ the Symbol / icon system). Each consumes semantic tokens; the **Chip** owns the unified-tint derivation. Built one at a time into `design/components/`.

### Not yet established — stubs

- **Semantic color tokens** beyond labels — `surface-background`, `surface-raised`, `text-primary` / `-dim`, `border`, …
- **Spacing scale** · **Radius scale** · **Shadow / elevation** · **Motion** (durations, easings) · **Z-index layers**.
- **Icon system** — SF Symbols (Swift) ↔ Phosphor (current React); mapping + sizing.
- **Theming** — light/dark; per-nexus accent (from Settings). vanilla-extract `createThemeContract` is the seam.
- **Glass / Surface** — the sidebar glass recipe (Apple-Regular CSS); the `Surface` swappable seam (see `Handoff.md`).
- **`@/design` import alias** — add to `tsconfig` + Vite when the first component imports tokens.
