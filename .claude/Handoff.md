### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (2026-05-22 end-of-day — **ParadigmV2 Phases 1–7 SHIPPED; Phase 8 next**)

**Active focus:** [[ParadigmV2]] — operational-layer domain model refactor. Plan locked at [`Planning/ParadigmV2.md`](Planning/ParadigmV2.md) (~2,360 lines, 11 phases). Playbook at `~/.claude/plans/velvet-crunching-frost.md`. Seven phases shipped this session via sequential + parallel subagent dispatch; build green, **357 tests passing** at session end.

##### What shipped (Phases 1–7)

Each phase ships green standalone (stub-and-progressively-replace per quirk #8). Commit ranges below; see `git log` for the full set.

- **Phase 1 — Docs** (`e6ddc04`) — Domain-Model + PageTypes + Items + Agenda + Contexts + Pages + Properties + Architecture + Prospects + Sidebar + Spaces/Collections stubs + root docs + guidelines + paradigm decisions all rewritten for ParadigmV2 vocabulary in one bundled commit.
- **Phase 2 — PageType + PageCollection renames** (`b86ddf0` → `aeb9a35`) — Schema sidecar unified to `_schema.json`; `Vault → PageType`, `Collection → PageCollection`; `Pommora.Collection` quirk #6 retired.
- **Phase 3 — Subtopic → Project** (`1e1fe77` → `1630586`) — Tier-3 Context renamed across the codebase.
- **Phase 4 — AgendaItem split** (`5e5b225` → `a4b497f`) — `AgendaItem` split into `AgendaTask` (EKReminder-shaped) + `AgendaEvent` (EKEvent-shaped); schemas + managers + validators split; legacy `AgendaItem` / `AgendaSchema` / `AgendaManager` / `AgendaValidator` deleted.
- **Phase 5 — Items-side subsystem** (`2e904ec` → `5dcbb95`) — `ItemType` + `ItemTemplateConfig` + `ItemCollection` + `ItemTypeManager` + `ItemTypeValidator` + `ItemCollectionValidator` introduced; `ContentManager` split into `PageContentManager` + new `ItemContentManager` (+ `+CRUD`); `ItemParent` added.
- **Phase 6 — Wrapper folders + adopter** (`2eba366` → `2686799` + fix-forward `2b8ade8`) — PageType paths now rooted under `<nexus>/Pages/`; ItemType paths under `<nexus>/Items/`; `NexusAdopter` surveys all three wrappers (`Pages/` + `Items/` + `Agenda/`); `AdoptionPreviewView` shows symmetric Vault/Collection + Type/Set counts. **Fix-forward `2b8ade8` pulls Phase 10's migration into the adopter**: legacy root-level folders are now classified by content sniff (`.md` → Pages-side; user `.json` → Items-side; empty → default Pages-side) and moved into the appropriate wrapper at `apply()`, with collision handling + fresh-sidecar generation for bare folders.
- **Phase 7 — Settings scaffold** (`331f0e2` → `207c3ee`) — `Settings` + `SettingsLabels` + `SettingsAccentColor` Codable structs; `SettingsManager` (`@MainActor @Observable`, atomic load/save to `<nexus>/.nexus/settings.json`); sidebar header label + sheet titles + context-menu items wired to SettingsManager getters; accent color via `.tint(currentAccent)` on `ContentView` (NOT `PommoraApp` — locked correctness fix); `SettingsScene` stub opens at `Cmd+,`.

##### One UI regression caught + fixed this session

Phase 7.5 wired `.tint(currentAccent)` on `ContentView`'s `NavigationSplitView`, which cascaded the accent color into the `.borderless` "New Collection" button at the bottom of the Vault detail view (`PageTypeDetailView`). Reverted to plain primary-text rendering via `.foregroundStyle(.primary)` after the `.buttonStyle(.borderless)` modifier — keeps the borderless style but opts out of tint cascade. Same pattern can be applied to any other footer/inline buttons that should NOT inherit the accent color.

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
8. 🟡 Phase 8 — Sidebar / Detail / Sheet UI restructure (**next session entry point**)
9. ⬜ Phase 9 — Tests consolidation + v0.3.0 Properties spec reconciliation
10. ⬜ Phase 10 — Nathan's user-data migration (**largely subsumed** by Phase 6 adopter fix-forward; may simplify to "open + adopt your real nexus" verification + an explicit backup step rather than a separate bash script)
11. ⬜ Phase 11 — Cleanup + Framework reconciliation + ship (tag `paradigmV2`)

##### Phase 8 entry path (start here next session)

**Phase 8 — Sidebar / Detail / Sheet UI restructure.** Five tasks:
- **8.1** — `SidebarSheet` + `SelectionTag` + `IconTarget` enums gain Item Type / Item Collection cases. NO Agenda cases (Calendar pin consolidates).
- **8.2** — `NewItemTypeSheet` + `NewItemCollectionSheet` as `ContentUnavailableView` stubs. NO Agenda sheets exist.
- **8.3** — `SidebarView` section order becomes Pinned / Spaces / Topics / **Items** / Pages. Drop the Agenda section. **Quirk #9 is load-bearing here** — preserve `Section(isExpanded:) { } header: { SectionHeader(...) }` shape; tests must actually bootstrap, not just compile.
- **8.4** — Detail-pane stubs for Item Type + Item Collection (ContentUnavailableView).
- **8.5** — `ItemTypeRow` + `ItemCollectionRow` as minimal `SelectableRow` (no context menus; no SettingsManager label reads — pure rendering shells).

**Dispatch plan (proposed):**
- Wave 1 (1 subagent): 8.1 + 8.2 — enum updates + stub sheets.
- Wave 2 (2 parallel subagents): {8.3 + 8.5 — SidebarView sections + Item rows, tightly coupled} and {8.4 — detail-pane stubs}.

**GATE 8 verification (manual, by Nathan):** Launch app. Sidebar order top-to-bottom: Pinned / Spaces / Topics / Items / Pages, no Agenda. Right-click a Vault: context menu intact. Click an Item Type or Item Collection: detail pane shows "coming soon" placeholder. `Cmd+,` still opens Settings stub. Run full test suite — must bootstrap not just compile.

##### Parallel-session state (Nathan's other session)

A concurrent session is shipping collapsible-heading work in `External/MarkdownEngine/` (untracked `NativeTextViewCoordinator+HeadingFolding.swift` + `NativeTextView+HeadingFoldHover.swift` + companion edits across MarkdownEngine; new `Pommora/PommoraTests/Pages/FoldableHeadingsTests.swift`; minor edits to `SpaceColor.swift` / `SpaceColorPicker.swift`; in-flight doc edits to `.claude/Features/PageEditor.md` / `Pages.md` / `Properties.md` / `Guidelines/Markdown.md`; new `.claude/Planning/v0.3.0-Properties-spec.md` + `Superseded/`). The Markdown work intermittently broke `xcodebuild` during this session (missing `invalidateHeadingLayout`); subagents fell back to per-file `swiftc -typecheck` and continued. Per quirk #11, all of those files remain untouched in ParadigmV2 commits — Nathan reconciles separately.

##### Key naming decisions (locked in plan, all enforced in shipped code)

- **Swift types:** `PageType`, `PageCollection`, `ItemType`, `ItemCollection`, `AgendaTask`, `AgendaEvent`, `Project`, `SavedView` (renamed from `VaultView`), `Settings`, `SettingsManager`, `SettingsLabels`, `LabelPair`, `SettingsAccentColor`.
- **UI labels (defaults, renameable via Settings):** Pages-side **"Vault"** / **"Collection"**; Items-side **"Type"** / **"Set"**; "Task", "Event", "Project"; section labels "Pages" / "Items" (no Agenda section).
- **Banned in on-disk schemas + Swift qualifications:** "Pommora" prefix. No `pommora_*` JSON keys; no `Pommora.X` qualifications — use side-prefixed names (`AgendaTask` not `Pommora.Task`). Existing `pommora_table_widths` grandfathered for v0.3.0; rename when Tables ship.

##### Test count + build status

- Build: `** BUILD SUCCEEDED **` (xcodebuild, macOS destination, run multiple times across the session — most recently after the New Collection button color fix).
- Tests: **357 passing**, 0 failing, 0 skipped. Pre-session baseline was 252; ParadigmV2 added a net +105 cases across Phases 4–7 (Agenda split tests, Items-side tests, wrapper-layout tests, adopter-migration tests, Settings tests).
- Pre-existing intermittent timing flake: `PageEditorViewModelTests.debounceCoalescesRapidEdits` (sleeps 500ms after 300ms debounce — tight margin under load). Pre-ParadigmV2; not blocking.

##### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. ParadigmV2 Phases 1–7 SHIPPED on `main`. Build green, 357 tests passing. Next: **Phase 8 — Sidebar / Detail / Sheet UI restructure** (5 tasks: 8.1 enum updates + 8.2 stub sheets + 8.3 sidebar section reorder + 8.4 detail-pane stubs + 8.5 Item rows). Playbook at `~/.claude/plans/velvet-crunching-frost.md`. Quirk #9 is load-bearing on the SidebarView section structure — preserve `Section(isExpanded:) { } header: { SectionHeader(...) }` shape and verify via test bootstrap, not just build. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Phase 10's data migration is largely subsumed by the adopter fix-forward at `2b8ade8` — when Phase 10 starts, scope it to 'open nexus + adopt + verify backup' rather than authoring a separate bash script. Parallel session may have collapsible-heading + Properties-spec work in `.claude/Features/*`, `.claude/Planning/*`, `External/MarkdownEngine/*` — never bundle those into ParadigmV2 commits (quirk #11)."

---

#### Prior versions (shipped — full detail in History.md)

- **v0.2.8.0** (commit `5a264f0`) — Blockquote chrome (v0.2.7.5) + drag-reorder Phase 1 persistence (v0.2.8)
- **v0.2.7.6** (commit `733cc47`) — Task checkbox redesign + initial-load styling + sidebar chrome
- **v0.2.7.4** (Session 14) — Nexus folder adoption + editor polish bundle (bullet glyph, task `-[]` shorthand, arrow chains, bracket auto-pair guard, code colors, HR jitter fix)
- **v0.2.7.2** (Session 12 + 13) — HR dynamic-syntax + Lists rewrite (space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source)
- **v0.2.7.1** (Session 10) — NavDropdown ship
- **v0.2.7.0** (Session 9) — Native TextKit-2 editor via vendored `swift-markdown-engine`

---

#### Known follow-up debt (not blocking ParadigmV2)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight appears to start at body text rather than extending into the hidden `>` syntax gap. Fix paths documented in `History.md` Session 15B entry.
- **NavDropdown Pinned drag-to-reorder** — lands with drag-reorder Phase 2 (post-ParadigmV2)
- **NavDropdown type chip removal** (drop trailing "Page / Type / Topic" text, rely on leading icon)
- **NavDropdown segmented picker polish** (opacity / contrast pass)
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface v0.4.0
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 wikilink work depends on this
- **MarkdownEngine collapsible-heading work** — in flight in parallel session as of session end; not a ParadigmV2 dependency

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
- **Session transcripts**: `.claude/Transcripts/`

---

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
- **Phase 10 scope** — the adopter fix-forward at `2b8ade8` now handles legacy-layout migration in-app. Phase 10's original scope (separate `migration/paradigmV2.sh` script with backup + dry-run + verbal-approval gate) is largely subsumed. Decision when Phase 10 starts: keep an explicit `.pre-paradigmV2-backup/` copy step + adopter verification, or skip Phase 10 entirely and absorb into Phase 11.
