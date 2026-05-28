### React Styling + Token Export

Tailwind CSS v4 + CSS custom properties exported from Figma Variables. Dual-export naming discipline (`surface// primary// bg` ↔ `--surface-primary-bg`) and the Figma → React translation findings.

> **Status:** Reference. Swift consumes brand values from `Color+Pommora.swift` + `Font+Pommora.swift` + `Assets.xcassets` per `// Guidelines//Design.md` (SF Symbol assignments live in `// Guidelines//Symbols.md`). This file documents the Figma-tool workflow and React-side translation path.

---

#### Figma file — design tool of record

The design system was built in Figma alongside the React-path evaluation. **Figma file:** https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora (fileKey `cm2wRDXWKg05iydG412z4B`).

For Swift, the canonical source is `Tokens.swift` — Figma is preserved here as the React-side reference. If the React pivot happens, this Figma file is where token export and component translation begin.

#### Current build state

Tokens (~118 vars) and primitives + composed components are built in the Figma file as gallery FRAMEs with full token bindings. Nine Tag components are converted to standalone COMPONENTs; the remaining 35 gallery items are still FRAMEs.

**Initial-build placeholder.** Until specific icons are finalized per role, the Figma design system uses the `crop_free` Material Symbol (a square frame) for every symbol slot. The icon-role finalization is post-conversion work; until then `crop_free` stays inline and the INSTANCE_SWAP `vector` slot on the Icon component is deferred.

#### What the Figma build revealed about the React path

Figma produces really good UIX for React — the Figma → React translation is a real, well-supported workflow that gives Nathan the design system he wants. It's also gimmicky in places, requires tweaking, and has things that look obvious to a designer but are hard for Claude to implement directly. The design system is a real option, not a free one — it requires work and frustration like anything else.

#### React build sequence (if pivoting)

1. Figma Variables → CSS custom properties → `UI-UX// Design// tokens.css`
2. Figma COMPONENT_SETs → React components in `UI-UX// Components//` consuming those tokens
3. Vite + Electron renderer scaffolded with `UI-UX// Components//` as root
4. Localhost dev server running the component gallery — this is the demo
