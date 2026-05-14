### Sidebar

The leading-edge navigation pane in Pommora's three-pane shell. Contains three top-level headings (Spaces / Saved / Collections) with disclosure-style expansion. Structural detail and entity-routing rules live in `Domain-Model.md`; this file documents the sidebar's **visual and selection behavior**.

The sidebar's selection language is one of Pommora's load-bearing design decisions — deliberately distinct from SwiftUI's default and aligned with **Mail**, **Finder**, and the **macOS 26 file picker**, not Settings.app.

---

#### Selection behavior

Selection on a sidebar row uses a **brightness-shift background** + **accent foreground**, not an accent-color fill. This applies to every selectable row in the sidebar tree (Spaces, Saved items, Collections, Collection members).

##### Visual treatment

| Element | Selected | Unselected |
|---|---|---|
| Row background | Subtle gray fill (Apple's `unemphasizedSelectedContentBackgroundColor`) | Transparent |
| Row icon | Accent color | Primary (adapts to appearance) |
| Row text | Accent color | Primary (adapts to appearance) |

The gray fill comes from Apple's named semantic color for "selected content that doesn't shout for attention" — the same color Mail and Finder use as their always-on selection. Selection contrast comes from the **foreground color shift** (icon + text turning accent), not from the background fill itself.

##### What this is explicitly not

Pommora's sidebar selection rejects the **accent-color fill** pattern used by Settings.app and SwiftUI's default `List(selection:) + .sidebar`:

| Element | Settings pattern (rejected) | Pommora pattern |
|---|---|---|
| Background | Solid accent fill | Subtle gray fill |
| Icon | White (high-contrast on fill) | Accent color |
| Text | White (high-contrast on fill) | Accent color |

The accent-fill pattern is visually loud — bright colored bars dominate the sidebar even for transient selection. Pommora's pattern reads as understated; the eye is drawn to the foreground tone shift, not a hard color block.

---

#### Light and dark mode

Selection styling is appearance-aware throughout. No mode-specific overrides needed:

- **Gray fill** — `unemphasizedSelectedContentBackgroundColor` renders different values in light vs. dark mode automatically. In light mode it's a faint darker-than-sidebar gray; in dark mode it's a faint lighter-than-sidebar gray (the brightness-raise Nathan asked for).
- **Accent foreground** — `Color.accentColor` resolves to the current accent. Xcode's default (system blue) stands in for v0.0–v0.x; replaced by brand purple after design lock.
- **Primary foreground** (unselected) — `Color.primary` renders black in light mode, white in dark mode.

The selection adapts cleanly to the user's macOS appearance preference and, eventually, to the brand accent override (Settings, v0.12).

---

#### Implementation pattern (brief)

Achieved with two modifiers — one on the List, one per-row. The List's selection background color is set via `.tint(Color(nsColor: .unemphasizedSelectedContentBackgroundColor))`; each row's foreground is conditionally set to `.accentColor` when selected and `.primary` otherwise. No custom row rendering needed for v0.1.

If the system's hover treatment proves wrong (see *Hover* below), the fallback is a fully custom row-rendering approach — same visual rule, different mechanism.

---

#### Hover — deferred

The sidebar's hover treatment isn't fully resolved. SwiftUI's `List(selection:)` exposes limited hover customization.

**Intent**: hovered (but unselected) rows show an even subtler gray fill — roughly half the opacity of the selected-row fill. This gives the sidebar a third visible state (idle / hovered / selected) without introducing new colors.

**Reality**: pending visual verification once rows actually populate the sidebar (v0.1+). If the system default hover is too subtle or absent, the workaround is custom row rendering. Treated as polish, not blocking.

---

#### Keyboard navigation — deferred

Up/down arrow navigation through sidebar items lands with the v0.1 sidebar (folder mirroring). Specifics — focus-ring styling, traversal across disclosure-group boundaries, keyboard shortcuts for expand/collapse — resolve at that point. The selection-styling rule applies regardless of how selection is triggered (mouse, keyboard, programmatic).

---

#### Why this exists

The sidebar is Pommora's primary navigation surface — every workflow starts here. The default SwiftUI sidebar selection is visually **loud**: accent-fill backgrounds dominate the sidebar with bright colored bars even for transient selection. This works for Settings.app where each row is a destination commitment, but feels wrong in a notes/database app where users select and re-select rapidly across many items.

Mail and Finder solve this with a quieter selection language — subtle gray fill that doesn't draw the eye, with foreground color shift providing the contrast. The selection is **legible without being noisy**.

This restraint pairs with Pommora's broader design intent: **chrome should be supportive, not assertive**. The single-row navigation bar already commits to minimal chrome; the sidebar's selection language matches that restraint. The two decisions reinforce each other — together they produce a window that reads as content-forward, with the structural pieces visible but never competing for attention.
