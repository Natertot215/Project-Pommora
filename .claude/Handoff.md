### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (2026-05-22 — **ParadigmV2 Phase 1 (docs) staged in working tree**)

**Active focus:** [[ParadigmV2]] — operational-layer domain model refactor. Plan locked at [`Planning/ParadigmV2.md`](Planning/ParadigmV2.md) (~2,360 lines, 11 phases). **Phase 1 (doc rewrites) is the current commit boundary.** All 14 Phase 1 doc tasks land in one bundled commit at Task 1.14 per the playbook's batch-commit discipline.

##### Phase 1 progress

All 14 doc rewrite tasks executed in the current session via parallel subagent dispatch (Tasks 1.3-1.10 fired in parallel; Tasks 1.1-1.2 + 1.11-1.14 done inline). Working-tree state at session-end:

- ✅ `Features/Domain-Model.md` — rewritten for ParadigmV2 (PARA mapping → Projects; operational layer split into Pages/Items/Agenda sub-tables; naming convention three-layer table; sidebar shape updated; What changed bullet appended)
- ✅ `Features/PageTypes.md` — NEW (renamed from `Vaults.md`); Pages-side-only spec
- ✅ `Features/Items.md` — Item Type + Item Collection container layer documented
- ✅ `Features/Agenda.md` — AgendaTask + AgendaEvent split + per-side schema tables
- ✅ `Features/Pages.md` — intro anchored on Page Type; sub-topic → project references
- ✅ `Features/Contexts.md` — Sub-topics → Projects globally (`.subtopic.json` → `.project.json`)
- ✅ `Features/Properties.md` — `_schema.json` per-Type, relation scope expanded
- ✅ `Features/Architecture.md` — Pommora-prohibited rule + symmetric model + updated bullets
- ✅ `Features/Prospects.md` — Item↔Page cross-side, Item Templates, Full Settings UI prospects
- ✅ `Features/Sidebar.md` — 5-group sidebar, Items above Pages, no Agenda section, wrapper-folder note
- ✅ `Features/Spaces.md` + `Features/Collections.md` stubs + [[Vaults]] wikilink sweep clean
- ✅ Root docs: `CLAUDE.md`, `PommoraPRD.md`, `Framework.md`, `Handoff.md` (this file), `History.md` (new ParadigmV2 entry at top)
- 🟡 Guidelines docs: `CRUD-Patterns.md` + `Design.md` + `Paradigm-Decisions.md` + Properties planning doc rewrite + stress-test (Task 1.13 — pending)
- 🟡 Commit + GATE 1 check (Task 1.14 — pending)

##### The refactor in one paragraph

Pre-ParadigmV2: kind-agnostic Vaults containing Pages + Items, with Collections as sub-folders, AgendaItem as a unified Task+Event struct, and Sub-topics for tier-3 Contexts. Post-ParadigmV2: **symmetric Page/Item model** — Page Type → Page Collection → Page (`.md`) on the Pages side; Item Type → Item Collection → Item (`.json`) on the Items side. AgendaItem splits into **AgendaTask** + **AgendaEvent** (EKReminder + EKEvent aligned). Sub-topics renamed to **Projects**. Schema sidecars unify to `_schema.json` everywhere. On-disk wrapper folders introduced: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. **UI label divergence**: Pages-side "Vault" + "Collection"; Items-side "Type" + "Set" — each side has one signature word + one shared word; all renameable via Settings. **Settings scaffold** (`.nexus/settings.json` + SettingsManager + label wiring + Cmd+, stub scene) lays groundwork for v0.6.0 Settings UI. **"Pommora" prohibited** in on-disk schemas + Swift namespace qualifications; retires `Pommora.Collection` quirk #6.

##### Locked phase sequence

1. ✅ Doc rewrites (Studio direct — staged; Task 1.14 bundle-commits)
2. PageType + PageCollection renames + `_schema.json` sidecar
3. Subtopic → Project rename
4. AgendaItem split → AgendaTask + AgendaEvent
5. New ItemType + ItemCollection subsystem
6. Pages/Items wrapper folders + NexusAdopter update
7. **Settings scaffold** (storage + manager + UI label wiring + Cmd+, stub scene)
8. Sidebar / Detail / Sheet UI restructure (consumes Phase 7 label source)
9. Tests consolidation + v0.3.0 Properties spec reconciliation
10. Nathan's user-data migration (one-shot script; not committed)
11. Cleanup + Framework reconciliation + ship (tag `paradigmV2`)

Phases 2/3/4 are parallelizable. Phases 5 → 6 → 7 → 8 are sequential. Each phase ships green standalone (stub-and-progressively-replace per quirk #8). All dispatched agents use Opus 4.7.

##### Key naming decisions (locked in plan)

- **Swift types:** `PageType`, `PageCollection`, `ItemType`, `ItemCollection`, `AgendaTask`, `AgendaEvent`, `Project`, `SavedView` (renamed from `VaultView`), `Settings`, `SettingsManager`, `SettingsLabels`, `LabelPair`
- **UI labels (defaults, renameable via Settings):** Pages-side **"Vault"** / **"Collection"**; Items-side **"Type"** / **"Set"**; "Task", "Event", "Project"; section labels "Pages"/"Items"
- **Banned in on-disk schemas + Swift qualifications:** "Pommora" prefix. No `pommora_*` JSON keys; no `Pommora.X` qualifications — use side-prefixed names (`AgendaTask` not `Pommora.Task`). Existing `pommora_table_widths` grandfathered for v0.3.0; rename when Tables ship.

##### Next-session entry path

After Phase 1 commits (Task 1.14), the next session picks up at **Phase 2 — Foundational code: Schema sidecar rename + PageType + PageCollection renames** in the playbook at `~/.claude/plans/velvet-crunching-frost.md`. Phase 2 starts with Task 2.1 (`NexusPaths.schemaSidecarFilename = "_schema.json"` constant + production-code literal sweep). Phases 2/3/4 can run in parallel since they touch different files; Phase 2 is the natural starting point because Phases 5-8 depend on it.

Builder agent handles all `xcodebuild` (quirk #3). Build verify + test pass + lint between every gate. 252/252 unit tests is the baseline.

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

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight appears to start at body text rather than extending into the hidden `>` syntax gap. Suspected bar-pill-radius vs card-corner-radius mismatch OR alpha visibility issue. Fix paths documented in `History.md` Session 15B entry.
- **NavDropdown Pinned drag-to-reorder** — lands with drag-reorder Phase 2 (post-ParadigmV2)
- **NavDropdown type chip removal** (drop trailing "Page / Type / Topic" text, rely on leading icon)
- **NavDropdown segmented picker polish** (opacity / contrast pass)
- **In-app Trash window** — `.trash//` data layer shipped v0.2.5; UI surface v0.4.0
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 wikilink work depends on this

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
- **Session transcripts**: `.claude/Transcripts/`

---

#### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. ParadigmV2 Phase 1 (docs) committed on `main`. Next: Phase 2 — Foundational code (schema sidecar rename + PageType + PageCollection renames). Playbook at `~/.claude/plans/velvet-crunching-frost.md` enumerates all 54 tasks across 11 phases with per-task gate checks and the subagent dispatch protocol. Start Task 2.1 (`NexusPaths.schemaSidecarFilename = "_schema.json"` + production-code literal sweep). Phases 2/3/4 can run in parallel since they touch different files. Every dispatched agent uses Opus 4.7. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Quirk #6 (`Pommora.Collection`) is RETIRED by ParadigmV2 — no more qualification needed."

---

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
