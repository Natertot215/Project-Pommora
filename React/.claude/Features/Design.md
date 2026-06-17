## Design System

The Pommora design system — the code mirror of the Figma "Pommora - React" library. Two-tier tokens (raw **primitives** → meaningful **semantic** aliases); components reference semantic tokens only. Typography has its own spec: `Typography.md`.

### Design philosophy

The React build follows its Swift counterpart closely — **near-identical by intent**. Apple's design language, and **macOS Tahoe** in particular, is the north star: restraint, depth through material over ornament, quiet precision. We mirror that feel rather than reinvent it.

Where React opens doors the native build couldn't — richer motion, interaction, and layout — we treat them as **additive prospects**, adopted only when they deepen the Apple-grade minimalism, never when they clutter it. Simplicity is the constraint, not the compromise.

### Source of truth

The Figma library is canonical for design *values*; this repo mirrors them as tokens. Values change in Figma first, then sync here. Figma is also the visual reference for components.

### Tooling

- **vanilla-extract** — token files are `*.css.ts`; the theme primitives emit real CSS variables **and** a typed `vars` object, so a mistyped token is a compile error. The plugin is wired into the renderer Vite config.
- **Inter** (variable font) covers the four weights the type ramp uses and is set as the app font.

The design system lives in `src/renderer/src/design-system/`. The `tokens/` folder holds the variables (color, typography, the chip tint, and a bridge that re-exports tokens as stable `var(--…)` names including `--accent`); a runtime accent module applies the per-Nexus accent; `symbols/` is the curated icon registry; `materials/` is the glass material; `showcase/` is the data-driven design-system site; `components/` holds the reusable pieces that mirror the Figma components.

Rule: components reference **semantic tokens only**, never raw values; one folder per component.

### Color

The dark surface system is built from **one neutral base** rendered at descending opacities. Fills, states, and separators are all that same single base at fixed opacities — never separate colors. The relationship is ordered by visual weight: **fills are the heaviest, strokes lighter, text-washes lightest**. Holding one base means the whole interior reads as one consistent material.

#### Semantic surface roles

Surfaces are addressed by **role**, not by literal shade. The window is the app substrate that everything sits on; **primary / secondary / tertiary** surfaces are progressively-lifted content layers above it. Components reference the role; the shade behind each role lives in the token files.

#### Fills, states, separators

All derived from the single neutral base at fixed opacities:

- **Fills** — overlay fills over a surface, in a five-step ramp from most to least present.
- **States** — `hover` and `selected` are the same base at low opacities; selection sits slightly above hover.
- **Separators** — lines, borders, and segment dividers, again the same base, at their own fixed opacities.

#### Solid spectrum

A fixed palette of named solids (red, orange, yellow, green, light-blue, cyan, blue, purple, lavender, grey, plus a neutral default). These are the source colors for accents and chips. The exact values live in the token files / Figma.

#### Accent

The accent is a **single user value**. Components reference one accent token plus two derivations: a **fixed-opacity tint** for accented fills, and the accent itself for accented text — so changing the accent recolors every accented surface at once. The per-Nexus choice is any spectrum solid or **`system`** (the OS accent), stored in `.nexus/settings.json`, validated on read, and applied on load. `system` resolves to the OS accent color (via Electron in the app, the CSS system-accent color in the web showcase); macOS has no live accent-change event, so it's read at load.

#### Chips

A chip's color is the picked base solid at fixed opacities — a heavier fill, a lighter stroke, and a near-white text wash with a faint tint of the base. No custom colors and no lightening; one tint recipe drives every chip color. **Chips are pills** (text or icon-only); the **checkbox is a small square** holding a checkmark. The opacities and dimensions live in the token files / Figma.

#### Labels

Text color is separate from surface color: three label tones — primary, secondary, tertiary — are one near-white base at descending opacities. (Also in `Typography.md`.)

### Glass

Glass is **blur plus a slight dimming** of what's behind it — a single shared material recipe spread by both the surface and control variants (identical now, separable later). `Surface` consumes it, and a draggable demo over photo backdrops lives in the showcase Materials section.

### Icons

A curated icon registry: an icon is listed by name in the registry manifest and only listed icons bundle (tree-shaken). Used as `<Icon name="…" />`. SF Symbols remain the Figma design reference only — they can't ship on web.

### Showcase

A data-driven design-system site (`npm run showcase`): color groups, type, chips, icons, and materials each iterate their registry, so a new token group appears by adding one line. It includes a live accent picker and builds to a static site deployed at https://pommora-design-system.vercel.app.

### Components

The reusable pieces mirror the Figma library — **Button · Label · Menu · Menu Header · Separator** — each consuming semantic tokens, built one at a time. The **Chip** tint and the **icon** system already ship.

### Not yet tokenized

**Spacing · radius · shadow/elevation · motion · z-index** scales are not yet formalized — corners and spacing are ad-hoc literals for now, to be lifted into tokens from Figma. **Light/dark theming** is a future seam (the theme contract is the hook); today the system is dark only. The Settings editing UI for the accent is deferred — for now the control surface is the config file.
