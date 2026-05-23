### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (2026-05-23 — **ParadigmV2 SHIPPED** — tag `paradigmV2` pushed to origin)

**Active focus:** [[ParadigmV2]] is **DONE**. Tag `paradigmV2` pushed to `origin` at commit `36d48c8`. All 11 phases complete. Build green, **358 tests passing**. Local + `origin/main` aligned at `36d48c8`. Next focus: **v0.3.0 Properties** — implementation plan locked at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0).

##### What shipped (Phases 1–11)

Each phase ships green standalone (stub-and-progressively-replace per quirk #8). Build green, **358 tests passing** at the ship tag.

- **Phase 1 — Docs** (`e6ddc04`) — Domain-Model + PageTypes + Items + Agenda + Contexts + Pages + Properties + Architecture + Prospects + Sidebar + Spaces/Collections stubs + root docs + guidelines + paradigm decisions all rewritten for ParadigmV2 vocabulary in one bundled commit.
- **Phase 2 — PageType + PageCollection renames** (`b86ddf0` → `aeb9a35`) — Schema sidecar unified to `_schema.json`; `Vault → PageType`, `Collection → PageCollection`; `Pommora.Collection` quirk #6 retired.
- **Phase 3 — Subtopic → Project** (`1e1fe77` → `1630586`) — Tier-3 Context renamed across the codebase.
- **Phase 4 — AgendaItem split** (`5e5b225` → `a4b497f`) — `AgendaItem` split into `AgendaTask` (EKReminder-shaped) + `AgendaEvent` (EKEvent-shaped); schemas + managers + validators split; legacy `AgendaItem` / `AgendaSchema` / `AgendaManager` / `AgendaValidator` deleted.
- **Phase 5 — Items-side subsystem** (`2e904ec` → `5dcbb95`) — `ItemType` + `ItemTemplateConfig` + `ItemCollection` + `ItemTypeManager` + `ItemTypeValidator` + `ItemCollectionValidator` introduced; `ContentManager` split into `PageContentManager` + new `ItemContentManager` (+ `+CRUD`); `ItemParent` added.
- **Phase 6 — Wrapper folders + adopter** (`2eba366` → `2686799` + fix-forward `2b8ade8`) — PageType paths now rooted under `<nexus>/Pages/`; ItemType paths under `<nexus>/Items/`; `NexusAdopter` surveys all three wrappers (`Pages/` + `Items/` + `Agenda/`); `AdoptionPreviewView` shows symmetric Vault/Collection + Type/Set counts. **Fix-forward `2b8ade8` pulls Phase 10's migration into the adopter**: legacy root-level folders are now classified by content sniff (`.md` → Pages-side; user `.json` → Items-side; empty → default Pages-side) and moved into the appropriate wrapper at `apply()`, with collision handling + fresh-sidecar generation for bare folders.
- **Phase 7 — Settings scaffold** (`331f0e2` → `207c3ee`) — `Settings` + `SettingsLabels` + `SettingsAccentColor` Codable structs; `SettingsManager` (`@MainActor @Observable`, atomic load/save to `<nexus>/.nexus/settings.json`); sidebar header label + sheet titles + context-menu items wired to SettingsManager getters; accent color via `.tint(currentAccent)` on `ContentView` (NOT `PommoraApp` — locked correctness fix); `SettingsScene` stub opens at `Cmd+,`.
- **Phase 8 — Sidebar / Detail / Sheet UI restructure** (`e976bb4` → `0bb58e1`) — `SidebarSheet` + `SelectionTag` + `IconTarget` enums gained Items-side cases (no Agenda); `NewItemTypeSheet` + `NewItemCollectionSheet` ContentUnavailableView stubs; `ItemTypeDetailView` + `ItemCollectionDetailView` stubs + routing; Items section live in the sidebar between Topics and Pages (order: Pinned / Spaces / Topics / **Items** / Pages, no Agenda). Section structure (`Section(isExpanded:) { } header: { SectionHeader(...) }`) preserved per quirk #9.
- **Phase 9 — Tests audit + v0.3.0 Properties plan re-derive** (`54b136b` → `cb97ae2`) — Coverage audit closed two real gaps (`ItemTypeManager.updateItemTypeIcon` + `ItemContentManager` type-root duplicate-title rejection); 359 cases passing at the audit. New 675-line implementation plan at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) grounded in actual file:line citations against the post-ParadigmV2 code surface; 5 phases (A schema editing → B value editing → C type-specific UI → D move-strip → E ship); `ItemTypeSettingsSheet` decision locked to **ship at v0.3.0** (parity-low-cost rationale). Final Task 9.3 doc sync at `2b1a1c4`.
- **Phase 10 — Data migration** (no code commit) — Subsumed by the Phase 6 adopter fix-forward at `2b8ade8`. Adopter classifies legacy folders by content sniff and moves them into wrappers atomically with collision handling + fresh-sidecar generation. Nathan's manual step (backup + open + adopt + verify) is the user-data side; engineering shipped.
- **Phase 11 — Cleanup + Framework + ship** (`36d48c8` + tag `paradigmV2`) — Final grep sweep caught 5 stale type-description docstrings (PageCollection, ItemCollection, PropertyDefinition, Filesystem, NexusManager) referencing the pre-ParadigmV2 sidecar names for the CURRENT state vs legacy state; cleaned. Framework.md `Current Focus` updated from "IN FLIGHT" to "SHIPPED" with full refactor description + v0.3.0 Properties plan pointer. Tag `paradigmV2` annotated + pushed to origin (sits between v0.2.8 and v0.3.0).

##### One UI regression caught + fixed during execution

Phase 7.5 wired `.tint(currentAccent)` on `ContentView`'s `NavigationSplitView`, which cascaded the accent color into the `.borderless` "New Collection" button at the bottom of the Vault detail view (`PageTypeDetailView`). Reverted to plain primary-text rendering via `.foregroundStyle(.primary)` after the `.buttonStyle(.borderless)` modifier (`7f491f7`) — keeps the borderless style but opts out of tint cascade. Same pattern can be applied to any other footer/inline buttons that should NOT inherit the accent color.

##### The refactor in one paragraph

Pre-ParadigmV2: kind-agnostic Vaults containing Pages + Items, Collections as sub-folders, AgendaItem as a unified Task+Event struct, Sub-topics for tier-3 Contexts. Post-ParadigmV2: **symmetric Page/Item model** — Page Type → Page Collection → Page (`.md`) on the Pages side; Item Type → Item Collection → Item (`.json`) on the Items side. AgendaItem splits into AgendaTask + AgendaEvent (EKReminder + EKEvent aligned). Sub-topics renamed to Projects. Schema sidecars unify to `_schema.json` everywhere. On-disk wrapper folders: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. **UI label divergence**: Pages-side "Vault" + "Collection"; Items-side "Type" + "Set" — each side has one signature word + one shared word; all renameable via SettingsManager. **Settings scaffold** in place — storage + manager + label wiring + Cmd+, stub scene; real editing UI lands v0.6.0. **"Pommora" prohibited** in on-disk schemas + Swift namespace qualifications.

##### Phase sequence + status

1. ✅ Phase 1 — Doc rewrites
2. ✅ Phase 2 — PageType + PageCollection renames + `_schema.json` sidecar
3. ✅ Phase 3 — Subtopic → Project rename
4. ✅ Phase 4 — AgendaItem split → AgendaTask + AgendaEvent
5. ✅ Phase 5 — New ItemType + ItemCollection subsystem
6. ✅ Phase 6 — Pages/Items wrapper folders + NexusAdopter update (+ legacy-layout migration fix-forward)
7. ✅ Phase 7 — Settings scaffold (storage + manager + UI label wiring + Cmd+, stub scene)
8. ✅ Phase 8 — Sidebar / Detail / Sheet UI restructure (Items section live, Item rows + detail stubs)
9. ✅ Phase 9 — Tests audit + v0.3.0 Properties plan re-derive
10. ✅ Phase 10 — Data migration (subsumed by adopter fix-forward `2b8ade8`; engineering shipped, user's manual step is open whenever Nathan adopts his real nexus)
11. ✅ Phase 11 — Cleanup + Framework reconciliation + tag `paradigmV2` pushed to origin

##### Next focus — v0.3.0 Properties

The post-ParadigmV2 v0.3.0 Properties implementation plan lives at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) — 5 phases (A schema-editing infrastructure → B value editing in detail views → C type-specific UI → D move-strip rule → E validation + ship). Anchor file:line citations against the post-ParadigmV2 code: `PageTypeManager` / `ItemTypeManager` / `PageContentManager` / `ItemContentManager` / `SettingsManager` / `AgendaTaskSchema` / `AgendaEventSchema`. `ItemTypeSettingsSheet` locked to ship at v0.3.0 alongside `PageTypeSettingsSheet`.

The conceptual WHAT — property types, value semantics, schema model — lives at [`Planning/v0.3.0-Properties-spec.md`](Planning/v0.3.0-Properties-spec.md). Pre-ParadigmV2 plan + uncertainty log archived under `Planning/Superseded/`.

##### Nathan's outstanding manual step (Phase 10 user-data side)

The adopter migration code is shipped + tagged. When you want to migrate your real nexus:

1. **Backup first** — `cp -R /path/to/your/nexus /path/to/your/nexus.pre-paradigmV2-backup`. Path documented in the playbook (`/Users/nathantaichman/The Nexus/Pommora/`) doesn't exist on disk — confirm the real path before running.
2. **Launch Pommora** pointed at your real nexus.
3. **Click adopt** when the preview appears. Should show "Legacy folders to migrate" listing your Vault folders with `<nexus>/Recipes/ → <nexus>/Pages/Recipes/` destinations.
4. **Apply.** Sidebar should populate: Pinned / Spaces / Topics / Items / Pages.
5. **If something surfaces** that the adopter doesn't handle on your specific data shape — fix-forward in `NexusAdopter.swift`; otherwise close Phase 10.

##### Parallel-session state (Nathan's other session)

A concurrent session is shipping collapsible-heading work in `External/MarkdownEngine/` (`NativeTextViewCoordinator+HeadingFolding.swift` + `NativeTextView+HeadingFoldHover.swift` modifications). Two files modified in the working tree as of this snapshot. Per quirk #11, those files remain untouched in ParadigmV2 commits — Nathan reconciles separately.

##### Key naming decisions (locked in plan, all enforced in shipped code)

- **Swift types:** `PageType`, `PageCollection`, `ItemType`, `ItemCollection`, `AgendaTask`, `AgendaEvent`, `Project`, `SavedView` (renamed from `VaultView`), `Settings`, `SettingsManager`, `SettingsLabels`, `LabelPair`, `SettingsAccentColor`.
- **UI labels (defaults, renameable via Settings):** Pages-side **"Vault"** / **"Collection"**; Items-side **"Type"** / **"Set"**; "Task", "Event", "Project"; section labels "Pages" / "Items" (no Agenda section).
- **Banned in on-disk schemas + Swift qualifications:** "Pommora" prefix. No `pommora_*` JSON keys; no `Pommora.X` qualifications — use side-prefixed names (`AgendaTask` not `Pommora.Task`). Existing `pommora_table_widths` grandfathered for v0.3.0; rename when Tables ship.

##### Test count + build status

- Build: `** BUILD SUCCEEDED **` (xcodebuild, macOS destination).
- Tests: **358 passing**, 0 failing, 0 skipped at the ship tag. Pre-ParadigmV2 baseline was 252; net +106 cases across Phases 4–9.
- Pre-existing intermittent timing flake: `PageEditorViewModelTests.debounceCoalescesRapidEdits` (sleeps 500ms after 300ms debounce — tight margin under load). Pre-ParadigmV2; not blocking.

##### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **ParadigmV2 SHIPPED** — tag `paradigmV2` pushed to origin at commit `36d48c8`. Build green, 358 tests passing. All 11 phases complete; Nathan's user-data migration step is the one remaining open item (manual backup + open + adopt + verify on his real nexus). **Next focus: v0.3.0 Properties** — implementation plan at `.claude/Planning/v0.3.0-Properties-plan.md` (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at `.claude/Planning/v0.3.0-Properties-spec.md`. The post-ParadigmV2 code surface — `PageType` + `ItemType` (symmetric containers) + `PageContentManager` + `ItemContentManager` + `SettingsManager` + `AgendaTaskManager` + `AgendaEventManager` — is the foundation Properties builds on. Playbook for ParadigmV2 itself archived at `~/.claude/plans/velvet-crunching-frost.md` (all 54 tasks ✅). Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have collapsible-heading work in `External/MarkdownEngine/` — never bundle into ParadigmV2 commits (quirk #11)."

---

#### Prior versions (shipped — full detail in History.md)

- **v0.2.8.0** (commit `5a264f0`) — Blockquote chrome (v0.2.7.5) + drag-reorder Phase 1 persistence (v0.2.8)
- **v0.2.7.6** (commit `733cc47`) — Task checkbox redesign + initial-load styling + sidebar chrome
- **v0.2.7.4** (Session 14) — Nexus folder adoption + editor polish bundle (bullet glyph, task `-[]` shorthand, arrow chains, bracket auto-pair guard, code colors, HR jitter fix)
- **v0.2.7.2** (Session 12 + 13) — HR dynamic-syntax + Lists rewrite (space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source)
- **v0.2.7.1** (Session 10) — NavDropdown ship
- **v0.2.7.0** (Session 9) — Native TextKit-2 editor via vendored `swift-markdown-engine`

---

#### Known follow-up debt (not blocking ParadigmV2 tag)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight appears to start at body text rather than extending into the hidden `>` syntax gap. Fix paths documented in `History.md` Session 15B entry.
- **NavDropdown Pinned drag-to-reorder** — lands with drag-reorder Phase 2 (post-ParadigmV2)
- **NavDropdown type chip removal** (drop trailing "Page / Type / Topic" text, rely on leading icon)
- **NavDropdown segmented picker polish** (opacity / contrast pass)
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface v0.4.0
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 wikilink work depends on this
- **MarkdownEngine collapsible-heading work** — in flight in parallel session; not a ParadigmV2 dependency
- **Items section header label not yet wired to SettingsManager** — Phase 8.3 left the "Items" header as a literal string; SettingsManager-driven wiring lands when the real Items UI ships in a follow-up plan (mentioned in `Planning/v0.3.0-Properties-plan.md` Phase C.3/C.7)

---

#### Document pointers

- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation guidelines**: `.claude/Guidelines/Markdown.md`
- **Editor planning (active + paused)**: `.claude/Planning/Page-Editor-Plan.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Roadmap**: `.claude/Framework.md`
- **Session history**: `.claude/History.md`
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **ParadigmV2 plan**: `.claude/Planning/ParadigmV2.md`
- **ParadigmV2 execution playbook**: `~/.claude/plans/velvet-crunching-frost.md`
- **v0.3.0 Properties spec (conceptual WHAT)**: `.claude/Planning/v0.3.0-Properties-spec.md`
- **v0.3.0 Properties implementation plan (post-ParadigmV2 HOW)**: `.claude/Planning/v0.3.0-Properties-plan.md`
- **Session transcripts**: `.claude/Transcripts/`

---

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
- **Phase 10 manual backup** — `<nexus>.pre-paradigmV2-backup/` via `cp -R` before running in-app adoption on Nathan's real data. Confirm before Phase 10 execution.
