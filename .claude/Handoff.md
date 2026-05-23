### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-23)

> **flatlayout refactor in-flight.** Plan at [`Planning/v0.3.0-Flat-Layout-Plan.md`](Planning/v0.3.0-Flat-Layout-Plan.md); code catches up over Phases 2–6; **docs already describe the target state** (flat root layout + six per-kind sidecars — `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`). Phase 1 (docs) sweeps first by design so Phase 2–6 subagents read the target spec cleanly. This is the ONE doc that explicitly signals the disk-state lag; everything else describes flat as canonical.

**ParadigmV2 SHIPPED.** Tag `paradigmV2` pushed to origin at commit `36d48c8`. Local + `origin/main` aligned at `b2e4c53` (post-ship doc sync). Build green via `xcodebuild`, **358 tests passing**. Pre-existing intermittent flake: `PageEditorViewModelTests.debounceCoalescesRapidEdits` (tight 500ms-after-300ms margin) — not blocking.

**Next focus: flatlayout refactor → then v0.3.0 Properties.** Flatlayout plan at [`Planning/v0.3.0-Flat-Layout-Plan.md`](Planning/v0.3.0-Flat-Layout-Plan.md) (6 phases; ships tagged `flatlayout` between `paradigmV2` and v0.3.0; gated on Nathan's explicit approval after Phase 1). Properties implementation plan at [`Planning/v0.3.0-Properties-plan.md`](Planning/v0.3.0-Properties-plan.md) (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at [`Planning/v0.3.0-Properties-spec.md`](Planning/v0.3.0-Properties-spec.md).

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **ParadigmV2 SHIPPED** — tag `paradigmV2` pushed to origin at commit `36d48c8`. Build green, 358 tests passing. **flatlayout refactor in-flight** — plan at `.claude/Planning/v0.3.0-Flat-Layout-Plan.md` (6 phases; tag `flatlayout` between `paradigmV2` and v0.3.0; ships before v0.3.0 Properties). Phase 1 docs sweep already updates `.claude/*` to describe the target flat layout (Types at nexus root; six per-kind sidecars `_pagetype.json` / `_pagecollection.json` / `_itemtype.json` / `_itemcollection.json` / `_taskconfig.json` / `_eventconfig.json`); Phases 2–6 catch the code up. Phase 1 → Phase 2 is the explicit gate — wait for Nathan's 'docs look good, proceed' signal before dispatching Phase 2. **Next focus after flatlayout: v0.3.0 Properties** — implementation plan at `.claude/Planning/v0.3.0-Properties-plan.md` (5 phases A–E; `ItemTypeSettingsSheet` ships at v0.3.0). Conceptual spec at `.claude/Planning/v0.3.0-Properties-spec.md`. The post-ParadigmV2 code surface — `PageType` + `ItemType` (symmetric containers) + `PageContentManager` + `ItemContentManager` + `SettingsManager` + `AgendaTaskManager` + `AgendaEventManager` — is the foundation flatlayout + Properties build on. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have collapsible-heading work in `External/MarkdownEngine/` — never bundle into commits (quirk #11)."

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

Concurrent session shipping collapsible-heading work in `External/MarkdownEngine/` (`NativeTextViewCoordinator+HeadingFolding.swift` + `NativeTextView+HeadingFoldHover.swift`). Per quirk #11, those files stay untouched in commits from this session — Nathan reconciles separately.

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow chrome design** — reuses main toolbar shape, or its own minimal one? Deferred until the primitive is built.

#### Document pointers

- **Roadmap**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation rules**: `.claude/Guidelines/Markdown.md`
- **Editor planning (active + paused)**: `.claude/Planning/Page-Editor-Plan.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **v0.3.0 Properties (conceptual spec)**: `.claude/Planning/v0.3.0-Properties-spec.md`
- **v0.3.0 Properties (impl plan)**: `.claude/Planning/v0.3.0-Properties-plan.md`
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Session transcripts**: `.claude/Transcripts/`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
