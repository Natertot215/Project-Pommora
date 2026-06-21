### Pommora — History

Changelog + the home for locked decisions — what shipped and when, newest first. Brief by design. Current state lives in the feature docs + `PommoraPRD.md`; roadmap in `Framework.md`; editor internals in `Features/PageEditor.md`. When an entry would enumerate file-level detail, it points to the canonical feature doc instead.

> Everything below the **v0.4.2 Views** milestone is post-version incremental work — features and hardening on the v0.4.x line, not new version cuts.

#### Refactoring program — ratified decisions + reorg (2026-06-20→21, branches `refactoring` / `refactoring-phase-b`)

A behavior-neutral hardening pass (build-verified, 1291 tests). **Ratified on-disk decisions** (roadmap → `Planning/06-20-Refactoring-Roadmap.md`):
- **Adopted-Page id** stays `SHA256(path)[:16]` + `adopted-` prefix — path-derived, stable, idempotent re-adoption.
- **Option-value minting** unifies on `opt_<ULID>` (Status already did; Select aligns — existing data untouched).
- **`context_links.id`** unifies on `ULID` (was `UUID` in `IndexBuilder`; index regeneratable, no migration).
- **`schemaVersion` "current" constants** consolidated to one shared source.
- **`loadAll` heal-on-read kept** — opening a nexus silently mints/rewrites missing sidecars (self-heal over read-purity).
- **Area color removed entirely** — the `AreaColor` palette + `Area.color` field + picker are cut; Areas are **icon-only** (the vestigial `TierConfig.taggingStyle` goes with it). Existing `color` / `tagging_style` keys drop on next write.

Then test-support consolidation into `PommoraTests/Support/` (shared `Fixtures` + a test-only `TestableContextManager` protocol; **decided: grow the existing folder, not a separate `PommoraTestSupport` target**) and a folder reorg — `Core/` absorbs the one-file utility folders (CRUD / Ordering / Filesystem / Formatters), `FlowLayout` → `Components/Layout/`, the Crockford ULID alphabet single-sourced (`Core/ULIDAlphabet`), `FilterBuilder` split out of the `IndexQuery` god-file. **Deferred for review:** magic-numbers → `PUI` + `.hoverFill()` (silent pixel risk), `PropertyValue` datetime → `IndexDateFormat` (fractional-seconds = on-disk decode change), the Domain/Features top-level grouping, and the `NexusAdopter` / `PageTypeManager` god-file splits. **Finding (deferred):** an empty `[]` decodes as `.multiSelect([])`, so an empty `.file([])` doesn't round-trip — codec left unchanged pending a decode-semantics call.

#### Nexus header + Homepage banner (2026-06-19, branches `file-watcher` / `nexus-header`)

The sidebar's top saved-leaves (Homepage / Calendar / Recents) give way to a **Nexus header banner** above the List — per-nexus profile image · title · custom subtitle. **Homepage** becomes that header (selecting it opens the Homepage dashboard); the **Calendar + Recents leaves are removed** (their managers stay; only the sidebar surfacing goes), leaving `SavedConfig` vestigial.

**Locked on-disk paradigm:**
- **Profile image** — bytes in `.nexus/assets/<nexusID>/` via `CoverAssetStore` (entity = nexus ULID); the nexus-relative path persists as `profile_image` in `settings.json`. Right-click image picker.
- **Subtitle** — free text (≤30 chars) at `profile_subtitle` in `settings.json`, a hook for future dynamic sources (weather / time / inbox); inline right-click edit. Both fields land via a `defaultsVersion` bump (additive — absent decodes to default).
- **Title = folder name** (no display-name field); inline rename **renames the nexus root folder** on disk. **Root rename ⇒ parent access** — renaming the root writes to its parent dir, so a security-scoped bookmark to the nexus's **parent** is persisted in app-level `state.json` and requested at initial load (free nexus placement kept; the grant's breadth follows location).
- **Homepage banner** — `banner` (nexus-relative path) joins `homepage.json` (additive optional, absent → nil); bytes in `.nexus/assets/homepage/` keyed by the literal `"homepage"` (the singleton's location IS its identity). It's a **bounded header band that adopts the content-view banner** — same height/gutters/title font + `backgroundExtensionEffect` bleed via shared `PUI.DetailHeader` tokens — deliberately not a full-pane background (the homepage has no table beneath). Import / Change / Remove via `HomepageManager.setBanner`.
- **No in-app meta-commentary** — version-promise placeholder strings ("… coming vX") removed; pending detail renders blank.

#### File watcher — live external-change sync (2026-06-18, branch `file-watcher`)

An FSEvents recursive watch on the Nexus root propagates external + out-of-band on-disk changes into the running app live, **authority by recency, origin-blind** — the newest write wins. Reconcile is **surgical** for the safe common case (a debounced batch of existing-Page edits/creates in known scopes → per-scope set-sync) and **coarse** for anything that could orphan a link or misclassify a move (a gone path, a non-Page change, dropped events, or a Page in an unloaded container → atomic full rebuild `IndexBuilder.populate` + manager reload). The index DB is excluded at watcher intake so reconciles can't self-feed; a last-seen-`mtime` gate drops duplicate events + self-write echoes. The open editor live-reloads on a clean external edit and re-points by stable id on an external rename — **unflushed edits are protected**, and a file deleted under a clean editor is never resurrected.

**Locked paradigm — stamp-on-first-sight.** A `.md` Page authored outside Pommora (no `id` frontmatter) is minted a real ULID into its own frontmatter (additive, foreign keys preserved), so an external rename tracks by id instead of degrading to delete-plus-create. Pages are stamped as they appear through the watcher **and bulk-stamped at index build** (folded into `IndexBuilder`'s walk, so an Obsidian import stamps every Page). Deferred — each net-negative to rush: Context/Agenda **sidecar stamping** and **open-adopted-Page stamping**.

#### Grouping redesign — interface shipped (2026-06-15, branch `grouping-redesign`)

The Grouping View-Settings pane rebuilt + the grouping data model extended. `PropertyGrouping` gains `order_mode` (configured / reversed / manual), `date_granularity` (day/week/month/year), `empty_placement` (top/bottom), and `hide_empty_groups` — backward-compatible Codable (legacy `order` dormant until Manual). `GroupResolver` gains date bucketing (ISO keys, lexicographic = chronological), the three order modes, empty-group placement + hide, checkbox-nil→Unchecked, and missing-property→`.structural` fallback. The new `GroupingPane` discloses an inline property picker (Select / Status / Checkbox / Date — multi-value tiers + multi-select excluded so every group is single-membership), per-type Order + Date-By popouts, a no-Add manual Options reorder list, and a pinned empty-group footer. Adjacent `main` fixes: inline-edit commit lag (optimistic cache in `PageContentManager`), stale Select/Status options (reload signature hashes option content), inspector pickers commit immediately, property-visibility ordered by `property_order` with drag handles. **Deferred:** view-side group-header manual-drag reorder + the disclosure-chevron animation.

#### Views — Table + Gallery cluster shipped (v0.4.2, 2026-06-12)

The 19-task Views cluster shipped. **SavedView v2** (`property_order` + hidden set, discriminated GroupConfig, column widths, collapsed groups, card size, cover/banner toggles) feeds a pure in-memory pipeline (filter → group → sort) into two renderers: a custom SwiftUI **Table** (quinary-zebra rows, disclosure-row groups, resizable/reorderable/hideable columns, selection + keyboard, macOS 26 drag-session reorder/move/property-rewrite with a live insertion preview) and a **Gallery** (8/6/4 grid, Nuke-backed covers, live drop indicator). Page covers (per-page frontmatter) + container banners (per-sidecar) store in `.nexus/assets/`; a toolbar Views dropdown drives multi-view CRUD with last-active-view persistence in `state.json`. Sort / Filter / Group / Layout View-Settings panes ship; Edit Properties is schema-only. **Native `Table`, `DetailRow`, `PropertyColumnBuilder` retired.** Spec → `Features/Views.md`.

#### Sets — third operational tier (v0.4.1, 2026-06-11)

The Pages-side hierarchy is now **Vault → Collection → Set (optional) → Pages**. A Page Set is a schema-less folder inside a Collection (`_pageset.json` — identity + icon + `page_order`; views / settings / open-in inherit from the Collection), owned by `PageSetManager`. Strict three levels — deeper folders stay sidecar-less and roll up into the nearest Set; adoption auto-tags depth-2 folders. Index schema **v13 → v14** (`page_sets` table + nullable `pages.page_set_id`); all in-vault page moves are strip-free; Set delete prompts two modes (pages-up vs trash-whole). Bundled: `ContainerIDHealer` mints fresh ULIDs for Finder-duplicated container sidecars. Spec → `Features/Sets.md`.

#### Contexts Decoupling — free-standing Areas / Topics / Projects (2026-06-10)

The three context tiers became **free-standing**. **Projects decoupled from Topics** (no containment, no `parents`, no `project_links`, no promotion); **Topics lost their `parents`**; **tier-1 Space renamed to Area**. Each tier is a folder with a config sidecar (`_area.json` / `_topic.json` / `_project.json`), owned by three sibling managers. The sidebar's separate Spaces/Topics headings collapsed into one **Contexts** section with three disclosure rows. Index schema → **v13** (v12 dropped `contexts.parent_topic_id`; v13 re-stamped Area kind strings — delete-and-rebuild on open, no data migration). Context→context relations, transitive roll-up, and the composed-blocks surface are deferred to a future design pass.

#### v0.4.0 — PagePreview real window + shared inspector (2026-06-10)

The in-window glass-card preview was rebuilt as a regular **`NSPanel`** owned by `PreviewTarget` — natively activating + never-main + key, the one combination no SwiftUI scene type expresses (refocus-from-outside works, it takes keyboard focus, it never dims the main window). Content stays 100% SwiftUI via `NSHostingView` (same editor / inspector / save path). `WindowGroup`, `NSWindow`, and `UtilityWindow` were all trialed before `NSPanel` + `NSHostingView` landed. Verified end-to-end on The Nexus via an accessibility-driven interaction matrix.

#### PagesV2 — Items collapse into Pages (2026-06-09/10)

The Items operational side is **deleted, not migrated** — Page is now the only operational entity beside Agenda. Detailed retrospective → `PommoraPRD.md` § "What Items Were".
- **Item* code deleted wholesale** — the Item entity, its Type/Collection containers + managers, the Item Window, templates, and the "Type" / "Set" UI label pair (legacy `settings.json` with retired keys loads decode-tolerantly).
- **`Class` frontmatter stamp dropped** — kind comes solely from the parent folder's sidecar; an on-disk `Class` key is preserved foreign frontmatter, never written.
- **`[[` declassed to the sole connection syntax** — `{{ }}` retired to plain text; the chip visual survives as one dormant design file wired to nothing.
- **`PageType.open_in` (`compact` | `window`; absent = `window`)** — per-vault presentation, set via a segmented View-Settings footer toggle.
- **User sidebar sections** — `.nexus/sidebar-sections.json`, navigation-only vault grouping, single-membership; empty sections render header-only.
- **Index schema v10 → v11** — item tables dropped; delete-and-rebuild on open, page-only `connections`. **No data migration anywhere**; legacy `_itemtype.json` folders adopt as sidecar-less Page Types.

#### Connections — page-level complete (v0.3.5, 2026-06-07)

`[[Page Title]]` connection syntax shipped end-to-end; bundles Contextv2, MarkdownPM perf, index hardening, and the page icon. Resolved links render as **blue styled colored text** (Obsidian-style); unresolved show literal brackets (`linkTextAttributes = [:]` decouples click detection from styling). Navigation via `resolvePageByIDOrTitle` (ID-first → title NOCASE). `[[` fires a Liquid Glass autocomplete (`titleCandidates` ranks exact → shortest → A-Z). A `connections` index table (`source_id`, normalized `target_title`, `kind`, `source_range`) body-scanned on write; a `connectionsChanged` bus restyles open editors. **Rename cascade** — `WikiLinkCascade` atomically rewrites all referencing bodies in one `SchemaTransaction`; nexus-wide title uniqueness enforced on create/rename. Index hardening (conflict-safe parent upserts, excluded-folder-honoring launch scan, schema 9 → 10) + in-editor page-header icon (`showPageIcon`, default OFF). Spec → `Features/Connections.md`.

#### Contextv2 — Drop Relations → Contexts (2026-06-04)

User-creatable relation properties removed; `tier1`/`tier2`/`tier3` are now the only relation-type connection. The `$rel` token, `PropertyValue.relation` codec, and `RelationTarget.contextTier` substrate are kept. `droppingUserRelations()` strips any stored relation def that isn't a reserved `_tier1/2/3` ID at decode time. `relations` SQLite table renamed `context_links`; all `Relation*` symbols renamed `Context*`.

#### ItemsV2 — floating Item Window + per-Type templates (2026-06-03)

> Superseded by PagesV2 — everything shipped here was deleted with the Items side.

#### Folder exclusion — vault-owned `excluded_folders` (2026-06-03)

User-configurable per-Nexus folder exclusion. An `excluded_folders` list on `.nexus/settings.json` — anchored vault-relative paths — that Pommora ignores **completely** (never adopted, shown, indexed, walked, or auto-tagged, at any depth). One `FolderFilter` value (case-insensitive + NFC, ancestor-walk subtree match, `..`-escape rejected) is the single rule, loaded via `FolderFilter.load(for:)` so it works in the pre-`NexusEnvironment` index pass, applied as a subtractive veto on every content-discovery site. The dot/underscore/`node_modules` skips and `.nexus/` internal reads stay exempt. No editing UI yet — hand-edit the JSON. Spec → `Features/Architecture.md`.

#### MarkdownPM rebuild — one cached parse spine + AST emphasis + one owned styler (2026-06-03)

The vendored `swift-markdown-engine` folded into the Pommora-owned **`MarkdownPM`** package (`External/MarkdownPM/`) and reassembled behind a characterization net. Shipped: ONE cached Apple-AST parse spine per edit (`ParsedDocument` holds `appleDocument` + `lineIndex` — the caret-stutter fix); the hand-rolled asterisk-only emphasis parser DELETED, emphasis now located on the Apple `swift-markdown` AST (underscore adopted; intra-word + in-code / wikilink / link-destination suppressed; CommonMark rule-of-3 + cross-line); the two heading detectors unified to one CommonMark rule; the dual styler collapsed into one owned `MarkdownPMStyler` + `MarkdownPMTheme`; new heading scale `[2.0,1.75,1.5,1.25,1.15,1.0]`. TextKit / OS-bug workarounds preserved verbatim. Editor internals → `Features/PageEditor.md`; behavior → `rules/MarkdownPM.md`.

#### Date property redesign + View Settings dynamic sizing (2026-06-02)

- **Date-only type retired → one unified "Date."** The separate `.date` type is dropped from the picker; the unified type (`.datetime`, relabelled "Date", icon `calendar`) covers both, date-only vs with-time chosen by the new **Display Time** setting. Migration is normalize-on-read (`PropertyDefinition`'s decoder folds `.date` → `.datetime`; the `.date` case retained for backward decode only); validators treat `.date` and `.datetime` *values* as interchangeable.
- **Display config reworked.** `DateFormat` → 4 labelled formats (Short / Full / `DD/MM/YYYY` / `MM/DD/YYYY`); new `TimeFormat` (None / 12 Hour / 24 Hour). Legacy values migrate on decode. Value editors use the native `.compact` `DatePicker`.
- **View Settings popover sizes to content** — `ViewSettingsPane` grows `PUI.Pane.minHeight`→`.maxHeight` then scrolls the middle with header + footer pinned (the fixed `measuredPaneHeight` cage removed). Resize is the native `NSPopover`'s.

Spec → `Features/Properties.md`; design rule → `Guidelines/Design.md`.

#### Items are Markdown — Shape A (2026-06-02)

> Superseded by PagesV2 — Items-as-Markdown and the `Class` stamp are gone; foreign-frontmatter-preserved-by-value survived into Pages.

#### Title-collision data-loss fix + NexusEnvironment injection + cleanup (2026-06-01)

- **Title-collision data-loss fix (all file-backed entities).** A same-title create / rename / cross-container move silently overwrote a sibling's file (`filename = title` + an overwriting atomic write). Now **rejected** uniformly: one shared `NameCollisionValidator` (case-insensitive; same-id rename exempt) covers Pages + Tasks/Events on create + rename; the cross-container move paths and `Filesystem.renameFile` got no-overwrite guards (`Filesystem.guardNoFile`). Self-recasing one's own title is allowed (the guard compares on-disk file identity). Policy: **reject, not auto-suffix** (registry #13) — supersedes the prior "duplicates allowed" claim.
- **`NexusEnvironment` injection container.** `ContentView`'s ~16 hand-wired manager optionals collapsed into one container owning every manager + a single `.injectNexusEnvironment(_:)` modifier — removes the missing-inject `EXC_BREAKPOINT` footgun (quirk #15). Held in `@State`, members `let`.
- **Cleanup:** `debounceCoalescesRapidEdits` made deterministic; `AppGlobals.publish(...)` collapses the 9-slot publish block.

#### Manager de-dup + vault-table display-only + creation-order default (v0.3.4, 2026-05-31)

Three-stage consolidation; full suite 1045.
- **Vault-table display-only + creation-order.** Type detail tables are display-only for row order (mirror the sidebar's file-level order); Collection/Set tables keep flat reorder. Empty-state default changed alphabetical → **creation order** (ULID-id ascending), uniform + portable, no new field. Reason: SwiftUI `Table` can't combine collapsible grouping with reliable nested reorder; per-view order deferred to the Views work.
- **Property-mutation de-dup.** The 5 duplicated schema-mutation methods across the four managers extracted into two shared `@MainActor` services — `SingletonSchemaService` (Agenda) + `PerTypeSchemaService` (Page/Item) — driven by per-side adapters (~590 lines removed). Zero behavior change; transactional member-strip atomicity preserved.

#### Native IconPicker (2026-05-30)

Replaced third-party `SymbolPicker` with Pommora's own **`IconPicker`** — a compact Liquid-Glass dropdown over the full SF Symbols 6 catalog (`IconCatalog`) with search + Saved/favorites (`IconFavorites`), hosted via one `.iconPickerPopover` modifier at every icon-edit entry; the SPM dep removed. (Forced by the library hardcoding a 540pt frame + `internal` catalog.)

#### Make Relations Real — render half + index/picker hardening (2026-05-29/30)

> Both this and the Relations Redesign below are superseded by Contextv2.

Entity `icon` denormalized into SQLite; `ContextDisplayResolver` resolves target ID → icon + title; tier columns render correctly. `IndexBuilder.populate` made per-row (bad rows skip + log). Picker zero-size glass-blob fixed via fixed panel width — earned **quirk #18** (confirm the data before blaming the store).

#### Relations Redesign — relations + tiers unified (2026-05-29)

> Superseded by Contextv2 — user-creatable relation properties are gone; tier tagging is the sole relation mechanism.

#### View Settings editor redesign + Design.md consolidation (v0.3.2, 2026-05-27)

Rebuilt the per-property editor to Nathan's Figma. The popover-family UIX lessons (PaneDivider rail, pinned destructive footers, type scale, plain-`Menu` inline selectors, back-label naming, idempotent inline-`TextField` commit) folded into `Guidelines/Design.md`; the standalone `UIX-Baseline.md` removed.

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` third tier then reverted it the same cycle — it duplicated Collections' rigid-grouping role. **Kept:** the system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`), the sidebar context-menu tweaks ("+" header is the sole vault-creation path), and `NexusAdopter.autoTagMissingSidecars`.

#### v0.3.1 — Properties end-to-end (2026-05-26)

View Settings popover live: schema CRUD via Edit Properties pane, dynamic property-value columns in all detail-view Tables (`TableColumnForEach`), click-to-edit cell popovers, Property Visibility pane. Added `DisplayVariant` + `DateFormat`, `PropertyChipColor` (12 cases), chip primitives, and the `updateProperty`/`updateView`/`updatePageProperty` manager methods. Ratified decisions in `Properties.md`.

#### v0.3.x — View Settings chrome slice + follow-up sweep (2026-05-25)

First slice of the View Settings popover: a static `slider.horizontal.3` toolbar button at `ContentView` level opening an empty scope-routed popover (`ViewSettingsScope` from `sidebarSelection`). Locked: the button is a single static instance whose content adapts via scope. A `Button(role: .close)`-in-popover crash earned **quirk #17**. The post-v0.3.0 sweep then shipped storage-view footers + session-local drag-reorder, restored sidebar disclosure (Item Types fold, Sets flat — mitigates the quirk #9 asymmetry crash), real Create sheets, chip primitives + `PommoraUIX.md`, the icon pipeline, and the `"Name"` → `"Title"` label sweep. Two invariants locked: **`loadAll` syncs in-memory parents to the SQLite index** (quirk #15 — kills the FK-19 toast; `LoadAllIndexSyncTests`) and **every detail-view `@Environment` must be injected at `ContentView.detail`** (quirk #16). Tables get no vertical column borders (Notion-flat).

#### v0.3.0 — Properties FEATURE-COMPLETE (2026-05-25, merged `3d1bc19`)

71 commits, full property system + SQLite index + placeholder UI. Data layer: `PropertyType` (11 types), `PropertyValue`/`FileRef`, `PropertyDefinition` (stable ULID id), `SchemaTransaction` (atomic multi-file commit), `PropertyIDMigration`, schema CRUD on all 4 managers, validators. SQLite: GRDB.swift, `IndexBuilder` + `IndexUpdater` + `IndexQuery`. Attachments (copy-on-attach), `_status` built-in on Agenda. Full detail → `Features/Properties.md`. (Scope was redirected 2026-05-23 to data layer + placeholder UI only — the Figma-driven Properties UI moved to v0.3.1; properties live in the Pages Pulldown / Preview / Item Window inspectors, never the main-window inspector. The shape was locked in a 2026-05-19 brainstorm: 10-type catalog + Status, mandatory dual relation for Vault/Collection, no inline option creation, property icons.)

#### Flat-Layout refactor (2026-05-23, tag `flatlayout`)

Dropped the `<nexus>/Pages/`, `/Items/`, `/Agenda/` wrapper folders — Types + singletons now live at the nexus root, classified by sidecar filename. Six per-kind sidecars replace the unified `_schema.json` (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). The adopter handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat), tolerates mixed per-folder states, and cleans co-located orphans (rule: only ONE per-kind sidecar is authoritative per folder). Nathan's real nexus migrated successfully. On-disk spec → `Features/Architecture.md`.

#### ParadigmV2 — operational-layer domain refactor (2026-05-22/23, tag `paradigmV2`)

Vault becomes Pages-only as Page Type; Item Type introduced as the parallel Items-side container; Page/Item Collection as parallel sub-folders. AgendaItem split into **AgendaTask + AgendaEvent** (EKReminder + EKEvent). Sub-topics renamed to Projects. UI label divergence locked: Pages-side "Vault" + "Collection", Items-side "Type" + "Set", renameable via Settings. Settings scaffold (`.nexus/settings.json` + `SettingsManager`) laid. New rule: **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.**

#### Editor — construct passes (v0.2.7.2 → v0.2.7.5, 2026-05-20/21)

The dynamic-syntax editor architecture (markers reveal under the caret, render off it; on disk standard CommonMark) established and filled out — full architecture + lessons in `Features/PageEditor.md`:
- **HR / divider** (v0.2.7.2) shipped via Obsidian/Typora-style dynamic syntax after the always-hidden design failed; `---` stays in storage for swift-markdown's ThematicBreak parse. Establishes the paragraph-level dynamic-syntax pattern. A jitter root-cause fix followed (selection-scope walk O(N)→O(1); caret-aware reveal must not change layout).
- **Lists** (v0.2.7.2) — space styles immediately (styler-driven, no source mutation), Enter continues, Shift+Enter exits; visual indent via paragraph style, not source `\t`.
- **Polish bundle** (v0.2.7.4) — bullet glyph substitution (`-` → `•` via always-on overlay), task-list shorthand, whitespace-gated bracket auto-pair, arrow auto-format. Locked: portable-source-with-overlay is the pattern; `-` is the only dash-bullet trigger.
- **Blockquote** (v0.2.7.5) — a renderer-drawn rounded card + continuous accent bar (always-show overlay, not dynamic-syntax); `> ` activates, the marker hidden in-editor but standard CommonMark on disk; multi-paragraph quotes butt-joint via per-fragment corner-rounding.

#### Editor — Nexus folder adoption (v0.2.7.4, 2026-05-21)

Obsidian-parity "open folder as Nexus." Both open paths run `NexusAdopter.scan` + a preview-and-confirm sheet (top-level → Vaults, sub-folders → Collections). `PageFile.loadLenient` accepts `.md` without Pommora frontmatter (synthesizes a stable `id`, never writes back — files stay byte-identical until edited). Locked: adoption runs on every open (idempotent); 3-level structural depth (deeper folders roll up to the nearest Set); existing notes never mutated.

#### v0.2.7.1 — Navigation shipped + simplified (2026-05-19)

Navigation shipped (Pinned + Recents; single-click select / double-click open; `⌘T` / `⌘[` / `⌘]`; state in `.nexus/state.json`). The earlier bloated attempt was cut back: standalone preview-window machinery stripped (the real PreviewWindow is a cross-feature primitive — build once, light up per kind); hover-heart favorites → right-click "Pin." New rule (`CRUD-Patterns.md`): the PreviewWindow primitive ships per kind before any "open in preview" UI.

#### v0.2.7.0 — native TextKit 2 editor (2026-05-18, tag `v0.2.7.0`)

Native TextKit-2 Page editor shipped after the WKWebView (Pallepadehat) and Milkdown directions both failed Nathan's visual baseline. Stack: Apple `swift-markdown` 0.8.0 + vendored `swift-markdown-engine` + a Pommora-side supplemental styler (BlockQuote / Strikethrough / Table / ThematicBreak). Writing Tools / Look Up / spell-check / IME / dynamic colors free. Editable title + body-binding wired. **`.md` is the architectural firewall** — domain wiring survived every editor pivot.

#### v0.2.x foundation (2026-05-16 → 18)

- **v0.2.0 — paradigm scaffolding** (merged `e3daedb`, 69 commits). Scaffolded the full locked paradigm — every entity Codable + validator + `@MainActor @Observable` manager, CRUD-able end-to-end via sidebar + sheets + detail pane + Item Window. Swift 6 strict concurrency + ExistentialAny enabled; Yams added. Established: the confirmation-before-code protocol; `PropertyValue.relation` as tagged `{"$rel": "<ULID>"}`; **stub-and-progressively-replace** (quirk #7); sidebar UX = right-click context menus, Pages under their parent; **sidebar selection chrome via `.listRowBackground`** (quirk #9). A missing-`.environment` launch crash seeded quirks #15/#16.
- **v0.2.1 → v0.2.3** — main patches: parallel-session sidebar UX + page-selection wiring; CodeRabbit tightening; GitHub Actions CI (`xcodebuild build` + `-only-testing:PommoraTests` on `macos-26`). Earned **quirk #4** (`.claude/*` IS in commits).
- **v0.2.4 → v0.2.6** — `swift-format` baseline (lineLength 120; CI lint — **quirk #12**); the `.trash//` data foundation (`Filesystem.moveToTrash`, 10 delete-sites routed through trash; lives inside the nexus, unlike the regeneratable index); spec catch-up.

#### Founding era (2026-05-16 → 18)

- **v0.1.0 — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, `.nexus/` init flow, per-nexus App Support subdir keyed by ULID. File → Open Nexus; Debug → Reset Bookmark.
- **v0.0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`; both side panes drag-resizable, widths persist.
- **Editor library exploration (sessions 6–8).** Tiptap/WKWebView → Pallepadehat (CodeMirror) → Milkdown → native TextKit 2 (shipped v0.2.7.0); `.md` as the portability firewall let user data survive every pivot. Earned **quirk #13**.
- **Semver locked** (`major.minor.patch`; minor = completed feature, patch = touch-up, major reserved for v1.0.0).
