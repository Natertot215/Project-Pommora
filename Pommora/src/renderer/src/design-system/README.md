## Design System

The Pommora design system — the **code mirror of the Figma Component Library**. One place that owns every design value and reusable piece, so the app stays DRY: edit a value here and it propagates everywhere that references it.

### The model

Two tiers, one direction of reference:

- **Primitives** — raw values (`gray-900 = #1C1C1F`, `size-17 = 17px`). The bottom layer; never referenced directly by components.
- **Semantic tokens** — meaningful aliases that point at primitives (`surface-background → gray-900`, `headline → 600 / size-17`). This is the vocabulary the rest of the app speaks.

Components reference **only** semantic tokens — never a raw hex or px. Re-skinning the app is then a matter of repointing a few semantic tokens.

### Layout

- `tokens/` — the variables (colors, typography, spacing, radius, shadow, motion, z). See `tokens/README.md`.
- `components/` — the reusable pieces (Button, Menu, Chip…), one folder each. See `components/README.md`.

### The two rules

1. **Components reference semantic tokens only** — `vars.color.solid.cyan`, never `#007AFF`.
2. **One folder per component** — the component, its styles, and its states live together.

### Tooling (planned — not yet wired)

Tokens will be authored with **vanilla-extract** (`@vanilla-extract/css`): each token file is a readable `name: value` list that compiles to real CSS variables *and* exposes a typed `vars` object, so a mistyped token name is a compile error. The Vite plugin + the `@/design` import alias are a setup step taken when the first token file lands.

### Status

Scaffold only. The token vocabulary + values (sourced from Figma) and the component set are authored under direction — nothing here is locked until reviewed.
