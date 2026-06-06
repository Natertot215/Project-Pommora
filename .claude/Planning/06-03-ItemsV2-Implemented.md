## Items V2 — Implemented (As-Built Spec)

> **What this is:** the **as-built record** of ItemsV2 — the model that **SHIPPED** (30 green tasks, 2026-06-03). The body below describes what was built; the closing **As-Built Status** notes the deviations + what's deferred/muted. Everything here is IMPLEMENTED.
>
> **⚠️ Do not conflate with the planned rework.** The next-iteration redesign — a **zone-based Item Window that RETIRES the `LayoutArchetype`/archetype model described below** — lives in `06-03-ItemsV2-Planned.md` and is **design-only, not built**. This doc = what exists; that doc = what's next.
>
> **Companions:** execution record → `06-03-ItemsV2-Plan.md` (30 tasks, all green) · ship log → `History.md` · schema → `Guidelines/Paradigm-Decisions.md` (#15).

### Background — the Decision That Frames Everything

We considered reverting Items off Markdown into "something else entirely" (JSON records / media-primary entities). A 9-agent review (5 lenses → 3 consolidators → synthesis), grounded in code, said **don't**:

- Premise "a folder can't tell item from page" is **overstated** — the parent Type sidecar already declares kind; the only real gap is sidecar-less dropped folders defaulting to Page.
- Premise "it collapses the Class machinery" is **false** — there's no `if markdown then page` branch; a revert would *re-fork* the just-unified codec, *adding* conditionals.
- "db-backed items" **breaks two locked load-bearing laws** ("no user data trapped in SQLite" + agent file-legibility).
- The differentiator Nathan actually wants (item→page connection, graph treatment) is **independent of file format**.
- Web precedent: Capacities / Tana / Anytype type their objects by **schema + layout on a uniform substrate**, not by a different file type; **Obsidian Bases** validates frontmatter-as-records exactly. Tools that split substrate (Anytype, SiYuan, Logseq) sacrifice file-legibility — Pommora's core differentiator.

**Resolution:** Items **stay Markdown**. They become categorically different via a per-Type **Template** layer — schema + display recipe — on the current substrate. This spec details that model.

### Core Model — What I Want

#### Properties Are the Content (No Separate "Fields")

- **One registry: properties.** A "field" is just a property given a render role by the template. `file`, `link`, and `photo` are property *types*, not a separate concept — keeping them as properties avoids item-side overlap and stays DRY.
- **New image-filtered `.file` property** (accepts image files only) — shared by **Items and Pages** (Pages use it for the page banner). Implemented as a `.file` with an image accept-filter, not a new `PropertyValue` case.
- **Foreign-frontmatter contract preserved.** A frontmatter key "counts" only if the Type config declares it; anything else is preserved-by-value and ignored. Adding an Obsidian property to an item never pollutes the Pommora Type. (This is already how properties behave — fields inherit it for free.)

#### Template = the Display Recipe (Distinct From View Layout)

- **Hard principle — Templates ≠ View Layout.** *View Layout* governs storage-level views/display (the existing ViewSettings surface). *Templates* govern the content's own display (the item panel / page surface). Two separate systems; do not conflate the template editor with ViewSettings.
- A **Template** is two things: (1) a named **layout archetype**, and (2) the set of **promoted properties** shown on the main panel — all other properties live in the "all properties" inspector / dropdown.
- The archetype dictates how a promoted property *renders*: the same photo property shows as a thumbnail in a Compact layout or as a banner in a Gallery layout. The property is content; the template decides treatment.

#### Template Scope: Type Default → Collection Override

- The **Item Type** defines the default template. An **Item Collection** may override it. Non-Collection items use the Type default. The same override model applies to Pages. **The cascade governs both the layout archetype and the promoted-property set** — one resolution (Collection → Type), not two. **Collection-level `templateConfig` is new** (only `ItemType` carries it today); the plan adds it to the Collection layer.

#### The Item Window — a Draggable Floating Panel

- A **draggable, dismissible floating panel**: movable around the screen, closeable. **Not** a full-frame surface, **not** a static/anchored popover, **not** a modal sheet. This has been the intended model from day one (docs are being corrected to match — see Landmines).
- **No macOS traffic lights.** The panel uses **custom chrome** — a custom close affordance and a custom drag region — never the standard red/yellow/green window controls. (This constrains the panel-form choice; see Landmines.)
- Today it is technically a SwiftUI `.sheet` (centered, modal, non-draggable — `SidebarDetailView.swift:126-128`). **Resolved:** rebuild as a **native SwiftUI scene** — `WindowGroup(for: ItemRef.self)` + `.windowStyle(.plain)` + `.windowLevel(.floating)` + `WindowDragGesture` + `dismissWindow` — which on the **macOS 26.4** target satisfies all four requirements (no traffic lights, custom drag, floats non-modally, custom close) with **zero AppKit**. The floating panel and the roadmapped **PreviewWindow** primitive are therefore the **same build**: build the generic `PreviewWindow` first, make the Item Window its **first consumer** (no throwaway one-off). Caveats: `.plain` removes the default keyboard close (re-add Escape-to-close) and strips material/shadow (add `.regularMaterial` + rounded card + shadow so it reads as a floating card). `NSPanel` is held as a fallback only if `.plain` reads too bare.

#### Description — MarkdownPM, 500-Char Cap

- The description **renders through MarkdownPM** (styled markdown) in the panel. MarkdownPM is domain-agnostic (a `Binding<String>` surface), so it drops onto the description field directly.
- Capped at **500 source chars**. The description IS the Markdown body — single source of truth, no separate frontmatter description field — so the cap binds the body.
- **Cap enforcement (resolved):** the single `ItemValidator.maxDescriptionLength` constant is 500; `ItemTemplateConfig.descriptionCap` becomes an optional **per-type override** layered over the 500 default. In-app saves over cap **reject with an error** (today's behavior, files-are-canonical). A raw Obsidian edit that overflows surfaces a **non-blocking warning** rather than hard-failing the file (Pommora must tolerate external edits).

#### Layout Archetypes (Render Recipes) + Single-Renderer Architecture

> **⚠️ Superseded direction.** This archetype model SHIPPED (only `standard` has a real recipe; the rest are muted stubs), but the planned rework **retires `LayoutArchetype` entirely** in favor of fixed type-bound **zones** — see `06-03-ItemsV2-Planned.md`. Read this section as "what's built," not "where it's going."

The Template's `layout` selects one archetype. Each archetype declares **how its "all properties" overflow surface presents** — a **dropdown** button/frame *or* a side-pane **inspector** (Nathan's directive: the overflow mode is a property of the layout, not a separate archetype and not a free user toggle). Promoted properties always render on the main panel; the rest live in that overflow surface, which **supplements** them (never duplicates — see Landmines). **Target: 5 layouts** pre-populated in the settings pane (exact set *Open* — finalized in Figma):

1. **Compact Stack** *(Bookmark)* — small panel; overflow = dropdown.
2. **Standard Panel** *(default / today)* — promoted inline in the body; overflow = dropdown.
3. **Banner / Two-Column** *(Movie)* — designated cover as banner/media column; overflow = inspector.
4. **Gallery / Media Card** *(Photo)* — image-dominant; overflow = dropdown.
5. **Wide / Horizontal** — landscape panel; overflow = dropdown (the "horizontally-heavy" layout).

(The former "Inspected Panel" is **not** a 6th archetype — "inspector" is the overflow mode any tall/wide archetype declares, since the side-pane toggle already exists on every window.)

```
Compact            Standard           Inspected
┌──────────────┐   ┌──────────────┐   ┌──────────┬──────┐
│(i) Title  [×]│   │(i) Title  [×]│   │(i) Title │Props │
│── Link ──────│   │Description … │   │Desc …    │prop: │
│── Desc ──────│   │── Props ──   │   │Desc …    │prop: │
└──────────────┘   │prop: value   │   └──────────┴──────┘
                   └──────────────┘
Banner/Two-Col          Gallery             Wide/Horizontal
┌──────────┬───────┐   ┌──────────────┐   ┌───────────────────┬─────┐
│(i) Title │[BANNER]│  │[ LARGE IMAGE]│   │(i) Title          │ ▾   │
│Link …    │[ IMG ]│   │   [×]        │   │Desc …             │prop │
│Desc …    ├───────┤   │(i) Title     │   └───────────────────┴─────┘
│Desc …    │prop:  │   │── short desc │
└──────────┴───────┘   └──────────────┘
```

- **Settings pane behavior (Nathan directive):** **unmute the Templates pane** on the item-side settings menu (it becomes a live `ViewSettingsRoute` section, no longer a muted placeholder). Within it, render the layout options as a **list driven by the `LayoutArchetype` enum cases**, **each option muted** (tertiary-styled / disabled) until its recipe ships; **unmute each as it lands.** A pre-populated list of enum cases — not stubbed config UI — until a real archetype is implemented.
- **Single-renderer architecture (resolved — supersedes the earlier `ItemWindowA…F` stub framing):** there is **one** `ItemWindowRenderer`, not six views. A layout is **data** — a `LayoutArchetype` enum case + a promoted-property-ID array — consumed via `AnyLayout(archetype.layout)` over **one** shared child set (preserves view identity/state, animates across archetype switches), with a custom `Layout` **region-recipe** backing only the archetypes plain stacks can't express (Banner/Two-Column; inspector mode). The existing `PropertyEditorRow` is the per-field builder, threaded once through a `RenderContext`. Adding a layout = **add an enum case + a recipe**, never a new view with copy-pasted field rendering (directives #1/#2). "Muted-until-shipped" survives as unshipped enum cases / unimplemented recipes, not empty view files. *Drag-to-reorder of promoted properties uses a **native SwiftUI** component — **no SPM dependency**. Extract a generic `PropertyIDReorderList` from the existing `PropertyVisibilityPane` (`ViewSettings/PropertyVisibilityPane.swift:82-90,117-154` — it already ships `.draggable(id)` + `.dropDestination(for: String.self)` + a `reorder([String])` splice persisting `SavedView.visibleProperties`) and reuse it for the item-window pinned strip (today append-only, no reorder UI — `ItemWindow.swift:128-135`). Same `[String]`-of-IDs model on both surfaces; zero schema change; the "bonus" settings-panel reuse is the component's **origin**, not an afterthought. Rejected adding a dependency: `visfitness/reorderable` (MIT) is the only defensible SPM option but re-imports a pattern the repo already owns natively; `globulus/...` is stale/iOS-feel. Fallback if richer drag feel is ever wanted: vendor Daniel Saidi's MIT `ReorderableForEach`.* This updates paradigm decision #4 / branch quirk #7's layout framing.

#### Banner / Cover — a Designated Property

- A template **designates one image property as the banner/cover**; the layout renders that specific property as the banner. Applies to Items (Banner/Gallery archetypes) and Pages (page banner). Implemented via `PropertyDefinition.accept: ["image/*"]` (already supported — `PropertyDefinition.swift:36`); **no new `PropertyValue` case** — the template config names which property ID is the cover. The banner render slot is **new** (mirrors the unbuilt Pages overlay approach).

#### Window Surfaces & Controls (Figma mockups, 2026-06-03)

Nathan supplied mockups + this governing rule: **pinned properties + their placement/order are edited in the TEMPLATE, not on the live item.** The live item window *renders* the resolved template (and edits property **values**); which properties are pinned, in what order/placement, is a per-Type/Collection template concern. The plan must allow for:

- **Edit the template via a "mockup item frame."** The Templates pane renders a **representative item** through the *same* `ItemWindowRenderer` (WYSIWYG) where the user **pins/unpins** properties (an "Add Property" checklist, ✓ = pinned) and **drag-sorts their placement**. Saving writes `template_config` (promoted set + order + cover + archetype) via `updateTemplateConfig`, scope-resolved (Collection override → Type default), and **applies to every item the template governs**. (Mockup image 1 = this editor — the "Add Property" checklist + sortable pinned rows + tier relations as their own rows above user props; image 2 = the resulting live items.)
- **Re-order is "via the template," not a per-item sort.** `promoted_properties` is an **ordered array** set in the template editor; the **live item window has no promote/reorder control** — it renders the order the template defines. (Resolves the earlier "sorting" ambiguity: no derived sort-key, no per-window sort — the order is the stored template array.)
- **Custom chrome, no traffic lights** (confirms LD-3): the header carries **two custom corner affordances** (a custom close + a custom drag/control), never the macOS red/yellow/green. A **footer bar** shows a container **breadcrumb** (left) + an **options control** (sliders glyph, right) that opens the template / view options.
- **Overflow presentation by archetype:** the resolved properties render as a right **side-pane inspector** (`icon + name + value-pill` rows; tiers **Spaces/Topics/Projects** above user props) or a **horizontal chip strip** above the body — the `usesInspector` axis. Property **values** are editable on the live item; pinning/order is not.

#### Item → Page Connection: `@item` Chips

- Items appear on pages as **chips** via a **new `@item` body syntax**, distinct from `[[wikilinks]]` (which stay page→page). A chip renders as the item's **icon + title in styled colored text** (the relation-chip look). **Resolved direction:** `@item` is a **MarkdownPM body grammar** (wikilink-adjacent, reusing `WikiLinkService` patterns), **not** a schema-level relation — keeps the link inline + file-legible. **Build deferred to v0.4.0** with graph edge-weighting (below).
- **Decentralized model:** pages link to each other (wikilinks); items appear wherever referenced (chips) plus in their item vaults. A page may surface a list of its attached items.
- **Forward consideration (graph):** the graph DB must weight connection **kinds** differently — page↔page wikilinks vs item→page `@item` chips vs frontmatter relations. Where `@item` body edges are indexed, and how the graph weighs each kind (incl. an item rendering as duplicate "orbiting" nodes across the pages that reference it), is *Open* — scoped with the v0.4.0 wikilink / graph work.

#### Pages Parity

This spec is mostly Items + how they relate to Pages; Pages are not overhauled. Page-side parity:

- **Symmetric `PageTemplateConfig`** (currently missing — see Realities). **Resolved:** add it now (mirroring `ItemTemplateConfig`) as a reserved, null-round-trip structure (codebase-first per directive #3), restoring the symmetric-code HARD RULE. Page template content: pinned under-title properties, banner positioning (via the shared cover property), pre-defined body text, and an **open-in default (preview | full page)** — the open-in field is present but **inert** pending PreviewWindow.
- **open-in is inert until the PreviewWindow primitive ships** — there is no open-mode infrastructure today, and the lever is gated by a locked prerequisite. Page Templates otherwise mirror the Item model: Type default → Collection override; Templates ≠ View Layout.
- **Page "open-in: preview" is a parallel track (Nathan).** Once the Item build lands the shared PreviewWindow primitive, Page open-in-preview becomes buildable as an **independent parallel workstream**. The ItemsV2 plan only lays the inert `PageTemplateConfig.openIn` field + the shared primitive — **not** the Page open-in UI.

### What Exists to Support It — Codebase Realities

Verified against source (`file:line`):

- **The exact slot is reserved on disk** — `ItemTemplateConfig { layout, descriptionCap, defaultDescription }` at `Items/ItemType.swift:109-119` (field at `:19`); round-trips as `null` today. Its three axes map 1:1 to layout / cap / seed text.
- **Side-pane inspector + dynamic frame already ship** — `ItemWindow.swift:53-64` (480↔760 width switch + conditional 260pt pane). The "tall → side-pane" archetype generalizes existing machinery.
- **Pinned-property chips already ship** — `ItemWindow.swift:33-35` reads `collection.pinnedProperties`. "Promote to main panel" **is** this mechanism.
- **Context-adaptive settings dropdown exists** — `ViewSettings/ViewSettingsScope.swift:19-30` routes one surface across page/item Type + Collection. Muted "Templates" rows already exist on **both** sides: `StorageMenuRoot.swift:56`, `VaultSettingsSheet.swift:597` (Pages), `TypeSettingsSheet.swift:549` (Items). History precedent: single static instance whose content adapts via scope (`History.md:90`).
- **PropertyValue** has `.file([FileRef])` + `.url`, **no** `.photo` — `Vaults/PropertyValue.swift:43-44`. The photo property = image-filtered `.file`.
- **Item Window is a `.sheet` today** — `Detail/SidebarDetailView.swift:126-128` (centered, modal). Not a panel; no `NSPanel`/floating-panel code exists yet.
- **Nothing locks the window form** — `Guidelines/Paradigm-Decisions.md:25` lists "sheet vs popover" as freely refactorable; decision #14 locks only Items-as-Markdown.
- **Roadmap already commits the redesign** — `Framework.md:88-89` (Item Window redesign + PreviewWindow → `WindowGroup(for: ItemRef.self)`); `Guidelines/CRUD-Patterns.md:7-11` (PreviewWindow prerequisite).
- **Symmetry gap** — `templateConfig` exists on `ItemType` but is **absent** from `PageType`; adding a parallel `PageTemplateConfig` *restores* the symmetric-code HARD RULE.
- **MarkdownPM is domain-agnostic, one call site** — `Pages/PageEditorView.swift:210` + `External/MarkdownPM/.../NativeTextViewWrapper.swift:23`; trivially re-wired to the item description.
- **Naming** — keep code types `PageTemplateConfig` + `ItemTemplateConfig`; one user-facing "Template" section that morphs by scope. Already-reserved Prospect: `Features/Prospects.md:44-51`; reserved on-disk note: `Features/Items.md:110-112`.

### Landmines & Considerations

- **Double-render bug (resolved)** — properties currently render in *both* the body and the inspector when open, and `PinnedPropertyChip` re-implements `PropertyEditorRow`'s entire 11-case value switch. Under the single-renderer model the split is **data**: promoted properties on the main panel, the rest in the overflow surface (dropdown/inspector per archetype) — so the overflow **supplements**, never duplicates. Also extract a shared read-side `PropertyValueDisplay` from `PropertyEditorRow` so chips + inspector + main rows share one value renderer (directive #2). *(Confirm the current double-render wasn't a deliberate reference affordance before removing — Fix Log #10.)*
- **Panel form (resolved — native scene, PreviewWindow-first)** — see *The Item Window*. The macOS 26.4 target makes the native SwiftUI scene route (`.windowStyle(.plain)` + `.windowLevel(.floating)` + `WindowDragGesture`) strictly better than `NSPanel`; `NSPanel` is held as fallback only if `.plain` reads too bare.
- **open-in / preview is gated** — no open-mode infra exists today; the "open in: preview | full page" lever is inert until the PreviewWindow primitive lands. (Corrects an earlier brainstorm assumption that this was a cheap near-term win — but PreviewWindow is now in-scope as the panel build, so this unblocks as a side effect.)
- **Layout encoding (resolved — enum + region-recipe)** — `template_config.layout` is a typed `LayoutArchetype` **enum** (named archetypes; enum+switch HARD RULE), with a custom-`Layout` region-recipe backing the archetypes plain stacks can't express. Only the exact **on-disk enum string values** remain to lock → AskUserQuestion confirmation protocol at plan-write time + amend registry decision #14.
- **500-char cap** (raised from 250; `Paradigm-Decisions.md:58`). Since the body IS the description, the cap binds the Markdown body — define behavior when a raw-Obsidian edit exceeds it.
- **Banner render slot is new** (mirrors the unbuilt Pages overlay).
- **`@item` is a new parser/grammar** — a new inline body construct (MarkdownPM / wikilink-adjacent), **not** the relation-by-ID path, so the graph must index body-level edges. Scope with v0.4.0 wikilinks.
- **DRY stub discipline** — shared field + interaction methods hoisted **once**; the 6 archetype stubs (`ItemWindowA…F`) are wired but UIX-empty (and muted in settings) until individually built. Prevents a big-bang layout build.
- **Effort shape (not a plan)** — splits into independent layers: template data model · the morphing template editor (filling the unmuted pane) · the floating-panel host · per-archetype rendering. The data + editor layers can precede the panel + visuals.
- **Doc-sweep pending** — ~9 downstream docs still call the Item Window a "popover" (`PommoraPRD.md`, `Features/Items.md`, `Pages.md`, `Agenda.md`, `Properties.md`). The canonical `CLAUDE.md` directive is already corrected to "floating panel"; the rest are queued (3 assert behavior — "anchored," "never standalone window" — tied to the panel-form decision). **Plus an Item-Templates correctness pass (Nathan):** existing docs (`Features/Items.md`, `Features/Prospects.md`, possibly `Properties.md`) may already describe Item Templates with stale intent — the doc pass must reconcile them to the **locked ItemsV2 model** (single renderer, overflow-mode-per-archetype, native reorder, image-filtered cover), not just the popover wording.
- **Precedent guardrail** — keeping records as frontmatter-on-a-uniform-substrate preserves file-legibility (Obsidian Bases model); the template-not-substrate approach is what keeps Pommora's differentiator intact.

### As-Built Status (shipped 2026-06-03)

Shipped in 30 green tasks (`a027145`…`40d910f`; whole test target green at 1278). What landed against this spec:

- **Built as specified:** one config-driven `ItemWindowRenderer`; `LayoutArchetype` enum (on-disk `compact|standard|banner_two_column|gallery|wide|reserved` + tolerant `unknown`) via `AnyLayout`; `template_config` (`layout` + `promoted_properties:[{id,display}]` + `cover_property_id` + `description_cap` + `default_description`) on **Type + Collection** (Collection override → Type default); 500-char cap + per-Type override; native floating scene (`WindowGroup(for: ItemRef.self)` + `.windowStyle(.plain)` + `.windowLevel(.floating)` + the reusable `PreviewWindow` primitive) **replacing the deleted `.sheet`/`ItemWindow.swift`**; promoted/overflow **disjoint** (double-render fixed structurally); the **Templates settings pane** (archetype picker + WYSIWYG mockup-item-frame + per-property display + image-filtered cover + Type→Collection override + reset).
- **Two deviations from the written plan:** **T4.0** simplified to just publishing the live env via `AppGlobals.current` (the `ItemWindow` relationDisplay refactor was throwaway — the scene hosts the renderer); **T4.5 inserted** to restore the live window's save machinery (`hydrate`/`save`/`commitSave`/drift guard) — so the live window edits **title + icon + description** (drift-guarded save), but property-**value** rows are **display-only** for now (the save path carries `draftProperties` through, ready for the editable-rows follow-up).
- **Selectable-but-muted:** only `standard` has a real recipe (`ItemWindowLayouts.hasRecipe`); compact / banner_two_column / gallery / wide / reserved are stock-layout stubs disabled in the picker until their Figma visuals land.
- **Deferred (not built):** `@item` chips + graph edge-weighting (→ v0.4.0); Page open-in-preview UI (parallel track once Pages consume `PreviewWindow`); the bespoke Banner/Two-Column region `Layout`.
- **Post-review fix:** `renameItemCollection`/`renamePageCollection` were silently dropping `templateConfig` (+ icon/pins/views) on rename — fixed to copy-mutate (`6508d28`).
- **Reused (not built by ItemsV2):** the footer is the parallel session's `DetailFooterBar`; the read-side renderer is the generalized `PropertyCellDisplay`; the reorder splice is `PropertyIDReorder.move`; the promoted→definition join is `TemplateResolver.promotedEntries`.

> **This whole model is slated for rework.** The `LayoutArchetype`/archetype layer is replaced by a fixed type-bound **zone framework** in `06-03-ItemsV2-Planned.md` (design-only). The pieces likely to survive the rework: the floating scene + `PreviewWindow`, `template_config` as the assignment store (shape evolves), the Templates pane (becomes the zone assigner), `PropertyCellDisplay` as the field renderer, and Type→Collection override.
