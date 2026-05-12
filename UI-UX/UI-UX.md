### UI-UX

Top-level home for Pommora's UI-UX layer. Contains the design system materials (mockups, exported tokens, references) and the component library (primitives + composed components, plus the React localhost dev server).

---

#### Structure

- `// Design//` — design materials, exported tokens, design-side guidelines. Connects to the Figma file as source of truth. Detail → `// Design//Design Guidelines.md`.
- `// Components//` — component library. On the React path, will host the component code and the Vite + Electron localhost dev server (the component gallery + working app surface — **no Storybook intermediary**). On the SwiftUI path, will host the SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. **Pre-translation the folder is empty except for `Component Guidelines.md`** — components are born from Figma and land here during the Figma → code translation step, not before. Detail → `// Components//Component Guidelines.md`.

---

#### Two-tier source of truth

Per `.claude// Guidelines//UIX-Guide.md`: Figma owns design tokens (canonical), and the component library here owns components built from those tokens (canonical). Components are not edited during implementation — refinements go through Figma first, then propagate.

---

#### Stack status

**Both React + Electron and SwiftUI remain candidate stacks.** The UI-UX folder structure is stack-shared; folder contents differ per stack (React lands `.tsx` files + Vite + Electron localhost in `Components//`; Swift lands SwiftUI views + Xcode preview targets). The Figma file feeds either direction; variable names stay constant across both exports.

---

#### Reference

- `.claude// Guidelines//UIX-Guide.md` — design tier model, dual-export naming discipline, settings overridability
- `.claude// Guidelines//Symbols-guide.md` — icon role indirection (`.pommora// symbols.json`)
- `.claude// Planning//Figma Prompt.md` — design-system build brief (primitives, tokens, icon role table, mockup scope)
- Figma file — https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora
