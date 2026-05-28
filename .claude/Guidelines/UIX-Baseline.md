### UIX Baseline — Popover-Family Surfaces

The canonical look + behavior for Pommora's popover-family UIX: the View Settings popover and its panes, the property editors, and the option pop-out. Locked 2026-05-27 from Nathan's Figma. Complements `Design.md` (philosophy + Liquid Glass continuity); this file is the concrete spec. All values route through `PUI` (`DesignSystem/PUI.swift`) — never inline raw numbers.

---

#### Where this applies

The View Settings popover (`ViewSettings/*`), the property editors (`EditPropertyPane`, the Select / Status option editors), and `OptionEditPopover`. The principles generalize to any future popover-hosted Pommora surface.

---

#### Field backdrop — the inspector's fill, not a pill

The old per-field `Capsule().fill(Color.primary.opacity(0.06))` is **retired**. Editable fields + icon buttons use:

- **Fill:** `PUI.Fill.field` — the page inspector's own native grouped-`Form` section color (system-managed, not a hand-set opacity). Candidate `.controlBackgroundColor`; verified against the inspector in build.
- **Shape:** rounded-rect at `PUI.Radius.field` (continuous), **never a capsule**. (Chips themselves stay capsule — see below.)
- **Apply via `.pommoraFieldBackground()`** (`DesignSystem/PommoraFieldBackground.swift`), never inline. This same backdrop applies to the `OptionEditPopover` title field + container.
- **Title field is fixed-width:** it fills the content rail of the fixed-width pane (so its width is content-independent); its trailing edge defines the rail that other elements (e.g. an "Add" affordance) right-align to.

---

#### Dividers + pinned footers

Every divider in the settings panes uses the shared **`PaneDivider`** — a system `Divider` inset to the content rail (`PUI.Pane.contentPadding`, 16pt), flush to the content edges (never full-bleed, never double-inset). This is the universal standard across *all* dropdown-settings panes, not just the property editor. The field↔content divider adds 5pt vertical (`PUI.Pane.dividerPaddingVertical`); footer dividers add none (the row's own padding provides the gap).

A pane's **destructive/global footer** (Delete / Duplicate, "New property") is **pinned to the popover bottom**, fixed regardless of middle-content height — the scrollable middle absorbs spare space. Each footer row uses the standard rail: `.padding(.horizontal, PUI.Row.paddingHorizontal)` (16) + `.padding(.vertical, PUI.Spacing.lg)` (10), so the gap above the row (to its divider) and below it (to the popover edge) match. Per-type selectors (e.g. Display As / date format) are **not** pinned — they scroll with their section as ordinary content.

---

#### Section headers + type scale

- **Section headers** ("Options", "Display As") = `PUI.Typography.sectionHeader` (Subheadline / emphasized), rendered `.foregroundStyle(.secondary)` (vibrant secondary). Each header may carry a right-aligned affordance ("Add", or the Display-As dropdown), right-aligned to the content rail.
- **Chip text** = `PUI.Typography.chip` (Callout / emphasized) — matches the shipping `PropertyChip`.

---

#### Chips + reorder grips

- Chips keep their **capsule** shape (`PropertyChip`, 50×20).
- Chip list spacing: **6pt between chips** (`PUI.Spacing.sm`), **12pt** from a section header to the first chip (`PUI.Spacing.xl`).
- **Reorder grip:** `line.3.horizontal`, vibrant secondary, sized to chip text (`PUI.Typography.chip`). Dragging happens on the grip.

---

#### Selectors

Inline value selectors (e.g. "Display As", date "Format") are a **plain native `Menu`** — vertical list, checkmark on the current value, **no chevron glyph** on the trigger, no `ControlGroup`. The label sits vibrant secondary; the value text is the tap target. (Supersedes the earlier "Menu label = Text + chevron-down" note in `Design.md`.)

---

#### Pane navigation — back-label

Pushed panes show a **back affordance = chevron + a small label naming the *previous* pane** (e.g. the per-property editor reads "‹ Edit Properties"). When a pane edits one named entity whose icon + name render inline at its top, there is **no duplicate pane title** — the inline field carries identity (already in `Design.md`).

---

#### Inline text-field commit

Every inline-edit `TextField` (property name, option label, type / group title) commits on **Enter, focus loss, AND popover/pane dismissal** — never Enter-only. Implement with `@FocusState` + `.onChange(of:)` (commit when focus goes `true → false`) plus an `.onDisappear` safety net for popover-hosted fields; `.onSubmit` alone only fires on Enter while focused, and a click-outside that dismisses the popover doesn't blur reliably. Commit closures must be **idempotent** — guard `trimmed != current` so Enter / blur / disappear can all fire without double-writing. Reference: `OptionEditPopover.titleField`.

The editable hit-target is the **field, not the whole row** — constrain a label-style inline field with `.fixedSize(horizontal: true, vertical: false)` so the caret/click area matches the text, not the row width.

---

#### Native-first

Prefer standard SwiftUI; reach for custom only where the platform can't carry the look (e.g. the in-content `PaneHeader`, which exists because `.navigationTitle` renders a dark band inside a popover). No new magic numbers — extend `PUI`.

---

#### Deferred (NOT built in this baseline)

Captured so it isn't lost; revisit in a later version:

- **Sidebar row context-popover** — a row-level popover (Open / Open in Preview / Edit Properties / Settings / Delete) opened from the native context menu, with the popover replacing the menu in place. Descoped 2026-05-27 as too large for this branch.
- **Retiring `TypeSettingsSheet` / `VaultSettingsSheet`** — the two-surface drift (toolbar popover vs. sidebar schema sheets) persists for now by design.
- **Leaf (page/item) value editing** from the sidebar, and the real **Item Window**.
