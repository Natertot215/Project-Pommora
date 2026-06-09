## Item Window UIX Sweep — Locked Design + Plan

Consolidates the 2026-06-08 design interview, grounded in the Figma frame + the code (not memory). Supersedes the prior consolidation. Built on the non-activating `NSPanel` platform (`91e53b3`). **No code yet — this is the controlling spec + task plan.**

### Source of truth

- **Figma:** file `V3wKMilXkoceCL1Q2J9kf4`, node `474-9432` — the **right-hand** "Item Title" frame. The **left** frame is OLD — ignore it.
- Decisions locked via the 06-08 interview. Where this doc and older notes disagree, this doc wins.

### Locked design

#### Panel / window

- One **fixed size ≈800×560** (tune in-build). NOT resizable, NOT minimizable, NOT content-sized. **Standard window background** (no glass fill). Floats, **non-activating**, **multiple at once**.
- **Inspector takes width FROM the body** (Pages-style): body ≈480 wide with the inspector open, ≈full when closed — the window never grows. Implementation: drop `.preferredContentSize` content-sizing → pin the SwiftUI content to a fixed frame; remove the main column's hard `.frame(width:)` so it flexes and yields width to the native `.inspector`.
- **Zero dimming on click-off:** hide all native traffic lights + custom non-glass ✕ + force `controlActiveState = .active` on the content so accents / selection / chips never grey when the panel is non-key. Override feasibility is RUNTIME — verify in a real build; document an honest fallback if it resists.

#### Header chrome — `[✕] [icon] [title] ········ [toggle]`

- **Custom v1 ✕** (the `PreviewWindow` xmark: `.secondary`, ~11pt semibold, 22×22, plain, **non-glass**), top-left. Closes via `ItemWindowPanelManager`. (The Figma omitted it only because the component wasn't handy — it stays.)
- **Icon** flush right of the ✕, sized to the title; dashed-rounded-square placeholder when unset; opens the icon picker.
- **Title** = standard window-title styling (system title font ≈ `NSFont.titleBarFont` / `.headline`; single-line; truncating; flexes so a long name never pushes the toggle). Inline-editable (rename on commit), as today — NOT a large document title.
- **Inspector toggle** (`sidebar.trailing`) at the main-pane's right edge.
- Hide all three native window buttons.

#### Main pane

Header · hairline · **property bar** · hairline · **body** · hairline · **footer**.

- **Property bar** (pinned-property segmented control): plain text cells + grey pill cells, vertical dividers, per the frame. **Placeholder mode (new):** when no template defines pinned properties, render placeholder "Label" segments (a few plain + a few pills) so the bar's look is always visible during this design phase. Replaces the current self-collapse-when-empty.
- **Body fills** the flexible width + the fixed remaining height (drop the 310pt fixed height); `quaternarySystemFill` rail-inset surface; 6pt symmetric gaps; char-cap counter bottom-right.
- **Footer:** breadcrumb (Type / Set), unchanged.

#### Inspector — one unified hairline menu (native glass, flush-top)

- Replace the grouped `Form` with a single flat-hairline `VStack` (PropertyPanel-style: rows padded 6 / 12, inset `Divider()` hairlines). **No section headers, no meta** (no ID / Created / Modified, no Auto-managed disclosure).
- **One row shape for both groups (DRY):** `[icon] [label] ········ [value]`.
  - **Contexts group (top):** Spaces / Topics / Projects — `[icon] [tier label] ··· [editable context chips]`; an empty tier shows `⊕ Add`.
  - **Properties group (below, built identically):** `[icon] [property name] ··· [editable value]`.
- **Red "Delete" text pinned bottom-right** (fixed over the scroll) — NOT a "Delete Item" button.

#### Behavior

Drag by background · close via ✕ · native inspector slide · non-activating focus · several panels at once. All RUNTIME — Nathan verifies in-build.

#### Bug to fix — select/status apply-on-click

- **Root cause:** `PropertyEditorRow.statusEditor` renders `ChipDropdown` (which IS the open options panel) directly inline, so every option always shows (screenshot: Awaiting / Active / Complete stacked). `ChipDropdown`'s own doc: *"the pill is the trigger (hosted by the caller's `.popover`); this is the panel."*
- **Fix:** render a **collapsed trigger pill** (current value, or a placeholder) → `.popover` hosts `ChipDropdown` → `onPick` sets the value AND dismisses. Apply-on-click; value shown collapsed. Fix in `PropertyEditorRow` → fixes every consumer (Pages inspector, PropertyPanel, Item inspector). Audit `select` / `multiSelect` for the same inline-panel shape.

#### Superseded (recorded so they don't resurface)

- "large ~28pt `.largeTitle`" → **standard window-title styling**.
- "native close dot" / "standard close" → **custom v1 ✕**.
- "grouped `Form` inspector (Pages `FrontmatterInspector`)" → **unified flat-hairline menu** (PropertyPanel-style).
- "tier rows unlabeled" → **tiers ARE labeled** Spaces / Topics / Projects.
- "keep meta collapsed at the bottom" → **no meta at all**.
- "body fixed 310pt" → **body fills** the fixed frame.
- "property bar self-collapses when empty" → **placeholder "Label" mode**.
- The LEFT Figma "Item Title" frame → old; ignore.

### Sweep plan

Each task: subagent authors → background `builder` verify (non-zero `-only-testing:PommoraTests/ItemWindowViewModelTests`) → read the diff → green-commit. Runtime behaviors (non-activating focus, dimming, inspector slide, drag) are RUNTIME-only — Nathan verifies in a real build.

- **T1 — Fixed size + header chrome.** Pin content to fixed ≈800×560; main column flexes; hide native buttons; add v1 ✕ top-left; icon flush + title-sized; title = window-title style (single-line, truncating, flex); toggle at the main-pane right.
- **T2 — Zero-dimming.** Force `controlActiveState = .active` on the panel content; verify the panel never greys on click-off. Runtime-judged; document a fallback if the override resists.
- **T3 — Body fills.** Drop the 310pt fixed height; body fills the flexible width + fixed remaining height; keep 6pt gaps + `quaternarySystemFill` + counter.
- **T4 — Property bar placeholder.** `PropertyFieldBar` renders placeholder "Label" segments (plain + pill, per the frame) when no real pinned properties exist; always visible.
- **T5 — Inspector unified menu.** Rewrite `ItemInspector`: one flat-hairline `VStack` with a single shared row builder; contexts (labeled Spaces / Topics / Projects, `⊕ Add` when empty) → properties (identical rows); no headers; no meta; red "Delete" bottom-right; native glass; flush-top.
- **T6 — Select/status apply-on-click.** Fix `PropertyEditorRow.statusEditor` (+ audit select / multiSelect) → collapsed trigger pill + `.popover(ChipDropdown)` → apply-on-click + dismiss.
- **T7 — Verify + review.** Build green → Nathan real-build review (focus / dimming behavior + every visual).
- **Phase F (after sign-off):** full `-only-testing:PommoraTests` + `swift format` + docs (update the stale `Features/Items.md` § Item Window + `History.md`) + merge `itemsv2-interactive-window` → `main`.

### Open / runtime-flagged

- `controlActiveState` override feasibility (T2) — runtime-only; fallback if there's no clean global override.
- Exact fixed dimensions, the title font match, and the gap that separates the two inspector groups — tune against the build.
- Empty-tier `⊕ Add` affordance styling — match the current build's pattern.
