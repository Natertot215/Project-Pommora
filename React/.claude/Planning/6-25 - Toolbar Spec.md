## Toolbar — React Build Spec (6-25)

Porting the Swift content-view toolbar buttons into the React build: two floating glass button clusters in the top window chrome, built off the Figma **Large icon-segmented control**. The Swift reference is `Pommora/Pommora/Features/Toolbar/` (`BackForwardButtons`, `NavigationButton`, `ViewSettingsButton`, `ToolbarGlyph`).

This pass builds the **chrome + buttons + placeholder panels**, and lands the **Segmented-Controls component family + a size-token system** underneath them. The data backends the buttons ultimately drive (navigation history, recents/pinned, per-view settings, the frontmatter inspector) don't exist in the React store yet — they're scoped here as follow-ups, not built.

### Goal & Scope

**Two clusters, both the Large icon-segmented control with glass behind it:**

- **Back/Forward** — 2-segment control, `chevron-left` │ `chevron-right`, top-leading.
- **ToolbarTrio** — 3-segment control, top-trailing: **Navigation** (`map`) │ **Settings** (`sliders-horizontal`) │ **Inspector** (`panel-right`).

ToolbarTrio order follows Nathan's listing (Navigation → Settings → Inspector), not Swift's (which leads with Settings).

The **Views** dropdown (Swift's 4th pill, conditional on container views) is **out of scope** — not part of this task.

### Decisions (ratified 6-25)

- **Glass, not fill.** Both clusters use the Figma `Fill=None` variant (transparent container) with `GlassControls` as the background — the `glass-controls` material. The per-segment fills in Figma (Tinted/Primary/…) are not used.

- **No active / pressed / selected state.** Open or clicked looks identical to idle — Apple toolbar behavior. No segment fill on toggle-on (Navigation/Settings popover open, Inspector on). The only interactive feedback is a faint `state.hover` highlight on hover (flagged for the visual pass — kill it if even that reads as too much).

- **No keyboard shortcuts.** Swift's ⌘[ / ⌘] / ⌘T / ⌥⌘0 are dropped. None ship without Nathan's explicit per-shortcut sign-off.

- **Back/Forward: buttons first, wiring later.** The segments render this pass but are inert (disabled). The history stack that makes them work is scoped below, built in a follow-up.

- **Inspector: real toggle, empty panel.** The button opens/closes a real (empty) inspector pane that slides in trailing; content is filled later.

- **Sizes are token aliases, per-component.** A control's size is a named alias (`button-small` / `button-medium` / `button-large`) that routes to a geometry bundle in the size-token file — the way a color name routes to `color.css.ts`. Per-component naming (not a shared `small/medium/large`) is the chosen model: explicit and self-documenting at the call site. Maps 1:1 to Figma's Small / Medium / Large.

- **Icon sizing is tokenized too (full DRY).** Raw `size={N}` literals are replaced by a named icon-size scale routing to the same size-token file. New code uses named sizes immediately; the sweep of existing call sites is a follow-up (scale locked 6-25 — see Follow-ups).

- **New regions are top-level**, organized by window region like the existing tree: `Toolbar/` and `Inspector/` sit beside `Sidebar/` and `Detail/`. Reusable controls are design-system components.

### Component Architecture

#### `design-system/components/Segmented-Controls/` — new component family

Mirrors the Figma Segmented Control family (one folder, per Design.md's "components mirror the Figma library"). Scoped to segmented controls (a plain non-segmented Button gets its own folder later if needed). Holds the two segmented variants, sharing one `Segmented` core that differs only in segment content:

- **`SegmentedSymbol`** — icon-only segments (what the toolbar uses).
- **`SegmentedButton`** — icon + label segments (same geometry + dividers + glass; label variant of the same core).

Each consumes **semantic tokens only** — the size aliases for geometry, `separator.segment` for dividers, `label.primary` for content, and `GlassControls` for the background. Driven by a segment list (`{ icon, label?, onClick, disabled?, active? }`); `size` is a `button-*` alias. `active` is accepted but renders nothing yet (kept as an opt-in seam, honoring the no-active-state decision). Figma's Segmented-Label variant can join this folder later on the same core.

Structure of one segmented control (from Figma **SEGMENTED · SYMBOL**, `fileKey fYZ5oiK7stC3diRhaBHl1r`, Large/None/3-seg node `587:2413` — exacts live in the size tokens + Figma, not this doc): a `GlassControls` container (`overflow-clip`) wrapping rounded segments separated by `2px` `separator.segment` dividers; one divider between adjacent segments, none at the ends.

#### `tokens/size.css.ts` — new size-token module

Vanilla-extract, sibling to `color.css.ts` / `typography.css.ts` (compile-time-safe vars + a typed object). Two scales:

- **Control-size aliases** — `button-small` / `button-medium` / `button-large`, each a geometry bundle: container height, segment height, padding-x, container radius, segment radius, divider width/height, and an icon-size reference. Values come from Figma's Small / Medium / Large symbol variants. A component takes `size="button-large"` and pulls the bundle.

- **Icon-size scale** — five fixed steps replacing raw `size={N}`: `icon-xs 12` · `icon-sm 14` · `icon-md 16` · `icon-lg 18` · `icon-xl 20` (locked 6-25). The control-size bundles reference these so a segment's icon follows its control size automatically.

Bridged into `theme-vars.css.ts` only if a plain-CSS consumer needs a step; vanilla-extract components read the typed `vars` directly.

#### `Icon` named-size support

`design-system/symbols/index.tsx` `Icon` gains a named size routing to the icon-size scale, keeping the `1em` default (text-flow icons) and a numeric escape hatch. New toolbar/buttons code uses named sizes.

**The detail-title icon stays type-bound** — it tracks the page-title type token (`--detail-title-size`), so leave it coupled to type. The MarkdownPM **heading-fold chevron snaps onto the ladder** (per Nathan): `--fold-chevron-size` rebinds from `var(--text-title3-size)` (15px) to **`icon-md` (16)**, the nearest step. The rebind rides the icon sweep.

#### `Toolbar/` — new top-level region

Composes two `SegmentedSymbol` instances at `size="button-large"` and places them in the top chrome.

- **BackForward** — 2-segment instance, both segments disabled this pass.
- **ToolbarTrio** — 3-segment instance: Navigation + Settings open popovers (stubs); Inspector toggles the inspector region.

#### `Inspector/` — new top-level region

The trailing window pane — the structural twin of the leading `Sidebar/`. This pass: an **empty** glass panel that slides in/out from the right when the Inspector segment toggles. Width in the Swift range (~240–320). Content (frontmatter → properties → page info) is a follow-up.

#### `Popover` — new minimal primitive (needed, doesn't exist yet)

React has **no** popover/anchoring primitive (the `menu/` component is rows + separators only, no positioning). The Navigation and Settings panels need one: a `GlassSurface`-backed panel anchored under its trigger, dismiss on outside-click / Esc. Build it minimal and reusable — it's one of the "real DS Components" already pending, and both stub panels consume it. The stub panel bodies are empty placeholders this pass.

### Icons

Add `panel-right` to the icon registry (`design-system/symbols/index.tsx` + `Symbols.md`). `map`, `sliders-horizontal`, `chevron-left`, `chevron-right` are already registered; `panel-left` is present (`panel-right` is the inspector glyph).

### Placement & Electron Drag

The window is frameless (`titleBarStyle: 'hidden'`, `src/main/index.ts`); the existing `.titlebar` strip already carries `-webkit-app-region: drag` ([styles.css](React/src/renderer/src/styles.css)) so the top edge moves the window — an Electron/Chromium mechanism (**not** Swift), the same one the sidebar already uses. These two clusters are the **only persistent toolbar items**, always in view regardless of selection — BackForward leading (clear of the traffic lights), ToolbarTrio trailing. Because they sit in that strip, each control sets `-webkit-app-region: no-drag` (exactly as the sidebar buttons do, e.g. `Sidebar.css`) so clicks register. Mirrors Swift's leading / trailing split.

### Build This Pass

1. `tokens/size.css.ts` — `button-*` control-size aliases + the icon-size scale (steps per Nathan).
2. `Icon` named-size support routing to the icon scale.
3. `panel-right` icon registered.
4. `design-system/components/Segmented-Controls/` — `SegmentedSymbol` + `SegmentedButton` on a shared core (glass, dividers, hover-only, `size` alias).
5. Minimal `Popover` primitive (glass surface, anchored, dismiss).
6. `Toolbar/` region: BackForward (inert) + ToolbarTrio, placed top chrome with `no-drag`.
7. Navigation + Settings → open empty stub popovers.
8. `Inspector/` region: empty glass pane; Inspector segment toggles it.

### Scoped Follow-ups (not this pass)

- **Icon call-site sweep** — migrate existing `size={N}` usages (App, Sidebar, Banner, Autocomplete, showcase) to the named icon-size tokens. Scale locked: `icon-xs 12 · icon-sm 14 · icon-md 16 · icon-lg 18 · icon-xl 20`. Includes rebinding the MarkdownPM heading-fold chevron `--fold-chevron-size` to `icon-md` (16), and the **table grips** (`GripHorizontal`/`GripVertical` at 14), which currently bypass the curated registry by importing straight from `lucide-react` — fold them in too: add `grip-horizontal`/`grip-vertical` to the registry and route through `<Icon>`. Inventory captured.

- **Back/Forward history** — a selection-history stack in the store: push on navigate, cursor stepping, suppress re-push while stepping (the Swift `RecentsManager` cursor pattern, minus recents/pinned). Enables the buttons + their end-of-stack disable.

- **Navigation panel content** — Pinned / Recents lists. Needs React equivalents of `RecentsManager` + `PinnedManager` (neither exists).

- **Settings panel content** — per-view settings that swap by selection scope (collection/set view settings; future page property-pulldown). Needs the React per-view settings surface.

- **Inspector panel content** — frontmatter / properties inspector (the Swift `FrontmatterInspector` analogue).

### Open for the Visual Pass

- Whether the faint hover highlight stays (Apple keeps it; Nathan may want zero feedback).
- Final icon size on the Large segment (`icon-lg` 18 or `icon-xl` 20 — pick in the visual pass).
- Cluster offsets/margins in the top chrome relative to the traffic lights and sidebar edge.

### Logistics

- Implementation runs in the `pommora-react` worktree, merged to `main` when done.
- Per-task green commits; a live UIX pass with Nathan before closeout (functional-green ≠ done).
