# Design-System Showcase Shell — Design

## Purpose

Turn the design-system showcase from three separate single-page builds (the
`DesignSystem` scroll page, the Interaction Lab, the CSS Glass Editor) into **one
navigable site** with a sidebar that mirrors Pommora's glass sidebar. Each sidebar
**leaf** showcases one design-system surface (colors, type, icons, chips, glass,
interactions) by importing the *real* source modules — the showcase is the
iteration surface for components before they enter the live app, never a copy of
them.

This is the container/system. Building the individual shippable components
(`Button`, `Label`, `Menu`, `Separator`, `Row`) is downstream work that lands as
new leaves inside this shell.

## Architecture

### Shell

`main.tsx` mounts `<Showcase />` instead of `<DesignSystem />`. The shell lays out
a glass sidebar on the left and a content pane on the right, mirroring the app's
`shell → surface-glass → content-pane` structure. The current monolithic
`DesignSystem.tsx` is **decomposed** into one focused module per leaf; the shared
render helpers it defines (the computed-style reader, the swatch/type renderers)
move to the leaves that use them or a small `showcase/_shared.tsx`.

### Routing — hash-based

A `useHashRoute()` hook is the only routing mechanism: it reads `location.hash`,
subscribes to `hashchange`, and returns the active leaf id (falling back to the
first leaf when the hash is empty or unknown). Selecting a leaf sets `location.hash`.
No router dependency — every leaf gets a shareable URL, survives refresh, and the
browser back/forward buttons work.

### Leaf registry — single source of truth

`leaves/registry.tsx` exports the ordered list of leaf definitions. Each entry
carries an `id`, a display `label`, an `icon` (a symbol-registry name), a `section`
(one of a small fixed `SectionId` union), and a `render` thunk. The sidebar renders
from this list grouped by section; the content pane finds the active leaf by id and
calls its `render`. **Adding a component to the showcase is one registry entry plus
one leaf module — nothing else changes.** The `SectionId` union is exhaustive and
switched on, so an unhandled section is a compile error, not a silent gap.

### Sidebar — visual mirror

`ShowcaseSidebar.tsx` reuses the shared `GlassSurface` material as the floating
inset panel (the identical glass to the app) and reproduces the app's section-header
+ selectable-row visual language. The active leaf renders in the selected-row state.
The collapse toggle (the sidebar's signature interaction) is mirrored; drag-resize
is **not** — a fixed-width nav is correct for a showcase.

The sidebar's nav styling is authored in the showcase stylesheet against the token
layer; it does **not** import the app renderer's `styles.css`, which would couple
the showcase to the app shell's layout and risk regressing the live app. When a
shared `Row`/sidebar primitive is later built in `components/`, both the app and
this showcase consume it — that unification is separate, downstream work.

### Mobile — top-right glass dropdown

Below a narrow breakpoint the sidebar is hidden and a top-right glass button (the
same `GlassSurface`) toggles a dropdown listing the **same registry leaves**.
Selecting one sets the hash and closes the menu. The swap is a CSS media query; the
leaf list is never duplicated.

### Intertwining the interaction library

Leaves where reordering reads as a real demo apply the in-house DnD engine via the
`interactions` seam (`Zone` / `useZoneItem` / `reorder`):

- **Colors** — the swatch grid is a reorderable gallery (grid reflow).
- **Chips** — a reorderable row.
- **Icons** — stays a static reference grid (reordering dozens of icons is noise).
- **Interactions** — the full existing Lab, folded in unchanged.

Reordering is ephemeral showcase play: it resets on reload, matching the existing
glass-drag and accent-swap demos.

## Module boundaries

Each unit has one purpose, a clear interface, and is understandable in isolation:

- `Showcase.tsx` — shell layout + wires `useHashRoute` to sidebar + content. Depends
  on the registry and the sidebar; knows nothing about any individual leaf's internals.
- `useHashRoute.ts` — pure hash↔state hook. No knowledge of leaves.
- `leaves/registry.tsx` — the leaf catalog. The only place the full leaf set is known.
- `ShowcaseSidebar.tsx` — renders nav from a leaf list + active id + a select
  callback. Pure presentation; no routing logic of its own.
- `leaves/*Leaf.tsx` — one per leaf; each imports the real design-system source it
  showcases. A leaf can change without touching the shell, the registry shape, or
  other leaves.
- The folded-in labs (`Interactions`, `GlassEditor`) are wrapped by thin leaf modules
  rather than modified.

## Data flow

`location.hash` → `useHashRoute` → active leaf id → shell looks the id up in the
registry → renders that leaf's `render()` into the content pane. Sidebar (and mobile
dropdown) selection writes `location.hash`, closing the loop. No app store, no IPC —
the standalone browser build has neither.

## Reused vs. new

**Reused (imported, never copied):** `tokens` (color/type/chip), `symbols`
(`Icon`/`icons`), `materials` (`GlassSurface`), `interactions` (`Zone`/`useZoneItem`/
`reorder`), the existing `Interactions` lab, the existing `GlassEditor`, `GlassStage`,
and the accent demo logic.

**New:** the shell (`Showcase.tsx`), `useHashRoute.ts`, `leaves/registry.tsx`,
`ShowcaseSidebar.tsx` (+ mobile dropdown), the per-leaf modules, and the showcase nav
CSS. The `design-system.html` entry now mounts the shell. The `interactions.html`
and `glass-editor.html` entries are kept as direct-access URLs — their components are
folded into leaves, so the standalone entries cost nothing and the shell is the
canonical home.

## Leaf taxonomy

- **Foundations** — Colors (with the live accent picker), Typography, Icons
- **Components** — Chips *(Button, Label, Menu, Separator, Row land here as built)*
- **Materials** — Glass, Glass Lab *(the folded-in CSS editor)*
- **Interactions** — Interaction Lab *(the folded-in lab)*

A leaf moves between sections by changing its `section` field — the grouping is data,
not structure.

## Out of scope (YAGNI)

Sidebar drag-resize; persisting leaf/collapse/reorder state across reloads;
building the actual `Button`/`Label`/`Menu`/`Separator`/`Row` components (separate
downstream tasks); any shared app↔showcase Row primitive extraction.

## Verification

- `useHashRoute` and registry integrity (every leaf id unique; every `section`
  in the union) get light unit tests under the existing Vitest setup.
- `npm run typecheck:web` and `npm run build:showcase` stay green.
- Visual confirmation in `npm run showcase` is the final gate (Nathan verifies):
  sidebar mirrors the app glass, leaves route by hash, galleries reorder, mobile
  dropdown swaps in at the breakpoint.

## Folder layout + where future components land

| Folder | Holds | Showcase leaf |
|---|---|---|
| `tokens/` | color / type / chip / theme-var tokens (source of truth) | Colors, Typography |
| `symbols/` | Lucide icon registry (`Icon`, `icons`) | Icons |
| `materials/` | glass: `GlassSurface`, `GlassControls`, `EdgeLens` | Glass, Glass Lab |
| `interactions/` | in-house DnD engine + behaviors | Interactions + galleries |
| `components/` | **README-only today** — `Button` / `Label` / `Menu` / `Separator` / `Row` | one leaf each |
| `showcase/` | the shell + leaves (this design) | — |
| `glass-editor/` | CSS glass research tool | folded in as Glass Lab |

Each future component is a new file in `components/` (`.tsx`, or `.css.ts` when
token-bound like `chip.css.ts`), plus one registry entry and one leaf under
**Components**. It is iterated in this showcase until ratified, then the *same* file
is imported by the live app — never re-implemented.
