### Pommora — History

Changelog — what shipped and when, newest first. Brief by design. Current state lives in the feature docs + `PommoraPRD.md`; roadmap + phases in `Framework.md`; locked decisions + registry in `Guidelines/Paradigm-Decisions.md`; editor internals in `Features/PageEditor.md`. This file records *what shipped*, not the decision registry or implementation internals — when an entry would enumerate locked decisions or file-level detail, it points to the canonical doc instead.

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

Follow-on to the Relations Redesign — the stored feature wasn't rendering/editing everywhere.

- **Render half.** Entity `icon` denormalized into the SQLite index; shared `RelationDisplayResolver` resolves any target ID → icon + title; the four table detail views render relation + tier columns as icon + title (killed "(missing)").
- **Index resilience** (`02f8a67`). `IndexBuilder.populate` made per-row (`attemptInsert` skips + logs a bad row instead of rolling back the whole rebuild); `schema_version` stamped only after `populate` succeeds. `currentSchemaVersion` 4 → 5.
- **Picker popover collapse** (`9deb818`). The inline tier picker rendered as a zero-size "glass blob" — fixed via fixed panel width. Data + wiring were correct throughout. Earned **quirk #18** (layer-confusion check: confirm the data before blaming the store).
- **Relation-lifecycle hardening** (`f1d66f6`). Member-file value-strip crashed on a frontmatter-less `.md`; hoisted the strip-loop resilience into one shared `MemberFileStrip.forEach` and routed all 8 strip sites through it. `upsertPage`/`upsertItem` FK-19 on an unindexed parent now retries without the orphan collection, else skips + logs.

#### Relations Redesign — relations + tiers unified (2026-05-29)

One linking system replaces two: tier tagging and relation properties share a single pipeline. Plan: superseded.

- **Tiers are relations.** `tier1/2/3` (root frontmatter arrays) flow through the property pipeline and emit into the SQLite `relations` table; the `tier_links` table retired (one reverse-lookup path, `IndexQuery.incomingRelations`).
- **Always-multi.** `allows_multiple` dropped; a relation value is always an array of `{"$rel": "<ULID>"}`. `RelationScope` → `RelationTarget` (user-creatable: Page Type / Item Type / Agenda Tasks / Agenda Events; `context_tier` internal-only).
- **One editor, one rendering.** A single-pane relation editor (create + edit, home side + reverse name + reverse icon) replaces the multi-step wizard. Values render as the target's icon + title via the single `RelationChip` primitive.
- **Context-delete cascades source-side** — deleting a Space / Topic / Project removes its tier reference from every Page, Item, and Agenda entry.
- **Adoption.** Per-Type sidecar `schemaVersion` 1 → 2 triggers a one-time normalizing re-save (silent; the one lossy change — dropping a context-tier-targeting relation — gated behind acknowledgment). Index DB `currentSchemaVersion` 2 → 3 forces a rebuild that backfills tiers.

Registry decisions #8–#12 in `Paradigm-Decisions.md`. Deferred items in `Prospects.md`.

#### View Settings editor redesign + Design.md consolidation (2026-05-27, v0.3.2)

Rebuilt the View Settings per-property editor to Nathan's Figma. The popover-family UIX lessons (PaneDivider rail standard, pinned destructive footers, Subheadline / Callout type scale, plain-`Menu` inline selectors, back-label names the previous pane, idempotent inline-`TextField` commit) folded into `Guidelines/Design.md`; the standalone `UIX-Baseline.md` removed.

#### Folders (third Pages-side tier) — tried and reverted (2026-05-27)

Built a full `PageType → PageCollection → Folder → Page` third tier then reverted it the same cycle — it duplicated Collections' rigid-grouping role and conflicted with the planned view-organization system. **Kept:** the system-wide stub-and-inline-rename CRUD (`CreateWithInlineEdit` + `DefaultTitleResolver`, `68caf96`), the sidebar context-menu tweaks (no "New Vault" in the row menu; "+" header is the sole vault-creation path), and `NexusAdopter.autoTagMissingSidecars`.

#### v0.3.1 Properties end-to-end (2026-05-26, v0.3.1)

The approved View-Settings-edit-properties plan shipped as 21 commits (`627e972` → `0d5aa16`). The `slider.horizontal.3` View Settings popover goes live: schema CRUD via the Edit Properties pane (Notion-format, per-type editors, Duplicate/Delete footer), dynamic property-value columns in all 4 storage detail-view Tables (`TableColumnForEach`, macOS 14+), click-to-edit cell popovers for every property type, and the Property Visibility pane.

Data-layer additions: `DisplayVariant` (Status-only) + `DateFormat` enums · `PropertyDefinition.displayAs` + `.dateFormat` · `ItemType.singular` · real `SavedView` fields + `views[]` on Collections + default-view migration · flat 12-case `PropertyChipColor`. Three chip primitives — `RelationChip` / `FileChip` / `LinkChip`. New manager methods: `updateProperty(id:in:transform:)`, `updateView(viewID:in:transform:)`, `updatePageProperty` / `updateItemProperty`.

Deferred: in-window Item property editing (its surface is slated for a rebuild), cell-editor inline Relation/File editors, the SelectOptions/StatusGroups chevron-push refactor. Ratified decisions in `Paradigm-Decisions.md` / `Properties.md`.

#### v0.3.x View Settings chrome slice (2026-05-25)

First slice of the View Settings popover: a static `slider.horizontal.3` toolbar button at `ContentView` level inside the existing primary-action Liquid Glass capsule (order `[ViewSettings] [NavDropdown] [InspectorToggle]`), opening an empty 300×360 popover scope-routed via `ViewSettingsScope` derived from `sidebarSelection`. Locked: the button is a single static instance whose content adapts via scope — never per-detail-view (registry). A `Button(role: .close)`-in-popover crash earned **quirk #17** (the role-only init only works inside a `.toolbar`).

#### v0.3.x follow-up sweep (2026-05-25)

Post-v0.3.0-merge design-system + UX correctness sweep (`88c9367` branch tip). All 4 storage detail views shipped with footers + session-local drag-reorder; sidebar disclosure restored (Item Types fold like Vaults, Sets are flat leaves — mitigates the quirk #9 asymmetry crash); real Create sheets replace stubs; chip primitives + `PommoraUIX.md`; icon pipeline wired through create methods; `"Name"` → `"Title"` label sweep; tier labels → `"Spaces"/"Topics"/"Projects"`.

Two forward-binding invariants locked: **`loadAll` syncs in-memory parents to the SQLite index** (quirk #15 — eliminates the recurring FK-19 toast; `LoadAllIndexSyncTests`) and **every detail-view `@Environment` must be injected at `ContentView.detail`** (quirk #16). Tables get no vertical column borders (Notion-flat). Full decision list in `Paradigm-Decisions.md`.

#### v0.3.0 Properties — FEATURE-COMPLETE (2026-05-25, merged `3d1bc19`)

71 commits across 11 phases A–K. The data-layer chapter — full property system + SQLite index + placeholder UI.

- **A–D — Data layer.** 11-type `PropertyType`; `PropertyValue` + `FileRef`; `ReservedPropertyID` + `mintUserPropertyID`; `PropertyDefinition` (stable ULID `id` + config + nested `StatusGroup`/`DualPropertyConfig`); `SchemaTransaction` atomic multi-file commit; `PropertyIDMigration` (runs every nexus open, preview-before-commit); schema CRUD on all 4 schema-bearing managers; `PropertyDefinitionValidator` (8 rules); `SchemaConflictDialog` drift defense.
- **E — SQLite index, live end-to-end.** GRDB.swift; per-nexus `.nexus/index.db`; 12-table schema; `IndexBuilder` two-phase populate; `IndexUpdater` wired into all 6 managers; `IndexQuery` Notion-style filter/sort/broken-links. Mid-session mutations propagate.
- **F–I — Attachments + Agenda + move-strip + Settings.** `AttachmentManager` (copy-on-attach, 50/500 MB caps, cascade-delete); `_status` built-in on AgendaTask + AgendaEvent; `DualRelationCoordinator` paired-relation lifecycle; name-matched move-strip (IDs are globally unique); `Settings.defaultsVersion` + `migrate` scaffold + label wiring.
- **J–K — Placeholder UI.** Every interaction has a working path: PropertyEditorRow dispatcher, Status/Relation/File pickers, RelationPropertyWizard, Vault/Type Settings sheets, PropertyPanel, PropertiesPulldown, FrontmatterInspector, CalendarDetailView + Calendar pin quick-create.

10 branch decisions (status `{"$status": value}` encoding, move-strip by name, reserved IDs, tier1/2/3 at frontmatter root, paired-relation lifecycle owner, etc.) in `Paradigm-Decisions.md`. Full per-phase detail in `Features/Properties.md`.

#### v0.3.0 Properties — scope redirection (2026-05-23, brainstorm)

v0.3.0 narrowed to **data layer + minimum-viable placeholder UI only**; the real Properties Pulldown + Property Panel UI redirected to v0.3.1 (Figma-driven). Surface architecture locked: properties live in the Pages Pulldown / Page Preview inspector / Item Window inspector — never the main-window inspector (which becomes the Claude chat). AgendaTaskSchema's placeholder `type` Select dropped for Status as sole built-in. Editor patches shipped alongside (foldable-headings fix + `folded_headings` persistence; em/en-dash auto-syntax).

#### Flat-Layout refactor (2026-05-23, tag `flatlayout`)

Dropped the `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/` wrapper folders — Page Types / Item Types / Tasks + Events singletons now live at the nexus root, classified by sidecar filename. Six per-kind sidecars replace the unified `_schema.json`: `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`. The adopter handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat), tolerates mixed states per-folder, cleans co-located orphans, and is `.DS_Store`-tolerant. Locked-decision detail in `Paradigm-Decisions.md`; on-disk spec in `Features/Architecture.md`.

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

Obsidian-parity "open folder as Nexus." Both open paths run `NexusAdopter.scan` and present a preview-and-confirm sheet (top-level folders → Vaults, sub-folders → Collections). `PageFile.loadLenient` accepts `.md` without Pommora frontmatter (synthesizes a stable `id`, never writes back — files stay byte-identical until edited). Locked: adoption runs on every open (idempotent); 2-level structural depth preserved (deeper folders roll up to nearest Collection); existing notes never mutated.

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

Established protocols + decisions (registry in `Paradigm-Decisions.md`): the confirmation-before-code protocol for paradigm-solidifying choices; `PropertyValue.relation` as tagged `{"$rel": "<ULID>"}`; **stub-and-progressively-replace** execution (quirk #7); sidebar UX = right-click context menus scoped to the cursor (no "+ New" buttons), Pages appear under their parent, Items/Agenda live only in detail-pane Tables; **sidebar selection chrome via `.listRowBackground` at row file level** (quirk #9). A launch crash (`EXC_BREAKPOINT` via missing `.environment` injection) bisected + fixed one-line — the seed of quirks #15/#16.

#### Founding era (2026-05-16…18)

- **v0.1.0 — Nexus Foundation.** Sandboxed picker, security-scoped bookmark persistence, `.nexus/` init flow, per-nexus App Support subdir keyed by ULID. Sidebar mirrors the picked folder. File → Open Nexus; Debug → Reset Bookmark. 25 unit tests.
- **v0.0.0 — Shell opens.** Two-column `NavigationSplitView(sidebar:detail:)` + `.inspector(isPresented:)`; both side panes drag-resizable, widths persist. 1440×810 default, 960×560 min; title suppressed.
- **Editor library exploration (sessions 6–8).** Reopened the editor decision twice — Tiptap/WKWebView → Pallepadehat fork (CodeMirror) → Milkdown → native TextKit 2 (shipped v0.2.7.0). `.md` as the portability firewall let user data survive every pivot. Earned **quirk #13** (branch-pinned SPM forks need a full cache nuke to bump).
- **Semver locked** (`major.minor.patch`; minor = completed feature, patch = touch-up, major reserved for v1.0.0). The original by-area founding-decisions block was superseded — live truth lives in `Domain-Model.md` / `Properties.md` / `Architecture.md` / `PommoraPRD.md`.
