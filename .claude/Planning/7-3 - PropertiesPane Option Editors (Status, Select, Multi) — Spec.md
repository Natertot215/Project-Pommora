## PropertiesPane Option Editors — Status · Select · Multi-Select

**Status:** Ratified V2 — round-1 adversarial review folded (see Review Deltas).

Build the PropertiesPane editor sub-view that edits the **options** of Select, Multi-Select, and Status properties — add · rename · recolor · reorder · remove · clear — replacing today's `{type} options — pending` placeholder (`PropertiesPane.tsx`, the `editor(id)` sub-view). Select and Multi-Select share one flat-list pane; Status is that same pane with the three fixed groups layered on. The reference is the Figma "Design" canvas (node `307:5248`) plus the base-pane photo Nathan provided. Figma spacing is rough intent — actual padding/type/color come from the code token system, spelled out below.

### Phasing

Deliberately sequential — the flat pane must be right before grouping rides on top of it.

- **Phase 1 — Mechanisms:** the option-CRUD backend (IPC + shared logic) and the data-model changes. No pane UI. The real weight.
- **Phase 2 — Select/Multi pane:** the flat-list editor UI over Phase 1.
- **Phase 3 — Status pane:** the grouped editor, reusing Phase 2's parts where it genuinely can.

### Data Model (Phase 1)

#### Option Identity — Value Is Title

An option's stored `value` **is its title** — no separate minted id. Uniqueness: no two options in one property may share a title, enforced by the existing `validateDefinition` unique-value check (`main/properties/schema.ts:74-77`), now also run on option **edits** (today it only fires at create). **Rename cascades:** changing a title rewrites that value on every page holding it — the Connections rename-cascade pattern — so Rename is a page-touching op, not a registry-only edit. Legacy options whose stored `value` differs from `label` still render on read and converge to value=title the next time they're edited.

#### Option Color — Open Solid-Palette Key

Swift on-disk compatibility is no longer a constraint, so the option color drops the closed Notion `selectColor` enum for an **open string key = the `colors.css` solid-palette key** (red / orange / yellow / green / lightBlue / cyan / blue / purple / lavender / grey — all ten, **lightBlue included**). The zod field becomes a permissive string on read, and **`chipColorFor` is the single normalizer**: a solid key passes straight through to the render palette, a legacy Notion value (gray / brown / pink / teal / indigo, from pre-existing data) maps via the existing `colorMap`, anything unknown falls to Default. Picker, storage, and render are one palette, so the 2×5 swatches all round-trip cleanly. A larger (~9×12) picker over the same open key is a **Prospect** — the open string already accommodates it, no schema churn later.

#### Status Relabel + Seeds

`defaultStatusSeed()` group labels become **Open · Active · Done** (group IDs `upcoming` / `in_progress` / `done` stay fixed — load-bearing for calendar-sync). Each group seeds one option labeled the same as its group and carrying the group color (a change — the current `upcoming` seed option carries no color). **`isUntouchedSeed` must also recognize the legacy seed**, or every pre-existing untouched Status property would surface its old seed options (Not started / In progress / Done) as real options in every picker and cell.

#### Unnamed-Option Fallback

Exiting the rename field empty never leaves a blank option — the fallback fires in the **pane's commit handler** (not the shared `EditableInput`, which already trims and commits): Select/Multi → **"Label"**; Status → the option's **group label**.

### Mechanisms / IPC (Phase 1)

Registry-only edits and page-touching edits ride **different serialization chains** — load-bearing (a review finding: the two chains guard different files).

- **`setOptions`** — add · recolor · reorder (registry-only) → the `mutateRegistry` chain (`io/propertiesRegistry.ts`). Validates unique titles. **Must not route an emptied options array through `seeded()`** — today `editProperty` re-injects `defaultSelectSeed()` on empty, which phantom-resurrects a just-deleted last option. Zero options is a valid empty state.
- **`renameOption`** — title change + page cascade → the `serializeSchemaOp` chain (`crud/schemaChain.ts`, guards sidecar/page ops). Updates the def and rewrites the stored value on every page across all assigning collections.
- **`removeOption`** — delete the option + strip its value from every page → `serializeSchemaOp`; a native confirm dialog resolves before the fan-out.
- **`clearOption`** — strip the value from every page, keep the option → `serializeSchemaOp`; native confirm dialog.
- **New per-value page-strip primitive** — genuinely new (the existing `stripPageMember` deletes whole keys only). Switch on the def's type: select / status delete the key iff the stored value matches; multi-select filters the array and deletes the key only when it empties. Walks all assigning collections (`allCollectionFolders`, as `deleteProperty` does).
- **Remove the create-time ≥1-option floor** (`validateDefinition`) so a Select can hold zero options.
- A pure, unit-tested option-editing model (append · rename · recolor · reorder · fallback · color resolution) under the IPC; the panes are thin over it.

### Phase 2 — Select / Multi-Select Pane

#### Layout (top → bottom)

- **`‹ Properties` back-row** + flush `MenuSeparator` — reused unchanged.
- **Icon + name header** — the existing `InlineEditHeader` (28px icon button → IconPicker; the property name inline-editable). Reused.
- **"Options" row** — the label **Options** (`footnote.emphasized`, 10 / 13px / 500, `label-tertiary`, matching the "All Properties" heading) + a trailing **always-shown `+`** (plus glyph 12px, `label-tertiary → label-primary` on hover, ~20px hit target, right-aligned).
- **Chip list** — each option a **squared `label`-shape** `Chip` (`chip-label`; `control.semibold`, 12 / 15px / 600). Status pills stay a different shape — the deliberate "read apart" rule. New chips fill **grey-default**; chips align to the pane content inset.
- **No bottom divider** — the list simply ends.

**Vertical rhythm:** header → **6px** → "Options" → **6px** → first chip → **4px** between chips. The two 6px gaps around "Options" are equal (Nathan's call); all four are knobs.

#### Interactions

- **Add** — the `+` appends a grey-default chip and drops an inline caret into it. Uses `EditableInput` with the input **shrink-wrapping to its text** via a **hidden mirror span** (never a per-keystroke layout read — the "no expensive work on every X" rule). Enter or blur saves; an empty commit → "Label" (in the caller).
- **Rename** — the right-click **Rename** drops the same inline caret; the commit cascades page values.
- **Recolor** — on chip-row hover a **palette icon** fades in at the row's right edge, mirroring the eye icon exactly: **14px glyph, 16px box, `label-secondary` color, ghosted at rest → full opacity on hover** (opacity-only, fast/standard transition). Click opens the **ColorPicker**.
- **ColorPicker** — a `PickerMenu` shell, `direction='down'` (the pane sits below the icon, beak pointing up at it). **2 columns × 5 rows** of solid swatches, **12 × 12px, 3px radius**, solid fill; **2px** gap (horizontal and vertical) and **2px** inner padding → roughly **30 × 72px**. The applied color's swatch reads selected via a **ring in that swatch's own color** (box-shadow, so the grid never reflows); clicking the selected swatch deselects → Default. Each pick maps to its `selectColor` value on save (the existing mechanism).
- **Right-click menu** (any chip) — **Rename** (inline) · **Remove** (delete → confirm → strip) · **Clear** (clear values, keep option → confirm → strip). The native-style menu.
- **Reorder** — dragging a chip runs a **single-region variant of `paneDnd`** (the current engine is hardwired two-region, `{assigned, all}`, so this is a new single-region slot model, not free reuse) with the drop-line (its CSS vars are already global). The drop writes the new order through `setOptions`.

### Phase 3 — Status Pane

The Phase 2 shell with grouping layered on.

#### Layout

- Back-row + `InlineEditHeader` — as Phase 2.
- **Three group sections** — headers **Open · Active · Done**, each with a **hover-revealed `+`** (it appears on hovering the group's heading/area, unlike the flat pane's always-shown Options `+`). Chips list under each header as **`pill`-shape** `Chip`s (distinct from Select/Multi's squared labels).
- **Bottom divider** + a **Style selector: Pill · Capsule · Check** — stored as a **per-property style on the collection, keyed by the property's ULID** (not per-view, and specific to this one property — not a blanket rule for every status column). So the status look is honored by **every view type** — table, card, gallery — not just the table. This **supersedes** the per-view `column_styles` status look (table-only today): views read the property-level style for status, and the table column-header Style menu reads/writes the same per-property store.

#### Interactions

- **Add (per group)** — the group's hover `+` appends a chip to that group, defaulting its label to the group name and its color to the group's color.
- **Cross-group drag** — dragging a chip into another group rewrites its `group_id` on drop and **keeps its own color** (no recolor); within a group it reorders. This needs an **N-group drag model** that carries a `group_id` payload — genuinely new work, NOT a `paneDnd` variant (the engine has no group concept).
- **Rename · Recolor · Remove · Clear** — per option, as Phase 2. An unnamed option → its group label.

### Reused vs. New

- **Reused:** `Chip` (label shape for Select/Multi, pill for Status), `InlineEditHeader`, `EditableInput` (+ the mirror-span width tweak), the eye-icon hover treatment (becomes the palette icon), `PickerMenu` (the ColorPicker shell), the native menu system (right-click menus + confirm dialogs), and the existing `selectColor`/`colorMap` color path.
- **New:** the option-CRUD IPC (`setOptions` / `renameOption` / `removeOption` / `clearOption`), the **per-value page-strip primitive**, the `ColorPicker` component, the pure option-editing model, the **single-region** `paneDnd` variant (Phase 2) and the **N-group** drag model (Phase 3), a **per-property status-style store on the collection** (keyed by property ULID) with its set-IPC and the view-render path that reads it — superseding the per-view `column_styles` status look — and the two pane bodies.

### Review Deltas (V1 → V2)

Round-1 adversarial review (compile-grounding + plan-attack, grounded against real code, several findings executed) surfaced eight issues; V2 folds them all:

- **F1** — the "open color key" was double-blocked (the closed `selectColor` enum drops 4 of the 10 solids, and `colorMap` collapses them to grey) → **resolved**: Swift compat is dropped, so the color becomes an open solid-palette string and `chipColorFor` becomes the single normalizer (solid keys pass through, legacy Notion values map). All ten colors including lightBlue round-trip.
- **F2** — deleting a Select's last option phantom-re-seeds via `editProperty` → `seeded()` → drop the ≥1 floor **and** stop re-seeding an emptied list.
- **F3** — no per-value page strip exists and Multi-Select's array shape was unhandled → a new per-value strip primitive, type-switched.
- **F4** — page fan-out was pointed at the registry chain → page-touching ops ride `serializeSchemaOp`.
- **F5** — the Status relabel would surface stale options on existing untouched props → legacy-aware `isUntouchedSeed`.
- **F6** — `paneDnd` can't absorb single-region or N-group drag → scoped as new drag work in both phases.
- **F7** — new-option value identity → value = title (Nathan).
- **F8** — `EditableInput` has no width logic and already trims/commits → shrink-wrap via a hidden mirror span; the empty-name fallback lives in the caller.

### Success Criteria

- A Select/Multi property's options are fully editable in-pane: add (grey-default, inline caret, "Label" fallback), rename (cascading page values), recolor via the 2×5 ColorPicker, reorder by drag-line, Remove and Clear (each confirmed, each fanning out correctly across every assigning collection).
- Deleting the last option leaves an empty options list — no phantom re-seed.
- Multi-Select value arrays lose exactly the removed/cleared option, never the whole key; Select/Status lose the key only when the value matches.
- Status edits the same way inside its three relabeled groups, with per-group add and cross-group drag that preserves color; existing untouched Status props show no stale options; the Style selector drives the active view's column style.
- Every main op is validated, atomic, serialized on the correct chain, and never throws across the IPC boundary.
