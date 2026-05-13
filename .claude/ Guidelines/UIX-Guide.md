### UIX Guide

Pommora's visual identity, component library, and design tokens. Figma is the source of truth; tokens export to SwiftUI `Color` / `Font` extensions.

---

#### Source of Truth

Two-tier model:

- **Figma is the source of truth for design tokens.** Colors, typography, spacing, radii, shadows. The Figma file holds the canonical token values; the SwiftUI export consumes them.
- **The component library is the source of truth for components.** Components are built using Figma's tokens; once a component lands in the library it's authoritative. Features consume from the library — they don't fork or tweak components per-screen.

**Components are not edited during implementation.** When building features, components from the library get used as-is. If a component needs to change, the change happens in the library first (which propagates everywhere it's used), then feature work continues. This keeps the library a single canonical reference and prevents drift between intended and actual visual identity.

Figma file: https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora (fileKey `cm2wRDXWKg05iydG412z4B`).

#### Current build state

Tokens (~118 vars) and primitives + composed components are built in the Figma file as gallery FRAMEs with full token bindings. Nine Tag components are converted to standalone COMPONENTs; the remaining 35 gallery items are still FRAMEs.

**Next step:** FRAME → COMPONENT_SET conversion per `.claude// Planning// Figma Components 5-13.md`. After conversion, the file is a real reusable component library (single source per concept, variant properties, INSTANCE references everywhere) ready for code translation.

**Then:** translate Figma → SwiftUI views in `UI-UX// Components//` and browse via Xcode `#Preview`. The component library lives as SwiftUI views inside the app target (or a small Swift Package); components reference design tokens via SwiftUI `Color` and `Font` extensions consumed from the Figma export.

#### Dual-Export Naming Discipline

The hard rule that keeps tokens stack-portable: **Figma Variables use semantic role-based names, never implementation-flavored names.**

| ✅ Use | ❌ Avoid |
|---|---|
| `surface/primary/bg` | `bg-zinc-900` |
| `element/secondary/fg` | `text-blue-500` |
| `text/muted` | `gray-400` |
| `border/subtle` | `border-zinc-800` |

Export target: SwiftUI `Color` extensions: `Color.surface.primary.bg`. Generated as a Swift source file consumed by the SwiftUI views from the same Figma source — adding a new token in Figma updates the export automatically.

> If pivoting to React, see `// ReactInfo// Styling-Tokens.md` — export target becomes CSS custom properties (`--surface-primary-bg`) referenced directly by Tailwind CSS v4.

#### Tier Model (Two Axes)

Components reference tokens organized on two independent axes:

**Surface tier (UI region):**
- `surface/primary/*` — main content area (editor, page body)
- `surface/secondary/*` — persistent chrome (sidebars, top bar, property panel)
- `surface/tertiary/*` — transient overlays (popovers, tooltips, modals, dropdowns)

**Element tier (interactive prominence):**
- `element/primary/*` — main CTAs, accent actions, selected states
- `element/secondary/*` — supporting buttons, cards, neutral actions
- `element/tertiary/*` — quiet UI, ghost buttons, dividers, muted controls

**Combinatorial rule:** any element tier can render on any surface tier. A primary button on a tertiary surface (a modal) is fully defined by referencing both tokens.

Each tier exposes per-role tokens: `bg`, `bg-hover`, `bg-active`, `fg`, `fg-muted`, `border`, `border-strong` (where relevant).

#### Initial Scheme

One initial scheme ships in v0.x — **no built-in light/dark, no theme switcher.** In-app customization for color + typography tokens lands in Framework v0.12.

The scheme leans neutral and quiet so customization feels like personalization rather than choosing between two presets. Exact color values are defined in the Figma file.

Dark mode first. Pommora design tokens applied on top of SwiftUI's native primitives (NSVisualEffectView for vibrancy, SF Symbols for icons, system controls for behavior). Native cohesion comes from the primitives; Pommora's visual identity comes from the tokens. Visual reference for the feel: minimalist dark systems like Obsidian, ChatGPT, Apple, Claude Desktop — tokens define the actual values; reference apps inform density, contrast, typographic restraint but aren't copied.

#### Icon System

**Symbol color tokens.** Symbols have their own color Variables (`symbol// primary`, `symbol// muted`, `symbol// active`) that default-resolve to text / accent values but can be overridden independently. Default symbol color is `symbol// muted` — every icon renders muted unless a component explicitly binds it to `primary` or `active`.

**Initial-build placeholder.** Until specific icons are finalized per role, the Figma design system uses the `crop_free` Material Symbol (a square frame) for every symbol slot. The icon-role finalization (mapping each placeholder to its real SF Symbol equivalent) is post-conversion work; until then `crop_free` stays inline and the INSTANCE_SWAP `vector` slot on the Icon component is deferred.

**SF Symbols** via SwiftUI's `Image(systemName:)` (outlined default; symbol weight and rendering mode adjusted per usage). Icons are defined as view modifiers consistent per surface tier. No indirection layer needed — SF Symbols is the native iconography, available everywhere.

> If pivoting to React, see `// ReactInfo// Symbols-guide.md` for the semantic-role indirection layer (`.pommora// symbols.json`) that lets the icon library be swapped without rewriting components.

#### v0.x Scope

**In:**
- Figma file with foundations: colors, typography, spacing, radii, shadows
- Three-pane shell components: Sidebar, MainContent, Inspector
- Token export to SwiftUI `Color` / `Font` extensions
- SF Symbols icon system

**Deferred to v1:**
- Auditor UI (token browser, component browser, hover-to-target)
- User-authored design overrides
- Theme files (full token remaps)
- Light/dark mode (revisit only after customization story is validated)

#### Resolved (formerly open)

- **Default typography** — locked: SF Pro (sans) + SF Mono (mono), system-native. Body 14px baseline; em-relative heading scale (H1–H5; no H6 in v0). Sub-body sizes added: caption 12px, micro 10px. Type tokens scoped per type so v0.12 in-app customization can override each independently. Full scale lives in the Figma file (`Tokens` collection, `font/size/*` and `font/lineHeight/*`).
- **Density** — locked: Notion-comfortable (moderate breathing room, ~1.6 body line-height).
- **Accent semantics** — locked: components binding to "accent" use a single accent token slot (typically `accent/primary/active`). Interactive states (hover / active / focus / disabled) apply opacity / brightness modifiers on top — they do NOT swap between accent sub-tokens. The 2×2 accent matrix exists for designer choice across contexts, not as a state-axis within a single component.

#### AppKit Interop

Where pure SwiftUI is sufficient vs. where `NSViewRepresentable` wrapping is the right tool for production polish:

- **Block reorder in a vertical stack** — pure SwiftUI is sufficient (`visfitness/reorderable`).
- **Resizable columns with persistent splitter** — SwiftUI's `HSplitView` works but is rough; wrap `NSSplitView` via `NSViewRepresentable` for production polish.
- **Tree-shaped reorderable structure with cross-level drag** — pure SwiftUI is doable (`DisclosureGroup` + manual `NSItemProvider`) but not pretty. Reference: [shufflingB/swiftui-macos-tree-list-demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo).
- **Unified cursor flow across columns / callouts** — only achievable via `NSTextView` / TextKit 2 (STTextView).

#### Open Questions

(none currently — Figma file is built; conversion plan is at `.claude// Planning// Figma Components 5-13.md`; SwiftUI translation begins after the conversion completes.)
