## ItemsV2 — Interactive Default Window (Spec V5)

> **Status: LEAN-PASS FOLDED (5 review rounds) — verification pending the Plan-V3 review; NOT yet ratified.** Supersedes V4. V5 = V4 (3 rounds) + a pre-plan build-tree interrogation (round 4) + a leanness/honesty pass (round 5) that caught a real bug (a stored-`index` snapshot would go stale) + optimistic extension claims — all folded (§16). Per `Guidelines/Review-Discipline.md`, V5 is **not** called bulletproof until a round comes back clean; the Plan-V3 review (which grounds every claim in code) is that verifying round. Changes vs V4: pooled-cap engine, grouped-pane pattern, build-tree decisions, + the round-5 corrections. Everything else carries from V4 verbatim:
>
> 1. **Pooled conditional-cap engine** replaces the single `cap: 4` (§4.2, §8/§9, §10) — property types group into **pools**, each with a capacity **rule** (combined-total or per-type). V1 enables Select+Multi only; the engine is built general.
> 2. **Templates pane = the existing grouped status/multi-select editor pattern** (§7): groups by property type → schema properties underneath, each with a checkbox; mute at pool-cap.
> 3. **Build-tree decisions recorded** (§17): components built as properly-scoped **reusable assets**; **not Figma-gated** ("use what you have" + existing Component-Library pieces); **foundations-first**; the `.null` gate is the **shared** manager fix.
> 4. Every V4 design decision (surface kept, mode-enum deleted, `commitItemEdits` deleted, chrome, footer, inspector, schema, `.null`-at-manager) stands. All `file:line` carried from V4's three verified fleets.
>
> **Pre-execution amendments (2026-06-07, Nathan — folded before build):**
> 5. **Property Field = segmented-style row** — a reusable Component-Library container (`PropertyFieldBar`) where each pinned property is a segment (icon + value) that opens its `ChipDropdown` on tap (§4.2, §9).
> 6. **§17.2 flips to design-gated — gate EACH visual** (D2/D4/D5/E1): ASK for Nathan's design when unsure; build each task's non-visual parts first so the plan isn't interrupted (§17.2).
> 7. **Inline text-field commit model is standard** (Enter + focus-loss + dismissal; idempotent; field-sized hit-target) per `Design.md` — title + inspector Number/URL fields (§4.1, §4.4, §5).
> 8. **Inspector row = `(icon) (title) ──── (field)`**, identity shown ONCE — never a type-as-text label, never the `FrontmatterInspector:188`/`PropertyEditorRow:16` double-name. Icon = `definition.icon ?? definition.type.pickerIcon` (shared glyph, `PropertyTypePicker.swift:23`) (§4.4, §9).
> 9. **Process:** `Design.md` governs visuals; every V1 interaction point is wired + verified at the right layer (quirk #17); each task report → adjust-plan-or-PAUSE; agent claims are independently evidence-verified; implementers run Opus 4.8 (Sonnet for trivial); a post-functional verified UIX review always runs (Phase F2); final task = a prose-level doc-sweep (§11, §17).

### 1. The shift this spec makes

The Item Window today is an intentional **read-only stub**: `ItemWindowRenderer` (`ItemWindow/ItemWindowRenderer.swift:35`, `var editing: Bool = false`) renders only icon + title + read-only body (the `else` branch at `:182-212`; `MarkdownPMEditor(isEditable:false)`); no value editing; `commitItemEdits` exists + is unit-tested but is **never called from production** (`Items/ItemContentManager+CRUD.swift:474-495`). **This spec replaces it with the real interactive window — inside the same window surface that already exists.**

On the live card the user can **assign/select property values**, **add an existing schema property** (then assign its value — never editing the schema), **write the body**, **edit title/icon**, and **delete**. Schema + option definitions stay in Type/Set settings; *what is pinned* is configured in Type/Set settings; everything else happens on the card.

### 2. Architectural law: one primitive, zones as variables

One primitive view — `ItemWindowRenderer`, always the live interactive card. Each **zone** is a configurable slot. A future zone = a slot + a property-type→zone rule on the same primitive. **No mode enum** — V3's `ItemWindowMode` is deleted (the Templates pane is a checkbox list with no embedded renderer preview, so the renderer has only one consumer); **remove `editing: Bool`** entirely (the only other reference, `ItemTemplatePane.swift:131`, is deleted with the embedded mockup; `ItemWindowEditModeTests` → repurposed, see §9).

**Surface unchanged.** The card stays a `WindowGroup(for: ItemRef.self)` scene (`PommoraApp.swift:61-69`: `.windowStyle(.plain)` + `.windowLevel(.floating)` + `.windowResizability(.contentSize)` + `.restorationBehavior(.disabled)`), hosted by `ItemWindowSceneRoot` → `ItemWindowSceneContent`, wrapped in `PreviewWindow`, opened via `AppGlobals.presentItemAction` → `openWindow(value: ItemRef(...))`. Because it stays a real window scene, `WindowDragGesture` (drag) and `@Environment(\.dismissWindow)` (close) keep working — no re-host, no overlay, no `presentItemAction` rewiring. Multiple windows (one per `ItemRef`) remain allowed. Env via `AppGlobals.current` + `.injectNexusEnvironment` (quirk #15 already satisfied at `ItemWindowSceneContent:69`).

### 3. V1 scope

**In — the interactive "Default" card** (inside the existing window surface):

- **Header** — `[✕ exit]` (left of icon) · `[◎ icon]` · `[Title]` (inline rename) · spacer · `[▥ inspector toggle]` (far right). Header row = drag handle. Exit + toggle use the **plain `xmark`-style button** (§4.1), **never Liquid Glass**.
- **Property Field** — the select / multi-select chip-row, holding the template-pinned select/multi-select properties (pooled-capped, §4.2). Values editable inline.
- **Body** — the MarkdownPM description, editable, 500-source-char cap.
- **Inspector** (right column, **collapsible**, shown by default) — three Context slots pinned at top (always), then filled **non-pinned** properties auto-shown, then "Add Property".
- **Footer** — reuse `DetailFooterBar`: the container path as `crumbs` + `⋯` + Delete (no new component).
- **Full-row (Standard) property rendering only.**

**Modeled-but-dormant in V1:** `template_config` models all property types via type→zone derivation; the **pooled-cap engine** is built general (all pools, both rule kinds); the Templates pane lists all property-type groups. But **only Select + Multi-select are checkable/rendered** in V1; the others are **muted (disabled-in-V1)**.

**What "enabling a future pool/zone" ACTUALLY requires (honest scoping — not a one-line flip).** The zero-change guarantee covers the **config/storage layer only** (`template_config`, item files, SQLite — untouched). The UI is net-new work each time. Concretely, enabling e.g. Pool B requires: (1) a **`enabledPools`/checkable mechanism** that V1 does not yet have — `v1Checkable` is a static `let`; a future version must introduce a way to mark a pool checkable without breaking the "disabled-in-V1" visual contract; (2) a **from-scratch zone render slot** for that pool's control types (Pool B = Checkbox/Status/Date/Datetime → `Toggle`/`ChipDropdown`/`DateTimePicker`, NOT a chip-row — its layout, sizing, and placement in the renderer are undesigned); (3) enabling that group's pane checkboxes. **There is NO prepared "flip" — each future zone is a real design + build task.** "Pools double as the cap-grouping unit" is true for caps only; it does NOT pre-define the zone UI. (This honesty is the lean-pass's #4 finding — the engine generality buys the *cap math + storage*, not the zone UI.)

**Deferred:** rendering the other pools' zones on the card; Compact rendering; Notion-style live preview in the pane; cover/banner zone; value-prefill; inspector "sections"; layout-customization UI; file-editor wiring.

### 4. Window anatomy (the zones)

The existing floating window surface (`PreviewWindow` card visuals: `.regularMaterial`, `PUI.Radius.large` corners, `shadow(radius:16,y:6)`, Esc-to-close). V5 restructures the **header** (delete `PreviewWindow`'s standalone `xmark`/drag header bar at `:42-63`; the item header row carries the close + `WindowDragGesture` — prefer making `PreviewWindow`'s header an optional `@ViewBuilder` param defaulting to empty, to protect future Page consumers) and the **footer** (reuses `DetailFooterBar` — the container path as `crumbs`, with `⋯` + Delete in its trailing slot). Two-column when the inspector is shown (~760pt: main ≈ 480, inspector ≈ 260); single-column collapsed (~480pt); height seed ~480pt — all tunable `PUI.ItemWindow.*` data.

```
┌─────────────────────────────────────────┬──────────────────┐
│ ✕  ◎ Item Title                    [▥]  │ ▢ Context 1      │  ← header row = drag handle
│ ───────────────────────────────────────  │ ▢ Context 2      │  inspector top: 3 tiers,
│ [ property field: select / multi chips ] │ ▢ Context 3      │  ALWAYS (when inspector shown)
│                                          │ ◦ Property [val] │
│  body (MarkdownPM, editable)             │ ◦ Property [val] │  filled NON-PINNED props
│                                          │ [ + Add Property]│
│ ───────────────────────────────────────  │                  │
│ ‹ Type › Set (Finder breadcrumb)   ⋯  🗑 │                  │  ← reused DetailFooterBar
└─────────────────────────────────────────┴──────────────────┘
```

#### 4.1 Header zone

- **Exit** `✕` — leftmost, left of the icon. Reuses the existing `PreviewWindow` look: `Image(systemName:"xmark").font(.system(size:11,weight:.semibold)).foregroundStyle(.secondary)` + `.buttonStyle(.plain)` (`PreviewWindow.swift:44-54` is the reference). Calls `dismissWindow()`. **Never Liquid Glass.**
- **Icon** — `.iconPickerPopover(isPresented:symbol:)` (`IconPicker.swift:231`; `symbol: Binding<String?>`).
- **Title** — filename, inline-edited; commits on **Enter + focus-loss + window-dismissal** (`@FocusState` false-transition + `.onChange` + an `.onDisappear` safety net), **idempotent** (guard trimmed ≠ current), hit-target sized to the text (`.fixedSize`) — the standard inline-commit model (`Guidelines/Design.md`). Routes through `renameItem`, never `updateItem`. Collision → inline error below the title; file untouched.
- **Inspector toggle** `▥` — far right; plain style (not Liquid Glass); collapses/expands the inspector; session state, shown by default.
- **Drag** — header row carries `.gesture(WindowDragGesture())` (real window → moves it; no offset/clamp).
- **Design-gated (D2):** the header-chrome arrangement (exit / icon / title / toggle) is signed off by Nathan before build (§17.2).

#### 4.2 Property Field zone (select / multi-select chip-row) + the pooled-cap engine

- Renders the template-pinned select & multi-select properties as a **segmented-style row** — a reusable Component-Library container (`PropertyFieldBar`) where each pinned property is a **segment** (its icon `definition.icon ?? def.type.pickerIcon` + current value); tapping a segment opens its value editor. Value editing via **`ChipDropdown`** (`.options` is `@Binding` → each segment holds a local `@State` seeded from `definition.selectOptions?.map { $0.asChipOption() }`; `asChipOption()` at `PropertyChipColorMapping.swift:33`), **not** `MultiSelectChips` (raw-value bug, `PropertyEditorRow.swift:166-167`). Built from existing pieces + `Design.md`, staged as a CL asset.
- **Two-level pinning** (Templates pane, §7): the **pooled-cap engine** decides what may pin; within the allowed types the user pins specific properties. A pinned chip **always shows even when empty**.
- **Pooled conditional-cap engine (V5 — replaces the single `cap: 4`).** Property types group into **pools**, each carrying a capacity **rule**:

  | Pool | Types | Rule |
  |---|---|---|
  | A | Select, Multi-select, Number | **combined-total 4** |
  | B | Checkbox, Status, Date, Datetime | **per-type 1** (1 each) |
  | C | URL, File | **combined-total 2** |

  Two rule kinds: **combined-total(N)** (count pinned across all the pool's types; mute the pool's remaining unselected at N) and **per-type(N)** (count pinned of that specific type; mute that type's remaining unselected at N). The engine is **data** (`ItemWindowZoneConfig`, §8/§9) and computes per-pool selection counts so conditional muting works ("3 Select + 1 Multi = 4 → rest of Pool A greys out until you deselect"). Pools double as the future zone-grouping unit. (`datetime` joins `date` in Pool B — assumed from §5's "Date / Datetime" pairing; Nathan can split them if intended. `relation` + `lastEditedTime` are **never user-pinnable** — not in any pool.)
  - **V1 scope:** the engine is built **general** (all pools, both rule kinds), but only **Select + Multi-select are checkable**; every other type is muted as **disabled-in-V1** (a visually **distinct** state from cap-reached — §7). So in V1 the only reachable cap is Pool A's combined-total of 4 across Select+Multi (Number is in Pool A but muted in V1). Seed values are tunable data, tuned by eye.
  - **Renderer slice:** the chip-row filters each pool's pinned entries to its rule **independently** (combinedTotal: ≤N; perType: ≤N per type) — not one global `.prefix`; the Templates pane blocks pinning past the rule (§7).
- **Integrity (type-filter):** a pinned property whose type is no longer chip-eligible, or whose ID is missing from schema, is filtered out of the chip-row via a **new additive `TemplateResolver.promotedForField(type:collection:)`** (filters `promoted(...)` by `ItemWindowZoneConfig` chip-eligibility = `v1Checkable` in V1; the union of enabled pools' types in future). **Do NOT modify `promotedEntries`** (`TemplateResolver.swift:25-36`; its 5 `PromotedEntriesTests` stay green). Add `PromotedForFieldTests`.

#### 4.3 Body zone

- The `.md` body, rendered via `MarkdownPMEditor(isEditable: true)` with a real `Binding` (`NativeTextViewWrapper.swift:90-107`; pass `documentId: vm.item.id`). **Frame constraint:** the editor wraps its own `NSScrollView` (`ClampedScrollView`, `:127`) → bound with `.frame(maxWidth:.infinity, minHeight: 80, maxHeight: ~200)`.
- 500-source-char cap (`ItemValidator.maxDescriptionLength = 500`, `:18`; effective cap via `ItemValidator.effectiveCap(template:)`, `:29-31`). Counter reddens at/over cap; in-app over-cap saves rejected (never clamped); already-over-cap on load → red counter, non-blocking.
- **Debounce flush on close.** VM debounces ~300ms; `ItemWindowSceneContent`'s `.onDisappear` runs `Task { await vm.flushBodyNow() }`. The VM is an `@Observable @MainActor` class held as `@State` by the scene content, so the flush `Task` captures it strongly and completes the final write even as the view tears down.

#### 4.4 Inspector zone (right column, collapsible)

- **Three Context slots, pinned at top, ALWAYS shown when the inspector is open** (filled or not, regardless of pin), tier order 1/2/3. Edited via `ContextValueEditor(ids:scope:index:resolver:)` → `ContextPicker`. **Both `index: PommoraIndex?` AND `resolver: ContextDisplayResolver?` are DIRECT parameters** (`ContextValueEditor.swift:17-18`) — the renderer reads `@Environment(ContextDisplayResolver.self)` (injected `NexusEnvironment.swift:274`) and threads it + the index into each tier editor. Labels from `TierConfigManager`. The 3-tier guarantee is `ItemType.resolvedProperties(tierConfig:)` → `BuiltInContextLinkProperties.merge(...)` (`:48-60`) — there is no `BuiltInContextLinkProperties.resolvedProperties(...)`.
- **Row layout — `(icon) (title) ──── (field)`** (the new `ItemInspectorRow`): for property rows, leading = the property icon (`definition.icon ?? definition.type.pickerIcon`, the shared glyph at `PropertyTypePicker.swift:23`) + the property name; trailing = the value field; identity shown **once**. The 3 tier rows follow the same shape (tier label + `ContextValueEditor`). **Never** a type-as-text label, and **never** the `FrontmatterInspector` double-name (`:188-199` wraps `LabeledContent(prop.name) { PropertyEditorRow }`, and `PropertyEditorRow:16` re-prints the name → it renders twice). Compose `ItemInspectorRow` directly; don't nest it in an outer `LabeledContent(name)`. Number/URL TextFields use the inline-commit model (`Design.md`).
- **Filled NON-PINNED properties auto-show** as editable full-row rows. **Pinned properties never appear here.** **"Filled" = key present with a value other than `.null`; `multiSelect([])`/empty-string/`relation([])` count as NOT filled.**
- **Session-surfaced set** (`Set<String>` on the VM): a row shows iff **filled** OR **surfaced**. Add-but-unfilled and cleared-value both surface; nothing persisted for an empty row; discarded on close. **Clearing a PINNED chip does NOT surface** (pinning already keeps it visible; pinned never renders in the inspector).
- **"Add Property"** — lists schema properties **not filled, not pinned (`promotedForField` IDs), not in `ReservedPropertyID.all`, not `type == .lastEditedTime`**. Selecting surfaces an empty inspector row; value set inline. **Assigns a value only; never edits the schema.**
- **Auto-managed meta** (`id`, `created_at`) collapse to a read-only section; `modified_at` read-only; none in Add-Property.

#### 4.5 Footer zone (reuse `DetailFooterBar`)

**Reuse `DetailFooterBar`** (`DetailFooterBar.swift:65-67`) — Nathan: use the views' footer component, just display the path; skip `NSPathControl` and a new component. Pass the container path (Type › Set) as its `crumbs: [FooterCrumb]`; put `⋯` options + **Delete** (destructive, `.confirmationDialog`; on confirm `dismissWindow()`) in its trailing `@ViewBuilder` slot. `DetailFooterBar` already renders the typographic path breadcrumb — no `NSPathControl`, no new type.

### 5. Per-type value editing

Every editor already ships. V1 surfaces select/multi on the chip-row; **all** types are editable in the **inspector** when filled/added except where noted. **Non-select/multi properties are fully usable in the inspector — they just can't be *pinned to a window zone* in V1** (their pane checkbox is disabled-in-V1).

| Type | Editor | V1 |
|---|---|---|
| Select / Multi-select | `ChipDropdown` | chip-row **and** inspector (when not pinned) |
| Status | `ChipDropdown` (grouped) | inspector |
| Date / Datetime | `DateTimePicker` | inspector |
| Number / URL | `TextField` | inspector |
| Checkbox | `Toggle` / `PropertyCheckbox` | inspector |
| File | `PropertyCellDisplay` | **read-only** V1 |
| Tier relations (1/2/3) | `ContextValueEditor` → `ContextPicker` | the 3 Context slots |
| Last Edited Time | read-only | never editable |

All inspector rows use the `(icon) (title) ──── (field)` layout (§4.4); TextField editors (Number / URL) follow the inline-commit model (`Design.md`).

### 6. Interactivity & save model

- **Value assignment vs schema editing (Nathan, load-bearing).** The card **assigns** a value to *this item*; it never edits option definitions or the schema.
- **Live-save**, no Save button. Pickers commit on click; text/body debounce ~300ms.
- A new **`@Observable @MainActor ItemWindowViewModel`** holds drafts (title/icon/body/properties/tiers) + the session-surfaced set, routing each field:
  - **property value** → `updateItemProperty(_:propertyID:newValue:type:collection:)` (`:719-725`).
  - **tier** → `updateItemProperty(…, newValue: .relation(ids))`; clearing → `.relation([])` (empties the array, **not** `nil`).
  - **icon** → `updateItemIcon`.
  - **body** → `updateItem` (description), debounced + cap-gated; flush-on-close (§4.3).
  - **title** → `renameItem` (re-hold the returned `Item`); commit on Enter or focus-loss.
- **`.null` gate in the SHARED manager seam (DRY).** Today `updateItemProperty:732-737` would persist `PropertyValue.null` (it's non-nil → hits the `else if let newValue` set branch at `:735`). Normalize at the top of `updateItemProperty`: **`if case .null = newValue → treat as nil → removeValue`.** This fixes BOTH the VM path AND the **live table-cell bug** (`PropertyCellEditor` commits `.null` on clear today → writes `null` YAML). Verified: no caller wants a stored `.null` (every `.null` is a clear-intent), so the manager-level gate is universally correct; `.relation([])` is unaffected (not `.null`). (Build-tree decision, §17.)
- **Icon/non-body edits must not reject on a pre-existing over-cap body.** `updateItemIcon` routes through `updateItem` → `validate()` → `ItemValidator.validate` body-cap (`ItemValidator.swift:61-64`), so an icon change on an already-over-cap item throws. The body-cap check must apply only to body edits (or non-body writes skip body validation).
- Managers re-read from disk before writing (`updateItemProperty` does `Item.load(from:)` at `:730`). Last-write-wins per distinct property accepted for v1.

### 7. Templates pane (configures pinning + property-layout)

- The pane is its own **"Templates" section of the context-view dropdown** (the ViewSettings popover) on item-type views AND Sets (route already exists: `StorageMenuRoot` → `ViewSettingsRoute.itemTemplate` → `ItemTemplatePane`). Items-only, Pages muted.
- **Visual pattern (Nathan):** follow the existing **grouped status/multi-select editor** pattern (e.g. `StatusGroupsEditor` / the property editors in `ViewSettings` — plan confirms the exact precedent component at build time): list **groups by property type**; under each group, the **schema properties of that type, each with a checkbox** = "show on the card."
- **REMOVE the existing pane content (confirmed by Nathan's screenshot):** the **archetype picker** rows — "Compact Stack / Standard Panel ✓ / Banner / Two-Column / Gallery / Wide / Reserved" (`LayoutArchetype.selectable`) — and the **"Layout preview"** section + its embedded `ItemWindowRenderer(editing: true)` mockup (`:122-141`). **Keep `coverSection`** (orthogonal); **remove `displaySection`** (per-`PromotedProperty.display` overrides die with the archetype model).
- **Pooled-cap muting (§4.2):** the pane computes current selections **per pool** and, when a pool hits its rule, mutes the pool's remaining unselected checkboxes. **Two visually distinct muted states:** (a) **cap-reached** (e.g. a "4/4" count indicator) and (b) **not-available-in-V1** (the non-Select/Multi groups — a lock/muted treatment). Exact visuals per the grouped-editor precedent. The selection count is **derived from `template_config.promoted_properties`** filtered by the pool's types — not a separate `@State` — so it reflects writes from any source.
- **Write path:** checking a property writes `template_config.promoted_properties` via `updateTemplateConfig` (`ItemTypeManager.swift:668-671`). On the first pin write to a Set still carrying legacy `pinnedProperties`, call `updateItemCollectionPinnedProperties(collection, to: [])` to collapse it (condition: `resolved.collection?.templateConfig?.promotedProperties == nil` before the write), reusing the path at `ItemTemplatePane.swift:379-396`. Pin order = chip-row order.
- **Inheritance cascade — pre-existing (Paradigm-Decision #15 + `TemplateResolver.effective`):** Item Type template inherited by all items; an Item Set may override; Type-root items use the Type template. `collection?.templateConfig ?? type.templateConfig`.
- **`property_layout` control** — Notion's "show property title": `standard` title+value; `compact` value-only. **V1 ships Standard**; Compact present-but-disabled. The control's visual follows the grouped-editor precedent; V1 wires only the enum + storage + a disabled Compact affordance.

### 8. On-disk schema — additive/forward-compat (extends registry #15)

`template_config` (on the Item Type, overridable on an Item Set) records *what renders*; **item `.md` files are never touched by pinning**. A property's **pool/zone is derived from its type**, so the config needs only the **pinned list + layout mode**.

`ItemTemplateConfig` (`Items/ItemType.swift:112-137` — explicit `CodingKeys` at `:130`, memberwise `init()` at `:119`, synthesized `decode`/`encode`). Change is **additive/forward-compatible**:

- **Keep** `promoted_properties` (flat pinned list; each property's type → its pool/zone). The per-element `PromotedProperty.display` field stays decode-tolerated, no longer a discriminator (it lives on each element, not as a top-level field — nothing to migrate).
- **Stop honoring** `layout` (archetypes retired) — decode-tolerated (`LayoutArchetype.unknown` `:9`), no migration.
- **Add `property_layout`** — net-new, `PropertyLayoutMode { standard, compact, unknown(String) }` (tolerant, matching the `LayoutArchetype.unknown` precedent); **absent decodes to `.standard`**. Add the `CodingKey` case + stored property + **the param to the memberwise `init()`**.
- **Keep** `cover_property_id` (reserved), `description_cap` (active), `default_description` (reserved).

The **pooled-cap config is NOT on disk** — it's code-side static data (`ItemWindowZoneConfig`, §9). No SQLite/index migration (sidecar-only).

### 9. Component reuse map

- **Reuse as-is:** the window surface (`WindowGroup` scene + `PreviewWindow` visuals + `WindowDragGesture` + `dismissWindow`); `ChipDropdown`, `ContextValueEditor`/`ContextPicker`, `DateTimePicker`, `IconPicker`/`.iconPickerPopover`, `PropertyCellDisplay`, `PUI` tokens, `TemplateResolver`, manager seams (`updateItemProperty`, `updateItemIcon`, `renameItem`, `deleteItem`, `updateItem`), and `PropertyType.pickerIcon` (the shared type→glyph map, `PropertyTypePicker.swift:23` — the inspector + segment icon source).
- **Build new (as reusable assets — §17):** `ItemWindowViewModel`; the zone-composing renderer (collapsible inspector); **`PropertyFieldBar`** (the **segmented-style** Property Field container); **`ItemInspectorRow`** (`(icon)(title)──(field)`, identity once — never the `FrontmatterInspector:188`/`PropertyEditorRow:16` double-name; composes `ChipDropdown`/`DateTimePicker`/`ContextValueEditor`/`PropertyCellDisplay` directly — do NOT modify `PropertyEditorRow`); the Add-Property affordance; the grouped-by-type checkbox Templates pane; the `property_layout` control; `PropertyLayoutMode`; **`ItemWindowZoneConfig`** (the pooled-cap engine — shape in §10).
- **Restructure:** `ItemWindowRenderer` header (exit-left-of-icon + toggle-right + drag handle on the header row); remove `editing: Bool` (update the file-level doc comment, still two-mode framed). **`PreviewWindow` goes header-less** (delete/parameterize the standalone `xmark` header `:42-63`; keep card frame + Esc).
- **Keep (pure utilities, reused):** `ItemWindowRenderer.reorderPromoted` (chip-row ordering) + `partition()`. Rename `ItemWindowEditModeTests` → `ItemWindowReorderTests` (its tests cover `reorderPromoted`, which survives — update the stale file comment); keep `ItemWindowPartitionTests` as a regression guardrail.
- **DELETE:** `commitItemEdits` + `CommitItemEditsTests` (dead + buggy — never called by the live VM; the rename two-step lives in the VM); the archetype picker + embedded mockup in `ItemTemplatePane`; `ItemWindowMode` (never built).
- **Do NOT use:** `MultiSelectChips`; `PropertiesPulldown` / `PropertyPanel`.

### 10. Must-fix prerequisites (verified — each a plan task)

1. **`renameItem` → `@discardableResult -> Item`** (both overloads, `:137` + `:338`, currently `Void`) — VM's title path re-holds the returned `Item` then live-saves other fields.
2. **`.null` gate in the SHARED `updateItemProperty`** (§6) — fixes the Item Window + the live table-cell bug. **First, audit:** grep every `PropertyValue.null` production site (the table editors in `PropertyCellEditor`, any others) and confirm each is a clear-intent (wants the key removed), since `ItemValidator` currently *allows* `.null` (`(.null,_) → return`). Only then gate. Regression-check the table editors still clear correctly.
3. **Index + resolver thread — LIVE, not a snapshot (lean-pass blocker fix).** Do **NOT** add a stored `let index` to `NexusEnvironment` — a stored value is a dead snapshot, stale after an index rebuild / degraded-mode recovery. The existing resolvers wrap a **live closure** over `nexusManager.currentIndex` (`:163-166`); the detail views read `nexusManager.currentIndex` at render time (`ItemCollectionDetailView.swift:152`). Mirror that: `ItemWindowSceneContent` reads the **live** `currentIndex` at render and passes it (plus the `@Environment(ContextDisplayResolver.self)` resolver) into **each** tier `ContextValueEditor` — confirm the scene's live index source at plan time (`env`'s `nexusManager`, or `@Environment(NexusManager.self)`). Wire `@State var vm` + `.onDisappear { Task { await vm.flushBodyNow() } }` into `ItemWindowSceneContent` (`ItemWindowSceneRoot.swift:43-93`).
4. **`property_layout` + `PropertyLayoutMode`** added to `ItemTemplateConfig` incl. the memberwise `init()` param (§8).
5. **`TemplateResolver.promotedForField`** (additive; §4.2) + `PromotedForFieldTests`; `promotedEntries` + its tests untouched. **Return `[(promotion: PromotedProperty, definition: PropertyDefinition)]`** (paired, like `promotedEntries`) so the chip-row gets both id + type without re-joining the schema; the pane derives `pinnedTypes` from the same paired result.
6. **`ItemWindowZoneConfig` — the pooled-cap engine.** A caseless namespace `enum` (the codebase idiom, cf. `PropertyIDReorder`). Shape:
   ```
   enum ZoneCapRule { case combinedTotal(Int); case perType(Int) }
   struct ItemWindowZonePool { let types: [PropertyType]; let rule: ZoneCapRule }
   enum MuteReason { case notInV1; case capReached }   // .notInV1 ALWAYS wins when both apply
   enum ItemWindowZoneConfig {
       static let pools: [ItemWindowZonePool] = [
           .init(types: [.select, .multiSelect, .number], rule: .combinedTotal(4)),    // Pool A
           .init(types: [.checkbox, .status, .date, .datetime], rule: .perType(1)),    // Pool B
           .init(types: [.url, .file], rule: .combinedTotal(2)),                       // Pool C
       ]
       static let v1Checkable: Set<PropertyType> = [.select, .multiSelect]
       static func pool(for type: PropertyType) -> ItemWindowZonePool?
       static func isAtCap(_ candidate: PropertyType, pinnedTypes: [PropertyType]) -> Bool
       static func muteReason(_ type: PropertyType, pinnedTypes: [PropertyType]) -> MuteReason?
   }
   ```
   **Inputs are pre-resolved `[PropertyType]`, NOT `[PromotedProperty]`** — `PromotedProperty` carries only `{id, display}` (no type), so a single pure helper joins the pinned IDs against the schema and filters to `v1Checkable` (so stale/off-V1 sidecar entries can't poison a count): `pinnedTypes(promoted:schema:) -> [PropertyType]`. **The pane (cap-count + muting) AND the chip-row (slice) call this same helper**, so their counts never diverge (LF-1). `isAtCap`/`muteReason` filter `pinnedTypes` to the candidate's pool internally — `combinedTotal(N)` counts all pool types, `perType(N)` counts only the candidate's type. `muteReason` precedence: **`.notInV1` over `.capReached`** (LF-2) — the pane checks `v1Checkable` first and short-circuits, so the cap check only runs for checkable types. Chip-row slicing is **per-pool, independent** (each pool to its own rule), not one global `.prefix` (LF-3). Unit-test (`ItemWindowZoneConfigTests`): combined-total at/under cap; **per-type Pool B scoping** (Checkbox at 1 does NOT mute Status/Date/Datetime); V1 select+multi=4; not-in-V1 muting; **the dual-reason case** (`muteReason(.number, pinnedTypes: 4 select+multi)` → `.notInV1`, not `.capReached`); the `pinnedTypes(promoted:schema:)` resolution helper. `promotedForField` (chip-eligibility = `v1Checkable` in V1; the union of enabled pools' types later) + the chip-row + the pane all read this engine.
7. **Remove `editing: Bool`** from `ItemWindowRenderer` (interactive renderer is the only form). **Also delete the now-dead archetype-display path** — the `resolvedDisplay` / `archetypeDefaultDisplay` static methods + the `PropertyDisplay`/`DisplayTreatment` resolution (`ItemWindowRenderer.swift:153-178`); `PromotedProperty.display` stays on-disk-decode-tolerated only, with no renderer consumer.
8. **Rebuild `ItemTemplatePane`** — delete the archetype picker + "Layout preview" mockup (+ the `editing: true` site `:131`); build the grouped-by-type checkbox list with pooled-cap muting + distinct disabled states (§7). **Keep** `coverSection` AND the scope section (`ScopeOverrideRow`/`ScopeInheritsRow` + the legacy `pinnedProperties` collapse write path); **remove** `displaySection`. **Tasks 7 + 8 ship as one atomic commit** (removing `editing:` alone leaves `:131` referencing a deleted param → won't compile). **Decoupled (ships earlier, in foundations):** removing `TypeSettingsTemplatesPlaceholder` (`TypeSettingsSheet.swift:219` call + `:540-542` struct) is an **independent pure deletion in a different file** — no dependency on the pane rebuild; ship it standalone. **Items only; leave `VaultSettingsSheet.swift:258`'s placeholder**.
9. **Footer** — reuse `DetailFooterBar` with the container path as `crumbs` + `⋯`/Delete in its trailing slot (§4.5); no new component, no `NSPathControl`.
10. **Icon/non-body edits don't reject on pre-existing over-cap body** (§6). **Approach:** add `isBodyEdit: Bool = false` to the `fileprivate func validate(_:type:)`; only the body-changing `updateItem` path passes `true` (body-cap checked only then). **Audit all ~6 `validate(...)` call sites** — `updateItem`(×2), `updateItemIcon`→`updateItem`, `updateItemProperty`, `createItem`, `renameItem` — and confirm each passes the right flag.
11. **Correct `Features/Items.md`** ~line 91 — Type-root items inherit the Type's pinned set.

### 11. UX states & edge cases

- **Session-surfaced set** drives add-but-unfilled + cleared rows; discarded on close. Clearing a **pinned** chip does NOT surface.
- **Add-Property:** selected → surfaced empty row (no write); editing → set value; committed → first `updateItemProperty`. Excludes filled + pinned + reserved + `.lastEditedTime`.
- **Clear a value:** key removed now (manager `.null` gate), row stays this session, gone on reopen.
- **Title collision** — inline error below the title; file untouched.
- **Body over-cap** — counter red; in-app save rejected; no clamp. Already-over-cap on load → red, non-blocking.
- **Empty schema** — inspector shows 3 contexts + disabled/empty Add-Property.
- **Templates pane cap** — at a pool's cap, the pool's remaining unselected checkboxes mute (distinct from not-in-V1 muting). For **per-type** pools (B), muting is **type-scoped**: Checkbox reaching 1 mutes only Checkbox's remaining, not Status/Date/Datetime.
- **Inspector toggle** — collapses to single-column; session state; default shown.
- **Delete** — `.confirmationDialog`; window closes on confirm.
- **Meta** — `id`/`created_at` read-only collapsed; `modified_at` read-only; excluded from Add-Property.
- **File rows (V1)** — read-only via `PropertyCellDisplay`.
- **Multiple windows** — current behavior retained (a window per `ItemRef`).
- **VM lifecycle / concurrency** — the VM holds `item` by value and the manager derives the write path from `item.title`; on its OWN rename the VM re-holds the returned `Item` synchronously before any further write. A concurrent **external** rename of an already-open item (e.g. from the sidebar) is an accepted v1 edge — the window's next write may target the old path and surface an error (not silent corruption); not guarded in v1.
- **Drag** — `WindowDragGesture` on the header moves the window anywhere on screen.

**V1 interaction points (all must be wired AND verified at the right layer — quirk #17):** title rename (Enter / blur / close), icon pick, body edit + flush-on-close, each pinned-property **segment** dropdown, each inspector field (per type), the 3 tier pickers, Add-Property (surface → assign), clear-value (key removed; row stays this session), inspector toggle, delete (confirm → window closes), header drag, exit. Each is manually verified to actually function; when a surface looks wrong, **name the confirmed layer (data vs UI)** before fixing.

### 12. Research-validated pattern (Notion + native macOS)

Notion Layouts pin properties at the top + a right-side panel you "+"-add into; Pommora configures pinning via a **checkbox list** (the realistic in-settings config; Notion's live drag-preview deferred). Native macOS reused: `.windowStyle(.plain)` floating window, `DetailFooterBar`'s typographic path breadcrumb, plain SF-Symbol buttons. Add-Property surfaces **existing** schema properties only; tiers never template-prefilled.

### 13. Out of scope / deferred

Other pools' card zones; Compact rendering; Notion-style live preview in the pane; cover/banner zone; value-prefill; inspector "sections"; layout-customization UI; file-editor wiring; Page-side parity (`PageTemplateConfig` reserved/inert); `@item` / `{{ }}` connections.

### 14. Confirmed decisions (full set)

**Design (V4-locked):** surface kept (no re-host); `ItemWindowMode` deleted; chrome (exit left of icon, toggle far right, plain xmark, no Liquid Glass, header = drag handle); footer = reuse `DetailFooterBar` (path crumbs + ⋯ + Delete; no new component); inspector collapsible (shown by default), 3 contexts always + filled non-pinned + Add-Property, pinned never in inspector; cleared-value stays-this-session (pinned-clear doesn't surface); schema additive in `template_config` (item files untouched, zone from type, all types modeled, select/multi rendered); `.null` gate at the manager; `commitItemEdits` deleted; `property_layout` Standard-V1/Compact-disabled; file props read-only; value-assignment only.

**V5 (this round):** pooled conditional-cap engine (Pool A {select,multi,number}=4 total · Pool B {checkbox,status,date,datetime}=1 each · Pool C {url,file}=2 total; combined-total + per-type rules), built general, **V1 enables Select+Multi only**; Templates pane = grouped status/multi-select editor pattern; components built as reusable assets; **not Figma-gated** (use existing specs + Component-Library pieces); `.null` gate is the shared manager fix.

### 15. Blast radius & ripple (verified)

**Affected:** `ItemTemplatePane` rebuild (largest UI task); remove `editing: Bool` (only other ref `ItemTemplatePane:131`, deleted with the mockup); delete `commitItemEdits` + `CommitItemEditsTests` (grep-confirmed test-only); **`.null` gate at the manager** affects ALL `updateItemProperty` callers incl. the table editors (net fix; regression-check table clearing); `renameItem @discardableResult -> Item` (~6 discarding callers stay compiling); `promotedForField` additive (`promotedEntries` + 5 tests untouched); `PreviewWindow` header-less (protect future Page consumers via optional header param).

**`@Suite` landmines for `-only-testing`:** string-label suites ≠ filename — `ItemContentManager`, `ItemMarkdownTransition`, `ClearTemplateConfig`, `ItemCollectionFile`, `ItemTypeFile`, `Move Item`, `ItemType.singular`; type-name suites — `TemplateResolverTests`, `PromotedEntriesTests`, `ItemTemplateConfigTests`, `ItemWindowReorderTests` (renamed), new `PromotedForFieldTests` / `ItemWindowZoneConfigTests`; **`ItemWindowLayoutsTests` has NO `@Suite`** → 0-test trap, rely on the full-target run. `CommitItemEdits` suite is deleted.

**Verified genuinely safe:** the window scene stays → `PommoraApp`/`SidebarDetailView`/`presentItemAction`(7 sites)/`ContentView` untouched; Agenda; detail tables (auto live-refresh; v1 last-write-wins); sidebar; no SQLite/index migration; no file watcher; `PageTemplateConfig` symmetry; `VaultSettingsSheet` placeholder left; new files auto-include (`PBXFileSystemSynchronizedRootGroup`).

**Paradigm registry:** AMEND #15 (additive `property_layout`; `layout`/`PromotedProperty.display` decode-tolerated-not-honored; `template_config` is the rendering-config home; item files untouched; pooled-cap config is code-side data, not on disk). Log to `History.md`.

### 16. Review provenance (carried)

V5 inherits V4's three-fleet certification (8 agents): compile-grounding verified all six V4 decisions SAFE; pipeline-coherence + intent-coverage certified FULL coverage; round-3 clean.

**Round 4 (V5 cap-engine, 2 agents):** all 8 pooled `PropertyType` cases verified; engine logically sound. Folded: `datetime`→Pool B; the cited grouped-checkbox precedent **does not exist** (build new from `PropertyVisibilityPane` row + `StatusGroupSection` header — `StatusGroupsEditor` is a drag-reorder chip editor, NOT a checkbox list); engine inputs are pre-resolved `[PropertyType]` via one shared helper; `muteReason` precedence; per-pool slicing.

**Round 5 (leanness/honesty, 1 agent):** caught a real bug + optimistic claims. Folded: **index must be LIVE, not a stored `NexusEnvironment` snapshot** (§10.3 blocker); **honest scoping of "enabling a future pool"** — no prepared flip; each zone is real design+build, the zero-change guarantee is config/storage only (§3 blocker); **`updateItemIcon` over-cap fix scoped** to an `isBodyEdit` validate param + a call-site audit (§10.10 blocker); `promotedForField` returns paired `(promotion, definition)` (§10.5); keep the scope section in the pane rebuild (§10.8); delete the dead `resolvedDisplay`/`archetypeDefaultDisplay` path (§10.7); decouple the `TypeSettingsTemplatesPlaceholder` deletion (§10.8); `.null`-production-site audit before gating (§10.2); VM concurrency contract (§11). **Surfaced to Nathan (owner-touching):** the dedicated Finder-breadcrumb footer + `property_layout` disabled control — kept per his locks, leanness noted.

**Verifying round = the Plan-V3 review** (grounds every claim in code); V5 is not ratified until it returns clean.

### 17. Build-tree decisions (pre-plan interrogation)

- **Reusable assets.** Every new component is built as a properly-scoped reusable asset — zones as configurable slots, atoms (footer, inspector row, chip-row cell, checkbox row) as standalone reusable views — never feature-locked one-offs. Component-Library-explorer staging is optional; reusability is the requirement.
- **Design-gated (§17.2).** Build from existing components + `Guidelines/Design.md` where they cover the step ("use what you have"). When a step requires Nathan's **net-new visual design**, STOP and ASK (may route to Figma). **Gate EACH visual step** (D2 header, D4 property bar, D5 inspector row, E1 pane): ASK Nathan for the design when unsure. To avoid interrupting the plan, build each gated task's **non-visual parts first** (scaffolding, data wiring, logic) — only the specific visual waits on Nathan; smaller well-defined pieces never block on a gate. A **post-functional, verified UIX review of the working window always runs** afterward, no matter how clean the build. **`Design.md` governs all visuals.**
- **Foundations-first.** All Figma-independent foundations (manager seams + `.null` gate + `renameItem` + `commitItemEdits` deletion + `property_layout`/`PropertyLayoutMode` + `promotedForField` + `ItemWindowZoneConfig` engine + the ViewModel) are built and unit-tested first; the visual renderer/pane/footer assemble on top. (Live index threading is render-time scene wiring, not a stored foundation — §10.3.) **Exception:** removing `editing: Bool` is architecturally a foundation but is **coupled to the pane rebuild (§10 tasks 7+8) as one atomic commit** — it does not ship standalone (removing it alone leaves `ItemTemplatePane:131` referencing a deleted param).
- **Shared `.null` fix.** Gated once in `updateItemProperty` (fixes the Item Window + the live table-cell bug); see §6/§15.
- **Execution model:** **subagent-driven** — a fresh subagent authors each task; implementer agents run **Opus 4.8** (instructed to avoid over-complicating mechanics + leave zero future-agent ambiguity), **Sonnet** for trivial/revisional fixes. The orchestrator **independently evidence-verifies** every completion claim (real build + non-zero tests + diff + source/docs) before each green commit, then re-assesses the plan (adjust or PAUSE+ASK).
- **Build discipline (folded pre-execution).** `Design.md` governs every visual; all V1 interaction points must be wired AND verified at the correct layer (quirk #17 — confirm data vs UI before blaming either); a **post-functional, verified UIX review of the live window always runs** before docs close out (no matter how clean the build); the final task is a prose-level doc-sweep (§11).
