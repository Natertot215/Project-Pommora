### UI-UX

Top-level home for Pommora's UI-UX layer. Contains the design system materials (mockups, exported tokens, references) and the component library (SwiftUI views + Xcode previews).

---

#### Structure

- `// Design//` — design materials, exported tokens, design-side guidelines. Connects to the Figma file as source of truth. Detail → `// Design//Design Guidelines.md`.
- `// Components//` — component library. Hosts the SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. **Pre-translation the folder is empty except for `Component Guidelines.md`** — components are born from Figma and land here during the Figma → code translation step, not before. Detail → `// Components//Component Guidelines.md`.

---

#### Two-tier source of truth

Per `.claude// Guidelines//UIX-Guide.md`: Figma owns design tokens (canonical), and the component library here owns components built from those tokens (canonical). Components are not edited during implementation — refinements go through Figma first, then propagate.

---

#### Reference

- `.claude// Guidelines//UIX-Guide.md` — design tier model, dual-export naming discipline, settings overridability
- `.claude// ReactInfo//Symbols-guide.md` — React-side icon role indirection (`.pommora// symbols.json`); SwiftUI uses SF Symbols natively with no indirection needed
- `.claude// Planning//Figma Prompt.md` — design-system build brief (primitives, tokens, icon role table, mockup scope)
- Figma file — https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora
