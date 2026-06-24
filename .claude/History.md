### Pommora — History

Changelog + the home for locked decisions — what shipped and when, newest first. Brief by design; current state lives in the feature docs + `PommoraPRD.md`, roadmap in `Framework.md`, editor internals in `// Features//PageEditor.md`. When an entry would enumerate file-level detail, it points to the canonical feature doc instead.

> Everything below the **v0.4.2 Views** milestone is post-version incremental work on the v0.4.x line, not new version cuts.

#### Collections / Sets / Sub-Sets — rename + infinite nesting (2026-06-23→24, branch `collections-sets-rename`)

The Pages model collapses from three tiers to **two**: a schema-bearing **Collection** (top — was `PageType`/"Vault") and a **recursive `PageSet`** ("Set" at depth-1, "Sub-Set" nested), nesting to any depth — old `PageCollection` + `PageSet` merged into one type. Discovery, rendering, adoption, navigation, and the index recurse on the real folder tree (cycle-proof by construction). Only depth-1 Sets carry views; deeper Sub-Sets are plain. `PageType` is retired (along with `EntityKind.pageType`, the vestigial `page_collections` table, and the dead `topTierIDs` view-helper); UI labels collapse to **Collection / Set** ("Sub-Set" derived). SQLite **schema v16** (delete-and-rebuild): `page_types`→`page_collections`, recursive `page_sets` (`parent_collection_id` | `parent_set_id`, exactly one non-null). Full spec → `// Features//PageCollections.md` + `// Features//PageSets.md`.

**Ratified decisions:** **Index FKs = Model A** — `pages.page_collection_id` = the top-tier Collection for every page; `page_set_id` = the immediate container (nil only at the bare top-tier root); the middle is derived by walking `page_sets.parent_collection_id` (regeneratable index → a code convention, not canonical data). **Delete-Set-keep-pages re-homes up one level** into the Set's immediate parent, never flattened to the root. **On-disk sidecar rename deferred** to a deepest-first migration phase (`_pagetype.json`→`_pagecollection.json`; lower tiers stay `_pageset.json`), gated on React-build parity — it can't run mid-nexus without colliding with the existing depth-1 `_pagecollection.json`.

#### Codebase-health refactoring program (2026-06-20→21, branches `refactoring` / `refactoring-phase-b`)

A behavior-neutral hardening program in dependency-ordered phases (A–H), tests green throughout (~1,272 → 1,294). It settled the unratified on-disk shapes, consolidated test-support (`PommoraTests/Support/` shared `Fixtures`), established the `Core` / `Components` / `Domain` / `Features` grouping (Core absorbing the one-file utility folders; ULID alphabet + formatters single-sourced; `FilterBuilder` split from `IndexQuery`), extracted the `SidebarRow` primitive behind all seven sidebar rows, collapsed the SavedView-scope + Page-CRUD duplication onto one scope-parameterized path, split the `ViewSurface` god-view into extensions + hoisted shared View-Settings rows (`SelectableOptionRow` / `LabeledToggleRow`) into `Components`, and modernized the concurrency / typed-throws idioms. **Phase F (manual → synthesized `Codable`) was dropped** — synthesized `Decodable` throws on a missing in-CodingKeys key instead of using the property default, so the pervasive defensive `decodeIfPresent ?? default` can't be synthesized. The two large managers (`NexusAdopter`, `PageTypeManager`) were **kept unified and internally cleaned** rather than split — splitting `PageTypeManager` would regress `private(set)` encapsulation on its observable state.

**Ratified on-disk decisions:** adopted-Page id = `SHA256(path)[:16]` + `adopted-` prefix; option-value minting unified on `opt_<ULID>`; `context_links.id` on `ULID`; `schemaVersion` "current" constants consolidated to one source; `loadAll` heal-on-read kept (self-heal over read-purity); **Area color removed** — Areas are icon-only (`AreaColor` / `Area.color` / `TierConfig.taggingStyle` cut; legacy `color` / `tagging_style` keys drop on next write).

#### Nexus header + Homepage banner (2026-06-19, branches `file-watcher` / `nexus-header`)

The sidebar's top saved-leaves give way to a **Nexus header banner** (per-nexus profile image · title · subtitle); Homepage becomes that header, and the Calendar + Recents leaves are removed (managers kept; only the sidebar surfacing goes). **Locked on-disk:** profile-image bytes in `.nexus/assets/<nexusID>/` with the nexus-relative path at `profile_image` in `settings.json`, subtitle (≤30 chars) at `profile_subtitle` (both via a `defaultsVersion` bump); **title = folder name** — inline rename renames the nexus root folder, so a security-scoped bookmark to the nexus's **parent** is persisted in app-level `state.json` (the rename writes to the parent dir). Homepage gains an optional `banner` (additive; bytes in `.nexus/assets/homepage/`) that adopts the content-view banner band. In-app version-promise placeholder strings removed.

#### File watcher — live external-change sync (2026-06-18, branch `file-watcher`)

An FSEvents recursive watch propagates external / out-of-band on-disk changes into the running app live, **authority by recency, origin-blind**. **Locked paradigm — stamp-on-first-sight:** a `.md` Page authored outside Pommora is minted a real ULID into its own frontmatter (additive, foreign keys preserved) as it appears through the watcher and at index build, so an external rename tracks by id instead of degrading to delete-plus-create. Deferred: Context/Agenda sidecar stamping + open-adopted-Page stamping. Full design → `// Features//Architecture.md` § File-watcher.

#### Grouping redesign — interface shipped (2026-06-15, branch `grouping-redesign`)

`PropertyGrouping` gains `order_mode` / `date_granularity` / `empty_placement` / `hide_empty_groups` (backward-compatible Codable; legacy `order` dormant until Manual); `GroupResolver` gains date bucketing, the three order modes, empty-group placement + hide, and missing-property → `.structural` fallback. New `GroupingPane` discloses an inline property picker (single-membership groupings only). Spec → `// Features//Views.md`. Deferred: view-side group-header manual-drag reorder.

#### Views — Table + Gallery cluster shipped (v0.4.2, 2026-06-12)

**SavedView v2** (property order + hidden set, discriminated GroupConfig, column widths, collapsed groups, card size, cover/banner toggles) feeds a pure in-memory pipeline (filter → group → sort) into two renderers: a custom **Table** (disclosure-row groups, resizable/reorderable/hideable columns, macOS 26 drag-session reorder/move/property-rewrite) and a **Gallery** (Nuke-backed covers). Page covers (frontmatter) + container banners (sidecar) store in `.nexus/assets/`; a toolbar Views dropdown drives multi-view CRUD with last-active-view persistence in `state.json`. **Native `Table` / `DetailRow` / `PropertyColumnBuilder` retired.** Spec → `// Features//Views.md`.

#### Sets — third operational tier (v0.4.1, 2026-06-11)

The Pages-side hierarchy is now **Vault → Collection → Set (optional) → Pages** — a Set is a schema-less folder inside a Collection (views / settings / open-in inherit from the Collection), strict three levels (deeper folders roll up into the nearest Set). Index schema **v13 → v14**. Bundled: `ContainerIDHealer` mints fresh ULIDs for Finder-duplicated container sidecars. Spec → `// Features//Sets.md`.

#### Contexts Decoupling — free-standing Areas / Topics / Projects (2026-06-10)

The three context tiers became **free-standing** — Projects decoupled from Topics (no containment, no `parents`, no promotion), Topics lost their `parents`, tier-1 Space renamed to **Area**. Each tier is a folder + config sidecar (`_area.json` / `_topic.json` / `_project.json`) owned by sibling managers; the sidebar's Spaces/Topics headings collapsed into one **Contexts** section. Index schema → **v13** (delete-and-rebuild, no migration). Context→context relations deferred. Spec → `// Features//Contexts.md`.

#### v0.4.0 — PagePreview real window + shared inspector (2026-06-10)

The in-window glass-card preview was rebuilt as a regular **`NSPanel`** owned by `PreviewTarget` — natively activating + never-main + key, the one combination no SwiftUI scene type expresses. Content stays 100% SwiftUI via `NSHostingView` (same editor / inspector / save path).

#### PagesV2 — Items collapse into Pages (2026-06-09/10)

The Items operational side is **deleted, not migrated** — Page is the only operational entity beside Agenda. Item* code (entity, containers, managers, Item Window, templates, the "Type"/"Set" label pair) deleted wholesale; the `Class` frontmatter stamp dropped (kind comes solely from the parent sidecar; an on-disk `Class` key is preserved foreign frontmatter); `[[` becomes the sole connection syntax; `PageType.open_in` (`compact` | `window`, absent = `window`) added; user sidebar sections (`.nexus/sidebar-sections.json`, navigation-only). Index schema **v10 → v11** (delete-and-rebuild, no migration; legacy `_itemtype.json` folders adopt as Page Types). Retrospective → `PommoraPRD.md` § "What Items Were".

#### Connections — page-level complete (v0.3.5, 2026-06-07)

`[[Page Title]]` shipped end-to-end: resolved links render as blue styled colored text (unresolved show literal brackets), navigation via `resolvePageByIDOrTitle`, a `[[` Liquid Glass autocomplete, a body-scanned `connections` index table, and a `connectionsChanged` restyle bus. **Rename cascade** atomically rewrites all referencing bodies in one `SchemaTransaction`; nexus-wide title uniqueness enforced on create/rename. Bundled the in-editor page-header icon (default OFF). Spec → `// Features//Connections.md`.

#### Contextv2 — Drop Relations → Contexts (2026-06-04)

User-creatable relation properties removed; `tier1`/`tier2`/`tier3` are the only relation-type connection. The `$rel` token, `PropertyValue.relation` codec, and `RelationTarget.contextTier` substrate kept; `droppingUserRelations()` strips any non-reserved relation def at decode. SQLite `relations` table renamed `context_links`; all `Relation*` symbols → `Context*`.

#### Folder exclusion — vault-owned `excluded_folders` (2026-06-03)

A per-Nexus `excluded_folders` list on `settings.json` (anchored vault-relative paths) that Pommora ignores **completely** at any depth. One `FolderFilter` value (case-insensitive + NFC, ancestor-walk match, `..`-escape rejected), loaded directly from disk so it works in the pre-`NexusEnvironment` index pass. No editing UI yet. Spec → `// Features//Architecture.md`.

#### MarkdownPM rebuild — one parse spine + AST emphasis (2026-06-03)

The vendored `swift-markdown-engine` folded into the Pommora-owned **`MarkdownPM`** package and reassembled behind a characterization net: ONE cached Apple-AST parse spine per edit (the caret-stutter fix), emphasis relocated onto the Apple `swift-markdown` AST (underscore adopted; CommonMark rule-of-3), the dual styler collapsed to one owned `MarkdownPMStyler` + `MarkdownPMTheme`, heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]`. Editor internals → `// Features//PageEditor.md`; behavior → `// rules//MarkdownPM.md`.

#### Date property redesign + View Settings dynamic sizing (2026-06-02)

The separate `.date` type retired into one unified "Date" (`.datetime`, date-only vs with-time via a Display Time setting; normalize-on-read migration, `.date` kept for backward decode only). `DateFormat` → 4 labelled formats; new `TimeFormat`. `ViewSettingsPane` sizes to content (header + footer pinned, middle scrolls). Spec → `// Features//Properties.md`; design rule → `// Guidelines//Design.md`.

#### Title-collision data-loss fix + NexusEnvironment injection (2026-06-01)

A same-title create / rename / cross-container move silently overwrote a sibling's file — now **rejected** uniformly via one shared `NameCollisionValidator` (case-insensitive; same-id rename exempt) + no-overwrite guards on the move paths. **Locked policy: reject, not auto-suffix** (registry #13) — supersedes the prior "duplicates allowed" claim. `ContentView`'s ~16 hand-wired manager optionals collapsed into one `NexusEnvironment` container + a single `.injectNexusEnvironment(_:)` modifier (quirk #15).

#### Manager de-dup + vault-table display-only + creation-order default (v0.3.4, 2026-05-31)

Type detail tables are display-only for row order (mirror the sidebar); empty-state default changed alphabetical → **creation order** (ULID-ascending). The five duplicated schema-mutation methods across the managers extracted into two shared `@MainActor` services (`SingletonSchemaService` + `PerTypeSchemaService`) driven by per-side adapters — zero behavior change.

#### Native IconPicker (2026-05-30)

Replaced third-party `SymbolPicker` with Pommora's own **`IconPicker`** — a Liquid-Glass dropdown over the full SF Symbols 6 catalog with search + favorites, hosted via one `.iconPickerPopover` modifier; the SPM dep removed.

#### View Settings editor redesign + Design.md consolidation (v0.3.2, 2026-05-27)

The per-property editor rebuilt to Figma; the popover-family UIX lessons folded into `// Guidelines//Design.md` (the standalone `UIX-Baseline.md` removed).

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` tier then reverted it the same cycle (it duplicated Collections' role). **Kept:** the stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`), the "+"-header-is-sole-vault-creation sidebar tweaks, and `NexusAdopter.autoTagMissingSidecars`.

#### v0.3.1 — Properties end-to-end (2026-05-26)

View Settings popover live: schema CRUD via Edit Properties, dynamic property-value columns in detail Tables, click-to-edit cell popovers, Property Visibility pane. Added `DisplayVariant`, `PropertyChipColor`, chip primitives, and the `updateProperty` / `updateView` / `updatePageProperty` manager methods. Ratified decisions → `// Features//Properties.md`.

#### v0.3.x — View Settings chrome slice + follow-up sweep (2026-05-25)

First slice of the View Settings popover (a static scope-routed toolbar button). Two invariants locked: **`loadAll` syncs in-memory parents to the SQLite index** (quirk #14 — kills the FK-19 toast) and **every detail-view `@Environment` must be injected at `ContentView`** (quirk #16). Restored sidebar disclosure (mitigates the quirk #9 asymmetry crash); the `"Name"` → `"Title"` label sweep.

#### v0.3.0 — Properties FEATURE-COMPLETE (2026-05-25, merged `3d1bc19`)

Full property system + SQLite index + placeholder UI: `PropertyType` (11 types), `PropertyValue` / `FileRef`, `PropertyDefinition` (stable ULID id), `SchemaTransaction` (atomic multi-file commit), schema CRUD on all managers, validators; GRDB `IndexBuilder` + `IndexUpdater` + `IndexQuery`; attachments (copy-on-attach). Shape locked in a 2026-05-19 brainstorm. Full detail → `// Features//Properties.md`.

#### Flat-Layout refactor (2026-05-23, tag `flatlayout`)

Dropped the `Pages/` / `Items/` / `Agenda/` wrapper folders — Types + singletons live at the nexus root, classified by sidecar filename. Per-kind sidecars replace the unified `_schema.json`. The adopter handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat), tolerates mixed per-folder states, and cleans co-located orphans (**rule: only ONE per-kind sidecar is authoritative per folder**). On-disk spec → `// Features//Architecture.md`.

#### ParadigmV2 — operational-layer domain refactor (2026-05-22/23, tag `paradigmV2`)

Vault becomes Pages-only; AgendaItem split into **AgendaTask + AgendaEvent** (EKReminder + EKEvent); Sub-topics renamed Projects; Settings scaffold (`settings.json` + `SettingsManager`) laid. New locked rule: **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.**

#### Editor — construct passes (v0.2.7.2 → v0.2.7.5, 2026-05-20/21)

The dynamic-syntax editor architecture established (markers reveal under the caret, render off it; on disk standard CommonMark): HR / divider, lists, polish bundle (bullet-glyph substitution, task-list shorthand, bracket auto-pair, arrow auto-format), and blockquote. Locked: portable-source-with-overlay is the pattern. Full architecture + lessons → `// Features//PageEditor.md`.

#### Editor — Nexus folder adoption (v0.2.7.4, 2026-05-21)

Obsidian-parity "open folder as Nexus" — both open paths run `NexusAdopter.scan` + a preview-and-confirm sheet. Locked: adoption runs on every open (idempotent); 3-level structural depth; existing notes never mutated (`PageFile.loadLenient` synthesizes a stable `id`, never writes back until edited).

#### v0.2.7.1 — Navigation shipped + simplified (2026-05-19)

Navigation shipped (Pinned + Recents; `⌘T` / `⌘[` / `⌘]`; state in `state.json`). The bloated first attempt was cut back. New rule (`// Guidelines//CRUD-Patterns.md`): the PreviewWindow primitive ships per kind before any "open in preview" UI.

#### v0.2.7.0 — native TextKit 2 editor (2026-05-18, tag `v0.2.7.0`)

Native TextKit-2 Page editor shipped after the WKWebView and Milkdown directions both failed Nathan's visual baseline. **`.md` is the architectural firewall** — domain wiring survived every editor pivot (quirk #13).

#### v0.2.x foundation (2026-05-16 → 18)

- **v0.2.0 — paradigm scaffolding** (merged `e3daedb`). Every entity Codable + validator + `@MainActor @Observable` manager, CRUD-able end-to-end. Swift 6 strict concurrency + ExistentialAny enabled. Established: the confirmation-before-code protocol; `PropertyValue.relation` as `{"$rel": "<ULID>"}`; stub-and-progressively-replace (quirk #7); sidebar selection chrome via `.listRowBackground` (quirk #9).
- **v0.2.1 → v0.2.6** — CI (`xcodebuild` + `-only-testing:PommoraTests` on `macos-26`, quirk #4); `swift-format` baseline (quirk #12); the `.trash//` data foundation (`Filesystem.moveToTrash`).

#### Founding era (2026-05-16 → 18)

- **v0.1.0 — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, `.nexus/` init, per-nexus App Support subdir keyed by ULID.
- **v0.0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`; both side panes drag-resizable, widths persist.
- **Editor library exploration.** Tiptap/WKWebView → Pallepadehat → Milkdown → native TextKit 2; `.md` as the portability firewall.
- **Semver locked** (`major.minor.patch`; minor = completed feature, patch = touch-up, major reserved for v1.0.0).
