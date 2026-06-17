### Pommora — History

Changelog + the home for locked decisions — what shipped and when, newest first. Brief by design. Current state lives in the feature docs + `PommoraPRD.md`; roadmap + phases in `Framework.md`; editor internals in `Features/PageEditor.md`. When an entry would enumerate file-level detail, it points to the canonical feature doc instead.

#### Grouping redesign — interface shipped (2026-06-15, branch `grouping-redesign`)

The Grouping View-Settings pane was rebuilt and the grouping data model extended. `PropertyGrouping` gains `order_mode` (configured / reversed / manual), `date_granularity` (day/week/month/year), `empty_placement` (top/bottom), and `hide_empty_groups` — backward-compatible Codable (legacy `order` stays dormant until Manual). `GroupResolver` gains date bucketing (ISO-format keys, lexicographic = chronological), the three order modes, empty-group placement + hide, checkbox-nil→Unchecked (no nil bucket), and a missing-property→`.structural` fallback. The new `GroupingPane` (replaces `GroupPane`): a Grouping toggle that discloses an inline property picker (Select / Status / Checkbox / Date — multi-value tiers + multi-select intentionally excluded so every group is single-membership), a per-type Order popout, a Date-By popout, a no-Add manual Options reorder list, and a secondary bottom-pinned empty-group footer. Adjacent fixes landed on `main` in the same stretch: inline-edit commit lag (optimistic cache in `PageContentManager`), stale Select/Status options (the table's reload signature now hashes option content), inspector pickers commit immediately (debounce only free-text), and the property-visibility list ordered by `property_order` with in-place un-hide + drag handles. **Remaining (deferred to a future session):** view-side grouping — group-header manual-drag reorder + the table disclosure-chevron animation. Spec + plan → `Planning/06-15-Grouping-Redesign.md` / `Planning/06-15-Grouping-Plan.md`.

#### Views — Table + Gallery cluster shipped (v0.5.0, 2026-06-12)

The 19-task Views cluster shipped. SavedView v2 (`property_order` + hidden set, discriminated GroupConfig, column widths, collapsed groups, card size, cover/banner display toggles) feeds a pure in-memory pipeline (filter → group → sort) into two renderers: a custom SwiftUI **Table** (26pt quinary-zebra rows, disclosure-row groups, resizable/reorderable/hideable columns, selection + keyboard, macOS 26 drag-session reorder/move/property-rewrite with a live insertion preview) and a **Gallery** (8/6/4 grid, interactive cards, Nuke-backed covers, live drop indicator). Page covers (per-page frontmatter) + container banners (per-sidecar) store in `.nexus/assets/`; a toolbar Views dropdown drives multi-view CRUD with last-active-view persistence in `state.json`. Sort / Filter / Group / Layout View-Settings panes ship; Edit Properties is now schema-only. **Native `Table`, `DetailRow`, and `PropertyColumnBuilder` are retired.** Spec-as-fact → `Features/Views.md`.

#### Sets — third operational tier (v0.4.1, 2026-06-11)

The Pages-side hierarchy is now **Vault → Collection → Set (optional) → Pages**. A Page Set is a schema-less folder inside a Collection (`_pageset.json` — identity + icon + `page_order`; views / settings / open-in inherit from the Collection), owned by a dedicated `PageSetManager`. Strict three levels — deeper folders stay sidecar-less and roll up into the nearest Set; adoption auto-tags depth-2 folders (supersedes the 2026-05-21 "2-level structural depth" adoption lock). Index schema v13 → v14 (`page_sets` table + nullable `pages.page_set_id`); all in-vault page moves are strip-free; Set delete prompts two modes (pages-up vs trash-whole). Bundled hardening: `ContainerIDHealer` mints fresh ULIDs for Finder-duplicated container sidecars (Collections + Sets). Spec → `Features/Sets.md`.

#### Contexts Decoupling — free-standing Areas / Topics / Projects (2026-06-10, 994 tests green)

The three context tiers became free-standing. **Projects decoupled from Topics** (no containment, no `parents`, no `project_links`, no promotion); **Topics lost their `parents`**; **tier-1 Space renamed to Area**. Each tier is now a folder with a config sidecar (`_area.json` / `_topic.json` / `_project.json`), owned by three sibling managers (`AreaManager` / `TopicManager` / `ProjectManager`). The sidebar's separate Spaces/Topics headings collapsed into one **Contexts** section with three `square.grid.2x2` disclosure rows (Areas / Topics / Projects); the dead sidebar search bar was removed. Index schema → **v13** (v12 dropped `contexts.parent_topic_id`; v13 re-stamped the Area kind strings — delete-and-rebuild on open, no data migration). Executed subagent-driven on `main`, P1–P6 each a green commit. Spec + plan → `Planning/Superseded/06-10-Contexts-Decoupling-{Spec,Plan}.md`. Context→context relations, transitive page roll-up, and the composed-blocks surface are deferred to a future design pass. **Previously** (what the prior model worked like, for the record): Areas were flat `.space.json` files named "Spaces"; Projects lived *inside* their Topic's folder (file location = the containment parent); Topics carried a `parents` array of Spaces, and Topic rows showed parent-Space color tags; deleting a Topic could promote its Projects up a tier; the sidebar had separate "Spaces" and "Topics" headings rather than one Contexts section.
#### v0.4.0 — PagePreview real window + shared inspector (2026-06-10, 987 tests green)

The V8 in-window glass card lasted one morning of real use: laggy drag (a SwiftUI gesture repainting a TextKit editor per frame), no opens from the main-pane tables, and a save-bricking validation bug on first contact with The Nexus. Rebuilt as a A regular `NSPanel` owned by `PreviewTarget` is natively activating + never-main + key — the one combination no SwiftUI scene type expresses: refocus-from-outside works, it takes keyboard focus, and it never dims the main window. Content stays 100% SwiftUI via `NSHostingView` (same editor / inspector / save path). 

Verified end-to-end on The Nexus via an accessibility-driven interaction matrix. `WindowGroup`, `NSWindow`, and `UtilityWindow` were all trialed until all desired functionality and design was finally achieved with an `NSPanel` + `NSHostingView`.

#### PagesV2 — Items collapse into Pages (2026-06-09/10, through `c7f48c7`, 986 tests green)

> The PagePreview bullet below describes the V8 in-window card, rebuilt the next morning as a real window — see v0.4.0 above.

The Items operational side is **deleted, not migrated** — Page is now the only operational entity beside Agenda. Detailed retrospective of what Items were → `PommoraPRD.md` § "What Items Were". Plan: `Planning/Superseded/PagesV2.md`.

- **Item* code deleted wholesale** — the Item entity, `ItemType` / `ItemCollection` containers, `ItemTypeManager` / `ItemContentManager`, the Item Window, templates (`template_config`), and the "Type" / "Set" UI label pair (Settings drops the item label fields; legacy `settings.json` with retired keys loads decode-tolerantly).
- **`Class` frontmatter stamp dropped** — kind comes solely from the parent folder's sidecar; an on-disk `Class` key is preserved foreign frontmatter, never written.
- **`[[` declassed to the sole connection syntax** — `{{ }}` retired entirely to plain text; the chip *visual* survives as one dormant Component Library design file (`Properties/Chips/ChipLink.swift`), wired to nothing.
- **`PageType.open_in` (`compact` | `window`; absent = `window`)** — per-vault presentation replaces the separate entity; a segmented footer toggle in the View Settings popover sets it.
- **`PagePreview` built; the standalone `PreviewWindow` primitive eliminated** — an in-window draggable Liquid Glass card (`PreviewStack` overlay in `ContentView`; 475×475 collapsed, resizable, cascading multi-card, opens locked with the inspector open, context-menu Open Page promotes to the main pane). A main-pane page never previews (edit-conflict guard).
- **User sidebar sections shipped (band 3)** — `.nexus/sidebar-sections.json`, navigation-only vault grouping, single-membership; empty sections render header-only.
- **Index schema v10 → v11** — item tables dropped; delete-and-rebuild on open, page-only `connections`. **No data migration anywhere** — the index is regeneratable and `.md` content keeps its shape; legacy `_itemtype.json` folders adopt as sidecar-less Page Types (stale sidecar left inert; test-pinned).

#### Connections — page-level complete (2026-06-07, v0.3.5)

> `{{ }}` item syntax removed by PagesV2; `[[ ]]` is the sole syntax.

`[[Page Title]]` connection syntax shipped end-to-end. Bundles Contextv2, MarkdownPM performance, index hardening, and page icon.

- **Syntax + render.** Resolved page links: blue styled colored text (Obsidian-style). Unresolved: literal text with brackets visible. `linkTextAttributes = [:]` decouples click detection from styling.
- **Navigation.** `resolvePageByIDOrTitle` (ID-first → title NOCASE); `resolveParentFromIndex` queries `page_type_id`/`page_collection_id` from SQLite. Uses `PageFile.loadLenient` for adopted pages.
- **Autocomplete popup.** `[[` fires a Liquid Glass popup; `titleCandidates` ranks exact → shortest → A-Z; caret nudges async to the nearest token boundary if it lands in a collapsed marker.
- **SQLite index.** `connections` table: `source_id`, `target_title` (normalized), `kind`, `source_range`. `ConnectionScanner` body-scans on write; `connectionsChanged` bus restyles open editors.
- **Rename cascade.** `WikiLinkCascade` atomically rewrites all referencing bodies — one `SchemaTransaction`. Nexus-wide title uniqueness enforced on create/rename.
- **Index hardening.** `ON CONFLICT DO UPDATE` parent upserts; launch scan honors `excluded_folders`; schema 9 → 10.
- **MarkdownPM performance.** `constructLineStarts` precomputed; heading/HR/blockquote/bullet reads from caches; scroll lag eliminated.
- **Page icon.** In-editor page-header icon + "Add Icon" hover; `showPageIcon` toggle (default OFF).

Full spec → `Features/Connections.md`.

#### Contextv2 — Drop Relations → Contexts (2026-06-04)

User-creatable relation properties removed; `tier1`/`tier2`/`tier3` are now the only relation-type connection. The `$rel` token, `PropertyValue.relation` codec, and `RelationTarget.contextTier` substrate are kept. `droppingUserRelations()` strips any stored relation def that isn't a reserved `_tier1/2/3` ID at decode time. `relations` SQLite table renamed `context_links`; all `Relation*` symbols renamed `Context*` (ContextChip, ContextValueEditor, ContextPicker, etc.). Orphaned `$rel` member values cleared during the migration walk; legacy `applyRelationTransforms` deleted (dead after the decode filter).

Plan → `Planning/Contextv2.md`.

#### ItemsV2 — floating Item Window + per-Type templates (2026-06-03)

> Superseded by PagesV2 — everything shipped here was deleted with the Items side.

#### Folder exclusion — vault-owned `excluded_folders` (2026-06-03)

User-configurable per-Nexus folder exclusion (branch `folder-exclusion`; full target 1204 tests / 0 failures). An `excluded_folders` list on `.nexus/settings.json` — anchored vault-relative paths (`Archive`, `Projects/Old`) — that Pommora ignores **completely**: never adopted, shown in the sidebar, indexed, walked for content, or touched by the launch auto-tag/cleanup pass, at any depth. One `FolderFilter` value (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected) is the single rule, loaded from disk via `FolderFilter.load(for:)` so it works in the pre-`NexusEnvironment` index pass, and applied as a subtractive veto in front of every user-content discovery site via a defaulted `folderFilter:` param on `Filesystem.childFolders` / `descendantFiles`. The dot/underscore/`node_modules` convention skips stay untouched; `.nexus/` internal Context reads (Areas/Topics/Projects) stay exempt. No editing UI yet — hand-edit the JSON; the Settings panel wires a row to the existing field when it ships. Settings gained `currentDefaultsVersion` 4 (no-op v3→v4 migration).

Full record → `Planning/2026-06-03-Folder-Exclusion-Plan.md`; on-disk + behavior spec → `Features/Architecture.md`.

#### MarkdownPM rebuild — one cached parse spine + AST emphasis + one owned styler (2026-06-03)

The vendored `swift-markdown-engine` folded into the Pommora-owned **`MarkdownPM`** package (`External/MarkdownPM/`) and reassembled cleaner behind a characterization net (branch `markdownpm-rehome`; package 119 tests / app 1166, 0 failures). Shipped: ONE cached Apple-AST parse spine per edit (`ParsedDocument` holds `appleDocument` + `lineIndex` — the #9 caret-stutter fix); the 173-line hand-rolled asterisk-only emphasis parser DELETED, emphasis now located on the Apple `swift-markdown` AST (underscore adopted; intra-word underscore + emphasis-inside-code / wikilinks / link-destinations suppressed; CommonMark rule-of-3 + cross-line); the two divergent heading detectors unified to one CommonMark rule; the dual styler collapsed into one owned `MarkdownPMStyler` + the theme merged into one `MarkdownPMTheme`; new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]` (H6 = body). Runtime TextKit / OS-bug workarounds preserved verbatim. Every behavior divergence logged (D-EMPH-1..7 / D-CODE-1 / D-HEAD-1/2 / #9).

Full record → `Planning/2026-06-02-MarkdownPM-Plan.md` (Execution Record) + `Planning/MarkdownPM-Divergence-Ledger.md`; editor internals → `Features/PageEditor.md`; markdown behavior → `rules/MarkdownPM.md`.

#### Date property redesign + View Settings dynamic sizing (2026-06-02)

- **Date-only type retired → one unified "Date".** The separate date-only `.date` type is dropped from the picker (`userCreatable` 10→9); the unified type (`.datetime`, relabelled "Date", icon `calendar`) covers both, date-only vs with-time chosen by the new **Display Time** setting. Migration is normalize-on-read — `PropertyDefinition`'s decoder folds a `.date` schema type → `.datetime` (the `.date` enum case is retained for backward decode only). `ItemValidator` / `PageValidator` / `SchemaConflictDetector` treat `.date` and `.datetime` *values* as interchangeable, so existing date-only values load clean.
- **Display config reworked.** `DateFormat` → 4 type-labelled formats (no "Default", no ISO): Short (`March 1st`) / Full (`Wednesday, March 1st 2026`) / `DD/MM/YYYY` / `MM/DD/YYYY`; new `TimeFormat` (None / 12 Hour / 24 Hour). Legacy v0.3.1 `DateFormat` values migrate on decode. Value editors use the native `.compact` `DatePicker`.
- **View Settings popover sizes to content.** New `ViewSettingsPane` container — panes grow `PUI.Pane.minHeight`→`.maxHeight` (360→500) then scroll the middle with header + footer pinned (single container-owned `ScrollView`); the fixed `measuredPaneHeight` cage + `PaneHeight.swift` removed. Resize is the native `NSPopover`'s (SwiftUI can't animate the glass window height).

Full spec → `Features/Properties.md`; design rule → `Guidelines/Design.md`.

#### Items are Markdown — Shape A (2026-06-02)

> Superseded by PagesV2 — Items as Markdown and the `Class` frontmatter stamp are gone; foreign-frontmatter-preserved-by-value survived into Pages.

#### Title-collision data-loss fix + NexusEnvironment injection + cleanup (2026-06-01)

- **Title-collision data-loss fix (all file-backed entities).** A same-title create / rename / cross-container move silently overwrote a sibling's file (e.g. a Page's `.md` body) — `filename = title` + an overwriting atomic write. Now **rejected** uniformly: one shared `NameCollisionValidator` (case-insensitive; same-id rename exempt) covers Pages, Items, and Agenda Tasks/Events on create + rename; the cross-container move paths (Page/Item between-Collection + across-Type, which commit via `SchemaTransaction`) and `Filesystem.renameFile` got no-overwrite guards (`Filesystem.guardNoFile`); the six container validators (Spaces / Topics, Page+Item Types & Collections) delegate to the same validator. Self-recasing one's own title (`notes`→`Notes`) is allowed — the rename guard compares on-disk file identity, not the case-folded name. Policy: **reject**, not auto-suffix → registry #13; supersedes the prior "duplicates allowed" doc claim. Independent duplicate titles remain a Prospect (needs a title field).
- **`NexusEnvironment` injection container.** `ContentView`'s ~16 hand-wired manager optionals + two scattered `.environment(...)` chains collapsed into one container owning every manager + a single `.injectNexusEnvironment(_:)` modifier — removes the missing-inject `EXC_BREAKPOINT` footgun (quirk #15); behavior-identical to the former `constructManagers`. Not `@Observable` (held in `@State`, read whole; members are `let`).
- **Cleanup:** `debounceCoalescesRapidEdits` made deterministic (event-poll + settle, reads the VM's real debounce interval) — the wall-clock flake is gone. Shared `Filesystem.guardNoFile` + a `NameCollisionValidator(…else:)` overload collapse the per-side collision wiring; `AppGlobals.publish(...)` collapses the 9-slot publish block.

#### Manager de-dup + vault-table display-only + creation-order default (2026-05-31, v0.3.4)

Three-stage consolidated refactor; per-commit green, full suite 1045.

- **Vault-table display-only + creation-order** (`f4bd2ad`→`a8585fa`). Page/Item **Type** detail tables are display-only for row order (mirror the sidebar's file-level order); Collection/Set tables keep flat reorder. Empty-state default order changed alphabetical → **creation order** (ULID-id ascending in `OrderResolver`), uniform across all containers, portable, no new field. Reason: SwiftUI `Table` can't combine collapsible grouping with reliable nested reorder. Full per-view order/sort/group deferred to the v0.7.0 view work.
- **`ItemTypeManager.typesByID` removed** (`df977d1`→`2c89fea`). The Item-only by-id lookup dict + its 18 `rebuildTypesByID()` calls deleted; both readers resolve by `types.first { … }` scan, matching `PageTypeManager`. The two type managers are now symmetric. Behavior-preserving.
- **Property-mutation de-dup** (`07eba8b`→`7f21698`). The 5 duplicated schema-mutation methods (`addProperty`/`renameProperty`/`deleteProperty`/`reorderProperty`/`changeType`) across all four managers extracted into two shared `@MainActor` services — `SingletonSchemaService` (Agenda) + `PerTypeSchemaService` (Page/Item) — driven by per-side adapters. ~590 lines removed; copy-paste collapsed 5×4 → 5×2. Zero behavior change (paired relations, transactional member-strip atomicity, `MemberFileStrip.forEach` resilience, the delete-tolerance fix, concrete per-manager error enums all preserved). Closed 4 prior test gaps first.

Flagged: `AgendaEventManagerError.cannotDeleteBuiltinProperty`'s doc says "events have no `_status`" yet the guard still blocks it (preserved; decide separately). `ULID.generate()` lacks same-millisecond monotonicity, so creation-order is exact across ms, stable-arbitrary within one.

#### Native IconPicker (2026-05-30)

Replaced the third-party `xnth97/SymbolPicker` with Pommora's own **`IconPicker`** — a compact (260×306) Liquid-Glass dropdown over the full SF Symbols 6 catalog (`IconCatalog`, 6,195 names) with search + Saved/favorites (`IconFavorites`). Forced by the library hardcoding a 540pt frame + `internal` catalog. Hosted via one `.iconPickerPopover` modifier at every icon-edit entry; the SPM dep is now removed. Also restyled `OptionEditPopover` to match the View Settings field. Crash fix: `IconPickerSheet` needed `TopicManager` in the detail env-chain (quirk #15). Live-update fix: `StorageMenuRoot` header reads a `liveScope` re-resolved from the managers.

#### Make Relations Real — render half + index/picker hardening (2026-05-29/30)

Follow-on to the Relations Redesign (both now superseded by Contextv2). Entity `icon` denormalized into SQLite index; `RelationDisplayResolver` (now `ContextDisplayResolver`) resolves target ID → icon + title; tier columns render correctly. `IndexBuilder.populate` made per-row (bad rows skip + log instead of rolling back). Picker popover zero-size glass-blob fixed via fixed panel width — this earned **quirk #18** (confirm the data before blaming the store). `MemberFileStrip.forEach` shared across all 8 strip sites.

#### Relations Redesign — relations + tiers unified (2026-05-29)

> Superseded by Contextv2 above — user-creatable relation properties are gone; tier tagging is the sole relation mechanism.

#### View Settings editor redesign + Design.md consolidation (2026-05-27, v0.3.2)

Rebuilt the View Settings per-property editor to Nathan's Figma. The popover-family UIX lessons (PaneDivider rail standard, pinned destructive footers, Subheadline / Callout type scale, plain-`Menu` inline selectors, back-label names the previous pane, idempotent inline-`TextField` commit) folded into `Guidelines/Design.md`; the standalone `UIX-Baseline.md` removed.

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` third tier then reverted it the same cycle — it duplicated Collections' rigid-grouping role and conflicted with the planned view-organization system. **Kept:** the system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`, `68caf96`), the sidebar context-menu tweaks (no "New Vault" in the row menu; "+" header is the sole vault-creation path), and `NexusAdopter.autoTagMissingSidecars`.

#### v0.3.1 Properties end-to-end (2026-05-26, v0.3.1)

View Settings popover live: schema CRUD via Edit Properties pane, dynamic property-value columns in all 4 detail-view Tables (`TableColumnForEach`, macOS 14+), click-to-edit cell popovers, Property Visibility pane. Added `DisplayVariant` + `DateFormat` enums, `PropertyChipColor` (12 cases), chip primitives (`RelationChip` / `FileChip` / `LinkChip`), `updateProperty`/`updateView`/`updatePageProperty` manager methods. Ratified decisions in `Properties.md`.

#### v0.3.x View Settings chrome slice (2026-05-25)

First slice of the View Settings popover: a static `slider.horizontal.3` toolbar button at `ContentView` level inside the existing primary-action Liquid Glass capsule (order `[ViewSettings] [NavDropdown] [InspectorToggle]`), opening an empty 300×360 popover scope-routed via `ViewSettingsScope` derived from `sidebarSelection`. Locked: the button is a single static instance whose content adapts via scope — never per-detail-view. A `Button(role: .close)`-in-popover crash earned **quirk #17** (the role-only init only works inside a `.toolbar`).

#### v0.3.x follow-up sweep (2026-05-25)

Post-v0.3.0-merge design-system + UX correctness sweep (`88c9367` branch tip). All 4 storage detail views shipped with footers + session-local drag-reorder; sidebar disclosure restored (Item Types fold like Vaults, Sets are flat leaves — mitigates the quirk #9 asymmetry crash); real Create sheets replace stubs; chip primitives + `PommoraUIX.md`; icon pipeline wired through create methods; `"Name"` → `"Title"` label sweep; tier labels → `"Spaces"/"Topics"/"Projects"`.

Two forward-binding invariants locked: **`loadAll` syncs in-memory parents to the SQLite index** (quirk #15 — eliminates the recurring FK-19 toast; `LoadAllIndexSyncTests`) and **every detail-view `@Environment` must be injected at `ContentView.detail`** (quirk #16). Tables get no vertical column borders (Notion-flat).

#### v0.3.0 Properties — FEATURE-COMPLETE (2026-05-25, merged `3d1bc19`)

71 commits, 11 phases. Full property system + SQLite index + placeholder UI. Data layer: `PropertyType` (11 types), `PropertyValue`/`FileRef`, `PropertyDefinition` (stable ULID id), `SchemaTransaction` atomic multi-file commit, `PropertyIDMigration`, schema CRUD on all 4 managers, `PropertyDefinitionValidator`. SQLite: GRDB.swift, `IndexBuilder` + `IndexUpdater` + `IndexQuery`. Attachments (`AttachmentManager`, copy-on-attach), `_status` built-in on Agenda. All interaction paths working (pickers, Settings sheets, `FrontmatterInspector`, `CalendarDetailView`). Full detail in `Features/Properties.md`.

#### v0.3.0 Properties — scope redirection (2026-05-23, brainstorm)

v0.3.0 narrowed to **data layer + minimum-viable placeholder UI only**; the real Properties Pulldown + Property Panel UI redirected to v0.3.1 (Figma-driven). Surface architecture locked: properties live in the Pages Pulldown / Page Preview inspector / Item Window inspector — never the main-window inspector (which becomes the Claude chat). AgendaTaskSchema's placeholder `type` Select dropped for Status as sole built-in. Editor patches shipped alongside (foldable-headings fix + `folded_headings` persistence; em/en-dash auto-syntax).

#### Flat-Layout refactor (2026-05-23, tag `flatlayout`)

Dropped the `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/` wrapper folders — Page Types / Item Types / Tasks + Events singletons now live at the nexus root, classified by sidecar filename. Six per-kind sidecars replace the unified `_schema.json`: `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`. The adopter handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat), tolerates mixed states per-folder, cleans co-located orphans, and is `.DS_Store`-tolerant. On-disk spec in `Features/Architecture.md`.

Post-ship hardening (5 commits): adoption preview fires only on structural migration (non-Pommora root folders stay invisible); folder-name fallback for "Collection parent vault not found"; co-located per-kind sidecar orphan cleanup with the rule "only ONE per-kind sidecar is authoritative per folder." Nathan's real nexus migrated successfully — flat with all 8 vaults + Tasks/Events singletons.

#### ParadigmV2 — operational-layer domain refactor (2026-05-22/23, tag `paradigmV2`)

Vault becomes Pages-only as Page Type; Item Type introduced as the parallel Items-side container; Page Collection + Item Collection as parallel sub-folders. AgendaItem split into AgendaTask + AgendaEvent (EKReminder + EKEvent). Sub-topics renamed to Projects. UI label divergence locked: Pages-side "Vault" + "Collection"; Items-side "Type" + "Set"; renameable via Settings. Settings scaffold (`.nexus/settings.json` + `SettingsManager`) lays groundwork. New paradigm rule: "Pommora" prohibited in on-disk schemas + Swift namespace qualifications.

#### Editor — Blockquote (2026-05-21, v0.2.7.5)

Blockquote rewritten from flat background + indent to a renderer-drawn rounded card + continuous vertical accent bar (Notion/Obsidian-style), using the always-show overlay pattern. `> ` (marker + space) activates; the `>` marker is hidden in-editor but standard CommonMark on disk; plain Enter continues, Shift+Enter exits. Multi-paragraph quotes butt-joint via per-fragment corner-rounding (`BlockquotePosition`). Locked: always-show overlay (not dynamic-syntax) for non-interactive markers. Caveat shipped: a small card-vs-bar horizontal positioning mismatch. Full architecture in `Features/PageEditor.md`.

#### Editor — polish bundle (2026-05-21, v0.2.7.4)

Four wins folded into v0.2.7.4: bullet glyph substitution (`-` → `•` via always-on overlay; source stays portable CommonMark); task-list shorthand `-[]` / `-[x]` alongside GFM `- [ ]`; bracket auto-pair guard (fires only after whitespace/line-start so `-[]` works); arrow auto-format (`<-` → `←`, `<->` → `↔`); code colors via system semantics. Locked: portable-source-with-overlay is the pattern for dash bullets; `-` is the only trigger. Decisions + internals in `Features/PageEditor.md`.

#### Editor — HR jitter root-cause + fix (2026-05-21)

Two jitter symptoms on large docs fixed via systematic debugging. **Selection-scope:** `syncHRVisibility` walked the entire document on every selection change (O(N)/tick); scoped to only the prior + current caret paragraphs (O(1)), full walks kept on restyle paths. **Layout-constancy:** caret entering an HR paragraph jumped vertically because dashes + paragraph style swapped; unified so both states share metrics and only dash color toggles. Locked: caret-aware reveal must not change layout; dynamic-syntax services must scope per-caret-move work. Internals in `Features/PageEditor.md`.

#### Editor — Nexus folder adoption (2026-05-21, v0.2.7.4)

Obsidian-parity "open folder as Nexus." Both open paths run `NexusAdopter.scan` and present a preview-and-confirm sheet (top-level folders → Vaults, sub-folders → Collections). `PageFile.loadLenient` accepts `.md` without Pommora frontmatter (synthesizes a stable `id`, never writes back — files stay byte-identical until edited). Locked: adoption runs on every open (idempotent); 3-level structural depth (deeper folders roll up to the nearest Set — see the v0.4.1 Sets entry); existing notes never mutated.

#### Editor — Lists (2026-05-20, v0.2.7.2)

Lists rewrite: space styles immediately (styler-driven, no source mutation), Enter continues with the next marker, Shift+Enter exits. Source on disk is portable CommonMark. Visual indent via paragraph style, not source `\t`. Architecture + lessons in `Features/PageEditor.md`.

#### Editor — HR / divider via dynamic syntax (2026-05-20, v0.2.7.2)

HR shipped via **Obsidian/Typora-style dynamic syntax** (caret on line shows `---`, caret off hides dashes and draws the rule) after the locked always-hidden design failed across two rounds. Establishes the architecture for paragraph-level dynamic-syntax constructs. `---` stays in storage for swift-markdown's ThematicBreak parse. Blockquote + Tables deferred. Known caveat: first HR renders slightly dimmer (sub-pixel). Full architecture + 8 lessons in `Features/PageEditor.md`.

#### Editor — v0.2.7.2 planning (2026-05-20, no code)

Locked the editor-fixes approach: NSTextTable rejected (forfeits Writing Tools/Look Up/etc. on TextKit-1 fallback) — Core Graphics overlay in `MarkdownTextLayoutFragment.draw` is the 2026 Apple-native pattern. HR cursor-atom behavior, structural right-click table menu (no popup), and the Apple-Calendar-card blockquote target locked. Spec in `Features/PageEditor.md`.

#### v0.2.7.1 NavDropdown — shipped + simplified (2026-05-19)

NavDropdown shipped (Pinned + Recents; single-click select / double-click open; `⌘T` / `⌘[` / `⌘]`; state in `.nexus/state.json`). The earlier bloated attempt (tagged `v0.2.7.2` in history) was cut back: standalone preview-window machinery stripped entirely (the real PreviewWindow is a cross-feature primitive — build once, light up per kind), hover-heart favorites → right-click "Pin". New rule (`CRUD-Patterns.md`): the PreviewWindow primitive ships per kind before any "open in preview" UI. Supersedes the earlier tab-strip navigation model.

#### v0.3.0 Properties brainstorm (2026-05-19, no code)

Locked the v0.3.0 Properties shape before implementation: 10-type catalog + Status (3 EventKit-aligned groups), relation scope rules + mandatory dual for Vault/Collection, no inline option creation, property icons, move-strip pulled v0.4.0 → v0.3.0. Carried forward into the shipped work above.

#### v0.2.7.0 — native TextKit 2 editor (2026-05-18, tag `v0.2.7.0`)

Native TextKit-2 Page editor shipped after the WKWebView fork (Pallepadehat) and Milkdown directions both failed Nathan's visual baseline. Stack: Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine` (Apache 2.0, `External/MarkdownEngine/`) + Pommora-side `AppleASTSupplementalStyler` (BlockQuote / Strikethrough / Table / ThematicBreak). Writing Tools / Look Up / spell-check / IME / dynamic colors free. Editable title + body-binding chain wired; character-pair auto-pair; expanded right-click menu; HR-as-real-line; hidden table markup. `.md` is the architectural firewall. Domain wiring (PageRef / PageFile / ContentManager.updatePage / PageEditorViewModel / inspector + sidebar) preserved across both pivots.

#### v0.2.4 → v0.2.6 (2026-05-18)

- **v0.2.4** — `swift-format` baseline (`.swift-format` config, lineLength 120; CI lint step). Earned **quirk #12** (`swift format` is a subcommand via Xcode 26's toolchain; no `swift-format` on `$PATH`).
- **v0.2.5** — `.trash//` data foundation: `Filesystem.moveToTrash` (preserves relative path, timestamp+hex collision suffix); 10 manager delete-sites routed through trash. `.trash//` lives inside the nexus (syncs as user data), unlike the regeneratable index.
- **v0.2.6** — spec catch-up: in-app version strings aligned to the Framework reorder; `Pages.md` + `Sidebar.md` doc passes.

#### v0.2.1 → v0.2.3 (2026-05-17)

Three patches on main after the v0.2.0 merge: parallel-session sidebar UX tweaks + page-selection wiring (`v0.2.1`); CodeRabbit tightening — `ItemWindow` refetch-after-rename recovery + filesystem assertions (`v0.2.2`); GitHub Actions CI baseline (`xcodebuild build` + `-only-testing:PommoraTests` on `macos-26`, `v0.2.3`). Earned **quirk #4** (`.claude/*` IS included in commits — explicit doc commits expected so branch switches preserve doc visibility).

#### v0.2.0 — paradigm scaffolding (2026-05-16/17, merged `e3daedb`)

The 69-commit `paradigm-scaffolding` branch scaffolded the full locked paradigm — every entity gets Codable + validator + `@MainActor @Observable` manager; every entity is CRUD-able end-to-end via sidebar + sheets + detail pane + Item Window. Swift 6 strict concurrency + ExistentialAny enabled; Yams added. 177 tests at merge.

Established protocols + decisions: the confirmation-before-code protocol for paradigm-solidifying choices; `PropertyValue.relation` as tagged `{"$rel": "<ULID>"}`; **stub-and-progressively-replace** execution (quirk #7); sidebar UX = right-click context menus scoped to the cursor (no "+ New" buttons), Pages appear under their parent, Items/Agenda live only in detail-pane Tables; **sidebar selection chrome via `.listRowBackground` at row file level** (quirk #9). A launch crash (`EXC_BREAKPOINT` via missing `.environment` injection) bisected + fixed one-line — the seed of quirks #15/#16.

#### Founding era (2026-05-16…18)

- **v0.1.0 — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, `.nexus/` init flow, per-nexus App Support subdir keyed by ULID. Sidebar mirrors the picked folder. File → Open Nexus; Debug → Reset Bookmark. 25 unit tests.
- **v0.0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`; both side panes drag-resizable, widths persist. 1440×810 default, 960×560 min; title suppressed.
- **Editor library exploration (sessions 6–8).** Reopened the editor decision twice — Tiptap/WKWebView → Pallepadehat fork (CodeMirror) → Milkdown → native TextKit 2 (shipped v0.2.7.0). `.md` as the portability firewall let user data survive every pivot. Earned **quirk #13** (branch-pinned SPM forks need a full cache nuke to bump).
- **Semver locked** (`major.minor.patch`; minor = completed feature, patch = touch-up, major reserved for v1.0.0). The original by-area founding-decisions block was superseded — live truth lives in `Domain-Model.md` / `Properties.md` / `Architecture.md` / `PommoraPRD.md`.
