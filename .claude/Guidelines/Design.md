### Design

Pommora's visual identity, brand values, and design conventions — Swift / Apple-native. SF Symbol registry → `Symbols.md`.

---

#### The Component Library is the source of design

Components and design come from the **Component Library** (Cmd+Shift+D, `ComponentLibraryView`) as reusable assets — stage them there, then pull into production. Avoid one-off designs. New patterns land in the Component Library first.

---

#### Design philosophy

Apple's macOS HIG for native cohesion. Toolkit is **SwiftUI primary + AppKit where SwiftUI doesn't reach** — both first-class.

- **Semantic colors** — `Color(.systemBackground)`, `.foregroundStyle(.primary/.secondary)`. Automatic dark mode + accessibility.
- **Materials** — `Material.regular/.thin/.thick/.ultraThin/.sidebar` for vibrancy.
- **Native typography** — SwiftUI Font scale (`.body`, `.callout`, `.caption`, `.system(.body, design: .monospaced)`). Custom sizes only where the scale doesn't fit. Dynamic Type free.
- **SF Symbols** — `Image(systemName:)`. Assignments → `Symbols.md`.
- **Native controls** — system Button / Slider / Toggle; encapsulate Pommora styling via `ButtonStyle` / `ViewModifier`.
- **Window chrome** — macOS unified title bar, OS traffic-light buttons.

A small set of brand values (code colors, callout border, blockquote accent bar) expresses Pommora's character within that aesthetic.
Dark mode first; no in-app light/dark toggle in v0.x. Accent color + font size customization folds into the v0.4.0 Settings scaffold.

---

#### Where brand values live

- **App accent** — `Assets.xcassets/AccentColor.colorset` (light/dark). Use via `Color.accentColor` / `.tint(.accentColor)`.
- **Pommora Colors / Fonts** — small extensions (`Color+Pommora.swift`, Asset Catalog) for what SwiftUI semantic colors / Font scale don't cover. Naming: `Color.nexusCodeBackground`, etc.

SwiftUI semantic colors + Font scale carry the rest.

> The ~118-token design system (semantic role-based naming, surface/element tier model) is a React pattern → `// ReactInfo//Styling-Tokens.md`. SwiftUI's semantic system covers it.

---

#### Component conventions

- **Modern modifiers.** `.foregroundStyle(.primary)` not `.foregroundColor()`. `.clipShape(.rect(cornerRadius: 12))` not `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **SF Symbol weight matches text weight** — symbols inherit weight from the surrounding text style; override with `.fontWeight()` only when intended.
- **o hardcoded brand values.** Pommora-brand colors / fonts resolve through `Color+Pommora` or Asset Catalog. Hardcoded *semantic* values (`.foregroundStyle(.primary)`) are fine — they ARE the semantic. Hardcoded or specialized design should be directed by Nathan and approved; don't create without explicit permission. 
- **No raw magic numbers in views.** Spacing, sizes, radii, paddings flow through `PUI` (`DesignSystem/PUI.swift`). Extend `PUI` rather than inlining a literal.
- **Popover-family type scale.** Section headers ("Options", "Display As") = Subheadline / emphasized, vibrant secondary. Chip text = Callout / emphasized — matches `PropertyChip`.
- **Chips.** Capsule, 50×20. 6pt between chips; 12pt from a section header to the first chip. Reorder grip = `line.3.horizontal`, vibrant secondary, sized to chip text; drag happens on the grip.

---

#### Sidebar section chevrons

Section header chevrons appear **on hover only** — Apple's default for `Section(_:isExpanded:)` under `.listStyle(.sidebar)`. Matches Mail / Notes / Finder.

---

#### Liquid Glass continuity

Surfaces hosted inside `.popover(...)` and toolbar-anchored panels sit inside Apple's Liquid Glass chrome. Don't compete with it.

- Apple drives the outer shell (translucent rounded background, drop shadow, anchor arrow, transitions). Don't add `.background(.regularMaterial)` / `.glassEffect()` / opaque fills to popover roots.
- **Inline selectors** = plain `Menu` over `Picker(.menu)` (Pickers render a heavy form-control background). Trigger = the value text, **no chevron glyph**; menu = vertical list, checkmark on current.
- **Picker content in `.popover` uses `.presentationBackground(.clear)`** + an explicit `.frame(width:height:)` — the clear background stops the system popover chrome from stacking a second material under the content's own `chipDropdownPanel` glass (the `RelationPicker` / `IconPicker` pattern); the fixed frame sizes the popover.
- **Pane dividers use `PaneDivider`** — system `Divider` inset to the content rail (`PUI.Pane.contentPadding`, 16pt), flush to content edges. Field↔content divider adds 5pt vertical (`PUI.Pane.dividerPaddingVertical`); footer dividers add none (the row's own padding provides the gap).
- **Destructive / global footers pin to the popover bottom.** Delete / Duplicate / "New property" stay fixed; the scrollable middle absorbs spare space. Per-type selectors (Display As, date format) scroll with their section.
- **Pushed panes show a chevron + previous-pane-name back affordance** ("‹ Edit Properties"). When the pane edits one named entity whose icon + name render inline at the top, drop the separate "Edit X" pane title — the entity row carries identity. Otherwise keep the standard `PaneHeader`.
- Reach for custom only where the platform can't carry the look (e.g., the in-content `PaneHeader`, which exists because `.navigationTitle` renders a dark band inside a popover).

---

#### Context-aware padding

- Padding stacks. A child's `.padding(...)` adds to the parent's; when wrapping previously-pinned content into a padded scroll container, strip the child's own horizontal padding.
- Order matters: `.padding → .frame → .background` — backgrounds wrap the framed size only when applied last.
- For "all rows share an exact horizontal rail," derive `contentWidth` from math (`N × elementSize + (N-1) × spacing`) and apply that same `.frame(width: contentWidth)` to every row.
- `LazyVGrid` with `.fixed` columns beats `HStack` + `Spacer(minLength: 0)` for pixel-exact alignment — grid math is deterministic; Spacer behavior negotiates sub-pixels.

---

#### Chrome animation

Apple's native chrome animations (`NSSplitView` collapse, toolbar reflow, inspector reveal) are gold standard. **Don't replace system chrome with custom equivalents.**

`.inspector(isPresented:)` is the exception — panel reveal isn't routed through SwiftUI's animation transaction, so wrap toggles in `withAnimation(.smooth(duration: 0.25))`. Inspector toolbar items belong **inside the `.inspector(...) { content }` closure** to anchor to the inspector's toolbar segment.

---

#### AppKit interop

Confirmed in real build, not pre-cataloged. Shipped: Page editor (NSTextView / TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` → `// Features//PageEditor.md`). Other wraps resolve when their consuming feature lands.

---

#### Inline text-field commit

Every inline-edit `TextField` commits on **Enter, focus loss, AND popover/pane dismissal** — never Enter-only. Wire `@FocusState` + `.onChange(of:)` (commit when focus goes `true → false`) plus an `.onDisappear` safety net for popover-hosted fields; `.onSubmit` only fires on Enter while focused, and click-outside dismissals don't blur reliably. Commit closures must be **idempotent** — guard `trimmed != current` so Enter / blur / disappear can all fire without double-writing.

The editable hit-target is the **field, not the whole row** — constrain a label-style inline field with `.fixedSize(horizontal: true, vertical: false)` so the caret/click area matches the text, not the row.

---

#### Reference

- `Symbols.md` — SF Symbol registry (Application ↔ Symbol table)
- `CRUD-Patterns.md` — per-entity CRUD UI patterns + atomic-write discipline
- `// Features//Sidebar.md` — right-click menu table + selection chrome spec
- `// Features//PageEditor.md` — editor implementation spec
- `// ReactInfo//Styling-Tokens.md` — Figma-tool workflow + React-side full token system (contingency reference only)
