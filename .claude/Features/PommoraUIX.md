### PommoraUIX — In-App Design System Explorer

A debug-only window inside Pommora that explores every Pommora-custom UI component + design token, three-pane Interactful-style. Lets Nathan see how each Figma component translates to live SwiftUI, tweak parameters in real time, copy code, and verify cross-component consistency without leaving the app.

#### Scope

This is **separate from any feature ship** — an evergreen debug surface that grows alongside Pommora's component catalog. Builds incrementally — new galleries land alongside the components they cover.

It lives in a single component-library view (router + galleries) plus the app's Debug menu, which exposes a `Cmd+Shift+D` shortcut and a window scene gated `#if DEBUG`.

#### Target Vision

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

Right column uses `.inspector(isPresented:)` (macOS 14+); the sidebar is a searchable section-grouped list. Selection drives the center pane via SwiftUI binding; inspector controls bind to `@State` properties on each gallery that the center pane reads.

#### Why NOT clone Interactful's full scope

Apple's [Interactful](https://apps.apple.com/us/app/interactful/id1528095640) and [SwiftUI Catalog](https://apps.apple.com/in/app/swiftui-catalog/id1597742701) already cover every generic SwiftUI primitive (Buttons / Menus / Pickers / Tables / Charts / Maps / etc.). Building those galleries ourselves is duplicate work. **PommoraUIX is exclusively for Pommora-custom components + Pommora design tokens** — the leverage is in the differentiated content, not the chrome.

#### Current State

A two-pane component explorer — a Components + Foundations sidebar over a category list — opened via `Cmd+Shift+D` (gated `#if DEBUG`). Several galleries are live; the rest are placeholders building toward full coverage, all in one library view. It advances toward the Target Vision incrementally — the third pane + search, then live parameter inspectors, then a fuller Foundations section (Colors / Typography / Symbols / Materials) — with new galleries landing alongside the components they cover. It grows with the catalog, no version gates.

#### Build Discipline

- **Debug-only**: every Window scene + every menu entry wrapped in `#if DEBUG`. Production builds ship without it. Pommora is pre-v1 / solo-dev so this is conservative — could lift the flag later if we want a public-facing component explorer.
- **No new tests required**: galleries are self-validating (visual). Existing component unit tests cover correctness. Galleries serve documentation + iteration, not regression coverage.
- **No backend / data dependencies**: galleries use ephemeral `@State` only. Never touch managers, never write to disk, never depend on a loaded Nexus. The window opens with no Nexus + works fine.

#### Open Questions

1. Spawning isolated windows per gallery for side-by-side comparison vs the single shared window.
2. Copy-code-to-clipboard button per gallery.
3. Gallery-level screenshot export (for design reviews).

#### Document Map

- This file: `.claude/Features/PommoraUIX.md` — feature spec, evergreen
- Code home: the component-library directory — gallery implementations
- Window scene: the app entry's Debug menu + component-library window
- Cross-references: each Pommora component file references its gallery in the component's doc comment when both exist
