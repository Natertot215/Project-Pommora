### UIX Guide

Pommora's visual identity, component library, and design conventions — Swift/Apple-native.

---

#### Design philosophy

Pommora follows Apple's macOS Human Interface Guidelines for native cohesion. The toolkit is **SwiftUI primary + AppKit where SwiftUI doesn't reach** — both are first-class. The shell uses SwiftUI native idioms wherever possible:

- **Semantic colors** — `Color(.systemBackground)`, `Color(.secondarySystemBackground)`, `.foregroundStyle(.primary)`, `.foregroundStyle(.secondary)`. Automatic dark mode and accessibility support; no overrides needed.
- **Materials** — `Material.regular`, `.thin`, `.thick`, `.ultraThin`, `.sidebar` for vibrancy/translucency.
- **Native typography** — SwiftUI Font scale (`.font(.body)`, `.font(.callout)`, `.font(.caption)`, `.font(.system(.body, design: .monospaced))`). Custom sizes only where the scale doesn't fit. Dynamic Type is free.
- **SF Symbols** — `Image(systemName: "settings")`. The native iconography, available everywhere.
- **Native controls** — system Button, Slider, Toggle, etc. with `ButtonStyle` and `ViewModifier` for reusable Pommora-specific styling.
- **Window chrome** — macOS unified title bar, OS-rendered traffic-light buttons.

**AppKit is used directly** where SwiftUI is insufficient or rough — most notably for the editor on Option 1 (NSTextView / TextKit 2 carries source-with-decorations text behavior; STTextView is the modern wrapper) and for splitter polish (NSSplitView via `NSViewRepresentable` outperforms SwiftUI's `HSplitView` in production). AppKit isn't an escape hatch — it's the Apple-native answer when SwiftUI's surface stops short. The AppKit Interop section below catalogues the specific places this comes up.

On top of the SwiftUI + AppKit baseline, Pommora has a small set of brand-specific values that don't have native equivalents — pastel-muted purple accent, code block colors, callout border, blockquote accent bar — that express Pommora's character within the Apple aesthetic.

---

#### Where Pommora's brand values live

- **App accent color** — Asset Catalog (`Assets.xcassets/AccentColor.colorset`) with light/dark variants. Accessed natively via `Color.accentColor` or set globally with `.tint(.accentColor)`.
- **Pommora-specific Colors** — small Color extensions (`Color+Pommora.swift` or Asset Catalog color sets) for the handful of values SwiftUI semantic colors don't cover: code block fg/bg, callout border (+ optional bg), blockquote accent bar, any custom surface variants. Apple-idiomatic naming: `Color.pommoraCodeBackground`, `Color.pommoraCalloutBorder`, etc.
- **Pommora-specific Fonts** — small Font extensions where the SwiftUI scale doesn't fit (e.g. micro / caption variants).

That's the entire "Pommora brand surface" on Swift. SwiftUI semantic colors and Font scale carry the rest.

> The full ~118-token design system (with semantic role-based naming, surface/element tier model, dual-axis taxonomy) is a React-pattern that prototyped well in Figma. It lives as the React-side reference at `// ReactInfo// Styling-Tokens.md`. For Swift, that level of token engineering isn't needed — SwiftUI's semantic system does most of the work.

---

#### Editor canvas (WKWebView Option 2)

The WKWebView editor renders HTML/CSS inside a native shell. CSS theming inside the canvas **does** use design tokens (CSS custom properties) because that's how web-side styling works. The token set is small — it mirrors the SwiftUI brand values above so the editor matches the shell — and gets injected into the editor canvas via the JS bridge at editor mount.

If Option 1 (native NSTextView) is chosen instead, no CSS tokens are needed; the editor styles with SwiftUI attributes directly.

---

#### Component conventions

- **Prefer SwiftUI semantic colors and fonts.** Use Pommora extensions only for values that don't have native equivalents.
- **Modern modifiers.** `.foregroundStyle(.primary)` not `.foregroundColor()`. `.clipShape(.rect(cornerRadius: 12))` not `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns. Example: `cardStyle()` modifier wraps padding + background + corner radius.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **Cascade discipline.** Brand values change in one place (Asset Catalog or extension); propagation is automatic.

---

#### Component library

`// UI-UX//Components//` holds SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. Components are not edited during feature work — refinements happen in the library first, then propagate.

---

#### Initial scheme

Dark mode first. SwiftUI semantic colors cover the shell; Pommora extensions provide the accent and brand-specific values. No built-in light/dark toggle in v0.x; in-app customization for the accent + typography size lands in Framework v0.12.

Visual reference for the feel: minimalist dark systems like Obsidian, ChatGPT, Apple, Claude Desktop. Pommora picks density, contrast, and typographic restraint cues from these but doesn't copy values.

---

#### AppKit Interop

Areas where pure SwiftUI is expected to be sufficient and areas where wrapping AppKit via `NSViewRepresentable` is likely to be the right tool. Specific tradeoffs are confirmed in build:

- **Block reorder in a vertical stack** — pure SwiftUI looks sufficient; a candidate community library is [visfitness/reorderable](https://github.com/visfitness/reorderable).
- **Resizable columns with persistent splitter** — SwiftUI's `HSplitView` exists; community reports suggest wrapping `NSSplitView` via `NSViewRepresentable` yields better splitter polish on macOS. Evaluate when the Spaces composer goes from spec to build.
- **Tree-shaped reorderable structure with cross-level drag** — doable in pure SwiftUI via `DisclosureGroup` + manual `NSItemProvider`. Reference: [shufflingB/swiftui-macos-tree-list-demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo). Whether the SwiftUI-only path is good enough vs. an AppKit wrap is open.
- **Unified cursor flow across columns / callouts** — generally requires `NSTextView` / TextKit 2 (STTextView is a modern wrapper) since SwiftUI's text primitives don't currently span sibling containers.
