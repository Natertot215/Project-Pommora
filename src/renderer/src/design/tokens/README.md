## Tokens

The variables. **Edit here → propagates everywhere.** Authored with vanilla-extract once wired (see the parent `README.md`).

### Tiers

- `primitives.css.ts` — raw values: the full palette, the size / weight / line-height scales. The bottom layer; not referenced by components.
- The semantic files — meaningful aliases that point at primitives, grouped by concern:
  - `color.css.ts` — `surface-background`, `surface-raised`, `text-primary`, `text-dim`, `accent`, `border`, plus interaction-state colors (`surface-hover`, `surface-selected`…).
  - `typography.css.ts` — `font` scale primitives + `text.<style>.{standard,emphasized}` composed classes (`mono` to follow).
  - `space.css.ts` — the spacing scale.
  - `radius.css.ts` · `shadow.css.ts` · `motion.css.ts` (durations + easings) · `z.css.ts`.

### One import everywhere

`index.ts` exposes a single `vars` object plus `text`. Every consumer does `import { vars, text } from '@renderer/design/tokens'` — read scalars as `vars.color.solid.blue` / `vars.font.weight.semibold` / `vars.font.scale.body.size`, and apply a whole text style with `className={text.headline.emphasized}`.

### Status

`color.css.ts` holds the **solid color spectrum** (11 hues; solids only — `fill` / `text` / `soft` variants to follow). `typography.css.ts` is authored — `font` primitives (family, four weights, the 10-style size / line scale) plus the composed `text.*` style classes, mirroring the Figma ramp; `index.ts` unifies them. Tooling is wired (vanilla-extract Vite plugin + Inter via `@fontsource-variable/inter`) and the build extracts the CSS green. Label / background / fill / state color tokens come next.
