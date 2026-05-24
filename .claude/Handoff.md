### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-23)

**flatlayout SHIPPED + post-ship hardening cluster landed.** Tag `flatlayout` was pushed to origin at the Phase 6 ship cluster (`049df19`). Since the tag, **5 follow-up commits** landed on `main` addressing issues Nathan found running the app post-ship on his real nexus — adoption preview noise on non-Pommora folders, drag-to-reorder UX wiring (Phase 2), folder-name fallback + diagnostics in `SidebarDetailView.lookupVault`, co-located per-kind sidecar orphan cleanup, and a cosmetic `var` → `let` warning silence. Build green, **366 tests passing** (+3 from the ship tag's 363).

The on-disk layout is flat — Page Types / Item Types / Tasks singleton / Events singleton live at the nexus root with six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). `NexusAdopter` handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat) with legacy-orphan + co-located sidecar cleanup, and `.DS_Store`-tolerant empty-wrapper detection. Agenda discovery is sidecar-driven (Tasks/Events folders renameable via Finder).

**Nathan's real-nexus migration is complete** — `/Users/nathantaichman/The Nexus/` is now flat with all 8 vaults (`Archives` / `Assets` / `Claude` / `Databases` / `Knowledge` / `Materials` / `Pommora` / `Systems`) at root, plus `Tasks/` + `Events/` singletons. Migration verified end-to-end on production data.

**Next focus: v0.3.0 Properties.** Implementation plan at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at [`Planning/v0.3.0-Properties-spec.md`](Planning/v0.3.0-Properties-spec.md). Properties' schema-editing operates on the per-kind sidecar files flatlayout just shipped, so this is the natural next step.

**Flatlayout phase status:**
- ✅ Phase 1 — Documentation sweep (5 commits)
- ✅ Phase 2 — NexusPaths foundation (4 sequential tasks + 1 sidebar-label follow-up)
- ✅ Phase 3 — Managers (3 commits; 3.2/3.4 verified clean)
- ✅ Phase 4 — NexusAdopter rewrite (3 commits)
- ✅ Phase 5 — Tests audit (2 commits)
- ✅ Phase 6 — Ship + tag `flatlayout` (pushed to origin at `049df19`)
- ✅ Post-flatlayout hardening cluster (5 commits: `2d42d63` adoption-preview gate / `9cd8cd1` drag-reorder Phase 2 UX / `9c3820c` lookup fallback + diagnostics / `5234f78` co-located orphan cleanup / `5f0e11d` `var` → `let` cleanup)

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **flatlayout SHIPPED** — tag `flatlayout` pushed to origin at `049df19`; 5 post-ship hardening commits on `main` since (adoption-preview gate / drag-reorder Phase 2 UX / lookup fallback + diagnostics / co-located orphan cleanup / `var` → `let`). Build green, **366 tests passing**. On-disk layout is flat — Types at nexus root + six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). `NexusAdopter` handles fresh / legacy v0.2 / paradigmV2-wrapper / already-flat input shapes with legacy-orphan + co-located sidecar cleanup. Nathan's real-nexus migration is complete (flat, 8 vaults at root). **Next focus: v0.3.0 Properties** — implementation plan at `.claude/Planning/v0.3.0-Properties-plan.md` (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at `.claude/Planning/v0.3.0-Properties-spec.md`. Properties' schema-editing operates on the per-kind sidecars flatlayout just shipped, so it builds directly on top. The post-flatlayout code surface — `PageType` + `ItemType` (symmetric containers) + `PageContentManager` + `ItemContentManager` + `SettingsManager` + `AgendaTaskManager` + `AgendaEventManager` + flat-aware `NexusPaths` + `NexusAdopter` — is the foundation Properties builds on. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have editor / wireframe work in working tree — never bundle into commits (quirk #11)."

#### Outstanding follow-ups

##### Known outstanding state

- **Collision-suffixed singleton folders on Nathan's nexus.** `Tasks.20260523-224558-760F/` and `Events.20260523-224558-46F1/` sit at `/Users/nathantaichman/The Nexus/` root — artifacts of the original adoption-pass folder-name collision (when `Tasks/` and `Events/` already existed pre-migration). The authoritative `Tasks/` + `Events/` singletons (carrying `_taskconfig.json` + `_eventconfig.json`) are in place; the timestamped siblings are inert. Nathan can `rm -rf` them manually if empty / confirmed-uninteresting.

##### Known debt (not blocking next focus)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight starts at body text rather than extending into the hidden `>` syntax gap. Fix paths in History.md Session 15B.
- **NavDropdown Pinned drag-to-reorder** — queued behind v0.2.8 Phase 2 (which shipped Pages-side + Contexts only).
- **Drag-to-reorder — Items-side rows** — still queued (Items ParadigmV2 sidebar rows are stubs; lights up when the designed Items UI lands).
- **Drag-to-reorder — cross-container drag** — out of scope for v1 per `Planning/v0.2.8-Drag-Reorder.md`.
- **Drag-to-reorder — detail-pane Tables** — Phase 4 of the v0.2.8 plan; not started.
- **NavDropdown polish** — type chip removal, segmented picker opacity/contrast.
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface at v0.4.0.
- **`do { try await … } catch { … }` rewrap** in SidebarView.swift + IconPickerSheet.swift — cosmetic.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 dependency.
- **Items section header label** — Phase 8.3 left "Items" as a literal string; SettingsManager-driven wiring lands when the real Items UI ships (Properties plan Phase C.3/C.7). (Default is now "Types" per `SidebarSectionLabels.defaults()`.)
- **Per-folder adoption UI** — Prospect. Today `AdoptionPlan.hasAnythingToAdopt` only triggers on structural migration (legacy renames / wrapper unwraps / explicit warnings); non-Pommora folders at root stay invisible to discovery. A future surface could let users opt non-Pommora folders into the Pommora vocabulary on a per-folder basis.

#### Parallel session

The concurrent editor session shipping collapsible-heading work in `External/MarkdownEngine/` continues to land commits on `main` interleaved with this work. Per Nathan's direction, those commits are included in `main`. Working tree at this snapshot has unattributed edits to `External/MarkdownEngine/Sources/MarkdownEngine/TextView/...` files + `.claude/Features/PageEditor.md` + `.claude/Features/Pages.md` — not bundled into the post-flatlayout hardening docs commit.

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow chrome design** — reuses main toolbar shape, or its own minimal one? Deferred until the primitive is built.

#### Document pointers

- **Roadmap**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation rules**: `.claude/Guidelines/Markdown.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **v0.3.0 Properties (conceptual spec)**: `.claude/Planning/v0.3.0-Properties-spec.md`
- **v0.3.0 Properties (impl plan)**: `.claude/Planning/v0.3.0-Properties-plan.md`
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Session transcripts**: `.claude/Transcripts/`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
