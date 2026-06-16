## Components

The reusable pieces — the code mirror of the Figma components. Each consumes **semantic tokens only** (never raw values), so the whole set re-skins from `tokens/`.

### One folder per component

```
Button/
  Button.tsx        the component — variants + states
  Button.css.ts     its styles, referencing vars.* only
```

Variants and states (hover / selected / pressed / disabled / focus) live inside the component's own folder — everything that changes together stays together. `index.ts` barrel-exports the set: `import { Button, Menu } from '@/design'`.

### Planned set (from the Figma library)

Button · Label · Chip · Menu · Menu Header · Separator. Each folder is created when that component is built — not before.

### Boundary

This folder holds **reusable** primitives. App-specific composite views (Sidebar, DetailPane, the page editor) live under `renderer/src/components` + `renderer/src/views` and *consume* these.

### Status

Scaffold only — no component folders yet. Built one at a time, under direction.
