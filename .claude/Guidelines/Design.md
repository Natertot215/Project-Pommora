### Design

Pommora's visual identity and design principles — Swift / Apple-native. SF Symbol registry → `Symbols.md`.

---

#### The Component Library is the source of design

Components and design come from the **Component Library** as reusable assets — stage them there, then pull into production. Avoid one-off designs. New patterns land in the Component Library first.

---

#### Design philosophy

Apple's macOS HIG for native cohesion. The toolkit is **SwiftUI primary + AppKit where SwiftUI doesn't reach** — both first-class. AppKit is used directly (via `NSViewRepresentable`) only where the platform can't carry the look in SwiftUI; the Page editor (NSTextView / TextKit 2) is the standing example, and other wraps resolve when their consuming feature lands.

- **Semantic colors first** — system background/label colors and `.primary` / `.secondary` foreground styles. Automatic dark mode + accessibility come free.
- **Materials** for vibrancy — the system material set (regular / thin / thick / sidebar, etc.).
- **Native typography** — the SwiftUI Font scale. Custom sizes only where the scale genuinely doesn't fit; Dynamic Type comes free.
- **SF Symbols** for iconography. Assignments → `Symbols.md`.
- **Native controls** — system Button / Slider / Toggle; encapsulate Pommora styling via `ButtonStyle` / `ViewModifier`.
- **Window chrome** — the macOS unified title bar and OS traffic-light buttons.

**Dark mode first.** No in-app light/dark toggle in v0.x.

**Accent is user-overridable.** The app accent resolves through the system accent color, overridable per-Nexus. Accent-color and font-size customization fold into the Settings scaffold.

---

#### Where brand values live

SwiftUI's semantic colors and Font scale carry the vast majority of the surface. The small set of brand values they don't cover (code-block tinting, callout border, blockquote accent bar) lives in a dedicated `Color` extension plus the asset catalog — never hardcoded at call sites. That extension is the single place a brand value changes.

The semantic system makes a separate design-token layer unnecessary on the Swift side. (The React contingency build carries a role-based token system instead → `// ReactInfo//Styling-Tokens.md`.)

---

#### Component conventions

- **Modern modifiers.** `.foregroundStyle(.primary)` over `.foregroundColor()`; `.clipShape(.rect(cornerRadius:))` over `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **SF Symbol weight matches text weight** — symbols inherit weight from the surrounding text style; override only when intended.
- **No hardcoded brand values.** Pommora-brand colors and fonts resolve through the `Color` extension / asset catalog. Hardcoded *semantic* values (`.foregroundStyle(.primary)`) are fine — they ARE the semantic. Any hardcoded or bespoke design must be directed and approved by Nathan; don't create one-offs without explicit permission.
- **No raw magic numbers in views.** Spacing, sizing, radii, and padding all flow through the design-system tokens — extend the token set rather than inlining a literal.
- **Chips** are capsule-shaped and come in a standard and a compact size tier; their dimensions and spacing flow through the design-system tokens. A reorder grip carries the drag.

---

#### Sidebar section chevrons

Section header chevrons appear **on hover only** — Apple's default for `Section(_:isExpanded:)` under `.listStyle(.sidebar)`. Matches Mail / Notes / Finder.

---

#### Liquid Glass continuity

Surfaces hosted inside `.popover(...)` and toolbar-anchored panels sit inside Apple's Liquid Glass chrome. Don't compete with it.

- Apple drives the outer shell (translucent rounded background, drop shadow, anchor arrow, transitions). Don't add opaque fills or your own material/glass effect to popover roots.
- **Inline selectors** = a plain `Menu` over `Picker(.menu)` (Pickers render a heavy form-control background). The trigger is the value text with no chevron glyph; the menu is a vertical list with a checkmark on the current value.
- **Picker content in `.popover`** uses a clear presentation background plus an explicit fixed frame — the clear background stops the system popover chrome from stacking a second material under the content's own glass, and the fixed frame sizes the popover.
- **Pane dividers** inset to the content rail, flush to the content edges.
- **Destructive / global footers pin to the popover bottom.** Delete / Duplicate / "New property" stay fixed; the scrollable middle absorbs spare space. Per-type selectors scroll with their section.
- **View Settings panes size to content.** A pane grows from a minimum toward a maximum height as its middle fills, then scrolls the middle while header and footer stay pinned. The container owns the single `ScrollView`; panes provide inner content only.
- **Pushed panes show a chevron + previous-pane-name back affordance.** When a pane edits one named entity whose icon + name render inline at the top, drop the separate pane title — the entity row carries identity. Otherwise keep the standard pane header.
- Reach for custom only where the platform can't carry the look — e.g. an in-content pane header, which exists because `.navigationTitle` renders a dark band inside a popover.

---

#### Context-aware padding

- Padding stacks. A child's `.padding(...)` adds to the parent's; when wrapping previously-pinned content into a padded scroll container, strip the child's own horizontal padding.
- Order matters: `.padding → .frame → .background` — backgrounds wrap the framed size only when applied last.
- For "all rows share an exact horizontal rail," derive the content width from math (`N × elementSize + (N-1) × spacing`) and apply that same `.frame(width:)` to every row.
- `LazyVGrid` with `.fixed` columns beats `HStack` + `Spacer(minLength: 0)` for pixel-exact alignment — grid math is deterministic; Spacer behavior negotiates sub-pixels.

---

#### Chrome animation

Apple's native chrome animations (`NSSplitView` collapse, toolbar reflow, inspector reveal) are the gold standard. **Don't replace system chrome with custom equivalents.** The one exception is `.inspector(isPresented:)`: its panel reveal isn't routed through SwiftUI's animation transaction, so wrap toggles in an explicit animation.

**A toolbar is owned by the container hosting the view it attaches to.** The main window's primary-action cluster (views / settings / nav / inspector) hosts on the **detail column** — not the inspector closure, not the `NavigationSplitView` root. Put toolbar content inside `.inspector(...)` only for items that belong to the inspector's own toolbar segment.

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
- `// ReactInfo//Styling-Tokens.md` — Figma-tool workflow + React-side token system (contingency reference only)
