### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history in `History.md`; phased roadmap in `Framework.md`.

#### Current state (2026-05-26 — `main` at `a872f45`, +35 commits ahead of `origin/main`)

**Session outcome: partial.** Six commits landed on `main`. Properties UX still doesn't work as Nathan intended — the plan that was approved (`.claude/Planning/quizzical-mapping-boot-plan.md` — the v0.3.1.0.1 hotfix + redesign + Notion-spec'd Relation + Date & Time consolidation + simple/rich editor surface split) was NOT executed in full. What shipped was a UI-tokens scaffold + Edit Properties editor structural rewrite to the Figma layout + two real bug fixes. The rest of the plan is still queued.

**Execution lessons for next session (Nathan's directive — don't repeat):**
1. **Pull the Figma file FIRST** when the user gives a URL or says "redesign this UI." Don't build off mental model + sketches. Have Nathan select the node in his Figma desktop app so `mcp__claude_ai_Figma__get_design_context` + `get_variable_defs` work (the bare URL + nodeId only gives `get_screenshot`).
2. **Don't migrate tokens BEFORE the structural redesign.** The token-migration commits ate session time that should've gone to matching the Figma spec. The structural change usually supersedes the token work.
3. **Confirm each surface visually before moving on.** Don't ship 3 commits on a surface without Nathan opening the app between them.
4. **Auto Mode is off by default in this project state** — Nathan wants explicit checkpoints, not "I'll fix it as I go."

**Branch state:**
- `main` (HEAD): `a872f45` — 35 commits ahead of `origin/main`.
- `git push origin main` is the last pending op — auth-gated, never given this session or last session.

**Commits shipped this session (newest first):**

| SHA | Type | What |
|---|---|---|
| `a872f45` | fix | Seed Select/MultiSelect with placeholder option on create — passes `selectMissingOptions` validator |
| `1fbe3a8` | fix | EditPropertyPane redesign per Figma — pinned footer (Delete \| Duplicate), SymbolPicker icon button, plain TextField, pinned bottom picker (Display As / Format) |
| `587ac81` | refactor | StorageMenuRoot PUI-token migration + strip "v0.X.X" annotations + reorder muted rows (Templates → Filter → Group → Sort) |
| `44553d0` | refactor | 5 View Settings panes migrated to PaneHeader + PUI tokens, dropped row Dividers, **delete-property race fix** (pop path before await delete) |
| `13e4d16` | feat | `PUI` tokens module + `PaneHeader` scaffold (new files only, no usage) |
| `9d88dfc` | fix | Drop AppGlobals from SidebarSelection — fixes sidebar runtime-entity selection + toolbar back/forward (one root cause, two bugs) |

#### What actually works after these commits

- ✅ Sidebar selection on runtime-created entities (PageType / ItemType / Collections / Pages / Items created via sidebar `+` are now clickable)
- ✅ Toolbar back/forward steps through history correctly (was silently no-op)
- ✅ Every View Settings sub-pane has the same chrome (`PaneHeader` — back chevron + title sitting on top of the popover's Liquid Glass backdrop, no NavigationStack dark band cutting through anywhere)
- ✅ Delete property no longer flashes "Property not found" mid-delete (commitDelete pops before await)
- ✅ Select / MultiSelect creation now passes the validator (was throwing `.selectMissingOptions`)
- ✅ EditPropertyPane has the bones of the Figma layout: icon Button at top opens SymbolPicker, plain TextField name field, Display As / Format pinned to bottom, Delete + Duplicate pinned footer (borderless mini-buttons)

#### What does NOT work (Nathan's "properties don't work as intended")

This is the honest list. None of these are fixed in this session:

1. **SelectOptionsEditor + StatusGroupsEditor are not redesigned.** The Figma spec puts options as **chip-rows with a chevron-push to EditOptionPane** (each option opens its own editor pane). The current editors still use the legacy inline-TextField + minus-circle pattern in the scroll body of EditPropertyPane.
2. **Drag-reorder of options is not implemented.** Comments in both editor files (`SelectOptionsEditor.swift:10`, `StatusGroupsEditor.swift:13`) explicitly say "Drag-only reordering ships at Task 11" — Task 11 came and went and it never shipped. Nathan asked for Liquid Glass + Finder-style displacement animation when this lands.
3. **Simple-type inline popup never built.** The approved plan's split — Number / URL / Checkbox / File should use an inline anchored popover instead of a pushed pane — is NOT implemented. `PropertyEditorPopover.swift` was never created. Every type still pushes to EditPropertyPane.
4. **Date & Time consolidation never shipped.** `PropertyType.date` and `.datetime` are still separate enum cases. The approved plan had us dropping `.date`, keeping only `.dateTime` (UI label "Date & Time"), adding a `TimeFormat` enum, and a migration. None of that happened.
5. **Relation editor is still a read-only scope summary.** The Notion-verified design (searchable target picker + `Show on [target]` toggle + mirror name TextField + Limit picker, all wired through `DualRelationCoordinator`) is NOT built.
6. **StorageMenuRoot is still the legacy 2-active + 4-muted shape.** The approved plan's 8-row redesign (Vault/Collection title inline-edit row + View Title inline-edit row + Edit Properties + Visibility + Templates + Filter + Group + Sort) is NOT built. Only the muted-row labels were updated + version notes stripped.
7. **`@FocusState` click-outside-commits on inline TextFields never shipped.** Nathan's "click outside to commit/cancel inline-edit" requirement is still missing — only `.onSubmit { commit() }` (Enter to commit) is wired. Click-outside does nothing, leaving the user locked in until they hit Enter.
8. **Phase 1B (Vault delete/rename bug) not fixed.** Explore agent identified the diagnosis (likely stale `pageType` capture in `PageTypeRow`) but no fix shipped. Sidebar Vault rename/delete may still be broken.
9. **Sidebar rows + detail-view chrome + sheets** never migrated to `PUI` tokens. They still use their own internal padding / spacing / icon values, which means **the cohesion problem Nathan flagged still exists everywhere outside the View Settings popover.**
10. **EditPropertyPane visual fidelity is not Figma-verified.** Nathan's Figma file at `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432` was only available as a low-res screenshot this session — `get_design_context` + `get_variable_defs` both errored ("nothing selected in Figma desktop"). The structural rewrite of EditPropertyPane is the closest approximation I could get without exact variable bindings.

#### What's next (Nathan's stated direction)

Nathan is clearing the chat after this handoff lands. He explicitly said "Properties dont work as intended, the plan was not executed well." Next session should re-plan from scratch with Figma as the spec, not rely on the existing plan file.

**Concrete first moves for next session:**
1. **Have Nathan select the EditPropertyPane node** (and any other relevant nodes — root pane, type picker, option chips) in his Figma desktop app. Then call `mcp__claude_ai_Figma__get_design_context` + `get_variable_defs` to pull the actual structured spec + variable bindings (paddings, colors, font sizes).
2. **Audit the current Pommora EditPropertyPane against the Figma spec** with the variable defs in hand. Identify deltas — likely paddings, the icon button visual style, the chip-row styling for options, the section-header "Options / +" pattern, etc.
3. **Decide whether to keep building on `a872f45` or revert and start over.** The PUI tokens scaffold + PaneHeader + delete-race fix + selection plumbing fix are net-positive and should stay regardless. The EditPropertyPane structural rewrite (`1fbe3a8`) is the right shape but may need rework once the Figma spec is precise.
4. **Then start on the genuinely missing pieces:** SelectOptionsEditor/StatusGroupsEditor chevron-push redesign, drag-reorder, Date & Time consolidation, Relation editor, simple-type popup, StorageMenuRoot 8-row redesign, click-outside FocusState, sidebar/detail-view PUI migration, Vault delete/rename fix.

**Approved plan (still on disk, partially executed):**
- `~/.claude/plans/quizzical-mapping-boot.md` — the v0.3.1.0.1 hotfix + redesign + Notion-spec'd Relation + Date & Time + simple/rich editor split. Phases 1A + parts of 2B + parts of 2D-Editor shipped. **Phase 1B, 2A (root redesign), 2C (popup split), 2D-Schema (Date & Time merge), 2D-Options (drag-reorder), 2D-Relation (Relation editor), 2E (FocusState)** are all queued.

#### Locked decisions in force (unchanged from prior session)

1. **Status value on-disk encoding = `{"$status": value}` tagged-object form.**
2. **Move-strip matches by NAME, not ID.** Property IDs are globally unique per `property_definitions.id PRIMARY KEY`.
3. **Reserved property IDs:** `_id`, `_created_at`, `_modified_at`, `_status`, `_tier1/2/3`, `_wikilinks`. User-defined mint `prop_<ulid>`.
4. **`schema_version: 1` on every sidecar.**
5. **`PropertyIDMigration` runs on EVERY nexus open** — idempotent.
6. **tier1/2/3 are root-level frontmatter fields** (not under `properties:`).
7. **AgendaTask + AgendaEvent default seed = single `_status` property.**
8. **`DualRelationCoordinator` owns paired-relation lifecycle.**
9. **`AttachmentManager` is the only path for file values.**
10. **Settings carries `defaultsVersion: Int`** bumped to v2 on 2026-05-25.
11. **Items + Pages are NOT renameable concepts** — only containers are (Vault / Collection / Type / Set).
12. **View Settings button = single static instance at ContentView level inside the existing primary-action `.glassEffect()` HStack.**
13. **`PUI` design tokens** (new this session) — single source of truth for paddings / spacings / icons / fonts / radii. Forbidden in new code: magic-number padding. Extend `Pommora/Pommora/DesignSystem/PUI.swift` rather than inlining raw values.
14. **`PaneHeader` is the chrome for every View Settings sub-pane** (new this session) — no `.navigationTitle(_:)` allowed on pushed panes; renders the back chevron + title in-content so it sits on top of the popover's Liquid Glass backdrop. Locked at `Pommora/Pommora/ViewSettings/PaneHeader.swift`.
15. **`SidebarSelection` no longer reads `AppGlobals`** (new this session) — all selection resolution goes through `SidebarLookupBundle` (struct holding live `@Environment`-injected manager refs). Constructors: `init?(tag:lookup:)`, `init?(stateRef:lookup:)`. AppGlobals stays for RecentsManager / MainWindowRouter / lifecycle observers but is forbidden as a selection-resolution source.

#### Active branch quirks (carry forward to every subagent dispatch)

1. **Test filter form uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`. Suite-name form silently no-ops.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include; pbxproj usually doesn't need editing. New `DesignSystem/` folder picked up automatically this session.
3. **Trust `xcodebuild`, not SourceKit squiggles.** "Cannot find type X" / "No such module 'SymbolPicker'" diagnostics are routinely stale post-edit. Always builder-verify.
4. **`.claude/*` is included in commits.** Don't auto-bundle docs into Swift commits without explicit ask; explicit doc commits are fine.
5. **Swift 6 strict concurrency + ExistentialAny ON.** Custom Codable: `init(from decoder: any Decoder)` / `func encode(to encoder: any Encoder)`. Errors: `var foo: (any Error)?`.
6. *(retired in ParadigmV2)*
7. **Xcode auto-reorders SymbolPicker/Yams/GRDB entries in pbxproj on every build** — incidental noop diff. Revert before commit.
8. **Stub-and-progressively-replace** is the locked execution strategy.
9. **Section structure in SidebarView is load-bearing.** Don't break `Section(isExpanded:) { } header: { SectionHeader(...) }` patterns; don't mix flat-leaf + disclosure rows inside one Section.
10. **Sidebar selection chrome at row file level via `.listRowBackground(SelectionChrome(...))`.**
11. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Working tree NOT guaranteed clean between subagent dispatches.
12. **`swift format` is invoked as a subcommand** (`swift format format --in-place ...`).
13. **Use `Agent run_in_background: true` for builder-subagent verification** — Nathan doesn't want xcodebuild grabbing window focus.
14. **GRDB `String` overload pollution in @ViewBuilder closures** — isolate per-row rendering into private struct sub-views.
15. **`loadAll` must sync in-memory parents to the SQLite index.**
16. **Every `@Environment(X.self)` declared on a detail view OR popover-hosted view must be explicitly re-injected at the boundary.** Detail-view + popover variants both apply.
17. **`Button(role: .close) { dismiss() }` without an explicit `label:` closure crashes outside `.toolbar { ... }` context.**
18. **(NEW)** **Don't trust the approved plan file as-is.** This session's plan (`~/.claude/plans/quizzical-mapping-boot.md`) was approved but execution drifted — UI polish pass ate into the structural redesign budget. Next session should re-read the plan AND check this Handoff's "What does NOT work" list before deciding what to ship.
19. **(NEW)** **Always pull from Figma when the user gives a URL.** Don't implement from sketches alone. `mcp__claude_ai_Figma__get_design_context` + `get_variable_defs` need the user to select the node in their Figma desktop app first — ask them to do so if the calls return "nothing selected."

#### Document pointers

- **Roadmap (chronological)**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **PRD**: `.claude/PommoraPRD.md`
- **Properties spec (single source of truth)**: `.claude/Features/Properties.md`
- **Per-entity specs**: `.claude/Features/{Domain-Model, Contexts, PageTypes, Pages, Items, Agenda, Homepage, NavDropdown, Sidebar, PageEditor, Architecture, Prospects, PommoraUIX}.md`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
- **Active planning + research notes**: `.claude/Planning/`
- **Approved-but-partially-executed plan**: `~/.claude/plans/quizzical-mapping-boot.md`
- **Figma source for property editor**: `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`

#### Resume prompt for next session (verbatim)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. **`main` at `a872f45`, +35 commits ahead of `origin/main`, all local — `git push origin main` is the last pending op (auth-gated).** Last session shipped 6 commits — a UI tokens scaffold (`PUI`), shared pane chrome (`PaneHeader`), selection-plumbing fix (sidebar runtime entities + toolbar back/forward), delete-property race fix, EditPropertyPane structural rewrite to the Figma layout, and a Select/MultiSelect creation-validator fix. **The headline UX still doesn't work as Nathan intended** — the approved plan at `~/.claude/plans/quizzical-mapping-boot.md` was only partially executed; SelectOptionsEditor/StatusGroupsEditor still use the legacy inline pattern (no chevron-push, no chip rows, no drag-reorder), the simple-type inline-popup never shipped, Date & Time consolidation didn't happen, the Relation editor is still a read-only scope summary, StorageMenuRoot is still the legacy shape, FocusState click-outside-commits never shipped, Vault delete/rename fix didn't ship, and sidebar/detail-view chrome are NOT migrated to PUI. Full broken-list at top of this Handoff. **FIRST MOVE: have Nathan select the EditPropertyPane node in his Figma desktop app** so `mcp__claude_ai_Figma__get_design_context` + `get_variable_defs` work — then audit the current implementation against the actual structured spec + variable bindings. Don't repeat last session's mistake of building off the screenshot + sketches alone. **Quirks #18 + #19 (new this session)** capture the meta-lessons: re-read this Handoff before trusting the plan file, and pull Figma first when there's a URL in play."
