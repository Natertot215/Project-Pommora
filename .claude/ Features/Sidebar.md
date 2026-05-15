### Sidebar

The leading-edge navigation pane in Pommora's three-pane shell. Three top-level headings (Spaces / Saved / Collections), disclosure-style expansion. Structural detail and entity-routing rules live in `Domain-Model.md`; this file captures the sidebar's **design direction** — pieces that are intended but not all built yet.

---

#### Selection language (intent — not yet built)

The intended selection treatment is a **subtle gray fill background + accent foreground**, not an accent-color fill. The target gray is Apple's `unemphasizedSelectedContentBackgroundColor` — the same color Mail and Finder use for their always-on selection. Selection contrast should come from the foreground tone shift (icon + text turning accent), not from the background fill.

This direction is deliberately distinct from the **accent-fill** pattern used by Settings.app and SwiftUI's default `List(selection:) + .sidebar` (solid accent bar with white foreground). That pattern is visually loud in a notes/database context where the user selects and re-selects rapidly. The intended Pommora pattern reads understated — eye drawn to foreground tone, not a color block.

**Status (v0.0):** the running build uses macOS-default `.listStyle(.sidebar)` selection (accent-blue fill + white foreground). The gray-fill direction wasn't built — `.tint(_:)` doesn't recolor sidebar List selection on macOS 26 Tahoe (the underlying `NSTableView` ignores SwiftUI's tint for its source-list highlight), and the AppKit introspection workaround was judged too much surface for v0.0 chrome polish. Open to revisit when content lands and the visual cost of bright-accent selection becomes concrete.

When built, the styling should be appearance-aware via SwiftUI's semantic colors; no mode-specific overrides needed. The rule should apply regardless of how selection is triggered (mouse, keyboard, programmatic).

---

#### Indentation mechanisms (working vocabulary)

When adjusting sidebar geometry, the mechanism depends on what's being adjusted — these are NOT interchangeable:

- **Row leading indent** — `.padding(.leading, N)` on the row, or `.listRowInsets(EdgeInsets(...))` modifier. Use for nesting/grouping (e.g., member rows inside a Collection).
- **Chevron-to-icon gap on a custom disclosure row** — `HStack(spacing: N)` between the chevron view and the `Label`. Only applies when the chevron is hand-rolled (not when SwiftUI's `DisclosureGroup` renders it internally).
- **Icon-to-text gap inside a row** — internal to `Label`, controlled by a custom `LabelStyle` or by writing the row as `HStack { Image; Text }` instead of `Label`. `HStack(spacing:)` on the outer row does NOT control this.
- **Chevron-column reservation across flat rows** — implicit, triggered by `DisclosureGroup`'s presence in a `.listStyle(.sidebar)` List. Not directly user-controllable; only suppressible by dropping `DisclosureGroup` and hand-rolling expansion.

---

#### Inline-chevron experiment (Finder-style flush-left flats)

Apple's default for `.listStyle(.sidebar) + DisclosureGroup` (Mail/Xcode pattern) reserves a chevron column on every row, so flat-row icons align horizontally with disclosure-row icons but sit indented from the sidebar leading edge. Finder uses a different pattern — flat rows sit flush-left, only "folder" rows show the inline chevron + slight indent.

The Finder pattern is achievable by **dropping `DisclosureGroup`** for Collection rows and hand-rolling the expansion as `HStack(spacing: N) { chevronButton; Label(...) }` with `if collectionExpansion[c]` gating the member ForEach beneath. Verified working at v0.0.

Captured intent (not committed): experiment with the chevron-to-icon gap value (currently `4` in the spike) — Nathan wants this **tighter than Apple's default**, with the rest of the sidebar matching the tighter visual. Resolution deferred until v0.1 content lands so spacing can be tuned against real data, not placeholders.

---

#### Open until v0.1 lands content

Row density, hover treatment, keyboard navigation, focus-ring styling, and any timing/opacity specifics resolve once the v0.1 sidebar tree populates and Tahoe rendering can be observed. Captured intent (not commitment): a third hovered state, subtler than the selected fill.
