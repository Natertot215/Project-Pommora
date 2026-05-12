### Design Guidelines

Guidelines for design assets and design-system materials in `// UI-UX//Design//`.

---

#### Source of truth

Figma owns design tokens. File: https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora. Build brief: `.claude// Planning//Figma Prompt.md`.

Reference: `.claude// Guidelines//UIX-Guide.md`.

---

#### What goes here

- **Exported design tokens** — generated from Figma Variables. CSS custom properties for React (`tokens.css`); SwiftUI `Color` / `Font` extensions for Swift (`Tokens.swift`).
- **Design mockups** for individual screens / surfaces (PNG / SVG / Figma frame exports).
- **Asset references** — image placeholders, icon previews, screenshot reference.
- **Design iteration notes** — decisions made during Figma round 1+ that need to persist outside Figma's history.

---

#### What doesn't go here

- Implemented component code → `// Components//`
- Top-level design philosophy / token taxonomy → `.claude// Guidelines//UIX-Guide.md`
- Icon role mapping → `.claude// Guidelines//Symbols-guide.md` + `.claude// Planning//Figma Prompt.md`

---

#### Discipline

- **Token names** follow the dual-export naming convention (semantic role-based; full rules in `.claude// Guidelines//UIX-Guide.md`). No hardcoded values — every exported value resolves through a Variable name.
- **Asset filenames** — kebab-case, descriptive.
- **Versioned exports overwrite** — no `tokens-v2.css` parallel files; the Figma file is the version source. Re-exporting produces the same filename with updated values.
