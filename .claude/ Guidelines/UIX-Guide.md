### UIX Guide

Pommora's visual identity, component library, and design tokens. Stack-agnostic at the design layer — the Figma source of truth exports cleanly to either stack's consumer.

---

#### Source of Truth

**The Figma file is the source of truth for all visual design.** Generated tokens are consumed by whichever stack lands. The design system is not a code architecture — it's a Figma file with strict naming discipline.

Figma file location: TBD (to be created in its own session via `figma-use`).

#### Dual-Export Naming Discipline

The hard rule that makes either stack viable: **Figma Variables use semantic role-based names, never implementation-flavored names.**

| ✅ Use | ❌ Avoid |
|---|---|
| `surface/primary/bg` | `bg-zinc-900` |
| `element/secondary/fg` | `text-blue-500` |
| `text/muted` | `gray-400` |
| `border/subtle` | `border-zinc-800` |

Export targets:

**For React**

CSS custom properties: `--surface-primary-bg`. Tailwind CSS v4 references the variables directly.

**For Swift**

SwiftUI `Color` extensions: `Color.surface.primary.bg`. Generated as a Swift source file consumed by the SwiftUI views.

The CSS variable file and the SwiftUI Color file are different artifacts generated from the same Figma source. Adding a new token in Figma → both export targets get the new value automatically.

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

One initial scheme ships in v0.x — **no built-in light/dark, no theme switcher.** Customization comes later via the Auditor (deferred to v1+).

The scheme leans neutral and quiet so customization feels like personalization rather than choosing between two presets. Exact color values are defined in the Figma file.

#### Icon System

Pommora's icon language adapts to whichever stack lands.

**For React**

**Material Symbols** via `react-material-symbols`. Default style: outlined; variable font allows weight, fill, grade, and optical-size adjustments per usage. Icons in the UI (sidebar items, property types, button affordances) are wrapped in components that apply consistent sizing per surface tier.

**For Swift**

**SF Symbols** via SwiftUI's `Image(systemName:)`. Default style: outlined; symbol weight and rendering mode adjusted per usage. Same wrapping discipline as the React side — icons are defined as view modifiers consistent per surface tier. (The Material Symbols font set is also available for direct font integration if a non-SF mapping is wanted, but SF Symbols is the natural default on Apple platforms.)

#### v0.x Scope

**In:**
- Figma file with foundations: colors, typography, spacing, radii, shadows
- Three-pane shell components: Sidebar, MainContent, Inspector
- Token export to whichever stack lands (CSS custom properties for React; SwiftUI Color extensions for Swift)
- Icon system per stack (Material Symbols for React; SF Symbols for Swift)

**Deferred to v1:**
- Auditor UI (token browser, component browser, hover-to-target)
- User-authored CSS snippets (`_pommora//snippets//user.css`)
- Theme files (full token remaps)
- Light/dark mode (revisit only after customization story is validated)

#### Open Questions

- Default font selections (system stack vs. specific opinionated choice — likely Inter or similar for v0.x)
- Density preset(s) — comfortable only for v0.x; compact deferred
- Whether the Figma file lives inside the project or as a standalone team library
