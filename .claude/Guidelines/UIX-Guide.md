### UIX Guide

Pommora's visual identity, component library, and design conventions — Swift/Apple-native.

---

#### Design philosophy

Pommora follows Apple's macOS Human Interface Guidelines for native cohesion. The toolkit is **SwiftUI primary + AppKit where SwiftUI doesn't reach** — both are first-class. The shell uses SwiftUI native idioms wherever possible:

- **Semantic colors** — `Color(.systemBackground)`, `.foregroundStyle(.primary)`, `.foregroundStyle(.secondary)`. Automatic dark mode and accessibility support; no overrides needed.
- **Materials** — `Material.regular`, `.thin`, `.thick`, `.ultraThin`, `.sidebar` for vibrancy/translucency.
- **Native typography** — SwiftUI Font scale (`.font(.body)`, `.font(.callout)`, `.font(.caption)`, `.font(.system(.body, design: .monospaced))`). Custom sizes only where the scale doesn't fit. Dynamic Type is free.
- **SF Symbols** — `Image(systemName:)`. Native iconography.
- **Native controls** — system Button, Slider, Toggle, etc. with `ButtonStyle` and `ViewModifier` for reusable Pommora-specific styling.
- **Window chrome** — macOS unified title bar, OS-rendered traffic-light buttons.

**AppKit is used directly** where SwiftUI doesn't reach — most notably NSTextView / TextKit 2 for Option 1's source-with-decorations editor (STTextView is the modern wrapper). AppKit isn't an escape hatch — it's the Apple-native answer when SwiftUI's surface stops short.

On top of the SwiftUI + AppKit baseline, Pommora has a small set of brand-specific values that don't have native equivalents — code block colors, callout border, blockquote accent bar — that express Pommora's character within the Apple aesthetic.

---

#### Where Pommora's brand values live

- **App accent color** — Asset Catalog (`Assets.xcassets/AccentColor.colorset`) with light/dark variants. Accessed natively via `Color.accentColor` or set globally with `.tint(.accentColor)`.
- **Pommora-specific Colors** — small Color extensions (`Color+Pommora.swift` or Asset Catalog color sets) for the handful of values SwiftUI semantic colors don't cover: code block fg/bg, callout border (+ optional bg), blockquote accent bar. Apple-idiomatic naming: `Color.nexusCodeBackground`, `Color.nexusCalloutBorder`, etc.
- **Pommora-specific Fonts** — small Font extensions where the SwiftUI scale doesn't fit (e.g. micro / caption variants).

That's the entire "Pommora brand surface" on Swift. SwiftUI semantic colors and Font scale carry the rest.

> The full ~118-token design system (semantic role-based naming, surface/element tier model, dual-axis taxonomy) is a React-pattern that prototyped well in Figma. It lives as the React-side reference at `// ReactInfo// Styling-Tokens.md`. For Swift, that level of token engineering isn't needed — SwiftUI's semantic system does most of the work.

---

#### Editor canvas (WKWebView Option 2)

The WKWebView editor renders HTML/CSS inside a native shell. CSS theming inside the canvas **does** use design tokens (CSS custom properties) because that's how web-side styling works. The token set is small — it mirrors the SwiftUI brand values above so the editor matches the shell — and gets injected into the editor canvas via the JS bridge at editor mount.

If Option 1 (native NSTextView) is chosen instead, no CSS tokens are needed; the editor styles with SwiftUI attributes directly.

---

#### Component conventions

- **Prefer SwiftUI semantic colors and fonts.** Use Pommora extensions only for values without native equivalents.
- **Modern modifiers.** `.foregroundStyle(.primary)` not `.foregroundColor()`. `.clipShape(.rect(cornerRadius: 12))` not `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **SF Symbol weight matches text weight.** Symbols inherit weight from the surrounding text style when paired — keep that link. If a symbol's weight needs to deviate, apply `.fontWeight()` explicitly.

---

#### Component library

`// UI-UX//Components//` holds SwiftUI views (app target or a small Swift Package), browsed via Xcode `#Preview`. Components are not edited during feature work — refinements happen in the library first, then propagate.

---

#### Initial scheme

Dark mode first. SwiftUI semantic colors cover the shell; Pommora extensions provide the accent and brand-specific values. No built-in light/dark toggle in v0.x. In-app customization (Framework v0.12) is limited to accent color + font size — everything else is handled by SwiftUI natively.

---

#### Sidebar section chevrons

Section header disclosure chevrons appear **on hover only**, never always-visible. This is Apple's default behavior for `Section(_:isExpanded:)` under `.listStyle(.sidebar)` — don't override it with custom always-visible disclosure indicators. The quiet hover-reveal matches Mail/Notes/Finder and keeps the sidebar reading as content-forward when idle.

---

#### Chrome animation

Apple's native chrome animations (`NSSplitView` sidebar collapse, toolbar reflow, inspector reveal) are the gold standard — Mail, Notes, and Finder use them. **Don't replace system chrome with custom-animated equivalents.**

`.inspector(isPresented:)` is an exception that needs explicit animation — its panel reveal isn't routed through SwiftUI's animation transaction by default, so wrap the toggle in `withAnimation(.smooth(duration: 0.30))` to sync content + column geometry.

**Inspector toolbar items live in the main toolbar, not the inspector segment.** The original v0.0 plan put the inspector toggle inside `.inspector { Color.clear.toolbar { ... } }` to anchor it to the inspector's toolbar segment (Apple HIG default). That created an inspector-segment glass material on macOS Tahoe (Liquid Glass) that couldn't be opted out without dropping the whole toolbar background. Resolution: put the inspector toggle in the NavigationSplitView's top-level `.toolbar { }` with `.primaryAction` placement — the toggle still appears at the trailing edge visually, no inspector-segment glass renders. Style with `.buttonStyle(.borderless).controlSize(.large)` for the borderless icon look.

Specific platform quirks (e.g. `.toolbar(removing:)` reliability on macOS 26+, exact animation curves) get verified in build and noted in `Handoff.md` "Known Spec Gaps" rather than locked here.

---

#### AppKit interop

AppKit wraps are confirmed when SwiftUI's surface stops short during real build, not pre-cataloged. The currently-known case is Option 1's editor (NSTextView / TextKit 2). Other candidates (splitter polish, cross-container cursor flow, tree-shaped reorder) resolve when their consuming feature lands.
