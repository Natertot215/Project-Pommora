### Sidebar

The leading-edge navigation pane in Pommora's three-pane shell. Three top-level headings (Spaces / Saved / Collections), disclosure-style expansion. Structural detail and entity-routing rules live in `Domain-Model.md`; this file captures the sidebar's **design direction** — pieces that are intended but not all built yet.

---

#### Selection language

**Subtle gray fill + accent foreground, with a brightness boost.** Specifics:

- Fill: `Color.gray.opacity(0.11)`, 6pt continuous corner radius, inset **11pt horizontal + 2pt vertical** from row edges (the 11pt aligns the fill's leading edge with the search field). Painted via `.listRowBackground(...)` so it spans the full row width.
- Foreground: selected icon and text shift to `Color.accentColor`. **Text** gets `.brightness(0.12)` to lift the accent over the fill; **icon** gets no brightness modifier.
- Row content padding: **4pt leading, 0 trailing, 2pt vertical**. The 4pt leading aligns the icon at roughly the same distance from the sidebar edge that a `DisclosureGroup` chevron would sit, so flat rows and disclosure rows visually line up.

**Why text-only brightness:** SF Symbols rendered through `.brightness()` composite differently inside `Section` vs `DisclosureGroup` vs direct-`List`, so the same icon brightness produced visibly different selected shades per context. `Text.brightness(_:)` composites predictably; removing the modifier from the icon eliminates the inconsistency.

Deliberately distinct from the **accent-fill** pattern (Settings.app, SwiftUI's default `List(selection:) + .sidebar`). That pattern is visually loud for a notes/database context with rapid selection churn; Pommora's reads understated — eye drawn to foreground tone, not a color block.

**Implementation** ([Pommora/Pommora/Sidebar/SidebarView.swift](../../Pommora/Pommora/Sidebar/SidebarView.swift)): private `SelectableRow` with custom tap-driven selection (`@State var selection: String?` + `.onTapGesture`), not `List(selection:)`. Required because `.tint(_:)` doesn't recolor sidebar List selection on macOS Tahoe (`NSTableView` ignores SwiftUI tint for its `.sourceList` highlight), and the system's default keeps fill + foreground reciprocal (accent fill → white text), blocking the gray-fill + accent-fg combo we want.

The icon uses `.symbolRenderingMode(.monochrome)` so `.foregroundStyle(.accentColor)` actually applies — sidebar-context `Label` rendering can otherwise ignore foregroundStyle via its built-in icon tinting.

Appearance-aware via `Color.accentColor` and `Color.primary`; no mode-specific overrides.

**Trade-off:** fill doesn't desaturate on window unfocus the way Finder/Mail do via `NSVisualEffectView` + `.sourceList`. Acceptable for v0.0 chrome.

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — these are NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` on the row, or `.listRowInsets(EdgeInsets(...))` modifier. Use for nesting/grouping (e.g., member rows inside a Collection).
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between the chevron view and the `Label`. Only applies when the chevron is hand-rolled (not when SwiftUI's `DisclosureGroup` renders it internally).
- **Icon-to-text gap inside a row** — internal to `Label`, controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }` instead of `Label`. `HStack(spacing:)` on the outer row does NOT control this.
- **Chevron-column reservation across flat rows** — implicit, triggered by `DisclosureGroup`'s presence in a `.listStyle(.sidebar)` List. Not directly user-controllable; only suppressible by dropping `DisclosureGroup` and hand-rolling expansion.

---

#### Inline-chevron experiment (Flush-left Icons)

Apple's default for `.listStyle(.sidebar) + DisclosureGroup` (Mail/Xcode pattern) reserves a chevron column on every row, so flat-row icons align horizontally with disclosure-row icons but sit indented from the sidebar leading edge. Finder uses a different pattern — flat rows sit flush-left, only "folder" rows show the inline chevron + slight indent.

The Finder pattern is achievable by **dropping `DisclosureGroup`** for Collection rows and hand-rolling the expansion as `HStack(spacing: N) { chevronButton; Label(...) }` with `if collectionExpansion[c]` gating the member ForEach beneath. Verified working at v0.0.

Captured intent (not committed): experiment with the chevron-to-icon gap value (currently `4` in the spike) — Nathan wants this **tighter than Apple's default**, with the rest of the sidebar matching the tighter visual. Resolution deferred until v0.1 content lands so spacing can be tuned against real data, not placeholders.

---

#### Open until v0.1 lands content

Row density, hover treatment, keyboard navigation, focus-ring styling, and any timing/opacity specifics resolve once the v0.1 sidebar tree populates and Tahoe rendering can be observed. Captured intent (not commitment): a third hovered state, subtler than the selected fill.
