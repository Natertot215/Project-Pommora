### UIX Guide

Pommora's visual identity, component library, and design tokens. Stack-agnostic at the design layer — the Figma source of truth exports cleanly to either stack's consumer.

---

#### Source of Truth

Two-tier model:

- **Figma is the source of truth for design tokens.** Colors, typography, spacing, radii, shadows. The Figma file holds the canonical token values; both stacks consume them.
- **The component library is the source of truth for components.** Components are built using Figma's tokens; once a component lands in the library it's authoritative. Features consume from the library — they don't fork or tweak components per-screen.

**Components are not edited during implementation.** When building features, components from the library get used as-is. If a component needs to change, the change happens in the library first (which propagates everywhere it's used), then feature work continues. This keeps the library a single canonical reference and prevents drift between intended and actual visual identity.

Figma file: https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora (fileKey `cm2wRDXWKg05iydG412z4B`). Build brief: `// Planning//Figma Prompt.md`.

**For React**

The component library lives on Pommora's own localhost dev server (the Vite + Electron renderer); **no Storybook intermediary.** The localhost preview IS the component gallery and the working app surface, at different stages of development. Components reference design tokens via CSS custom properties consumed from the Figma export. Designs flow Figma → Pommora localhost directly via the Claude Figma skills (`figma:figma-generate-design`, `figma:figma-use`).

**For Swift**

The component library lives as SwiftUI views inside the app target (or a small Swift Package), browsed via Xcode `#Preview`. Components reference design tokens via SwiftUI `Color` and `Font` extensions consumed from the Figma export.

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

One initial scheme ships in v0.x — **no built-in light/dark, no theme switcher.** In-app customization for color + typography tokens lands in Framework v0.12.

The scheme leans neutral and quiet so customization feels like personalization rather than choosing between two presets. Exact color values are defined in the Figma file.

**For React**

Dark mode first. Visual reference for foundations: minimalist dark systems like Obsidian, ChatGPT, Apple, Claude Desktop. Pommora's design tokens define the actual values; the reference apps inform the *feel* (density, contrast, typographic restraint) but aren't copied.

**For Swift**

Dark mode first. Same Pommora design tokens applied on top of SwiftUI's native primitives (NSVisualEffectView for vibrancy, SF Symbols for icons, system controls for behavior). Native cohesion comes from the primitives; Pommora's visual identity comes from the tokens.

#### Icon System

Pommora's icon language adapts to whichever stack lands.

**Symbol color tokens.** Symbols have their own color Variables (`symbol// primary`, `symbol// muted`, `symbol// active`) that default-resolve to text / accent values but can be overridden independently. Default symbol color is `symbol// muted` — every icon renders muted unless a component explicitly binds it to `primary` or `active`.

**Initial-build placeholder.** Until specific icons are finalized per role, the Figma design system uses the `crop_free` Material Symbol (a square frame) for every symbol slot. The canonical icon role table (in `.claude// Planning//Figma Prompt.md`) records what each placeholder eventually becomes.

**For React**

**Material Symbols** via `react-material-symbols` (outlined default; variable font allows weight / fill / grade / optical-size adjustments per usage). Components reference **semantic symbol roles** (`settings`, `add`, etc.), not direct Material Symbol names — the mapping lives in `.pommora// symbols.json` and carries the SF Symbols equivalent for each role so the icon library can be swapped via a planned setting. Detail → `Symbols-guide.md`. Sizing per surface tier is applied by the same wrapper that resolves the semantic role.

**For Swift**

**SF Symbols** via SwiftUI's `Image(systemName:)` (outlined default; symbol weight and rendering mode adjusted per usage). Icons are defined as view modifiers consistent per surface tier.

#### v0.x Scope

**In:**
- Figma file with foundations: colors, typography, spacing, radii, shadows
- Three-pane shell components: Sidebar, MainContent, Inspector
- Token export to whichever stack lands (CSS custom properties for React; SwiftUI Color extensions for Swift)
- Icon system per stack (Material Symbols for React; SF Symbols for Swift)

**Deferred to v1:**
- Auditor UI (token browser, component browser, hover-to-target)
- User-authored CSS snippets (`.pommora//snippets//user.css`)
- Theme files (full token remaps)
- Light/dark mode (revisit only after customization story is validated)

#### Resolved (formerly open)

- **Default typography** — locked: SF Pro (sans) + SF Mono (mono), system-native. Body 14px baseline; em-relative heading scale (H1–H5; no H6 in v0). Type tokens scoped per type so v0.12 in-app customization can override each independently. Full scale in `// Planning//Figma Prompt.md`.
- **Density** — locked: Notion-comfortable (moderate breathing room, ~1.6 body line-height).

#### Open Questions

(none currently — Figma file is created and linked above; build brief is at `// Planning//Figma Prompt.md`.)
