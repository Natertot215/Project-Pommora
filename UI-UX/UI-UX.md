### UI-UX

Top-level home for Pommora's UI-UX layer. Contains design materials (`Assets.xcassets`, Pommora-specific Color/Font extensions, mockups) and the component library (SwiftUI views + Xcode previews).

---

#### Structure

- `// Design//` — design materials. Holds `Assets.xcassets` (app icon, accent color, color sets), `Color+Pommora.swift` / `Font+Pommora.swift` (Pommora-brand Color/Font extensions), design mockups, and asset references. Detail → `// Design//Design Guidelines.md`.
- `// Components//` — component library. Hosts SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. **Pre-translation the folder is empty except for `Component Guidelines.md`** — components are authored when the SwiftUI translation step of v0.0 runs. Detail → `// Components//Component Guidelines.md`.

---

#### Where Pommora's design values live

- **Native SwiftUI semantic colors and Font scale** carry most of the design surface — `Color(.systemBackground)`, `.foregroundStyle(.primary)`, `.font(.body)`, `Material.regular`. Pulled directly from SwiftUI in components.
- **Pommora-brand values** (accent color, code block colors, callout treatments) live in `// Design//Assets.xcassets` and `// Design//Color+Pommora.swift`. Components consume these alongside the SwiftUI native semantics; brand values change in one place, propagation is automatic.
- **AppKit is used directly via `NSViewRepresentable`** where SwiftUI falls short — most notably NSTextView/TextKit 2 for Option 1 editor, NSSplitView for splitter polish. Both SwiftUI and AppKit are first-class Pommora tools; AppKit isn't an escape hatch. Detail → `.claude// Guidelines//UIX-Guide.md` "AppKit Interop" section.

---

#### Reference

- `.claude// Guidelines//UIX-Guide.md` — design philosophy, component conventions, AppKit interop
- `.claude// ReactInfo//Styling-Tokens.md` — Figma-tool workflow (file URL, FRAME conversion plan, full ~118-token React-flavored taxonomy)
- `.claude// ReactInfo//Symbols-guide.md` — React-side icon role indirection; SwiftUI uses SF Symbols natively
