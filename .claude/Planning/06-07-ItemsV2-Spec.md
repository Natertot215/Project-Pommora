## ItemsV2 — Interactive Default Window (Finalized Spec)

> **⛔ SUPERSEDED by `06-07-ItemsV2-Spec-V3.md`.** This original spec assumed a separate `WindowGroup` scene, a single flat-pinned select/multi zone, and an always-two-column layout. V3 changes the surface to an **in-app draggable overlay card** (not a separate window), models **all 8 property-type zone-groups** in `template_config`, adds a **collapsible inspector** + **exit-left-of-icon** chrome, and folds in the full second-round agent findings. Kept for history only — read V3.

> **Status: FINALIZED SPEC — ready to plan.** The authoritative design for the first interactive Item Window. It **builds on** `06-03-ItemsV2-Planned.md` (the zone-framework direction) and **supersedes** its "live window = display-only stub" framing plus the `LayoutArchetype` archetype layer in `06-03-ItemsV2-Implemented.md`. Grounded in a 5-agent code-verification sweep + two adversarial advisory reviews (every `file:line` below was verified in the session record) + Notion-Layouts research.
>
> **§8 carries one PENDING paradigm decision** requiring Nathan's explicit confirmation before the plan locks code (per `Guidelines/Paradigm-Decisions.md`).

### 1. The shift this spec makes

The Item Window today is an intentional **read-only stub** (`ItemWindowRenderer` with `editing == false` renders only icon + title + read-only body + footer; `MarkdownPMEditor(isEditable: false)`; no value editing; `commitItemEdits` exists + is unit-tested but is never called). That stub was bedrock. **This spec replaces it with the real interactive window.**

On the live window the user can: **assign/select property values** (pick which option(s)/date/tiers apply, type body text), **add an existing schema property to this item** (then assign its value — never editing the schema), **write the body**, and **edit title/icon**. Schema definition + option definitions stay in Type/Set settings; the template (what's pinned) is configured in Type/Set settings; everything else happens on the window.

### 2. Architectural law: one primitive, zones as variables

The Item Window is **one primitive view**. Each **zone** is a configurable slot on that one primitive — never a separate per-layout window. A future zone (dates, statuses, links…) = adding a slot + a type→zone rule to the same primitive. This is the DRY contract and the controller of the design.

Direct consequence: the renderer's current `editing: Bool` (`ItemWindowRenderer.swift:35`) is insufficient because the **same** primitive backs the live window **and** the Templates-pane mockup. It becomes a mode enum:

```
enum ItemWindowMode { case liveEdit; case templateMockup }   // room for .readOnlyPreview later
```

- `liveEdit` — the floating window: values editable, Add-Property active, body editable.
- `templateMockup` — embedded in the Templates pane: edits *pinning/order*, NOT a representative item's values.

This is an **internal code-shape change, not a paradigm decision** (no on-disk effect). It is a compile-time-breaking signature change: the single task that introduces it must update **all three** call sites together — `ItemWindowRenderer.swift`, `ItemTemplatePane.swift:125` (`editing: true`), and `ItemWindowSceneContent` (uses the default) — or it won't compile.

### 3. V1 scope

**In — the interactive "Default" window:**

- **Header** zone — icon (`IconPicker`) + title (inline rename), editable.
- **Property Field** zone — the faint-outlined horizontal bar under the header: the **select / multi-select chip-row**, holding the template-pinned select/multi-select properties (capped). Values editable inline.
- **Body** zone — the MarkdownPM description, editable, 500-source-char cap.
- **Inspector** zone (right column) — three Context slots pinned at top (always), then filled properties auto-shown, then "Add Property". All values editable.
- **Footer** zone — container breadcrumb (left); item **Delete** (destructive) bottom-right.
- **Full-row (Standard) property rendering only.**

**Deferred (Nathan designs these later):** additional in-window zones (dates, statuses, URLs/links, checkboxes, numbers, files) + their field designs — i.e. pinning non-select/multi-select types to the *main* window; in V1 every non-select/multi-select property lives in the **inspector** only. Also deferred: the **Compact** property-rendering mode (reserved; architected-for, not built); cover/banner zone; value-prefill templates; inspector "sections"; layout-customization UI.

### 4. Window anatomy (the zones)

Two-column floating card on the existing `PreviewWindow` primitive (material card, custom 2-corner chrome, Esc-to-close, drag-to-move — no traffic lights). The window is **always two-column** (the 3 Contexts guarantee the inspector is never empty); V1 keeps a fixed two-column width — seed **~760pt** (main ≈ 480pt, inspector ≈ 260pt), as tunable data.

```
┌────────────────────────────────┬──────────────────┐
│ (icon) Item Title              │ ▢ Context 1      │  inspector top:
│ ────────────────────────────   │ ▢ Context 2      │  3 tiers, ALWAYS
│ [ property field: select chips ]│ ▢ Context 3      │
│                                │ ◦ Property [val]  │  filled props,
│  body (MarkdownPM, editable)   │ ◦ Property [val]  │  Standard rows
│                                │ [ + Add Property ]│
│ ────────────────────────────   │                  │
│ Label › Label  (breadcrumb)    │          Delete   │
└────────────────────────────────┴──────────────────┘
```

#### 4.1 Header zone

- **Icon** — optional SF Symbol via `IconPicker` (`.iconPickerPopover` / `updateItemIcon`).
- **Title** — the filename, inline-edited. On title change the save routes through `renameItem` (atomic rename + connection cascade + `NameCollisionValidator`), **not** `updateItem` (§10). A rejected collision surfaces as an inline error directly below the title field.

#### 4.2 Property Field zone (select / multi-select chip-row)

- Renders the template-pinned select & multi-select properties as a single **horizontal row of boxes**, each rendered full-row (Standard): title + its value control. Value editing uses `ChipDropdown` (the Component-Library control — colored, label-correct; **not** `MultiSelectChips`).
- **Two-level pinning** (Templates pane configures, §7): the zone is keyed to a property **type** (select/multi-select for V1); within it the user pins **specific** properties of that type. Unpinned select/multi-select properties fall to the inspector.
- **Capacity = tunable framework data, not hard-coded.** Seed cap = **4** select/multi-select properties in the single row (derived from the mock against the ~480pt main column; matches the Planned-doc first pass). Enforced twice: the Templates pane blocks pinning past the cap; the renderer defensively slices. Nathan tunes the seed against the built window — a data edit.
- **Integrity (type-filter):** a pinned property whose type is no longer select/multi-select, or whose ID is missing, is **filtered out** of the chip-row and (if still in schema) flows to the inspector. `TemplateResolver.promotedEntries` already drops missing IDs (`TemplateResolver.swift:32-35`); a select/multi-select **type filter must be added** — and applied to **BOTH** `promotedEntries` **and** the `promoted()` / `ItemWindowRenderer.partition()` path. (Blast-radius finding: `partition()` reads *unfiltered* `promoted()`, so filtering only `promotedEntries` leaves off-type pins in the main panel. Prefer one shared `promotedForField()` helper both consume.)

#### 4.3 Body zone

- The Markdown-source description IS the `.md` body (single source; no frontmatter `description`). Rendered through the existing `MarkdownPMEditor` flipped to `isEditable: true` with a real `Binding`. **Required frame constraint:** because the editor wraps its own `NSScrollView` (`ClampedScrollView`) and the renderer body is inside a SwiftUI `ScrollView` (`ItemWindowRenderer.swift:183`), the editable body must get an explicit `.frame(maxWidth: .infinity, minHeight:, maxHeight: ~200)` to bound the nested-scroll interaction (the 500-cap keeps content short).
- Capped at **500 source chars** (`ItemValidator.maxDescriptionLength` + optional per-Type `description_cap`). A live counter shows remaining and **turns red at/over cap**; in-app over-cap saves are rejected (never silently clamped); external/raw over-cap surfaces a non-blocking warning.

#### 4.4 Inspector zone (right column)

- **Three Context slots, pinned at top, ALWAYS shown** (filled or not), tier order 1/2/3. Edited via `ContextValueEditor` → `ContextPicker`; labels from `TierConfigManager` (dynamic per-Nexus, never hardcoded). The `exposed` flag is ignored — all three always appear (`resolvedProperties(tierConfig:)` always yields exactly 3 tier definitions; `BuiltInContextLinkProperties.swift:48-60`).
- **Filled properties auto-show** below the contexts as editable full-row (Standard) rows (`[icon] Name [value]`), one per property that has a value.
- **"Add Property"** — lists the Type's schema properties **not yet on this item** (excludes `modified_at` / `lastEditedTime` / reserved IDs). Selecting one surfaces it as an inspector row where the value is set inline. **It only assigns a value to this item; never edits the schema.** Add-Property state machine in §11.
- **Auto-managed meta** (`id`, `created_at`) collapse to a divider-separated read-only section; `modified_at` shows read-only (Last Edited Time); none appear in Add-Property.

#### 4.5 Footer zone

- `DetailFooterBar`: container **breadcrumb** (left). **Delete** (destructive) bottom-right, wired to `deleteItem(_:in:)` / `deleteItem(_:inTypeRoot:)` behind a standard macOS `.confirmationDialog`; on confirm the window closes. (The stub `ellipsis.circle` "Options" menu is retained/absorbed as the template-options entry.)

### 5. Per-type value editing

Every editor already ships and is production-proven (`PropertyCellEditor` in table cells; `FrontmatterInspector` on Pages). The window composes them. V1 surfaces select/multi-select on the main field; **all** types are editable in the inspector except where noted:

| Type | Editor (Component Library) | V1 |
|---|---|---|
| Select / Multi-select | `ChipDropdown` | main field **and** inspector |
| Status | `ChipDropdown` (grouped) | inspector |
| Date / Datetime | `DateTimePicker` | inspector |
| Number / URL | `TextField` | inspector |
| Checkbox | `Toggle` / `PropertyCheckbox` | inspector |
| File | `FileAttachmentEditor` (unwired today) | **read-only** in V1 via `PropertyCellDisplay` (wiring deferred) |
| Tier relations (1/2/3) | `ContextValueEditor` → `ContextPicker` | the 3 Context slots |
| Last Edited Time | read-only | never editable |

### 6. Interactivity & save model

- **Value assignment vs option/schema editing (Nathan, load-bearing).** The window **assigns** a value to *this item* — selecting which option(s)/date/tiers apply, typing body text. It does **not** edit option *definitions* (add/rename/recolor options) or the schema — those stay in Type/Set settings (the existing right-click "Manage options…" routes there). "Editable on the window" always means **value assignment**, never schema/option editing.
- **Value edits = live-save** (`Properties.md` two-save-models): pickers commit on click; text/body debounce (~300ms). No Save button.
- A **new Item-side draft ViewModel** (Pages have `FrontmatterInspectorViewModel`; Items have none) holds draft title/icon/body/properties/tiers and routes each to the right seam:
  - **property value** → `updateItemProperty(item:propertyID:newValue:type:collection:)`. **`.null` gate (required):** the handler must do `if case .null = newValue { updateItemProperty(nil) } else { updateItemProperty(newValue) }` — a `nil`/`.null` removes the key rather than persisting `.null` (`ItemContentManager+CRUD.swift:735-737`). This keeps "absent key = no value."
  - **tier** → `updateItemProperty(…, newValue: .relation(selectedIDs))`; the existing `setRelationIDs` branch routes to the `tier1/2/3` root arrays; clearing → `.null` → key/array cleared.
  - **icon** → `updateItemIcon`.
  - **body** → `updateItem` (description), cap-validated. The ViewModel implements its **own debounce** on the body binding (`MarkdownPMEditor` fires its text binding per keystroke; there is no built-in debounce).
  - **title** → the rename redesign in §10 (never plain `updateItem`).
- Managers re-read from disk before writing (drift-guarded). Last-write-wins per distinct property is acceptable for v1; concurrent same-property edits from a detail-table open on the same item can lose a write — accepted for v1.

### 7. Templates pane (configures which zones/properties are pinned + the property-layout mode)

- The mounted `ItemTemplatePane` (Type/Set settings → ViewSettings popover → `.itemTemplate` route; Items-only, Pages muted) configures pinning — **never** on the live window. It uses the same primitive in `templateMockup` mode.
- **Two levels (Nathan):** (1) which property **type/zone** is on the main window (V1: the select & multi-select chip-row); (2) the **exact specific properties** of that type pinned into it (up to the cap) + order. Unpinned properties of that type fall to the inspector. Writes `template_config.promoted_properties` via `updateTemplateConfig`.
- **Inheritance cascade — pre-existing, NOT new** (locked as Paradigm-Decision #15 + `TemplateResolver.effective`): the **Item Type** template is inherited by all its items; an **Item Set (Collection)** may carry its **own** template that **overrides** the Type's for items in that Set; items directly in the Type root use the Type template. Resolution: `collection?.templateConfig ?? type.templateConfig`. This mirrors the Pages views model (a Vault view vs a per-Collection view).
- Adds the **per-template** `property_layout` control — **this is directly Notion's "show property title" template option**: `standard` shows each pinned property's title alongside its value; `compact` shows value-only (title muted/hidden until interacted). **V1 ships Standard**; Compact present-but-disabled until built.
- **Archetype picker removed.** Archetypes are retired (the renderer stops honoring `layout`); the existing archetype-picker rows in `ItemTemplatePane` must be removed/replaced (otherwise they select an ignored field). The pane's job becomes: pick which select/multi-select properties pin to the chip-row (capped) + order + `property_layout`. (The `display`-per-property `DisplayPickerRow` write path stays harmless — `display` is decode-tolerated — but is no longer the zone discriminator.)

### 8. On-disk schema — CONFIRMED additive/forward-compat (extends registry #15)

**Model (Nathan, locked):** the template records **which property types/zones are on the main window** and, within each, the **exact specific properties** of that type pinned into the zone; the rest of that type flow to the inspector. The Type→Set cascade (§7) is unchanged from #15.

`template_config` is a locked on-disk shape (`Paradigm-Decisions.md` #15; `ItemTemplateConfig` at `Items/ItemType.swift:112-137`, synthesized Codable, all fields optional). The change is **additive/forward-compatible (approved)**:

- **Keep** `promoted_properties` as the pinned-property list. Its element stops the *active use* of `display` (a property's **type → zone** now decides the field treatment); `display` stays decode-tolerated for old files.
- **Stop honoring** `layout` (archetypes retired) — decode-tolerated + ignored (`LayoutArchetype.unknown` already tolerant); no migration needed.
- **Add `property_layout`** — a **net-new** field (does not exist today) with a new tolerant enum `PropertyLayoutMode { standard, compact, unknown(String) }`; **absent decodes to `.standard`**.
- **Keep** `cover_property_id` (reserved, unused V1), `description_cap` (active), `default_description` (reserved).
- **No explicit on-disk zone key in V1** — zone derives from property type. Explicit zone-assignment keys arrive only when Nathan designs additional zones (additive then too).

Net: old item/type/collection files round-trip untouched; the new shape writes on next save (migrate-on-write), consistent with the tolerant-`unknown` precedent. **Needs an explicit yes (or alternative) before the plan locks code.**

### 9. Component reuse map

- **Reuse as-is:** `PreviewWindow`, `ChipDropdown`, `ContextValueEditor`/`ContextPicker`, `DateTimePicker`, `IconPicker`, `PropertyCellDisplay` (read side), `DetailFooterBar`, `PUI` tokens, `FieldBackground`, `TemplateResolver`, `PropertyIDReorder`, manager seams (`updateItemProperty`, `updateItemIcon`, `renameItem`, `deleteItem`).
- **Build new:** the Item-side draft ViewModel; the zone-composing renderer (mode enum); **new Item inspector rows** that compose `ChipDropdown`/`DateTimePicker`/`ContextValueEditor`/`PropertyCellDisplay` directly (do **NOT** modify `PropertyEditorRow` — it is shared with the Pages `FrontmatterInspector`; editing it ripples into Pages); the Add-Property inspector affordance; the `property_layout` field + control; the `PropertyLayoutMode` enum. (The `MultiSelectChips` raw-value bug is a separate, out-of-scope Pages cleanup — not touched here.)
- **Redesign:** `commitItemEdits` (§10).
- **Do NOT use:** `MultiSelectChips` (raw-value-not-label bug; still used at `PropertyEditorRow.swift:167` — replace that call site when building inspector rows); `PropertiesPulldown` / `PropertyPanel` (dead stubs).

### 10. Must-fix prerequisites (verified gaps — each a plan task)

1. **`commitItemEdits` redesign (not a patch).** Today it routes all edits through `updateItem`, which on a title change writes `<NewTitle>.md` but **orphans `<OldTitle>.md`** and skips the connection cascade (`ItemContentManager+CRUD.swift:474-495`; the existing `CommitItemEditsTests` does not catch it — it never asserts the old file is gone). Redesign to a two-step flow: **if title changed → `renameItem` first (await; capture the renamed `Item`), then if other fields changed → `updateItem` on the renamed item.** Make `renameItem` (both overloads) **`@discardableResult -> Item`** — this lets the ViewModel re-hold the renamed ref while keeping all ~6 existing discarding callers (ConnectionLiveRefreshTests, ConnectionCascadeTests, ItemContentManagerTests, ItemMarkdownTransitionTests, NameCollisionTests, production) compiling unchanged. New tests must assert the old file is removed and the old title is absent from the index. (`renameItem` intentionally skips body/schema `validate()` — that's correct; the follow-up `updateItem` covers it.)
2. **Index injection.** `ContextValueEditor`/`ContextPicker` take `index: PommoraIndex?` as a **direct parameter** (not `@Environment`) — `FrontmatterInspector` receives it from `nexusManager.currentIndex` (`FrontmatterInspector.swift:94`). `NexusEnvironment` has no `index` property today. **Recommended:** add `let index: PommoraIndex?` to `NexusEnvironment` (init from `nexusManager.currentIndex`, mirroring the `pageConnectionResolver`/`itemConnectionResolver` pattern) and pass `env.index` into the ViewModel. (Direct-parameter, not a new `@Environment` value.)
3. **Manager injection (branch quirk #15).** The interactive window needs `ItemContentManager`, `ItemTypeManager`, `TierConfigManager`, `ContextDisplayResolver` — all already injected via the single `injectNexusEnvironment` modifier. Any *new* `@Environment` manager read on the window MUST be added there or it asserts `EXC_BREAKPOINT` on first open. (No new managers required by this design.)
4. **`property_layout` field + `PropertyLayoutMode` enum** added to `ItemTemplateConfig` (§8) — a prerequisite for the Templates-pane control.
5. **Type-filter in `TemplateResolver.promotedEntries`** (§4.2).
6. **Remove the stale "Templates — reserved post-v1" placeholder in `TypeSettingsSheet.swift` ONLY** (Items — the live `ItemTemplatePane` route now exists). **Leave `VaultSettingsSheet.swift`'s placeholder in place** — Pages have no live template route yet, and removing it would hollow out the Vault settings section (blast-radius finding). Items-side cleanup only.
7. **Correct `Features/Items.md`** — line 91 still says "items in a Type root get no pinning controls (the pinned set persists per Item Collection)." Under template_config-on-Type, **Type-root items inherit the Type's pinned set.** This correction is a prerequisite doc task (NOT yet done).

### 11. UX states & edge cases

- **Add-Property state machine:** (a) *selected* → the row appears immediately in the inspector with an empty/void input (placeholder), held in the **ViewModel draft** only — no disk write; (b) *editing* → user sets the value inline; (c) *committed* → first real value triggers the first `updateItemProperty` write. **On window close, a surfaced-but-unfilled row is silently discarded** (nothing was written). On reopen, filled props auto-show; unfilled re-add as needed.
- **Title collision** — `renameItem` rejection surfaces inline below the title field; the on-disk file is untouched.
- **Body over-cap** — counter turns red; in-app save rejected with the red affordance; no clamp.
- **Empty schema** — inspector shows the 3 contexts + a disabled/empty Add-Property.
- **Delete** — standard `.confirmationDialog`; window closes on confirm.
- **Meta** — `id`/`created_at` read-only collapsed; `modified_at` read-only; excluded from Add-Property.
- **File rows (V1)** — render read-only via `PropertyCellDisplay` (editor wiring deferred).

### 12. Research-validated pattern (Notion Layouts, 2026)

Independent confirmation the design follows a current, proven pattern: Notion Layouts pin specific properties **horizontally at the top**, expose a **right-side properties panel** you add properties into via "+", support **inline property editing inside the layout builder**, and use **database templates** to prefill values + body with a settable **default**. Pommora's deliberate divergences: "Add Property" surfaces **existing** schema properties only (creating new = Type settings); tiers are never template-prefilled (Notion's own best practice warns against prefilling relations). Sources: Notion Help — Layouts, Database properties, Database templates; Notion API — page property values.

### 13. Out of scope / deferred

Compact rendering; additional in-window zones + field designs (Nathan-designed later); cover/banner zone; value-prefill templates; inspector "sections"; layout-customization UI; file-editor wiring; Page-side parity (`PageTemplateConfig` stays reserved/inert); `@item` / `{{ }}` connections (separate spec).

### 14. Confirmed decisions

1. **§8 on-disk change** — additive/forward-compat: **approved**.
2. **File-property values** — **read-only in V1** (assignment/wiring deferred); see §5 + the value-assignment note in §6.
3. **Template inheritance** — Type→Set cascade is **pre-existing** (Paradigm-Decision #15), not new.
4. **`property_layout`** — equals Notion's "show property title" option; V1 ships Standard.

### 15. Blast radius & ripple (verified — the plan is NOT isolated)

**Affected "assumed-safe" areas (plan must handle):**
- **Pages `VaultSettingsSheet`** — do NOT remove its template placeholder (see §10.6).
- **Pages `FrontmatterInspector`** — isolate by building new Item inspector rows; do NOT edit `PropertyEditorRow` (see §9).
- **`PromotedEntriesTests`** (5 tests) — break under the type-filter (all `.number` fixtures); re-fixture to `.select`/`.multiSelect` + add a "filtered-out" test.
- **`partition()` double-filter** — apply the type-filter to both paths (see §4.2).
- **`renameItem` `@discardableResult -> Item`** — keeps ~6 discarding callers compiling (see §10.1).
- **Archetype picker removal** in `ItemTemplatePane` (see §7).
- **Suite-name landmines for `-only-testing`:** `CommitItemEdits` (not `…Tests`), `ItemContentManager` (not `…Tests`), `ItemMarkdownTransition` (not `…Tests`), `Archetype picker` (literal space), and `ItemWindowLayoutsTests` has **no `@Suite`** → silent 0-test no-op. Verification must use real suite names or run the whole `PommoraTests` target and confirm a non-zero count.

**Verified genuinely safe (not assumed — proven):** Agenda (no shared UI; no `template_config`/`TemplateResolver`/editor usage); detail tables (auto live-refresh via `@Observable`; only the v1-accepted last-write-wins on concurrent same-property edits); sidebar (items aren't rows; rename updates `pinnedManager`/`recentsManager` caches); **no SQLite/index migration** (`property_layout` is sidecar-only; `IndexSchema` untouched); **no file watcher exists** (no echo/double-write; external edits undetected = known v1 gap); `PageTemplateConfig` symmetry intact (LayoutArchetype stays a type; zero Page-side change; defer `property_layout` on Pages per §13); no on-disk fixtures embed `template_config`; `ItemFormatMigration`/`PropertyIDMigration` don't touch it (additive-decode safe); new files auto-include via `PBXFileSystemSynchronizedRootGroup` (no pbxproj edits).

**Data round-trip integrity (verified):** all write seams reach the index — `updateItemProperty`→`upsertItem`→`reconcileContextLinks`; tier write→full `context_links` DELETE+INSERT; `renameItem`→`ConnectionCascade`→`activateConnections`; `deleteItem`→`deleteItem`+`deactivateConnections`. The ONLY integrity gap is the `commitItemEdits` orphan bug (§10.1, the #1 task). Clear-semantics verified: property nil→removeValue (no orphan key); tier `.relation([])`→empty root array + clean context_links; user-relation `[]`→key omitted.

**Paradigm registry:** AMEND #15 (additive `property_layout`; `layout`/`display` decode-tolerated-but-not-honored). The `ItemWindowMode` enum is an internal code-shape change — no registry entry.
