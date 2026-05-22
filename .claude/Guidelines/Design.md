### Design

Pommora's visual identity, brand values, and design conventions — Swift / Apple-native. SF Symbol registry → `Symbols.md`.

---

#### Design philosophy

Apple's macOS HIG for native cohesion. Toolkit is **SwiftUI primary + AppKit where SwiftUI doesn't reach** — both first-class.

- **Semantic colors** — `Color(.systemBackground)`, `.foregroundStyle(.primary/.secondary)`. Automatic dark mode + accessibility.
- **Materials** — `Material.regular/.thin/.thick/.ultraThin/.sidebar` for vibrancy.
- **Native typography** — SwiftUI Font scale (`.body`, `.callout`, `.caption`, `.system(.body, design: .monospaced)`). Custom sizes only where the scale doesn't fit. Dynamic Type free.
- **SF Symbols** — `Image(systemName:)`. Assignments → `Symbols.md`.
- **Native controls** — system Button / Slider / Toggle; encapsulate Pommora styling via `ButtonStyle` / `ViewModifier`.
- **Window chrome** — macOS unified title bar, OS traffic-light buttons.

A small set of brand-specific values (code colors, callout border, blockquote accent bar) express Pommora's character within the Apple aesthetic.

---

#### Where Pommora's brand values live

- **App accent** — `Assets.xcassets/AccentColor.colorset` with light/dark variants. Accessed via `Color.accentColor` or `.tint(.accentColor)`.
- **Pommora Colors** — small extensions (`Color+Pommora.swift` or Asset Catalog) for values SwiftUI semantic colors don't cover: code fg/bg, callout border, blockquote accent bar. Naming: `Color.nexusCodeBackground`, etc.
- **Pommora Fonts** — small Font extensions where the scale doesn't fit.

That's the whole brand surface on Swift; SwiftUI semantic colors + Font scale carry the rest.

> The ~118-token design system (semantic role-based naming, surface/element tier model) is a React pattern → `// ReactInfo// Styling-Tokens.md`. Swift doesn't need it — SwiftUI's semantic system does most of the work.

---

#### Component conventions

- **Prefer SwiftUI semantic colors and fonts.** Use Pommora extensions only for values without native equivalents.
- **Modern modifiers.** `.foregroundStyle(.primary)` not `.foregroundColor()`. `.clipShape(.rect(cornerRadius: 12))` not `.cornerRadius()`.
- **Reusable styling via `ViewModifier` and `ButtonStyle`.** Encapsulate repeated visual patterns.
- **Single component per concept.** One `Button` with a `style` enum or `ButtonStyle`, not seven button files.
- **SF Symbol weight matches text weight.** Symbols inherit weight from the surrounding text style when paired — keep that link. If a symbol's weight needs to deviate, apply `.fontWeight()` explicitly.
- **No hardcoded brand values.** Every Pommora-brand color/font resolves through `Color+Pommora` or Asset Catalog; hardcoded *semantic* values (`.foregroundStyle(.primary)`) are fine because they ARE the semantic.

---

#### Initial scheme

Dark mode first. SwiftUI semantic colors cover the shell; Pommora extensions provide the accent and brand-specific values. No built-in light/dark toggle in v0.x. In-app customization (accent color + font size) folds into the v0.6.0 Settings scaffold; everything else is handled by SwiftUI natively.

---

#### Sidebar section chevrons

Section header chevrons appear **on hover only** — Apple's default for `Section(_:isExpanded:)` under `.listStyle(.sidebar)`. Don't override with always-visible indicators. Matches Mail / Notes / Finder.

---

#### Creation affordance pattern: right-click context menus, scoped by cursor location

**Canonical pattern for all sidebar CRUD-creation** (paradigm decision 2026-05-17). No always-visible "+ New" buttons in the sidebar; users right-click the relevant heading / row / area and get a context menu whose "New X" options auto-scope to that location's parent.

Implementation pattern in SwiftUI:

```swift
ForEach(pageTypeManager.pageTypes) { type in
    PageTypeRow(pageType: type, ...)
        .contextMenu {
            // Sheet titles are user-facing — read from SettingsManager.
            // Defaults: Pages-side "Vault" / "Collection"; Items-side "Type" / "Set".
            Button(settings.labels.pageType.singular("New ")) { presentedSheet = .newPageType }
            Button(settings.labels.pageCollection.singular("New ")) {
                presentedSheet = .newPageCollection(type: type)
            }
            Button("New Page") { presentedSheet = .newPage(collection: nil, type: type) }
            Divider()
            Button("Rename") { ... }
            Button("Change Icon") { presentedSheet = .editIcon(.pageType(type)) }
            Divider()
            Button("Delete", role: .destructive) { confirmingDelete = .deletePageType(type, collectionCount: ...) }
        }
}
```

The `.contextMenu` attaches to the row view directly — clicking on the Page Type row's chevron, title, or icon all open the same scoped menu. Each enum case in `SidebarSheet` / `SidebarConfirmation` carries the parent entity binding through to the presented sheet — the sheet never re-asks for parent location. Items-side rows ship as minimal stubs at v0.3.0 (no context menus); designed Items-side UI lands in a follow-up plan.

**Why over always-visible "+ New":**
- Sidebar reads content-forward at rest (matches chevron-on-hover)
- Right-click is universal macOS muscle memory (Finder, Notion, Obsidian)
- Location scoping is automatic — cursor already identified the parent
- Quick-capture (Cmd+Shift+N, v0.6.0) absorbs the global creation path

Detail → `// Features//Sidebar.md`.

---

#### Chrome animation

Apple's native chrome animations (`NSSplitView` collapse, toolbar reflow, inspector reveal) are gold standard. **Don't replace system chrome with custom equivalents.**

`.inspector(isPresented:)` is the exception — panel reveal isn't routed through SwiftUI's animation transaction, so wrap toggles in `withAnimation(.smooth(duration: 0.30))`. Inspector toolbar items belong **inside the `.inspector(...) { content }` closure** to anchor to the inspector's toolbar segment.

Platform quirks (`.toolbar(removing:)` on macOS 26+, exact curves) verified in build and noted in `Handoff.md`.

---

#### AppKit interop

AppKit wraps are confirmed during real build, not pre-cataloged. Shipped: Page editor (NSTextView / TextKit 2 + Apple `swift-markdown` + vendored `swift-markdown-engine` → `// Features//PageEditor.md`). Other candidates resolve when their consuming feature lands.

---

#### Reference

- `Symbols.md` — SF Symbol registry (Application ↔ Symbol table)
- `CRUD-Patterns.md` — per-entity CRUD UI patterns + atomic-write discipline
- `// Features//Sidebar.md` — right-click menu table + selection chrome spec
- `// Features//PageEditor.md` — editor implementation spec
- `// ReactInfo//Styling-Tokens.md` — Figma-tool workflow + React-side full token system (contingency reference only)
