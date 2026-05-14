### Design Guidelines

Guidelines for design assets and materials in `// UI-UX//Design//`.

---

#### Where values live

Pommora uses SwiftUI native semantic colors and Font scale wherever possible. Pommora-specific brand values (accent purple, code block colors, callout treatments) live as:

- **`Assets.xcassets`** — color sets with light/dark variants for the app accent color, brand assets, image placeholders.
- **`Color+Pommora.swift`** — Swift extensions for code-defined Pommora colors that need access from SwiftUI views.
- **`Font+Pommora.swift`** — Swift extensions for Pommora-specific Font variants where the SwiftUI scale (`.body`, `.callout`, `.caption`) doesn't fit (e.g. micro size).

Most values use SwiftUI semantic forms directly (`Color(.systemBackground)`, `.foregroundStyle(.primary)`, `.font(.body)`, `Material.regular`); only Pommora-brand values need extensions. Design philosophy + component conventions live in `.claude// Guidelines//UIX-Guide.md`.

> The full ~118-token Figma-built design system is a React-pattern preserved as the React-side reference at `.claude// ReactInfo//Styling-Tokens.md`. For Swift, the brand-color set is small — SwiftUI native idioms cover most cases.

---

#### What goes here

- `Assets.xcassets` — app icon, accent color, brand image assets, color sets with light/dark variants
- `Color+Pommora.swift`, `Font+Pommora.swift` — Swift extensions for Pommora-specific values
- Design mockups for individual screens / surfaces (PNG / SVG exports)
- Asset references — image placeholders, icon previews, screenshot reference
- Design iteration notes — decisions that need to persist outside any design tool's history

---

#### What doesn't go here

- Implemented component code → `// Components//`
- Design philosophy and component conventions → `.claude// Guidelines//UIX-Guide.md`
- Figma-tool workflow (file URL, FRAME conversion, full token taxonomy) → `.claude// ReactInfo//Styling-Tokens.md`

---

#### Discipline

- **Prefer SwiftUI native idioms.** `Color(.systemBackground)`, `.foregroundStyle(.primary)`, `.font(.body)`, `Material.regular`. Use Pommora extensions only for values that don't have native equivalents.
- **Asset filenames** — kebab-case, descriptive.
- **Color sets with light/dark variants** — when adding a Pommora-brand color, prefer adding to `Assets.xcassets` with both modes defined, even if light mode isn't shipped in v0.x.
