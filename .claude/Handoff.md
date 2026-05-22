### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (2026-05-22 — **ParadigmV2 plan LOCKED; execution is the active focus**)

**Active focus:** [[ParadigmV2]] — operational-layer domain model refactor. Plan locked at [`Planning/ParadigmV2.md`](Planning/ParadigmV2.md) (~2,360 lines, 11 phases). Execution is the next session's priority; all other in-flight work (v0.2.7.5 blockquote polish + v0.2.8 drag-reorder Phase 1) is **paused behind it** — see "Prior in-flight work" below for status.

##### The refactor in one paragraph

Pre-ParadigmV2: kind-agnostic Vaults containing Pages + Items, with Collections as sub-folders, AgendaItem as a unified Task+Event struct, and Sub-topics for tier-3 Contexts. Post-ParadigmV2: **symmetric Page/Item model** — Page Type → Page Collection → Page (`.md`) on the Pages side; Item Type → Item Collection → Item (`.json`) on the Items side. AgendaItem splits into **AgendaTask** + **AgendaEvent** (EKReminder + EKEvent aligned). Sub-topics renamed to **Projects**. Schema sidecars unify to `_schema.json` everywhere. On-disk wrapper folders introduced: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. **UI label divergence**: Item Collections render as **"Set"** in the app by default (renameable via Settings). **Settings scaffold** (`.nexus/settings.json` + SettingsManager + label wiring + Cmd+, stub scene) lays groundwork for v0.6.0 Settings UI. **"Pommora" prohibited** in on-disk schemas + Swift namespace qualifications; retires `Pommora.Collection` quirk #6.

##### Locked phase sequence

1. Doc rewrites (Studio direct — no Nexus-first workflow)
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
- **UI labels (defaults, renameable via Settings):** "Type" for both sides; "Collection" for Pages-side, **"Set"** for Items-side; "Task", "Event", "Project"; section labels "Pages"/"Items"/"Agenda"
- **Banned in on-disk schemas + Swift qualifications:** "Pommora" prefix. No `pommora_*` JSON keys; no `Pommora.X` qualifications — use side-prefixed names (`AgendaTask` not `Pommora.Task`). Existing `pommora_table_widths` grandfathered for v0.3.0; rename when Tables ship.

##### Next-session entry path — Phase 1 ready to dispatch

The execution playbook lives at `~/.claude/plans/velvet-crunching-frost.md`. It enumerates all 54 tasks across 11 phases with per-task gate checks and the subagent dispatch prompt template. Execution mode is locked: **subagent-driven, sequential** (one fresh Opus 4.7 subagent per task; main session reviews between tasks).

1. Open the playbook. Confirm Phase 1 checkbox state (all unchecked = fresh start).
2. Dispatch Task 1.1 — rewrite `Features/Domain-Model.md` — per the dispatch protocol template in the playbook.
3. Review subagent return + run GATE 1 check after Task 1.14 lands (full doc rewrite ships as one commit).
4. Continue sequential dispatch through Phase 11.

Builder agent handles all `xcodebuild` (quirk #3). Build verify + test pass + lint between every gate. 252/252 unit tests is the baseline.

---

#### Prior shipped work (no longer in working tree)

- **v0.2.7.5 blockquote chrome + v0.2.8 drag-reorder Phase 1 persistence** — both shipped in commit `5a264f0` (combined v0.2.8.0). Working tree is clean of these. The "Prior session record" section below remains as historical context only.

---

#### Prior session record (v0.2.7.5 blockquote + v0.2.8 drag-reorder — full context for the v0.2.8.0 first commit)

##### v0.2.7.5 blockquote chrome (late 2026-05-21 Session 15B)

**Concurrent with Session 15's drag-reorder work** (see next section). Engine-only scope; Session 15B did NOT touch any Pommora-target files. MarkdownEngine + Pommora target both build clean as of last check. **Blockquote ships now to land what works — one visual issue carries over to tomorrow.**

##### What shipped (engine-side)

**Blockquote chrome — visible always-show overlay** (pattern locked at `// Guidelines//Markdown.md` §9.10; same model as v0.2.7.4 bullet glyph + task checkbox; no caret-aware service):

- **Source `>` hidden** via font-0.1 + clear-color on `> ` (marker + space) at line start. Activation gate requires `>` + space/tab; bare `>` doesn't activate (matches list UX where `-` alone doesn't activate until `- `).
- **Renderer-drawn rounded card** in `MarkdownTextLayoutFragment.drawBlockquoteCard` — `CGPath` with selective corner rounding (`.only`/`.first`/`.middle`/`.last` position enum), `NSColor.tertiarySystemFill` at native intensity.
- **Continuous vertical accent bar** (4pt wide, `NSColor.secondaryLabelColor`, pill-shaped ends). Bar Y-extent matches card exactly (both inflated by `cornerRadius = 6pt` on rounded ends). `paragraphSpacing = 0` on consecutive quote paragraphs so per-fragment bar segments butt-joint flat across multi-line quotes.
- **`tailIndent = -8`** on the paragraphStyle for slight right margin.
- **`minimumLineHeight = ceil(bodyFont.ascender - bodyFont.descender + bodyFont.leading)`** prevents 1pt collapse when the line is empty `> ` (only font-0.1 marker chars on it).
- **Enter / Shift+Enter** match list convention: plain Enter on a `> foo` line inserts `\n<prefix>` (continues the quote, preserving leading indent); Shift+Enter inserts plain `\n` (exits the quote). New `blockquoteMarkerRegex` in `MarkdownListHandler.swift` powers detection.

##### Carries to tomorrow (rework)

**Horizontal "highlight not extending into syntax gap"** — Nathan reports the card highlight visually appears to start at the body text position, with empty space between the bar and the highlight (where the hidden `>` marker sits). Code says `cardLeftX = barX` (card starts AT bar's left edge with bar drawing on top), so the math should put the card's body adjacent to the bar's right edge. Suspected causes:

1. Card's 6pt corner radius curves INWARD at top/bottom, creating a visual gap at the rounded corners between the bar's right edge and where the card's body becomes visible (bar pill cap radius = 2pt, card corner radius = 6pt → mismatch).
2. Card fill alpha (system-native `tertiarySystemFill`) may still be subtle enough that the syntax-gap area looks indistinguishable from background.

**Tomorrow's fixes to try**: either (a) reduce card cornerRadius to match bar pill radius (~2pt) for visual alignment at corners, or (b) increase the card alpha further, or (c) verify via temporary high-contrast fill that the card IS extending to `barX` as the code claims and the issue is purely alpha visibility.

##### Files modified this session (engine package only)

- [`External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/Styling/AppleASTSupplementalStyler.swift) — `visitBlockQuote` rewrite: drops `.backgroundColor` emission, adds `>`-collapse via new private `applyMarkerCollapse(in:)` method (mirrors `visitTable`'s pipe-collapse pattern), adds `paragraphSpacing = 0` + `paragraphSpacingBefore = 0` + `tailIndent = -8` + `minimumLineHeight`.
- [`External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/Renderer/MarkdownTextLayoutFragment.swift) — added `import Markdown`; `hasBlockquoteMarker` (3-stage detection); `BlockquotePosition` enum + `blockquotePosition` computed property (peeks neighbors via `lineRange`); `drawBlockquoteCard(at:in:)` + `makeSelectiveRoundedRect(_:radius:roundTop:roundBottom:)` helper; vertical-inflation extension to `renderingSurfaceBounds`; wired draw call into `draw(at:in:)` between `drawCodeBlockBackground` and `drawLatexImages`.
- [`External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift`](../External/MarkdownEngine/Sources/MarkdownEngine/Input/MarkdownListHandler.swift) — added `blockquoteMarkerRegex` static let (`^[ \t]*>[ \t]`); new plain-Enter blockquote-continue branch in `handleInsertion`'s `\n` fall-through (between fenced-code completion and list detection); Shift+Enter intercept always inserts plain `\n` (exits quote).
- [`External/MarkdownEngine/NOTICE.md`](../External/MarkdownEngine/NOTICE.md) — appended v0.2.7.5 entries for both modified engine files.

##### Doc updates this session

- [`.claude/Features/PageEditor.md`](Features/PageEditor.md) — blockquote spec line rewritten (always-show overlay; hidden `>`; renderer-drawn card; continuous bar; corner rounding + right padding); v0.2.7.x QUEUED entry updated.
- [`.claude/Guidelines/Markdown.md`](Guidelines/Markdown.md) — §6.11-6.14 anti-patterns added (planning bloat, AST-vs-regex lockstep, font-collapse swallowing width, detection-regex drift); L11-L16 lessons in §8 table; §9.7 rewritten (bullet glyph SHIPPED, no longer "deferred"); §9.8 NEW (`-[]` task shorthand tradeoff); §9.9 NEW (bracket-skip Enter); §9.10 NEW (blockquote architecture lock: always-show, not dynamic-syntax).
- [`.claude/Planning/Page-Editor-Plan.md`](Planning/Page-Editor-Plan.md) — Blockquote section rewritten as REVISED 2026-05-21 (always-show overlay, 2-file change, no service). Tables section preserved as PAUSED.
- [`.claude/History.md`](History.md) — Session 15B entry added; v0.2.7.5 paradigm decisions (#10 always-show locked, #11 Enter/Shift+Enter convention).

##### Next session priorities (this session's carry-over)

1. **Resolve the horizontal "highlight not extending into syntax gap" visual quirk** (see above).
2. **Resolve Session 15 drag-reorder row-content engagement** (see next section — Path B LazyVStack rebuild is the documented answer).
3. Decide commit packaging: v0.2.7.5 vs v0.2.8 vs bundle.

---

#### Current State (mid 2026-05-21 Session 15 — **v0.2.8 drag-reorder IN PROGRESS, NOT SHIPPED**)

**Working tree is uncommitted. Phase 1 persistence is complete and tested. Drag UI is partial.** Reorder works only when the cursor is on the thin row margins (outside the row label / SelectionChrome highlight) — not on the row content itself. Cause is architectural and documented; the next step (Path B — LazyVStack rebuild) is specced but unstarted.

##### What's in the working tree (uncommitted)

**Phase 1 — persistence foundation (tested 252/252 unit tests passing, lint clean):**
- New `Pommora/Pommora/Ordering/` folder — [`OrderResolver.swift`](../Pommora/Pommora/Ordering/OrderResolver.swift) (pure generic resolver: alphabetic fallback + persisted-order honoring + tombstone filtering + new-arrival append) and [`OrderPersister.swift`](../Pommora/Pommora/Ordering/OrderPersister.swift) (`@MainActor` read-modify-write helper, one method per order kind).
- Optional order fields on four sidecars — all `[String]?`, encode-if-present, decode-if-present (existing on-disk JSON unchanged):
  - [`Vault.swift`](../Pommora/Pommora/Vaults/Vault.swift): `collectionOrder`, `pageOrder`, `itemOrder`
  - [`Collection.swift`](../Pommora/Pommora/Vaults/Collection.swift): `pageOrder`, `itemOrder`
  - [`Topic.swift`](../Pommora/Pommora/Contexts/Topic.swift): `subtopicOrder`
  - [`NexusState.swift`](../Pommora/Pommora/NavDropdown/NexusState.swift): `spaceOrder`, `topicOrder`, `vaultOrder`
- Manager updates — every `.sorted { localizedStandardCompare }` site (28 across SpaceManager / TopicManager / VaultManager / ContentManager + ContentManager+CRUD) replaced with `OrderResolver.resolve(...)`. Behavior identical when persistedOrder is nil (the universal state today).
- Manager `reorderX(fromOffsets:toOffset:)` methods on all four managers + `nexusID` accessor — dormant without `.onMove` UI but ready.

**Drag UI — partial, blocked on row-content gesture pipeline:**
- `.onMove` attached to 6 ForEaches across `SidebarView.swift`, `TopicRow.swift`, `VaultRow.swift`, `CollectionRow.swift`.
- `SelectableRow.body` uses `.simultaneousGesture(TapGesture().onEnded { onSelect() })` — frees row outer margins for drag initiation.
- **Empirical state:** drag fires only when the cursor starts on the row's edge margins (outside SelectionChrome). Click-and-drag on the row's label content does nothing. Reorders that DO fire persist correctly via `OrderPersister` → sidecar.

##### The actual architectural blocker

`SwiftUI's List on macOS reserves the row content area for its own click-to-select gesture handling.` Four gesture patterns tested this session, all variants failed (`.onTapGesture`, `.simultaneousGesture`, `Button` with `.plain` style, `List(selection:)` + `.tag()` — last one caused a launch hang via quirk #9). Diagnostic removing `.listStyle(.sidebar)` did NOT unblock — confirming the issue is `List`'s gesture pipeline in general, not the sidebar style specifically.

##### Path forward (documented, unstarted)

Locked plan at [`.claude/Planning/v0.2.8-Drag-Reorder.md`](Planning/v0.2.8-Drag-Reorder.md) documents three fallback paths:

- **Path A** (`.draggable` + `.dropDestination` per row): tested, dead — List absorbs drops.
- **Path C** (`List.onMove` + native blue line): the current partial-success state. Documented as "edge-only" until row-content gesture is solved.
- **Path B — LazyVStack rebuild** (last resort, **the actual answer for full row-content drag**): replaces `List` with `ScrollView { LazyVStack }` and the detail-pane `Table` with a LazyVStack-based table. Plan-documented Visual Fidelity Contract spells out every color/padding/spacing/chrome value to preserve. 4 shelved files already built and ready to wire — [`Sidebar/Drag/SidebarDragPayload.swift`](../Pommora/Pommora/Sidebar/Drag/SidebarDragPayload.swift), [`SidebarDragPreview.swift`](../Pommora/Pommora/Sidebar/Drag/SidebarDragPreview.swift), [`DragValidator.swift`](../Pommora/Pommora/Sidebar/Drag/DragValidator.swift), [`ReorderableRow.swift`](../Pommora/Pommora/Sidebar/Drag/ReorderableRow.swift). These compile but aren't referenced by live code paths yet.

Nathan accepted Path C (native blue line) as the lightweight fallback during planning. Current state IS Path C, just incomplete on row-content engagement.

##### Open issues (non-blocking)

- **Xcode-launch hang.** Running Pommora via Cmd-R from Xcode hangs the app on launch. Launching the SAME binary from Finder / dock / app launcher works fine. Diagnosis: scheme Diagnostics (Main Thread Checker / Thread Sanitizer / etc.) or debugger-attach race. Code is fine. Workaround: run from dock — the DerivedData Debug binary persists across Xcode quits and is updated by `xcodebuild build` from the builder agent. Investigation deferred.

##### Files modified this session (Session 15 — NOT yet committed)

- `Pommora/Pommora/Ordering/` (NEW folder + OrderResolver + OrderPersister)
- `Pommora/PommoraTests/Ordering/OrderResolverTests.swift` (NEW)
- `Pommora/Pommora/Sidebar/Drag/` (NEW folder — 4 shelved Path B files)
- `Pommora/Pommora/Vaults/Vault.swift`, `Collection.swift` — order fields
- `Pommora/Pommora/Contexts/Topic.swift`, `SpaceManager.swift`, `TopicManager.swift` — order field + resolver swap
- `Pommora/Pommora/NavDropdown/NexusState.swift` — top-level order fields
- `Pommora/Pommora/Vaults/VaultManager.swift`, `Pommora/Pommora/Content/ContentManager.swift`, `ContentManager+CRUD.swift` — resolver swap + reorder methods + nexusID + SwiftUI import
- `Pommora/Pommora/Sidebar/SidebarView.swift`, `TopicRow.swift`, `VaultRow.swift`, `CollectionRow.swift` — `.onMove` attachments + SelectableRow `.simultaneousGesture`
- `.claude/Planning/v0.2.8-Drag-Reorder.md` NEW — locked spec

##### Session 15 next session

Decide: ship Phase 1 persistence as v0.2.8.0 (invisible foundation, drag-deferred) **OR** commit to Path B rebuild now (substantial, gets full row-content drag working). Resume prompt below assumes the decision is open.

---

#### Prior versions

See [`History.md`](History.md) for shipped-version detail:
- **v0.2.7.4** (Session 14) — Nexus folder adoption + editor polish bundle (bullet glyph, task `-[]` shorthand, arrow chains, bracket auto-pair guard, code colors, HR jitter root-cause + two-phase fix)
- **v0.2.7.2** (Session 12 + 13) — HR dynamic-syntax + Lists rewrite (space-creates / Enter-continues / Shift+Enter-exits; portable CommonMark source)
- **v0.2.7.1** (Session 10) — NavDropdown ship
- **v0.2.7.0** (Session 9) — Native TextKit-2 editor via vendored `swift-markdown-engine`

---

#### Known follow-up debt (not blocking)

- **NavDropdown Pinned drag-to-reorder** — will land when Session 15's drag-reorder ships
- **NavDropdown type chip removal** (drop trailing "Page / Vault / Topic" text, rely on leading icon)
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

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. Two parallel sessions on `main`: **Session 15** (drag-reorder Phase 1 persistence complete, drag UI edge-only — Path B LazyVStack rebuild specced at `.claude/Planning/v0.2.8-Drag-Reorder.md`) and **Session 15B** (v0.2.7.5 blockquote chrome shipped with horizontal-positioning visual TBD — fix path documented in `Handoff.md` 'Carries to tomorrow' section). MarkdownEngine + Pommora target build clean. Two carry-over priorities for tomorrow: (1) resolve blockquote horizontal-positioning visual; (2) resolve drag-reorder row-content engagement (Path B). Decide commit packaging at session start: v0.2.7.5 standalone vs v0.2.8 vs bundle. Branch policy: all commits on `main` directly (Nathan-locked). Every dispatched agent uses Opus 4.7. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1)."

---

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
