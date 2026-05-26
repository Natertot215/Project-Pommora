### PommoraUIX — In-App Design System Explorer

A debug-only window inside Pommora that explores every Pommora-custom UI component + design token, three-pane Interactful-style. Lets Nathan see how each Figma component translates to live SwiftUI, tweak parameters in real time, copy code, and verify cross-component consistency without leaving the app.

#### Scope

This is **separate from any feature ship**. Not part of v0.3.x, v0.4.0, or any pending plan. It's an evergreen debug surface that grows alongside Pommora's component catalog. Builds incrementally — new stories land alongside the components they cover.

#### Current State (v0.1 shipped)

A minimal Cmd+Shift+D window built during v0.3.x Properties side-work. Two-pane (sidebar + detail), no inspector column, three stories:

- **Property Chip** — Pill (50×20 label) + Chip (32×20 icon) variants in all 9 PropertyChipColor cases
- **Chip Dropdown** — single-select + multi-select with Liquid Glass dropdown, drag-reorder, hover-X (single-select only), checkboxes (multi-select)
- **Property Checkbox** — colored fill + custom SF Symbol when checked, 3 sizes

Files: `Pommora/Pommora/ComponentLibrary/ComponentLibraryView.swift` + `Pommora/Pommora/PommoraApp.swift` (Window scene + Cmd+Shift+D shortcut).

#### Target Vision (v1.0)

Three-pane `NavigationSplitView` matching the Interactful App Store app's UX pattern:

```
┌──────────┬─────────────────────┬──────────────┐
│ Sidebar  │     Center pane     │  Inspector   │
│          │                     │              │
│ Search   │  Component title    │  Parameter   │
│ ──────   │  + description      │  controls    │
│ Chips    │                     │  (sliders,   │
│ Sidebar  │  Variants laid out  │   toggles,   │
│ Detail   │  side-by-side       │   pickers,   │
│ Sheets   │  with code samples  │   color      │
│ Editor   │                     │   pickers)   │
│ ──────   │                     │              │
│ Founda.  │  Live preview       │  bound to    │
│ Colors   │                     │  preview     │
│ Typo     │                     │              │
│ Symbols  │                     │              │
└──────────┴─────────────────────┴──────────────┘
```

Right column uses `.inspector(isPresented:)` (macOS 14+). Sidebar uses `.searchable` + `Section`-grouped `List`. Selection drives the center pane via SwiftUI binding; inspector controls bind to `@State` properties on each story that the center pane reads.

#### Sidebar Categories (target)

**COMPONENTS**
- Chips: Property Chip · Chip Dropdown · Property Checkbox
- Sidebar: Selectable Row · Renameable Row · Section Header · Selection Chrome
- Detail Views: Detail Row · (sort header — when sort ships v0.5.0)
- Sheets: New Item Sheet · Vault Settings Sheet · Type Settings Sheet · Icon Picker Sheet · Color Picker Sheet
- Page Editor: Blockquote · Code Block · Lists · HR · Tables (when ships)
- NavDropdown: NavDropdown Button · Entity Row · BackForward Buttons
- Item Window: (lands as Item Window redesign ships)

**FOUNDATIONS**
- Colors: PropertyChipColor palette + Apple system colors + Pommora accents
- Typography: Apple text scale × Pommora's usage (caption2 / callout / headline as Pommora applies them)
- Materials & Liquid Glass: background swatches Pommora uses (sidebar / popover / hover states)
- Symbols: live registry from `Guidelines/Symbols.md` — semantic-role → SF Symbol mapping
- Spacing: Pommora-specific spacing tokens (if any emerge)

#### Why NOT clone Interactful's full scope

Apple's [Interactful](https://apps.apple.com/us/app/interactful/id1528095640) and [SwiftUI Catalog](https://apps.apple.com/in/app/swiftui-catalog/id1597742701) already cover every generic SwiftUI primitive (Buttons / Menus / Pickers / Tables / Charts / Maps / etc.). Building those stories ourselves is duplicate work. **PommoraUIX is exclusively for Pommora-custom components + Pommora design tokens** — the leverage is in the differentiated content, not the chrome.

#### Phased Roadmap

| Phase | Scope | Trigger |
|---|---|---|
| **v0.1** ✓ | Minimal 2-pane window, 3 stories, Cmd+Shift+D | Shipped 2026-05-25 alongside v0.3.x chip work |
| **v0.2** | 3-pane layout (sidebar + center + inspector) + search + port existing 3 stories | When chip system is feature-stable |
| **v0.3** | Live parameter inspectors (sliders/toggles/pickers) for existing stories — bind controls to `@State` props the preview reads | After v0.2 |
| **v0.4** | Foundations section (Colors, Typography, Symbols, Materials) | After v0.3 |
| **v0.5+** | New Component stories ship alongside the components themselves | Ongoing |

#### Build Discipline

- **Debug-only**: every Window scene + every menu item wrapped in `#if DEBUG`. Production builds ship without it. Pommora is pre-v1 / solo-dev so this is conservative — could lift the flag later if we want a public-facing component explorer.
- **No new tests required**: stories are self-validating (visual). Existing component unit tests cover correctness. Stories serve documentation + iteration, not regression coverage.
- **No backend / data dependencies**: stories use ephemeral `@State` only. Never touch managers, never write to disk, never depend on a loaded Nexus. The window opens with no Nexus + works fine.
- **One story per file** (as catalog grows): `Pommora/Pommora/ComponentLibrary/Stories/<Component>Story.swift`. Library `ComponentLibraryView` becomes a thin router over the Story registry.

#### Open Questions for v0.2

1. Inspector parameter controls in same v0.2 ship or v0.3?
2. Search affordance worth it at ~10 stories, or wait until ~20+?
3. `WindowGroup(for: StoryRef.self)` vs single `Window(id:)` for spawning isolated story windows (useful for side-by-side comparison)?
4. Copy-code-to-clipboard button per story?
5. Story-level screenshot export (for design reviews)?

#### Document Map

- This file: `.claude/Features/PommoraUIX.md` — feature spec, evergreen
- Code home: `Pommora/Pommora/ComponentLibrary/` — story implementations
- Window scene: `Pommora/Pommora/PommoraApp.swift` (Debug menu + `Window(id: "component-library")`)
- Cross-references: each Pommora component file references its story in the component's doc comment when both exist

#### Versioning

PommoraUIX has its own version line independent of Pommora-app versions (no semver discipline needed — it's a debug surface). Track major bumps (v0.1 → v0.2 → v1.0) in this doc's "Current State" section as ships happen.
