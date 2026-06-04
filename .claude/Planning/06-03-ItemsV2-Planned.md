## Item Window Rework — Planned (Zone Framework)

> **Status: DESIGN ONLY — NOT built.** Next-iteration direction for the Item Window, captured from a 2026-06-03 Figma-grounded brainstorm with Nathan. The currently-SHIPPED model is in `06-03-ItemsV2-Implemented.md`; this rework **replaces that doc's `LayoutArchetype`/archetype layer**. Nothing here is implemented — do not build from this until it's promoted to a spec → plan. Item Chips are explicitly OUT of scope (separate spec — see below).

### The shift

The shipped window picks a named **layout archetype** (compact / standard / banner / gallery / wide). This rework **retires archetypes entirely.** Instead the window is a **fixed framework of type-bound ZONES**; a template's only job is to **assign specific schema properties into their type's zone**, up to a cap. The layout **emerges** from which zones end up populated — the "variants" (Base / Base+Select / Full) become *computed results*, not authored archetypes.

Nathan, verbatim: *"The 'Zones' can't change, but the properties assigned to them depend on A, the type of property, B, the specific property in that group the schema assigns. So if I have 10 multi-select properties in the vault schema, the template could assign 4 of those max to the main-window."*

### Zones (fixed, type-bound — they never change)

Each zone is reserved for a property type/group, with a cap + one field design. From the Figma mockups:

- **Header** — plan icon + title. Always present.
- **Body** — the bodytext/description (MarkdownPM). Always present.
- **Chip row (top)** — the **select group** (single/multi-select — the "chips"). Renders as a horizontal row of boxes. This is the "Base + Select" variant.
- **Property column (right)** — the **row-design types** (checkbox / status / date / url / file + relations) as `icon + name + value-Label` rows; **tiers (Spaces / Topics / Projects)** as rows atop the column. When this zone is active the body shifts left (two-column). This is the "Full" variant.
- **Footer** — container breadcrumb (`Label > Label`) + an options/settings glyph (opens the inspector / template options).

The zone *set* and each zone's *type binding* are fixed. The template chooses only **which specific schema properties** fill each zone (constrained to that zone's accepted type(s), within the cap) and their **order**.

### Caps (tunable DATA — exact numbers debatable)

Nathan's first pass (explicitly "debatable for the current being"):

- {Multi-select, Select, Number} → **≤ 4 total** (chip row).
- {Checkbox, Status, Date} → **≤ 1 each**.
- {URL, File} → **≤ 2 total**.

Caps are held as **framework data, not hard-coded**, so they retune without code edits. Properties beyond a cap (or not assigned at all) live in the **property panel** (inspector/dropdown), not on the main window.

### Template = assignment only

The template's single job: which specific schema properties fill each (type-matched) zone, + order/sort. Edited in the **Templates settings pane** — the **"edit the template, not the live item" rule HOLDS**: the live window does not curate its own properties.

> **Clarification (resolves the Figma ambiguity):** the "Add Property" checklist in the Figma "Full" mock is for the **property PANEL / sidebar (the "full" type)** — it adds properties to the **panel/inspector, NOT the main window.** Main-window properties are attributed *only* via the template settings.

### Field designs (the DRY hot-swap)

Each property **type** has **one** field design = its fixed visual treatment, bound to its zone. Properties hot-swap into fixed positions; **no per-property `display` override** is needed (the shipped `promoted_properties[].display` likely drops — type+zone decides the treatment). Field designs seen in the Figma: select → chip-row box; row-types → `icon + name + value-Label` row; tiers → row.

### Architecture (replaces the shipped LayoutArchetype machinery)

- **Zones as DATA:** `zone → { accepted types, cap, field design }`. Removes `LayoutArchetype`, the `ItemWindowLayouts` switch, the `archetypeDefaultDisplay` type×archetype matrix, and the fixed-order region `body` — i.e. it directly retires the four lock-in spots the 2026-06-03 flexibility review flagged.
- **Renderer** composes whichever zones have assigned properties → emergent layout. Adding a field design or tuning a cap = a **data edit**, not a renderer rewrite.
- **`template_config` simplifies:** an assignment store (property IDs → their type-zone, + order); caps + field designs are framework data; `layout` + per-property `display` likely removed.

### Live window = display-only (first build step = a clean stub)

The window's intent is **display + an options/inspector affordance** — value-editing/curation is **not** on the live window. **First implementation step: strip the live window to a clean display-only stub** (icon + title + body + footer; no editing, no half-built regions) so the zone framework builds onto bedrock rather than the current renderer. (Nathan: the stub is *"a clean working basis for tomorrow's session… not the ACTUAL intent of the window."*)

### Scope — Item Chips are a SEPARATE spec

The Figma's **"Item Chip"** (in-page `@item` tag: single-click → text-only dropdown + a settings button → secondary pane with property rows for inline edit; double-click → opens the item window) is the **deferred `@item` / wikilink feature (v0.4.0)** — its **own** spec, NOT this rework. It shares the field-row component, so this rework feeds it; but it pulls in graph/tagging concerns that would bloat this design.

### Open / to finalize (when this becomes a spec)

- The full zone roster + each zone's exact field design (beyond chip-row + property-column) — against the finished Figma.
- The exact caps + per-zone grouping (Nathan: debatable).
- The Templates settings pane's editor shape for zone assignment (evolve the shipped pane).
- Build order: display-only stub → zone framework data model → renderer → settings pane.
