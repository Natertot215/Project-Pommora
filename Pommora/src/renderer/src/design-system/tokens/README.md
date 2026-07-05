## Tokens

The variables. **Edit here → propagates everywhere.** Authored with vanilla-extract once wired (see the parent `README.md`).

### Tiers

- `primitives.css.ts` — raw values: the full palette, the size / weight / line-height scales. The bottom layer; not referenced by components.
- The semantic files — meaningful aliases that point at primitives, grouped by concern:
  - `color.css.ts` — the `solid.*` spectrum (11 hues), `label.*` tones, `background.window`, `surface.*`, `fill.*`, `state.*`, and `separator.*`. The accent is **not** a token here — it's a runtime `--accent` pointer to one of the solids (see `accent.ts` / `theme-vars.css.ts`).
  - `typography.css.ts` — `font` scale primitives + `text.<style>.{standard,emphasized}` composed classes (`mono` to follow).
  - `space.css.ts` — the spacing scale.
  - `radius.css.ts` · `shadow.css.ts` · `motion.css.ts` (durations + easings) · `z.css.ts`.

### Color format

Authored colors are **hex** — `#RRGGBB`, or `#RRGGBBAA` (8-digit) when an alpha is needed (e.g. `#8E8E930A` = grey at ~4%). Never `rgb()` / `rgba()` in token values or component styles — the spectrum, fills, states, and separators all follow this. The lone exception is a color the *platform* returns (e.g. `getComputedStyle` in `accent.ts` hands back an `rgb(…)` string): that value is read, not authored.

### One import everywhere

`index.ts` exposes a single `vars` object plus `text`. Every consumer does `import { vars, text } from '@renderer/design-system/tokens'` — read scalars as `vars.color.solid.blue` / `vars.font.weight.semibold` / `vars.font.scale.body.size`, and apply a whole text style with `className={text.headline.emphasized}`.

### Status

`color.css.ts` holds the **solid spectrum** (11 hues), **label tones** (`label.primary` / `secondary` / `tertiary`), plus `background` / `surface` / `fill` / `state` / `separator`. `typography.css.ts` — `font` primitives + composed `text.*` classes. `chip.css.ts` — the unified chip tint (`chip` + `chipColor.*` + `chipCheckbox`): one `color-mix` formula over the solids (fill 60% · stroke 40% · text label-primary + 15%, matching Figma's `Tint/Quinary`). `index.ts` unifies all three. A live showcase renders them at `design-system/showcase/` (`npm run showcase` → localhost). Tooling wired (vanilla-extract + Inter); build green. The **accent is a runtime `--accent` pointer** to a spectrum solid (or the OS accent) — not a baked token (see `accent.ts` + `theme-vars.css.ts`).
