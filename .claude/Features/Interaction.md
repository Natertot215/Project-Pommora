## Interaction & Motion

The single home for the React build's animation system: the motion token vocabulary, the named animation aliases, the shell's one-progress driver, the expand/collapse primitive, and the per-surface motion catalog. Drag-specific motion (the reorder "feel", insertion line, auto-scroll) lives in [[PommoraDND]] and is only cross-referenced here. Code holds the exact values; this doc names the system and the canonical decisions. Motion is **Pommora-native, inspired by Apple** — adopted only when it deepens the minimalism, never when it clutters it.

### Motion Tokens — The Shared Vocabulary

The single source is `design-system/tokens/motion.ts`, surfaced as CSS vars through `tokens/theme-vars.css.ts`. Every permanent transition references these, not literals.

- **Durations:** `disclosure` (chevron + disclosure open/close, app-wide — sidebar `.twisty`, the `Reveal` primitive, the editor fold; `--disclosure`) · `fast` (quick hover / affordance feedback — grips, button hovers) · `dropdown` (the inline picker + autocomplete open/close — the Bloom keyframes at a snappier pace) · `base` (the shell slides — sidebar + inspector + the reflow that tracks them) · `slow` (the menu Bloom open/close). CSS: `--disclosure` / `--duration-fast` / `--duration-dropdown` / `--duration-base`.
- **Easings:** `standard` (everyday `ease`) · `out` (`cubic-bezier(0.22, 1, 0.36, 1)` — emphatic moves, also the drag "out" curve). CSS: `--ease-standard`.
- **Bloom curve** (Pommora-native, Apple-inspired) — `cubic-bezier(0.32, 0.72, 0, 1)` — is the open + close curve for both dropdown motions (the menu **Bloom** + the inline **Dropdown**, below), which share one set of keyframes; it's special-cased as the lone literal in `animations.css.ts` rather than living in the everyday token set.

Spacing / radius / shadow / z-index scales are still partly ad-hoc literals pending a Figma lift; the **shadow** standard is the exception — one `--shadow-standard` token (`tokens/color.css.ts`) feeds every frost surface (see [[Resources/II. Pommora/II. Features/Design]]).

### Named Animations

There are **two** dropdown motions, and they're the same animation at two speeds: both reuse the one `@keyframes dropdown-menu` (open) + `dropdown-menu-out` (close) pair and the one **Bloom curve** in `design-system/animations.css.ts` — they differ only in which duration token they run.

#### Bloom

Pommora's canonical pane/menu open — a zoom-from-the-trigger (`scale → 1` + fade on the Bloom curve, no blur), inspired by Apple's popover motion but Pommora-native. The `dropdownMenu` / `dropdownMenuClosing` classes run the shared keyframes on the **`slow`** token, **symmetric** (open + close match), so a click-off **retracts** the pane instead of cutting it; the parent keeps it mounted through the exit via the shared **`useExitPresence`** hook (`design-system/useExitPresence.ts`, whose default exit window covers this slowest close). The origin point is the consumer's: the class reads `--dropdown-origin` (defaults `top center`) so the pane blooms from its own trigger. This is the **menus'** motion; the inline picker + autocomplete take the snappier `dropdown`-token variant (below).

- **Consumers:** `MenuSurface` (the toolbar Navigation + Settings panels, `--dropdown-origin: top right`) and the `IconPicker` (centered `GlassPane`, origin `center`).

#### Dropdown

The same zoom — the same keyframes + Bloom curve — mounted on the **`dropdown`** token instead: snappier than the menu Bloom, also **symmetric**. The `dropdownOpen` / `dropdownClose` classes (`animations.css.ts`) read the same `--dropdown-origin` and retract through the shared `useExitPresence`. The split is deliberate: menus get the deliberate Bloom, inline surfaces the quicker Dropdown.

- **Consumers:** the inline-edit `PickerMenu` (frost `GlassPane` clipped to a notch beak; origin = the notch tip) — mounted by the table's cell value picker (`PropertyPicker`, the status/select/multi dropdown, anchored in the editing cell and retracting through the shared presence hook) — and the `AutocompletePanel` (wikilink autocomplete, `top left` — grows from the caret; retains its last position/rows so it can retract in place after the query clears).

- **Note:** liquid `GlassControls` (the autocomplete) re-samples its refraction per frame, so the zoom reads slightly less crisp mid-flight than on the frost panes — timing/scale are identical.

#### Caret Blink

The drawn editor caret (and native-field overlay) fades on a symmetric on/off cycle via twin keyframes (`mdpm-blink` / `mdpm-blink2`) in `Carets.css`; `editor/caret.ts` swaps the keyframe name on selection change to restart the cycle without reflow. Tunable via `:root` knobs (`--caret-width` / `--caret-color` / `--caret-gap` cycle / `--caret-dim` dip — `dim:1` = solid, no blink). Extending the drawn caret to table cells + the inline-rename input is outstanding.

#### Header Scroll-Park

The page banner/title zone slides up under the toolbar as you scroll — a **scroll-timeline** animation (`mdpm-header-park`, `MarkdownPM/Styles.css`) bound to the `.cm-scroller` timeline, ranged over `--header-zone` (the live header height, set by a ResizeObserver in `MarkdownPM/index.tsx`). Compositor-driven, zero JS lag, no duration (scroll-linked).

### The `--io` Progress — The Shell's One Motion Driver

A single registered `@property --io` (`<number>`, 0 = closed → 1 = open, `styles.css`) transitions once on `--duration-base`/`--ease-standard` and drives the **entire** inspector open/close in lockstep: the inspector slide (`InspectorPanel` reads `--io`, carries no transition of its own), the content-inset reflow (Detail body / editor / subfield padding), the toolbar **trio "swallow"** (the pill rides the pane edge via a gated `max()` so it holds home until the inspector reaches it), and the trio's **glass void** (the pill's glass fades over the first fraction of the ramp while the bare icons stay solid). `.shell.is-resizing` sets `transition: none` for 1:1 cursor tracking during an edge-drag. The **sidebar collapse** is a sibling `transform` slide on the same base token.

**Why the glass voids as a two-layer pill, not a fade:** liquid glass can't be CSS-faded in place (its `backdrop-filter` displacement is a generated SVG-filter id CSS can't interpolate), so `Toolbar/ToolbarTrio` is a fading glass layer behind a solid bare-button layer. Full rationale → [[Resources/II. Pommora/II. Features/Design]] + History.

### Reveal — The Expand/Collapse Primitive

`design-system/components/Reveal.tsx` is the canonical body open/close: a `grid-template-rows: 0fr ↔ 1fr` transition on the `disclosure` token / `easing.standard`, mounting at 0fr then flipping on the next frame, and unmounting on `transitionend`. It (or the same `grid-template-rows` pattern) backs the sidebar nested trees and the heading-fold body (`.mdpm-fold-reveal`). Disclosure **chevrons** rotate 90° on `--disclosure` (sidebar `.twisty`, editor fold `::before`); the drag-engine's tree collapse + `.ix-caret` ride the drag feel (`--ix-dur`) instead, separate by design.

### Pane Slide + Resize

`Components/Detail/PaneSlider.tsx` is the View Settings detail-pane navigator: a two-slot horizontal track (root ↔ detail) where the **slide and the width+height resize run on the one shared `--duration-base`/`--ease-standard`**, so the horizontal move and the box reshape land on the same frame. Both slots stay mounted (each measured by a `ResizeObserver`) so the target size is known the instant the active slot flips; a `minHeight` floor keeps a sparse pane from collapsing, and footer actions pin to the bottom (`margin-top: auto`) so they hold their edge as the pane grows. Transitions arm only after first paint (so a pane snaps to size on open instead of growing from zero).

### Switch

`design-system/components/Switches/` — the knob slides between its on/off ticks and the ticks cross-fade, both on `--duration-fast`; the track tint also crossfades on the same beat. One `ease` const drives all three so the toggle reads as a single move.

### Drag Motion

Owned by the in-house engine — see [[PommoraDND]]. In brief: a live "feel" (duration + easing) shared across every surface via `--ix-dur`/`--ix-ease` (presets Glide / Smooth-default / Snappy, `interactions/feel.tsx`); **decide-then-animate** (the accept/reject is resolved first, then one transition settles the item, committing on `transitionend`); a quadratic edge-proximity **auto-scroll** ramp (`interactions/autoscroll.ts`, rAF). The **sidebar** uses a bespoke insertion-line treatment (muted row in place + a portal-rendered ghost), and the **editor block-drag** has its own chrome (in-place shade decoration + a `position:fixed` accent line/dot + edge auto-scroll, `editor/blockDrag.ts` + `dragChrome.ts`) — all positioned 1:1 with the pointer, not timed.

### Per-Surface Catalog

- **Sidebar** (`Sidebar/Sidebar.css`): row hover + section "+" reveal + the collapse/expand button (fade + `translateX`); twisty rotate on `--duration-fast`. Row/section hovers run a faster hardcoded `120ms` (see inconsistencies).
- **Editor** (`MarkdownPM/Styles.css`): fold chevron rotate + fade and the block/blockquote **grip reveal** (hover opacity) on `--duration-fast`; fold body via the Reveal pattern; banner/editor padding reflow on `--duration-base`.
- **Subfield** (`Detail/Subfield/subfield.css`): the footer bar height-reveal + its toggle chevron ride on `--duration-base`.
- **Banner** (`Detail/Banner/Banner.css`): title inset slide on `--duration-base`; "Add Banner" hover reveal.
- **Menus** (`menu.css.ts` / `menuSurface.css.ts`): row hover is an instant state swap (no transition); the surface **opens** with the Bloom (`dropdown-menu` keyframes on the `slow` token) and **retracts** with `dropdown-menu-out` on click-off.
- **Modals / pickers:** `PhotoCropModal` is imperative (pointer-tracked, no timed motion); `IconPicker` is a stub awaiting its Figma design + a shared dropdown-open primitive.

### Duration Inventory & DRY Backlog

Every motion-timing value in the app — CSS `ms`/`s` strings (grepped) **and** the JS-driven timing a string-grep misses (numeric durations, `transitionend` fallbacks, rAF ramps; deep-audited). The **canonical** sources stay; the **hardcoded CSS** ones should migrate to the `motion.ts` tokens (or a justified new token) in a dedicated DRY pass. The `transition: none` on `.shell.is-resizing` is intentional, not a gap.

**Canonical (keep — these ARE the sources):**
- `tokens/motion.ts` — the duration scale (`fast` / `disclosure` / `dropdown` / `base` / `slow`) + easings; the menu Bloom runs `slow`, the inline Dropdown runs `dropdown`.
- `interactions/feel.tsx:13-15` — the drag feel presets (Glide 340 / Smooth 230 / Snappy 130) — numeric, the engine's source.
- `design-system/animations.css.ts` — the shared `dropdown-menu` / `dropdown-menu-out` keyframes + the Bloom curve; durations come from `motion.ts` tokens (no literal ms here — the Bloom curve is the one special-cased literal).

**Engine timing (JS-driven, intentional — keep local, not a DRY gap):**
- `interactions/shared.ts:28` — `SETTLE_FALLBACK = 80` (ms slack); the drag commit fires on the overlay's `transitionend`, falling back to `feel.duration + SETTLE_FALLBACK` (`engine.tsx:284`, `group.tsx:216`) — decide-then-animate, not a blind timer.
- `interactions/autoscroll.ts:5-6` — `EDGE = 48`px / `MAX = 14`px-per-frame, quadratic proximity ramp (rAF). Motion *tuning*, not a duration.
- `transitionend` commits (no literal duration): `engine.tsx:283`, `group.tsx:201`, and the fold reveal `MarkdownPM/editor/folding.ts:164`.
- No other WAAPI/spring anywhere (the temporary `DropdownAnimationLab` + ⌘D `GlassTuner` were removed once the Bloom curve was chosen).

**Hardcoded CSS — migrate (permanent surfaces):**
- `Sidebar/Sidebar.css:55` (row hover) + `:141` (section "+" reveal) — the `120ms` snappy-hover pair; no matching token (decide: adopt `--duration-fast` or add a `snappy` token). (`:93` expand-button hover already hoisted to `--duration-fast`.)
- `Detail/Banner/Banner.css:88` ("Add Banner" hover — also a literal `ease`, not the token)
- `MarkdownPM/Styles.css:676`
- `MarkdownPM/Tables/widget.css:50` + `:70` (widget opacity/transform)
- `MarkdownPM/editor/folding.ts:89`
- `design-system/components/switch.css.ts:20` + `:34` (the Switch toggle)
- `interactions/interactions.css:255` + `:267` (the `--ix-dur` fallback literal)
- `Carets.css:12` (the caret-cycle default — arguably a tunable knob, low priority)

**Showcase / demo only (lowest priority — not app chrome):**
- `design-system/showcase/showcase.css:185` · `:245` · `:279` · `:359`
- `design-system/interactions/Surfaces.tsx:163` (+ `:166`, a 300ms async-reject *demo* promise)

**Not motion (exclude):** `Detail/PageView.tsx:34` + `:35` (400ms autosave + 120ms live-update **debounces**, not transitions); `Sidebar/sidebarDnd.tsx:209` (`setTimeout 0` event-cleanup); `interactions/autoscroll.ts:1` (a comment).

### Principles

- **One progress variable** drives a coordinated multi-element move (the `--io` shell) rather than N independent transitions that can desync.
- **One primitive per pattern** — Reveal for expand/collapse, `dropdown-menu` for pane open, the drag engine for reorder — applied everywhere, not re-derived per surface.
- **Tokens over literals** — duration/easing come from `motion.ts`; the named curves (Bloom, drag "out") are the only special-cased ones.
- **Compositor / pointer-driven where it counts** — scroll-park (scroll-timeline), drag chrome + resize (1:1, no timed transition) — so motion never lags the input.
