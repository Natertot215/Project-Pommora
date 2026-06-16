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

`color.css.ts` holds the **solid spectrum** (11 hues) + **label tones** (`label.primary` / `secondary` / `tertiary`). `typography.css.ts` — `font` primitives + composed `text.*` classes. `chip.css.ts` — the unified chip tint (`chip` + `chipColor.*` + `chipCheckbox`), one `color-mix` formula over the solids. `index.ts` unifies all three. A live showcase renders them at `design/showcase/` (`npm run showcase` → localhost). Tooling wired (vanilla-extract + Inter); build green. Accent / background / fill / state tokens come next.
