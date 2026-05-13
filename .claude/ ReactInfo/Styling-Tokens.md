### React Styling + Token Export

Tailwind CSS v4 + CSS custom properties exported from Figma Variables. Dual-export naming discipline (`surface// primary// bg` ↔ `--surface-primary-bg`) and the Figma → React translation findings.

> **Status:** Reference. Swift exports the same Figma Variables to `Color` / `Font` extensions per `// Guidelines//UIX-Guide.md`.

---

#### Design system status (Figma → React)

The Figma design system is built at the variable + visual-mock level: ~118 tokens with full binding, primitives and composed components rendered as gallery FRAMEs, three-pane shell mockup. Conversion of gallery FRAMEs into reusable COMPONENT_SETs is planned at `.claude// Planning// Figma Components 5-13.md` and runs next.

**What the Figma build revealed about the React path:** Figma produces really good UIX for React — the Figma → React translation is a real, well-supported workflow that gives Nathan the design system he wants. It's also gimmicky in places, requires tweaking, and has things that look obvious to a designer but are hard for Claude to implement directly. The design system is a real option, not a free one — it requires work and frustration like anything else. This matters for the stack decision because it sizes the rest-of-app build effort: React's path means every component is a Figma → translation chain, and Nathan owns that surface.

**Live React demo is the gate.** Until components are translated to React + Tailwind in `UI-UX// Components//` and the localhost dev server is running, "what React feels like" is hypothetical. The Figma file alone reveals static design intent; the live demo reveals UIX behavior under interaction.

**Build sequence to live demo (after Figma component conversion):**
1. Figma Variables → CSS custom properties → `UI-UX// Design// tokens.css`
2. Figma COMPONENT_SETs → React components in `UI-UX// Components//` consuming those tokens
3. Vite + Electron renderer scaffolded with `UI-UX// Components//` as root
4. Localhost dev server running the component gallery — this is the demo
