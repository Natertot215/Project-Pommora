### Pommora — Session Handoff

> **Read this first at session start.** Snapshot of where things stand + what to pick up next. Detailed shipped history lives in `History.md`.

#### Current state (2026-05-23 EOD)

Today shipped three threads in parallel + a Properties scope brainstorm:

1. **Foldable headings toggle — fixed.** Parallel-session editor work in `External/MarkdownEngine/` resolved the heading-fold mechanism; chevron-on-hover + frontmatter persistence via `folded_headings` now works correctly.
2. **Em-dash / en-dash auto-syntax — shipped.** Trivial editor add: `--` → en-dash, `---` → em-dash. Parallel session.
3. **v0.3.0 Properties — scope redirected + locked.** Brainstorm session reshaped v0.3.0 from "ship everything end-to-end" to **data layer + minimum-viable placeholder UI**. Real Properties Pulldown + Property Panel becomes v0.3.1 (Figma-driven fast-follow). Broader inspector architecture (Claude chat, PreviewWindow, Item Window redesign) ships in later v0.3.x patches whenever designed.
4. **Sidebar disclosure-click bug — fixed.** Vault rows weren't expanding to show their Collections / root Pages. Root cause: `.draggable` in `.reorderable(...)` was applied to the entire DisclosureGroup, swallowing chevron clicks as drag-init. Fix: moved `.reorderable(...)` into the DisclosureGroup's `label:` closure (PageTypeRow / PageCollectionRow / TopicRow). Build green, 365/365 tests passing.
5. **Sidebar header label "Pages" → "Vaults"** — Nathan's `settings.json` had stale `sidebar_sections.pages = "Pages"` from before the defaults change. Updated directly.
6. **PageType context menu cleanup** — verbose clarifiers stripped: "New Vault" / "New Collection" / "New Page" (direct-to-vault page already supported).

**Tomorrow:** more brainstorm on Properties before locking implementation spec. The 6 conceptual decisions captured today (lazy properties, per-Type order, "No properties" empty state, right-click Pin, Status as universal informational, live red-border validation) are locked. Tomorrow's session digs into the remaining design questions Nathan hasn't decided yet.

#### v0.3.x sub-sequence (refined 2026-05-23)

```
v0.3.0 — Properties data layer + minimum-viable placeholder UI
v0.3.1 — Properties Pulldown + Panel UI (Figma-driven)
v0.3.2 — Page-wikilinks
v0.3.3 — SQLite + querying
```

**Independent v0.3.x patches (TBD timing):** Item Window redesign with pinned chips at Item Collection level; Claude chat as main-window inspector; PreviewWindow primitive (Page / Context Preview windows). Each ships when designed.

#### Surface architecture (locked direction)

Properties live in three different surfaces depending on context. UI design is deferred to Figma; the architecture is locked.

| Surface | Property home | Timing |
|---|---|---|
| **Page in main window** | NavDropdown-style pulldown at top of content | Real UI v0.3.1 |
| **Page Preview** (standalone window) | Property panel in window inspector (toggle, default closed) | When PreviewWindow ships |
| **Item Window** (popover) | Property panel in popover inspector (toggle, default closed) + pinned-property chips above title (Item Collection-level) | When Item Window redesign ships |
| **Context Preview** (window) | Inspector reserved for TBD purpose; Contexts have no properties | n/a |
| **Main window inspector** | Claude chat (CLI subprocess bridge). Properties NEVER live here. | Ships independently |

Canonical reference: `.claude/Features/Properties.md` § "Where Properties Live".

#### Verbatim resume prompt

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. Today shipped foldable headings toggle fix + em/en dash editor syntax + sidebar disclosure-click bugfix + sidebar header label fix + Vault context menu cleanup. **v0.3.0 Properties scope was redirected** (2026-05-23 brainstorm) to ship data layer + minimum-viable placeholder UI only; real Properties Pulldown + Panel UI becomes v0.3.1 (Figma-driven fast-follow). Broader inspector architecture (Claude chat main-window inspector, PreviewWindow primitive, Item Window redesign with pinned chips) ships in later v0.3.x patches with TBD timing. 6 conceptual decisions locked: lazy-properties model (only existing schema properties in '+ Add property' picker), per-Type property order persistence, empty-pulldown 'No Properties' state, right-click 'Pin Property' interaction, Status as universal informational on non-Agenda Types, live red-border validation feedback. Build green, **365/365 tests passing** (one timing flake in PageEditorViewModelTests re-runs clean). Nathan's nexus settings.json updated to render 'Vaults' / 'Types' section headers. **Tomorrow's session:** more design brainstorm on Properties before locking implementation spec — see 'Open questions for tomorrow' below for the queued topics. The post-flatlayout code surface is the foundation; the v0.3.0 implementation plan at `.claude/Planning/v0.3.0-Properties-plan.md` reflects the narrowed scope. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1). Parallel session may have editor / wireframe work in working tree — never bundle into commits (quirk #11)."

#### Open questions for tomorrow's brainstorm

Conceptual gaps surfaced in today's sweep that Nathan hasn't decided yet — queue for tomorrow's session before implementation spec locks:

1. **Multi-window state.** When a Page is open in the main window AND a Page Preview window simultaneously, how do property edits propagate? Conflict resolution? Live update both?
2. **Pinned chip overflow.** Item Collection-level pinned set with more chips than fit. Wrap to second row? Scroll? Hide overflow with "+N more"?
3. **Per-property icon vs per-Type icon distinction.** Both use SF Symbols. Visual distinction or contextual-only?
4. **Move-strip + dual relation interaction.** Page moves to a new PageType that ALSO has a same-named relation property with the same target. Transfer value or strip-and-orphan-target-side?
5. **Number format storage shape.** Schema says `number_format: currency`. User enters "$100.50". Stored as `100.50` raw + format applied at render? Or `"$100.50"` formatted string? (Round-trip implications.)
6. **Status property — move option between groups.** Spec says data-semantic (changes EventKit mapping at v0.7.0). UX: confirmation dialog needed? What does it list?
7. **Properties Pulldown default state.** Open or closed on page load? Affects discoverability.
8. **AgendaTask + AgendaEvent placeholder UI entry point.** Locked: reuse Item Window UX pattern, separate code per entity. But WHERE does the user open these from at v0.3.0? Calendar pin → list → click → window?
9. **Settings scaffold migration story.** Nathan's settings.json was stale (pre-defaults change). For future users, should `SettingsManager.loadOrCreate()` migrate stale `sidebar_sections` values to new defaults automatically? Or stays user-managed?
10. **Validation on dual relations.** Both sides must succeed atomically. What's the UI feedback when one side fails (e.g., target Type's reverse-property name conflicts)?

#### Outstanding follow-ups

##### Known outstanding state

- **Sidebar drag-to-reorder REGRESSION (introduced 2026-05-23 by `fb6d581`).** Today's disclosure-click fix moved `.reorderable(...)` from the outer DisclosureGroup modifier to inside the `label:` closure on PageTypeRow / PageCollectionRow / TopicRow. This restored chevron-click toggling but shrunk the drag/drop hit zone to label area only AND broke `rowHeight` measurement (label height ≠ full row height → above/below drop position calc is off). Drag may feel non-functional or land in wrong positions. **Fix direction:** split drag source from drop destination — keep `.draggable` scoped to label only (so chevron click stays free), but apply `.dropDestination` to the full row (so users can drop anywhere). Requires refactoring `ReorderableRowModifier` to support split application, OR adding a separate `.dropTarget` modifier alongside `.reorderable`. Queue before v0.3.0 starts.
- **Collision-suffixed singleton folders on Nathan's nexus.** `Tasks.20260523-224558-760F/` and `Events.20260523-224558-46F1/` sit at `/Users/nathantaichman/The Nexus/` root — inert artifacts of the original adoption-pass folder-name collision. Authoritative `Tasks/` + `Events/` singletons are in place. Nathan can `rm -rf` the timestamped siblings manually.
- **Settings.json `sidebar_sections` migration debt.** Today's fix was direct file edit on Nathan's nexus. A SettingsManager migration shim that detects stale-default values and updates in place is queued (see Open Question #9 above).

##### Known debt (not blocking next focus)

- **Blockquote horizontal-positioning visual** (v0.2.7.5 carryover) — card highlight starts at body text rather than extending into the hidden `>` syntax gap.
- **NavDropdown Pinned drag-to-reorder** — queued behind v0.2.8 Phase 2.
- **Drag-to-reorder — Items-side rows** — queued (Items rows are stubs).
- **Drag-to-reorder — cross-container drag** — out of scope for v1.
- **Drag-to-reorder — detail-pane Tables** — Phase 4 of v0.2.8 plan; not started.
- **NavDropdown polish** — type chip removal, segmented picker opacity/contrast.
- **In-app Trash window** — `.trash/` data layer shipped v0.2.5; UI surface at v0.4.0.
- **`do { try await … } catch { … }` rewrap** in SidebarView.swift + IconPickerSheet.swift — cosmetic.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 dependency.

#### Parallel session

The concurrent editor session shipping collapsible-heading work + em/en dash syntax in `External/MarkdownEngine/` continues to land commits on `main` interleaved with this work. Today's commits include the foldable-headings toggle fix (works correctly now) + em/en dash syntax. Working tree at this snapshot carries unattributed edits to `External/MarkdownEngine/Sources/MarkdownEngine/...` + `Pommora/Pommora/ContentView.swift` + `Pommora/Pommora/Pages/PageEditorView.swift` — never bundled into property-scope commits per quirk #11.

#### Document pointers

- **Roadmap**: `.claude/Framework.md`
- **Session history (canonical decision + ship log)**: `.claude/History.md`
- **Editor feature spec**: `.claude/Features/PageEditor.md`
- **Editor implementation rules**: `.claude/Guidelines/Markdown.md`
- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Properties — full feature spec**: `.claude/Features/Properties.md` (§ "Where Properties Live" is the canonical surface architecture)
- **v0.3.0 Properties (conceptual spec)**: `.claude/Planning/v0.3.0-Properties-spec.md` (26 locked decisions; surface architecture section at top)
- **v0.3.0 Properties (impl plan)**: `.claude/Planning/v0.3.0-Properties-plan.md` (scope split note at top; ~5.5 sessions estimated)
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Session transcripts**: `.claude/Transcripts/`
- **Paradigm-decision rules**: `.claude/Guidelines/Paradigm-Decisions.md`
