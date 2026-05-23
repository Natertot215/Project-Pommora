### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-23)

**flatlayout SHIPPED.** Tag `flatlayout` pushed to origin at the Phase 6 ship cluster (`5ceca94` 6.2 Handoff/History snapshot → `f2d42fe` 6.3 lint cleanup → tag self-reference fixup). The on-disk layout is now flat — Page Types / Item Types / Tasks singleton / Events singleton live at the nexus root with six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). `NexusAdopter` handles four input shapes (fresh / legacy v0.2 / paradigmV2-wrapper / already-flat) with legacy-orphan cleanup and `.DS_Store`-tolerant empty-wrapper detection. Agenda discovery is sidecar-driven (Tasks/Events folders renameable via Finder).

Build green via `xcodebuild`, **363 tests passing** at the ship tag. Pre-existing intermittent flake: `PageEditorViewModelTests.debounceCoalescesRapidEdits` (tight 500ms-after-300ms margin) — not blocking.

**Next focus: v0.3.0 Properties.** Implementation plan at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at [`Planning/v0.3.0-Properties-spec.md`](Planning/v0.3.0-Properties-spec.md). Properties' schema-editing operates on the per-kind sidecar files that flatlayout just shipped, so this is the natural next step.

**Flatlayout phase status:**
- ✅ Phase 1 — Documentation sweep (5 commits)
- ✅ Phase 2 — NexusPaths foundation (4 sequential tasks + 1 sidebar-label follow-up)
- ✅ Phase 3 — Managers (3 commits; 3.2/3.4 verified clean)
- ✅ Phase 4 — NexusAdopter rewrite (3 commits)
- ✅ Phase 5 — Tests audit (2 commits)
- ✅ Phase 6 — Ship + tag `flatlayout` (pushed to origin)

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **flatlayout SHIPPED** — tag `flatlayout` pushed to origin. Build green, **363 tests passing**. On-disk layout is flat — Types at nexus root + six per-kind sidecars (`_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). `NexusAdopter` handles fresh / legacy v0.2 / paradigmV2-wrapper / already-flat input shapes with legacy-orphan cleanup. **Next focus: v0.3.0 Properties** — implementation plan at `.claude/Planning/v0.3.0-Properties-plan.md` (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at `.claude/Planning/v0.3.0-Properties-spec.md`. Properties' schema-editing operates on the per-kind sidecars flatlayout just shipped, so it builds directly on top. The post-flatlayout code surface — `PageType` + `ItemType` (symmetric containers) + `PageContentManager` + `ItemContentManager` + `SettingsManager` + `AgendaTaskManager` + `AgendaEventManager` + flat-aware `NexusPaths` + `NexusAdopter` — is the foundation Properties builds on. Outstanding manual step: Nathan's real-Nexus migration (backup + adopt + verify at `/Users/nathantaichman/The Nexus/`). Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have editor / wireframe work in working tree — never bundle into commits (quirk #11)."

#### Outstanding follow-ups

##### Nathan's manual data migration (one adoption pass — post-flatlayout)

Flatlayout's Phase 4 rewrites `NexusAdopter` to handle four input shapes in a single pass and land directly at the flat target (no intermediate wrapper-unwrap step from the user's side). When the refactor ships, Nathan's path on his real Nexus is:

1. **Backup first** — `cp -R "/Users/nathantaichman/The Nexus" "/Users/nathantaichman/The Nexus.pre-flatlayout-backup"`.
2. **Launch Pommora** pointed at the real nexus.
3. **Click adopt** when the preview appears. Preview describes the migration in target-shape terms (per-folder action counts: `N` unwraps from `Pages/`, `M` from `Agenda/`, empty wrapper deletions, legacy sidecar deletions inside moved folders) — no separate user-facing "unwrap" intermediate state.
4. **Apply.** Sidebar populates: Pinned / Spaces / Topics / Items / Pages. Items section reads from root folders carrying `_itemtype.json`; Pages section from root folders carrying `_pagetype.json`.
5. **Spot-check the Nexus root** in Finder — should be flat: `Archives/ Assets/ Claude/ Databases/ … Tasks/ Events/` (no `Pages/` / `Items/` / `Agenda/` wrappers remaining).
6. **If something surfaces** that the adopter doesn't handle on Nathan's specific data shape — fix-forward in `NexusAdopter.swift` and re-launch (adoption is idempotent per locked decision #11; already-flat folders skip cleanly).

##### Known debt (not blocking next focus)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight starts at body text rather than extending into the hidden `>` syntax gap. Fix paths in History.md Session 15B.
- **NavDropdown Pinned drag-to-reorder** — lands with drag-reorder Phase 2.
- **NavDropdown polish** — type chip removal, segmented picker opacity/contrast.
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface at v0.4.0.
- **`do { try await … } catch { … }` rewrap** in SidebarView.swift + IconPickerSheet.swift — cosmetic.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 dependency.
- **Items section header label** — Phase 8.3 left "Items" as a literal string; SettingsManager-driven wiring lands when the real Items UI ships (Properties plan Phase C.3/C.7).

#### Parallel session

The concurrent editor session shipping collapsible-heading work in `External/MarkdownEngine/` has been landing commits in parallel on `main` throughout the flatlayout doc-sweep dispatches (recent ones: `f6a0661`, `806de93`, `325232a`, `8a81b3a`, `596d89d`, `e29f7e3`, `5c66be8`, etc.). Per Nathan's direction, those commits ARE included in `main` and will be in the eventual `flatlayout` tag push. Interleaving caused one metadata anomaly — `e29f7e3` incidentally absorbed the 1.3 doc-sweep edits to `Paradigm-Decisions.md` + `Symbols.md`; content is correct in HEAD, ship entry should note this.

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
