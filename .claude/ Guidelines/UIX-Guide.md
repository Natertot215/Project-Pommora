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

On top of the SwiftUI + AppKit baseline, Pommora has a small set of brand-specific values that don't have native equivalents — code block colors, callout border, blockquote accent bar — that express Pommora's character within the Apple aesthetic.

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
- **SF Symbol weight matches text weight.** Symbols inherit weight from the surrounding text style when paired — keep that link. Don't render a `.thin` symbol next to `.heavy` text (or vice versa); the mismatch reads as inconsistent. If a symbol's weight needs to deviate, apply `.fontWeight()` to the symbol explicitly so the choice is visible.

---

#### Component library

`// UI-UX//Components//` holds SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. Components are not edited during feature work — refinements happen in the library first, then propagate.

---

#### Initial scheme

Dark mode first. SwiftUI semantic colors cover the shell; Pommora extensions provide the accent and brand-specific values. No built-in light/dark toggle in v0.x. In-app customization (Framework v0.12) is limited to accent color + font size — everything else is handled by SwiftUI natively (dark mode auto-adapts, Materials handle vibrancy, Dynamic Type handles typography scale).

---

#### Chrome animation

Apple's native chrome animations (`NSSplitView` sidebar collapse, toolbar reflow, inspector reveal) are the gold standard — Mail, Notes, and Finder use them. **Don't replace system chrome with custom-animated equivalents** — the cost is duplicate buttons, mismatched timing, and a worse result than the system gives for free.

- **The system sidebar toggle (`≡`) is auto-provided by `NavigationSplitView` + `.unified` toolbar style** and uses `NSSplitView`'s native animation. Don't add a custom sidebar toggle wrapped in `withAnimation`. Don't bind `columnVisibility` unless there's a non-toolbar reason (programmatic control, keyboard shortcut, restoration state). The system path is the path.
- **`.toolbar(removing: .sidebarToggle)` is unreliable on `NavigationSplitView` in macOS 26+.** It compiles but may not actually suppress the system toggle, producing duplicate sidebar buttons. Avoid; if needed for a future case, visually verify before assuming it worked.
- **Only wrap `withAnimation` on chrome that has no system equivalent.** `.inspector(isPresented:)` qualifies — its panel reveal isn't routed through SwiftUI's animation transaction by default, so view content inside snaps while column geometry animates. Curve: `withAnimation(.smooth(duration: 0.30))` matches macOS-native column timing.
- **Inspector toolbar items belong inside the `.inspector(...) { content }` closure**, not on the root view's `.toolbar`. Items in the inspector content's `.toolbar` anchor to the inspector's segment of the unified toolbar — they sit at the trailing edge and visually attach to the inspector's column when the panel is open. Items on the root toolbar may render in the wrong segment.
- **Don't extract animation constants for fewer than three call sites.** Inline `.smooth(duration: 0.30)` directly. Premature abstraction adds nothing.

---

#### AppKit Interop

Areas where pure SwiftUI is expected to be sufficient and areas where wrapping AppKit via `NSViewRepresentable` is likely to be the right tool. Specific tradeoffs are confirmed in build:

- **Block reorder in a vertical stack** — pure SwiftUI looks sufficient; a candidate community library is [visfitness/reorderable](https://github.com/visfitness/reorderable).
- **Resizable columns with persistent splitter** — SwiftUI's `HSplitView` exists; community reports suggest wrapping `NSSplitView` via `NSViewRepresentable` yields better splitter polish on macOS. Evaluate when the Spaces composer goes from spec to build.
- **Tree-shaped reorderable structure with cross-level drag** — doable in pure SwiftUI via `DisclosureGroup` + manual `NSItemProvider`. Reference: [shufflingB/swiftui-macos-tree-list-demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo). Whether the SwiftUI-only path is good enough vs. an AppKit wrap is open.
- **Unified cursor flow across columns / callouts** — generally requires `NSTextView` / TextKit 2 (STTextView is a modern wrapper) since SwiftUI's text primitives don't currently span sibling containers.
