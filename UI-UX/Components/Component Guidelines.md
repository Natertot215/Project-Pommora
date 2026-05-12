### Component Guidelines

Guidelines for the component library in `// UI-UX//Components//`.

> **When this folder fills.** Pre-translation, only this guidelines doc lives here. Component code (primitives, composed components, the renderer entry, shell, styles) lands **during the Figma → code translation step** of v0.0's build order — not before. Pre-stocking the folder with skeleton files would defeat the cascade discipline: every component is born from Figma, never invented in code first.

---

#### Two-tier source of truth

Per `.claude// Guidelines//UIX-Guide.md`: Figma Variables own design tokens; this folder owns components built from them. Components are not edited during implementation — refinements happen in Figma first, then propagate. The Figma component library (see `.claude// Planning//Figma Prompt.md`) is the design source for what gets built here.

---

#### Architecture

- **Primitives-first composition.** Build atomic primitives first (Surface, Text, Icon, Stack, Pressable, Button, Field, Divider, Disclosure, DisclosureLine, Tag, Tooltip, Menu, MenuItem, Checkbox, Radio); compose larger components from those primitives. Composed components never reach around primitives to set literal values.
- **Tokens via Variables.** Every visual property in every component is bound to a token Variable. **Zero hardcoded values.**
- **Cascade discipline.** Changing a token Variable propagates to every consumer; no per-component overrides.
- **Single component, many variants.** One component per concept with variant properties — no duplicated components per state / tier / intent (a single `Button` with a `variant` prop, not seven button files).
- **Initial-build symbol placeholder.** All symbol slots render the `crop_free` Material Symbol until specific icons are finalized per role; replacement happens in a round-2 pass per `.claude// Planning//Figma Prompt.md`.

Full primitive list, composed-component list, and acceptance criteria → `.claude// Planning//Figma Prompt.md`.

---

#### Stack-conditional implementation

**For React**

- TypeScript (strict mode)
- Components consume tokens via CSS custom properties (exported from Figma into `// UI-UX//Design//tokens.css` or similar)
- Material Symbols via `react-material-symbols` through the semantic role indirection layer (`.pommora// symbols.json`; see `.claude// Guidelines//Symbols-guide.md`)
- **This folder hosts the Vite + Electron localhost dev server.** The running app IS the component gallery; no Storybook intermediary.
- Initial-build symbol placeholder is `crop_free`; replace per-role during round 2.

**For Swift**

- SwiftUI views in the app target or a small Swift Package
- Components consume tokens via SwiftUI `Color` and `Font` extensions (generated from Figma Variables, exported to `// UI-UX//Design//Tokens.swift`)
- SF Symbols via `Image(systemName:)` through the same role table
- Browsed via Xcode `#Preview`

---

#### Scope discipline

See `.claude// Planning//Figma Prompt.md` for the canonical primitive and composed-component list. **Don't add components outside that list** without updating the Figma source first — the cascade discipline depends on Figma being authoritative for what exists.

---

#### Reference

- `.claude// Guidelines//UIX-Guide.md` — design tier model, naming discipline, settings overridability (in-app token override mechanism)
- `.claude// Guidelines//Symbols-guide.md` — icon role indirection
- `.claude// Planning//Figma Prompt.md` — full design-system spec
- `// UI-UX//Design//Design Guidelines.md` — design-side conventions and exports
