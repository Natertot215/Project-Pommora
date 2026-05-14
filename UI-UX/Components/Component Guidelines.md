### Component Guidelines

Guidelines for the component library in `// UI-UX//Components//`.

> **When this folder fills.** Pre-translation, only this guidelines doc lives here. Component code (primitives, composed components, the app shell, styles) lands when the SwiftUI translation step of v0.0 runs — not before.

---

#### Conventions

- **Native SwiftUI idioms first.** Use SwiftUI semantic colors (`Color(.systemBackground)`, `.primary`, `.secondary`, etc.), Materials (`Material.regular`, `.sidebar`), and Font scale (`.font(.body)`, `.font(.callout)`). Reach for Pommora-specific extensions (`Color+Pommora.swift`) only when SwiftUI doesn't cover the case.
- **Modern modifiers.** `.foregroundStyle(.primary)` not `.foregroundColor()`. `.clipShape(.rect(cornerRadius: 12))` not `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns. Example: `cardStyle()` modifier wraps padding + background + corner radius.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **Cascade discipline.** Brand values change in one place (Asset Catalog or extension); propagation is automatic. No per-component overrides of brand values.

---

#### Architecture

- **Primitives-first composition.** Build atomic primitives first (Surface, Text, Icon, Stack, Pressable, Button, Field, Divider, Disclosure, DisclosureLine, Tag, Tooltip, Menu, MenuItem, Checkbox, Radio); compose larger components from those primitives.
- **No hardcoded brand values** — every Pommora-brand color/font resolves through `Color+Pommora` or Asset Catalog. Hardcoded *semantic* values (like `.foregroundStyle(.primary)`) are fine because they ARE the semantic.

---

#### Implementation

- SwiftUI views in the app target or a small Swift Package
- Components consume SwiftUI semantic colors + Pommora extensions (`Color+Pommora.swift`, `Font+Pommora.swift`, Asset Catalog)
- SF Symbols via `Image(systemName:)`
- Browsed via Xcode `#Preview`

> If pivoting to React, see `// ReactInfo// Styling-Tokens.md` for the full design token system (CSS custom properties + Tailwind v4 + Material Symbols indirection via `.pommora// symbols.json`).

---

#### Reference

- `.claude// Guidelines//UIX-Guide.md` — design philosophy, component conventions, AppKit interop
- `// UI-UX//Design//Design Guidelines.md` — design-side conventions, where Pommora-brand values live
- `.claude// ReactInfo//Styling-Tokens.md` — Figma-tool workflow + React-side full token system reference
