## Tokens

The variables. **Edit here → propagates everywhere.** Authored with vanilla-extract once wired (see the parent `README.md`).

### Tiers

- `primitives.css.ts` — raw values: the full palette, the size / weight / line-height scales. The bottom layer; not referenced by components.
- The semantic files — meaningful aliases that point at primitives, grouped by concern:
  - `color.css.ts` — `surface-background`, `surface-raised`, `text-primary`, `text-dim`, `accent`, `border`, plus interaction-state colors (`surface-hover`, `surface-selected`…).
  - `typography.css.ts` — `headline`, `body`, `caption`, `mono`…
  - `space.css.ts` — the spacing scale.
  - `radius.css.ts` · `shadow.css.ts` · `motion.css.ts` (durations + easings) · `z.css.ts`.

### One import everywhere

`index.ts` re-exports a single `vars` object. Every consumer does `import { vars } from '@/design/tokens'` and reads `vars.color.surfaceBackground`, `vars.font.headline`, etc.

### Status

Files are created as the agreed vocabulary is settled. Names are Nathan's to define; values come from the Figma library. Nothing authored yet.
