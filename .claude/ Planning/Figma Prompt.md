### Pommora Design System — Build Brief

> Pasteable prompt for the Figma design-system build session. Open a fresh session with `/figma-use` invoked; the Figma file is already linked at the URL below. Paste the contents in the fenced block (everything from "Pommora Design System — Build Brief" onward) to commission the build.

> **Figma file:** https://www.figma.com/design/cm2wRDXWKg05iydG412z4B/Project-Pommora (fileKey `cm2wRDXWKg05iydG412z4B`).

> The brief locks architectural decisions and baseline token values. Figma round 1 refines exact hex / sizing relationships within the locked structure; cascade behavior is the load-bearing requirement.

> **⚠ Stack status — both React + Electron AND SwiftUI remain live candidate stacks.** The design system is being built React-flavored first because the React UIX outcome is the unknown quantity (SwiftUI gets a baseline of native cohesion for free). The Figma file itself is stack-portable: design tokens (Variables) export to CSS custom properties (React) OR SwiftUI `Color` / `Font` extensions (Swift); the icon role table seeds Material Symbols for React and SF Symbols for Swift through the same mapping. The component library in Figma is built React-flavored (Material Symbols rendered, CSS-style mental model); an eventual SwiftUI build re-implements the primitives from the same tokens + role table. **Nothing in this brief forecloses either stack — the stack decision is downstream of the design-system outcome, not the other way around.**

---

````markdown
# Pommora Design System — Build Brief

## Context

Reference docs:
- `// Guidelines//UIX-Guide.md`
- `// Guidelines//Symbols-guide.md`
- `History.md` (Design System section)
- `// Features//Architecture.md`

## ⚠ Stack status — both React + Electron AND SwiftUI remain candidate stacks

The Pommora codebase stack is **not yet decided.** Both React + Electron and SwiftUI are live options. This design system is being built React-flavored first because the React UIX outcome is the unknown quantity (SwiftUI gets a baseline of native cohesion for free); the design-system outcome is what makes the stack decision evidence-based.

**Stack-agnostic in this file:**
- Design tokens (Variables) — names, hierarchy, values
- Tier model (surface × element)
- Typography pairing and sizes
- Spacing / radius / shadow scales
- Icon **role** list (semantic names; per-role Material / SF entries are deferred — every role uses the `crop_free` placeholder initially)

**React-flavored in this file:**
- Component library implementation (Material Symbols rendered as the icon set; mental model is CSS / props)
- The `Icon` primitive's rendered output uses Material Symbols
- In-app token override mechanism (see Settings overridability) is detailed for React; SwiftUI gets the parallel pattern

**If SwiftUI is eventually chosen**, primitives are re-implemented from the same tokens + role table using SF Symbols (rendered via `Image(systemName:)`) and SwiftUI's `@AppStorage` / environment for token override. The Figma file itself does not need to be rebuilt — Variables export to either stack, and the icon role table seeds both.

**Nothing in this brief forecloses either stack.** Build React-flavored. Don't lock in patterns that would block a SwiftUI port from the same tokens.

## Architecture (locked — implement, don't redesign)

- **Two-tier source of truth.** Figma Variables own design tokens; Figma Components own primitives + composed components. Both layers consume variables; **no hardcoded values anywhere**.
- **Primitives-first composition.** Build atomic primitives first; build everything else by composing them. Composed components never reach around their primitives to set literal values.
- **Components are not edited during implementation.** Once a component lands in the library, it's authoritative. Refinements happen in Figma first, then propagate to code.
- **Dual-export naming.** Semantic role-based variable names only (`surface// primary// bg`, never `bg-zinc-900`).
- **Icons: dual-stack via semantic role indirection.** Components reference roles like `add`, `settings` — never raw Material or SF names. The role list seeds `.pommora// symbols.json` and is dual-stack (Material for React render, SF for Swift render). **Per-role Material / SF icon assignments are deferred** until a later pass — during this initial Figma build, every role renders the `crop_free` Material Symbol as a placeholder.
- **Single component, many variants.** Each component is ONE Figma component with **variant properties** — not duplicated separate components per state / tier / intent. The variant model cascades to React as a single component with a `variant` prop, not as multiple files. Apple's component-gallery convention.
- **Variant gallery convention.** Each component's Figma frame **displays all its variants in a horizontal row** (Apple-style component gallery). Lets a reviewer scan every state at once.
- **Window chrome — macOS unified title bar.** The macOS traffic-light buttons sit in the top-left, **within the sidebar pane's column** at its top. Tabs sit alongside (to the right of) that traffic-light area in the same horizontal row, spanning above the main pane. No separate Pommora title bar. **Do NOT draw the traffic-light buttons in the Figma file** — leave the top-left area of the sidebar empty / reserved; the OS renders the buttons at runtime. Just lay out the rest of the chrome assuming they'll appear there. Pattern: Obsidian / Notion / Linear on macOS.
- **Layout aspect ratio.** Full-width page frames (the three-pane shell and any full-app context) are drawn at **16:9 aspect ratio** to match typical desktop displays. Individual component-gallery frames (showing variants in a row) don't need a fixed ratio.
- **Scope: block components, not page demos.** This Figma build is **the component library** — primitives, composed components, and the assembled three-pane shell that proves the library works together. **Full page-level mockups are out of scope** — no full Page editor surface, no full Collection view, no full Space block surface, no Settings UI mockup. Those land *after* the library is built. Component context shots (small assemblies that demonstrate components in use) are fine; full app screens are not.

## Cascade requirement (locked)

Every visual property in every component is bound to a Figma Variable. Changing any token variable visibly propagates to every consumer.

Examples:
- Change `accent// primary// active` → every focused link, every primary CTA hover, every selected state updates
- Change `radius// surface` → every surface / card / panel updates simultaneously
- Change `font// size// body` → all five headings rescale (em-based scale)
- Change `space// 3` → every component using that step updates

Acceptance: pick three variables; change each; confirm every consumer updates with no exceptions.

## Settings overridability

Every token is a *baseline*; the user will be able to override any of them via in-app customization (Framework v0.12). Build the system so override is a single variable change at runtime, not a rebuild.

**For React (the in-app override mechanism)**

Variables export to CSS custom properties on `:root` (e.g., `--accent-primary-active: #A78BCC`). The in-app settings panel writes user-scoped overrides to a separate CSS layer (`:root.user-overrides` or a CSS layer / custom-property block) that cascades on top of the defaults. Effect: changing the accent color from settings is a single property mutation at runtime — no rebuild, no component touched, no Figma round-trip required.

**For Swift (the equivalent override mechanism, if SwiftUI is chosen)**

The same Figma Variables export to SwiftUI `Color` and `Font` extensions (e.g., `Color.accent.primary.active`). The in-app settings panel writes overrides into `@AppStorage` (or a comparable persisted store); a token-resolution layer reads from the override store first, falling back to the Figma-derived defaults. Components consume tokens via the SwiftUI environment so the override propagates without a rebuild. Token names remain identical to the React export — the override pattern is stack-isomorphic.

**Settings panel scope (v0.12):** at minimum, all color tokens (surfaces, text, borders, accent stops) and all typography tokens (font families, body size, heading scale, line-heights). Spacing, radius, and shadow are not user-overridable in v0.12 — those stay on the Figma baseline.

## Tier model (locked)

**Surface tier — UI region:**
- `surface// primary` — main content area (pages, editor)
- `surface// secondary` — persistent chrome (sidebar, menus, inspector)
- `surface// tertiary` — transient overlays (popovers, modals, dropdowns)

**Element tier — interactive prominence:**
- `element// primary` — main CTAs, accent actions, selected states
- `element// secondary` — supporting buttons, cards, neutral actions
- `element// tertiary` — quiet UI, ghost buttons, dividers, muted controls

Any element tier renders on any surface tier (combinatorial — a primary button on a tertiary surface is fully defined by both tokens).

Per-tier role tokens: `bg`, `bg-hover`, `bg-active`, `fg`, `fg-muted`, `border` (where applicable).

---

## Baseline token values

### Surfaces (flat dark; no shadows except on overlays)

```
surface// primary// bg          #1C1C1D   (main pages, editor)
surface// secondary// bg        #191919   (sidebar, menus, inspector)
surface// tertiary// bg         (round-1 derive — slightly elevated tone for overlays, ~#222224 starting point)
```

### Text

```
text// primary                  #F1F1F1
text// muted                    #D5D5D5
text// syntax                   uses text// muted   (markdown syntax markers)
```

### Borders

```
border// subtle                 ~#2A2A2C   (proposed; refine in Figma)
border// strong                 ~#3A3A3C   (proposed; refine in Figma)
```

### Symbols — color tokens

Icons have their own color tokens, independent of text and accent so they can be overridden separately without touching text or accent values. Each default-resolves to a text or accent value but can be retargeted independently.

```
symbol// primary               defaults to text// primary      (high-prominence symbol render — toolbar icons in active state)
symbol// muted                 defaults to text// muted        (DEFAULT — first-draw, sidebar items, property row icons, any unspecified symbol)
symbol// active                defaults to accent// primary// active   (active / selected symbol states — focused tab icon, active toggle, selected item)
```

**Default render:** every symbol drawn in the design system uses `symbol// muted` unless explicitly overridden. Components that need a more prominent symbol (e.g., a primary CTA's icon) bind to `symbol// primary` or `symbol// active`.

### Accent — single-hue purple, pastel / muted, 2×2 matrix

```
accent// primary// active       #A78BCC   (brightest muted lavender — focused links, hovered CTAs, active toggles, selected states)
accent// primary// muted        #7C6A99   (default link color, idle toggle dots, supporting accent)
accent// secondary// active     #5F5278   (less prominent secondary actions / highlights)
accent// secondary// muted      #3F3650   (subtle background tints, focus glows, low-alpha use)
```

All 4 stops share the same hue (~268° purple); descending in saturation + lightness. Hierarchy: `primary// active` (most visible) > `primary// muted` > `secondary// active` > `secondary// muted` (least visible). Round 1 in Figma: validate the relationships visually; adjust within ±5% saturation / lightness as needed; keep hue constant.

### Construct-specific color tokens (Callout, Blockquote, Code)

Markdown constructs that get distinct visual treatment have their own token families. All are tied to the color primitives so each construct's palette can be tuned independently of text and accent.

**Callout** — outlined-box callout (rendered by the `:::callout` directive; minimally-rounded bordered box, distinct from blockquotes).

```
callout// bg                   transparent or surface// primary// bg (default)
callout// fg                   defaults to text// primary
callout// border               independent token; defaults to border// strong
```

Rendering: bordered rectangle at `radius// tight` (very minimal rounding) using `callout// border`; text in `callout// fg`.

**Blockquote** — standard `>` syntax; filled box with a left-side emphasis bar (distinct from callouts).

```
blockquote// bg                filled tone (defaults derived from surface// secondary// bg)
blockquote// fg                defaults to text// primary
blockquote// bar               left-side emphasis bar color — defaults to blockquote// fg (matches the text color, NOT accent)
```

Rendering: filled rectangle with a vertical left-edge bar in `blockquote// bar`; text in `blockquote// fg` on `blockquote// bg`.

**Code** — code blocks (fenced ``` ```) and inline code (backticks).

```
code// fg                      text color (default #FF2525) — tied to a red color primitive; tunable through the color system
code// bg                      background (default #323233) — independent token; tunable through the color system
code// font// family           defaults to font// family// mono (SF Mono)
code// font// size             1.0 em (same size as body; em-relative)
```

Rendering: monospaced text at 1.0 em with `code// fg` on `code// bg`. Block code uses the bg as a wrapper at `radius// tight`; inline code uses the bg as a tight chip behind the text.

### Interactive states

Every interactive primitive (Pressable, Button, Field, Tab, Disclosure, Sidebar item, etc.) consumes these state tokens. State tokens are layered on top of base tier tokens — they don't replace them.

```
state// hover                  applied on cursor hover (subtle bg-overlay tint; uses opacity// hover over base bg)
state// active                 currently selected / pressed (active tab, selected sidebar item, on-toggle; uses accent// primary// muted as bg tint with opacity// active)
state// inactive               default / not-active (no token render — the base tier color is the inactive baseline)
state// focus                  keyboard focus ring (separately rendered; uses accent// primary// active as ring color with opacity// focus; doesn't replace underlying state)
state// disabled               greyed-out, non-interactive (text + bg apply opacity// disabled to base tier values)
```

States compose with tier (`element// primary` × `state// hover` = primary button on hover). Implementation pattern: Figma variants for each interactive primitive expose a `state` property with `idle / hover / active / focus / disabled` values.

### Semantic states

Used for inline validation, status indicators, and notification surfaces. **Inherit from color primitives** — defined as muted / pastel-flavored families derived from a base hue per role, matching the overall aesthetic. Each role has `bg`, `fg`, `border`.

```
state// success                muted pastel green family (e.g., dusty sage; round-1 derive exact hex)
state// warning                muted pastel amber family (e.g., warm ochre)
state// error                  muted pastel red family (e.g., dusty rose; ≠ destructive-action red, which can use this same family or a slightly more saturated variant)
state// info                   muted pastel blue family (e.g., dusty cornflower)
```

Each value resolves from a base color primitive (so changing a base green updates every `state// success` consumer). Pastel-leaning to match the rest of the palette — semantic colors should read as quiet, not alarming.

### Opacity + brightness scales

State overlays, muted fills, and transparency effects pull from these scales instead of hardcoded hex with alpha. Lets a hover treatment be re-tuned globally by changing one variable.

```
opacity// hover                ~8–10%   (subtle overlay applied on hover bg shift)
opacity// active               ~12–15%  (selected / pressed bg tint)
opacity// focus                ~30–40%  (focus ring alpha)
opacity// disabled             ~40%     (disabled element render)
opacity// translucent          ~80%     (overlays / vibrancy effects)
opacity// muted                ~60%     (de-emphasized elements)
```

Plus a numeric scale for general use: `opacity// 10`, `opacity// 20`, `opacity// 40`, `opacity// 60`, `opacity// 80`.

```
brightness// hover             small bump (a few % luminosity up; for pressable elements where hover should "lift")
brightness// active            larger bump
```

Round 1 in Figma: pick exact percentages. Both scales are stable as a structure; the values within them are tuned.

### Typography

```
font// family// sans            SF Pro (system)
font// family// mono            SF Mono (system)

font// size// body              14px   (baseline; user-overridable via settings)

Heading scale (em — relative to body, so changing body rescales all headings):
font// size// h1                2.0 em   (28px @ body 14)
font// size// h2                1.75 em  (24.5px @ body 14)
font// size// h3                1.5 em   (21px @ body 14)
font// size// h4                1.25 em  (17.5px @ body 14)
font// size// h5                1.0 em   (14px — same size as body; differentiated by weight + spacing)
                                (no h6 in v0)

Weights: regular, medium, semibold
Line-heights: body ~1.6 (Notion-comfortable density)
```

### Spacing (4px base — round-1 derive full scale)

```
space// 1                       4px
space// 2                       8px
space// 3                       12px
space// 4                       16px
space// 5                       24px
space// 6                       32px
space// 8                       48px
```

Density target: **Notion-comfortable** — moderate breathing room, generous padding on prose surfaces, tighter on chrome.

### Radius (mixed scale by role)

```
radius// none                   sharp corners (rarely used — only where explicitly square)
radius// tight                  minimal rounding (buttons, toggles, labels, dense controls)
radius// surface                slight rounding (cards, panels, modals, popovers — Notion / Claude reference)
radius// pill                   full radius (tags, chips, status badges)
```

Exact radius values are derived in Figma round 1 within the locked role mapping. The role names (`tight`, `surface`, `pill`) are what's stable — the underlying values are tokens that can change without renaming anything.

Mapping discipline:
- Tags / chips → `radius// pill`
- Buttons / toggles / labels → `radius// tight`
- Surfaces / cards / overlays → `radius// surface`

### Shadow (minimal — flat dark)

```
shadow// none                   no shadow (most components)
shadow// overlay                subtle drop for modals / popovers / dropdowns only (e.g., 0 4px 12px rgba(0,0,0,0.4))
```

Sidebar, inspector, main pane: all `shadow// none`. Borders + surface-color shifts define separation.

---

## Tag / Select color palette (separate from accent)

Pommora uses Notion's fixed 9-color palette for Select and Multi-select properties (locked in `History.md`). All 9 should be **pastel-flavored** (muted, low-saturation, luminous against the dark surface — not the saturated rainbow you'd see in a light theme).

```
tag// gray
tag// brown
tag// orange
tag// yellow
tag// green
tag// blue
tag// purple
tag// pink
tag// red
```

Each gets:
- `bg`  — pastel surface tone (used for tag fill)
- `fg`  — readable text color against that fill
- `border` — slightly emphasized edge (where used)

Reference: Notion's dark-mode tag chips, Claude Desktop's tag treatments.

---

## Icon role table (seeds `.pommora// symbols.json`)

Components reference icons via **semantic roles** (`add`, `settings`, etc.) — never raw Material or SF names. The role list below is the canonical seed for `.pommora// symbols.json`. **Specific Material and SF icon names per role are not yet assigned** — every role's icon defaults to the `crop_free` Material Symbol as a placeholder until Nathan reviews and assigns specific icons in a later pass. The role names themselves are stable; the `material` and `sf` fields in `symbols.json` get populated later.

> **Initial-build placeholder convention.** During the first Figma draw, **every symbol slot renders the `crop_free` Material Symbol** (a square frame outline) as a visual placeholder. The role list below records what each placeholder eventually represents; specific Material / SF icon names get assigned in a later round.
>
> Material reference: [`crop_free` (outlined)](https://fonts.google.com/icons?selected=Material+Symbols+Outlined:crop_free:FILL@0;wght@400;GRAD@0;opsz@24).
>
> Canonical placeholder SVG (render this exact path for every icon slot until per-role icons are assigned):
>
> ```html
> <svg xmlns="http://www.w3.org/2000/svg" height="24px" viewBox="0 -960 960 960" width="24px" fill="#e3e3e3"><path d="M200-120q-33 0-56.5-23.5T120-200v-160h80v160h160v80H200Zm400 0v-80h160v-160h80v160q0 33-23.5 56.5T760-120H600ZM120-600v-160q0-33 23.5-56.5T200-840h160v80H200v160h-80Zm640 0v-160H600v-80h160q33 0 56.5 23.5T840-760v160h-80Z"/></svg>
> ```
>
> Every symbol placeholder defaults to `symbol// muted` for color (see Symbols color tokens above). The `fill="#e3e3e3"` in the SVG is the reference color; bind it to the active `symbol//` token at render time.

When `.pommora// symbols.json` is seeded, the `material` and `sf` fields per role point to the placeholder; subsequent rounds re-write them to the chosen Material and SF names. The role list is dual-stack from day one (React renders the eventual `material` value; Swift renders the `sf`). For Example; non-solidified: 

| Semantic role | Use case |
|---|---|
| **Shell / chrome** | |
| `expand` | Disclosure (expanded state) |
| `collapse` | Disclosure (collapsed state) |
| `sidebar` | Toggle sidebar visibility |
| `inspector` | Toggle inspector visibility |
| `search` | Global search |
| `settings` | App / entity settings |
| `back` | Navigate back |
| `forward` | Navigate forward |
| **Common actions** | |
| `add` | Create new entity |
| `delete` | Remove entity / property |
| `edit` | Rename / edit |
| `duplicate` | Duplicate entity |
| `more` | Overflow menu |
| `close` | Close panel / modal |
| `drag` | Drag handle |
| **Entity kinds** | |
| `page` | Page entity |
| `collection` | Collection entity (folder) |
| `space` | Space entity |
| `item` | Item entity (row) |
| **Editor formatting** | |
| `bold` | Bold |
| `italic` | Italic |
| `strikethrough` | Strikethrough |
| `code` | Inline code |
| `codeBlock` | Code block |
| `link` | Hyperlink / wikilink |
| `image` | Image insertion |
| `quote` | Blockquote (standard `>`) |
| `divider` | Horizontal rule |
| `heading` | Heading menu (H1–H5) |
| `listBulleted` | Bullet list |
| `listNumbered` | Numbered list |
| `listCheckbox` | Checklist |
| `columns` | Multi-column block (`@Columns`) |
| **Property types** | |
| `propertyNumber` | Number property |
| `propertyCheckbox` | Checkbox property |
| `propertyDate` | Date property |
| `propertyDatetime` | Datetime property |
| `propertySelect` | Select property |
| `propertyMultiSelect` | Multi-select property |
| `propertyRelation` | Relation property |
| `propertyUrl` | URL property |
| **Views** | |
| `viewTable` | Table view |
| `viewBoard` | Board view (kanban) |
| `viewList` | List view |
| `viewCards` | Cards view |
| `viewGallery` | Gallery view |
| **View controls** | |
| `filter` | Filter |
| `sort` | Sort |
| `group` | Group by |

**Notes:**
- Specific Material and SF icon-name assignments per role are **deferred** — they populate after Nathan reviews per-role candidates. The placeholder `crop_free` stands in until then.
- Sizing per surface tier (size token resolution) is applied by the same role-resolution wrapper at component level — the role list doesn't carry sizes.

---

## Disclosure types

Pommora has multiple disclosure patterns; all use the same `Disclosure` primitive, but with different settings for its `indent line` variant. The variant is chosen per placement, not inherent to disclosure as a category.

| Type | Where it appears | `Disclosure.indent line` |
|---|---|---|
| **Tree / folder disclosure** | Sidebar nested structure (Collections expand to members, nested folders), any hierarchical tree in interface chrome | `true` |
| **Heading disclosure** | Foldable Markdown headings inside a Page (every heading H1–H5 is collapsible by default) | `false` |
| **Section header (sidebar top-level)** | Spaces / Saved / Collections section headers (expand to show their list) | `true` (they contain tree content) |

Rule of thumb: line appears whenever a disclosure reveals **hierarchical children that can themselves nest**. Inside a Page, foldable headings collapse inline content vertically — no tree, no line. There is no separate "toggle block" construct in Pommora; heading-fold is the only in-Page disclosure pattern.

## Primitives to build (atomic — pure token consumers)

- **Surface** — renders a region at a given surface tier; consumes `surface// X// bg`, optional `border`, `radius`, `shadow`
- **Text** — typography variant (`heading-1..5` | `body` | `caption` | `label` | `syntax`); consumes font / size / weight / line-height / color tokens
- **Icon** — resolves a semantic symbol role from the role list above. During the initial Figma build, every role renders the `crop_free` Material Symbol as a placeholder (per-role Material / SF assignments are deferred until Nathan reviews). Sized via token; color defaults to `symbol// muted`.
- **Stack** — horizontal or vertical layout consuming a `space// N` gap token
- **Pressable** — tap-target primitive (hit area + focus ring); no visual surface of its own
- **Button** — composes Surface + Stack + Text + Icon at an element tier; variants for `element// primary// secondary// tertiary`
- **Field** — input primitive at a surface tier; consumes border + text tokens
- **Divider** — uses `border// subtle`
- **Disclosure** — **load-bearing.** Primitive for any expand / collapse group. Composes a Pressable header (Icon from `expand` / `collapse` role + label content slot) + a children container. **Has a variant property `indent line: true / false`** — the choice is made when a Disclosure is placed; it is not automatic. When `true`, renders a `DisclosureLine` alongside the children container's left edge, aligned to the chevron column. When `false`, no line — just indented children. See Disclosure types section for which use cases set the variant to which value.
- **DisclosureLine** — internal styling sub-element used by `Disclosure` when its `indent line` variant is `true`. Vertical hairline; consumes `border// subtle` for color and a hairline width token; positioned by a spacing token offset aligning to the chevron column of the parent row. Spans from just below the parent's row down to the last visible child row. **Not placed independently** — always reached through `Disclosure`'s variant.
- **Tag** — `radius// pill` chip; consumes a `tag// <color>` palette entry. Tag hover state is captured during the live demo phase — Figma static frames don't model the hover interaction; the design system records the idle tag only.
- **Checkbox** — square checkbox. Variants: `unchecked` / `checked` / `indeterminate`. Composes Surface (`radius// tight`, `border// subtle`) + Icon (`checkbox` Material role for the check mark when checked). Consumes `accent// primary// active` for the checked-state fill.
- **Radio** — circular radio. Variants: `unselected` / `selected`. Composes Surface (`radius// pill`, `border// subtle`) with an inner filled circle when selected (uses `accent// primary// active`).
- **Tooltip** — small popover anchored to an element, shown on hover after a brief delay. Composes Surface (`surface// tertiary// bg`, `radius// tight`, `shadow// overlay`, `border// subtle`) + Text(caption). Single-line copy by default; multi-line allowed. Used on every icon-only control, every truncated label, every keyboard-shortcut-bearing button.
- **Menu** — floating menu surface for dropdowns, context menus, and command palettes. Composes Surface (`surface// tertiary// bg`, `radius// surface`, `shadow// overlay`, `border// subtle`) + a vertical Stack of MenuItem primitives. Variants by trigger context (`dropdown` / `context` / `palette`) — same visual structure, different invocation. **Right-click context menus** (rename / duplicate / delete on sidebar items, table rows, tabs) use the `context` variant.
- **MenuItem** — single row within a Menu. Stack(horizontal) of Icon (optional, semantic role) + Text(label) + Text(shortcut hint, muted, right-aligned, optional) + Icon (chevron for submenu, optional). State variants: `idle` / `hover` / `active` / `disabled`. Destructive variant (`intent: destructive`) renders the label using `state// error// fg`.

## Composed components to build (assemblies of primitives only)

- **Three-pane shell** — Surface(secondary) | Surface(primary, with top-bar tab row at top) | Surface(secondary); drag splitters at default widths 240 / flex / 280. **Window chrome (macOS unified title bar):** the macOS traffic-light buttons live in the top-left of the sidebar pane's column at runtime — **do NOT draw them in Figma; leave that area empty / reserved** (assume the OS renders them). The top-bar tab row sits in the same horizontal band as the (reserved) traffic-light area, starting from the right edge of the sidebar column and spanning across the main pane. **There is no separate 
- **Top-bar tab** — single tab unit. Surface consuming `surface// secondary// bg` when inactive, `surface// primary// bg` when active (active tab is visually continuous with the main pane it heads). Stack(horizontal) inside: Icon (entity-kind: page / collection / space) + Text (entity title, truncated with ellipsis if needed) + Icon (`close` for the `×` close affordance, shown on hover or always-visible per design pass). Variants: active / inactive / hover.
- **Top-bar tab row** — horizontal Stack of multiple Top-bar tabs at the trailing edge of which sits a Pressable + Icon(`add`) for the `+` new-tab button. **Sits in the unified title bar band, starting from the right edge of the sidebar column** (the empty / reserved area to its left is where the OS renders the traffic lights — not drawn in Figma). Spans above the main pane content. **Default height: 35px** (bound to a token; tunable). The mock must show **at least 2–3 tabs in different states** (active, inactive, hover) plus the trailing `+` to demonstrate the tab-row pattern. Obsidian / Notion reference.
- **Sidebar section header** — Disclosure (`indent line = true`) with label content slot rendering Text(label, muted) only. **No icon.** The three top-level section labels (Spaces / Saved / Collections) are text-only headings — entity-kind icons (`page` / `item` / `collection` / `space`) appear on individual navigation rows inside each section, not on the section headings themselves.
- **Sidebar item (leaf)** — Pressable wrapping Stack(horizontal) of Icon (entity kind, optional) + Text
- **Sidebar item (parent / folder disclosure)** — Disclosure (`indent line = true`) with label content slot rendering Icon (entity kind, optional) + Text; children render indented with the line
- **Sidebar tree (recursive composition)** — section headers contain folder disclosures and / or leaf items; folder disclosures contain leaf items OR more folder disclosures; every level deeper adds an indent step and (because `indent line = true`) renders a DisclosureLine. **The sidebar mock must demonstrate at least 3 levels of nesting** (section header → expanded folder disclosure → child folder disclosure → leaf items), with the line visible at each expanded level. Reference: Obsidian / VSCode file explorer indent-guide pattern.
- **Page heading disclosure** — small in-context example only: Disclosure (`indent line = false`) wrapping heading Text + a couple of body Text rows. No DisclosureLine. Built-in fold behavior on every heading (not a directive). Full Page editor surface is a post-library page demo — out of scope here.
- **Callout** — `:::callout` directive output. Surface (consumes `callout// bg`, `callout// border`, `radius// tight`) wrapping a Stack(vertical) of Text(body) in `callout// fg`. Slight padding inside the bordered rectangle. Minimally rounded; distinct visually from blockquotes.
- **Blockquote** — standard `>` syntax output. Stack(horizontal) of a thin vertical Surface (left-side bar consuming `blockquote// bar`, which defaults to `blockquote// fg`) + a Surface (consumes `blockquote// bg`) wrapping a Stack(vertical) of Text(body) in `blockquote// fg`. Filled box with left-edge bar; distinct visually from callouts.
- **Code block** — fenced code-block output. Surface (consumes `code// bg`, `radius// tight`) wrapping a Stack(vertical) of Text using the mono font at `code// font// size` (1.0 em) in `code// fg`.
- **Inline code** — inline backtick output. Surface (tight inline chip; consumes `code// bg`, very tight radius) wrapping Text(mono, `code// fg`, 1.0 em).
- **Property row** — Stack(horizontal) of Icon (property type) + Text(label, muted) + Field
- **Tab / segmented control** — Stack of Pressable + Text per tab
- **Toggle** — Pressable + Surface circle on track (uses `accent// primary// active` when on, `text// muted` when off)
- **Slider** — Track Surface + handle Surface (uses `accent// primary// active` for fill)

---

## Deliverables

1. **Figma file** with:
   - All Variables defined per the groups above (Color, Symbols, Accent, Interactive states, Semantic states, Opacity, Brightness, Typography, Spacing, Radius, Shadow, Border)
   - All primitives built as **single Figma components with variant properties** (zero hardcoded values, no duplicated components per state / tier / intent)
   - All composed components built by composing primitives (no reaching around)
   - Material Symbols (outlined) wired through the Icon primitive, every usage resolving via the role table — `crop_free` placeholder for any role not yet finalized
   - **Variant gallery frame per component** — each component's frame displays all variants in a horizontal row (Apple-style component gallery)
   - **One assembled context: the three-pane shell mockup at 16:9 aspect ratio** — sidebar with multi-level disclosure tree (≥ 3 nested levels using `Disclosure` with `indent line = true`), top-bar tab row in the unified title bar band (traffic-light area left empty / reserved; 2–3 tabs in active / inactive / hover states + trailing `+`), inspector placeholder. Main pane content area is empty placeholder copy.
2. **Variable-naming audit** — every variable name follows the dual-export discipline (semantic, role-based)
3. **Cascade audit** — pick three variables (`accent// primary// active`, `radius// surface`, `font// size// body`); change each and confirm every consumer updates with no exceptions
4. **Icon coverage audit** — every icon usage in every composed component resolves through a semantic role; no raw Material name appears anywhere
5. **Variant-model audit** — every component is ONE Figma component with variant properties; no duplicated components (no separate `PrimaryButton` / `SecondaryButton` files — one `Button` with `variant` property)
6. **Gallery audit** — every component's frame shows all variants in a single horizontal row

## Acceptance criteria

- Zero hardcoded values in any component (every color, size, radius, spacing, shadow, opacity resolves through a Variable)
- Every primitive is built first; every composed component uses only primitives
- Variable names are semantic; never implementation-flavored
- Single component, many variants — no duplicated components for state / tier / intent variations
- Each component's frame displays its variants in a row
- Three-pane shell renders correctly at 16:9 using only the design system; traffic-light area left empty / reserved; tabs render in the unified title bar band; multi-level disclosure tree in the sidebar
- Cascade audit passes for the three test variables
- Icon coverage audit passes — no raw Material Symbol names in any component
- Page-level mockups (full Page editor, full Collection view, full Space block surface, Settings UI) are NOT in this file — those are post-library deliverables

## Out of scope (deferred to post-library work)

- **Page-level mockups** — full Page editor surface (prose + H1–H5 + callouts + code blocks + GFM tables), full Collection view (table / board / list / cards / gallery rendered with realistic data), full Space block surface, Settings UI. All happen after the library lands; not in this Figma file.
- **Empty states** render as empty surfaces (no placeholder copy or illustration in v0). Over-designed empty states are post-library.
- **Tag hover state** is captured during the live demo phase — Figma static frames don't model the hover interaction for tag chips. The design system records the idle tag only.
- **Animation tokens** (durations, easing curves) — deferred. Initial design pass is static.
- **Scrollbar styling** (native vs custom thin) — deferred.
- **Window-unfocused dimming** (macOS convention) — deferred.
- **Pressed-state animation, drag-ghost styling, drop-indicator shape** — captured during live demo, not Figma static.

## Round-1 refinement scope

After the structure is built, expect refinement on:
- Exact border hex values (between ~#2A2A2C and ~#3A3A3C)
- Exact accent stops (validate primary muted / active relationship; secondary stops derivation)
- Tertiary surface tone
- Tag palette specific hex values per color
- Spacing scale completeness (may need 2px or 6px additions)
- Material Symbol name verification against the current catalog (any stale names update both the icon table and `.pommora// symbols.json` seed)

Round 1 happens inline — explore variations in the Figma file, settle the values, propagate.
````
