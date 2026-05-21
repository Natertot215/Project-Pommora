### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (end of 2026-05-20 — **v0.2.7.2 DIVIDER SHIPPED (locally); Blockquote + Tables deferred**)

**Implementation session.** The HR (horizontal divider) portion of the v0.2.7.2 plan SHIPPED with Obsidian-style dynamic syntax. Blockquote (was Phase 1) and Tables (were Phase 3) are deferred per Nathan's call mid-execution — divider took ~4h instead of the planned ~45min once real-world bugs surfaced. Tables in particular flagged as a likely nightmare given the depth of the divider iteration; marked ASAP-but-not-immediate.

**Local-only — not committed, not pushed yet.** `main` still at `3907ae1` (v0.2.7.1 ship). Modified files in working tree pending Nathan's commit decision.

##### What shipped (HR / divider — Obsidian-style dynamic syntax)

Final design **substantially different** from the original locked plan (which used a custom `.pommoraThematicBreak` attribute + always-hidden dashes). Replaced after the original design's first attempt hit four cascading bugs across two execution rounds. The shipped design:

- **Renderer** (`MarkdownTextLayoutFragment.swift`): AST-backed detection via `Markdown.Document(parsing: fragmentString)` at draw time — no custom NSAttributedString attribute. Two-stage check (Stage 0 code-block guard via existing `hasCodeBlockBackground` property → Stage 1 string prefilter → Stage 2 swift-markdown AST parse). Companion `caretIsInFragment` check (paragraph-start identity match against the cursor's `lineRange`) gates the line draw — caret on the line means no line drawn, caret elsewhere means line drawn. Y anchor uses `textLineFragments.first?.typographicBounds.midY` for stable positioning across neighbor-induced layout changes. `renderingSurfaceBounds` extended tightly (±3.5pt around the line) for clipping safety.
- **Styler** (`AppleASTSupplementalStyler.swift`): `visitThematicBreak` emits **NOTHING**. The styler has zero authority over HR visual state. (Major change from original plan — earlier drafts had the styler emit paragraphStyle and hidden font/color; that caused premature visual jumps on the 3rd dash.)
- **Caret-awareness service** (`NativeTextViewCoordinator+HRVisibility.swift`, new file): SOLE owner of HR visual state. Walks document on every selection-change + after every restyle pass; for each HR paragraph (detected via same prefilter + AST), applies `font 0.1 + clear color + paragraphSpacingBefore/After=16` when caret is OUT, restores `body font + body color + base paragraphStyle` when caret is IN. Reentry-guarded via `isSyncingHRVisibility` flag on the coordinator to prevent infinite recursion through the restyle hook.
- **Legacy HR expansion removed** (`MarkdownListHandler.swift` lines 245-267): the prior v0.2.7.0 behavior replaced `---` with a visible-width-wide string of dashes on Enter (~100 chars). Conflicted directly with the visual-overlay approach. Removed.
- **`()` auto-pair preserved** from Nathan's parallel work — added to the character-pair switches in `MarkdownInputHandler.swift` (heads-up: closeMarker is `"))"` which is asymmetric with the single-close-char unpair; might want to revisit).

**Auto-transform DROPPED** from the plan. Original plan called for a 3rd-dash handler that appended `\n` and a 4th-dash swallow. Both removed during planning — Enter is the natural trigger via dynamic syntax + swift-markdown's CommonMark parsing of `---\n`. No special input handler needed.

**Right-click "Insert HR" menu item** — out of scope this session per Nathan's lock.

##### Known caveat (acceptable for ship; out of scope to chase)

- **First HR appears slightly dimmer than subsequent HRs.** Almost certainly sub-pixel anti-aliasing — the first paragraph's `point.y + firstLine.typographicBounds.midY` lands at a fractional Y value that splits the 1pt line across two pixel rows at partial alpha; subsequent HRs land at different fractional values that happen to look crisper. Attempted fix (`.rounded()` snap to integer pixel boundary) was tested and DID NOT resolve the issue — reverted to avoid leaving speculative code that doesn't actually help. Punted; "call the separators solved." If it bothers in practice, next investigation should test `NSScreen.backingScaleFactor`-aware half-pixel snapping or explicit `CGContextSetShouldAntialias(false)` on the line draw.

##### Lessons learned (apply to next dynamic-syntax features)

Documented in detail in [`// Features//PageEditor.md` → "Dynamic-syntax pattern"](Features/PageEditor.md). Headlines:

1. **AST-backed detection > custom attribute as render signal.** Custom NSAttributedString attributes on full-paragraph character ranges leak via AppKit's attribute-inheritance machinery in ways `shouldChangeTypingAttributes` cannot prevent. The original plan's `.pommoraThematicBreak: true` attribute caused the "duplicate HR on every Enter" bug. AST parse at draw time (prefilter for cheap early-exit + swift-markdown parse on the small set that look HR-shaped) has no leak vector.
2. **Two detectors MUST share their logic.** When the renderer and the caret-awareness service each had their own `isHR?` check, drift produced "dashes hidden but no line drawn" / "line drawn over visible text" half-applied states. Pull the detection into a shared utility — or at minimum, mirror the stages exactly and audit any divergence.
3. **Service-as-sole-writer eliminates races.** When the styler and the service can both write the same attributes, a restyle firing while the caret is on the construct undoes the service's work. Make ONE layer the sole writer of the construct's visual attributes; the other layer emits nothing for that construct.
4. **Caret-aware reveal/hide eliminates 3 entire workaround categories.** Cursor-out push, smart-backspace, and caret-policy hide-the-indicator all become unnecessary when the dashes are VISIBLE while the caret is on the line. There's no invisible content for the cursor to fall into.
5. **Don't add over-cautious safety guards that contradict design intent.** I added a setext-underline guard during plan review (`if first == "-" && lineAbove non-blank → not HR`) thinking it was prudent. It directly contradicted CLAUDE.md's explicit `"Pommora removed Setext H2 support"` and rejected the very case Nathan wanted to render. ALWAYS check the design docs before adding "safety" guards.
6. **Legacy source-mutation expansion + visual-overlay rendering can't coexist for the same construct.** Pick one strategy per construct and delete the other. Half-and-half produces conflicting state.
7. **Real-world testing finds bugs heavy planning misses.** The locked plan had been review-iterated 6+ rounds. It still shipped with the cursor-invisible bug, the typingAttribute-leak bug, the legacy-expansion conflict, the renderer/service setext disagreement, and the over-cautious setext guard. Build the plan as carefully as possible — but expect 2-4 hotfix iterations after first ship.
8. **When fixing a problem and trying many things, STRIP and try again — don't just keep adding stuff.** The original HR attempt earlier in the session piled hotfix on hotfix (font-0.1 hide, then renderingSurfaceBounds extension, then attribute removal, then cursor-out push, then atom-delete, then strip-typingAttributes…) — each new fix introduced a new failure surface. The session restarted only after a full revert to v0.2.7.1 baseline + replan from scratch. **Same lesson surfaced again at the end:** the `.rounded()` pixel-snap attempt for first-HR dimness didn't help, so it got reverted rather than left in the tree as "well, it might help". When N speculative fixes don't resolve a bug, the right move is to revert all N and reconsider the design — NOT add fix N+1.

##### What this planning session locked

- **Blockquote target swapped: Notes-minimal-bar → Apple Calendar event-card chrome.** Grey rounded-rect card (6pt corner radius, `Color.primary.opacity(0.06)` fill — resolved as `NSColor.labelColor.withAlphaComponent(0.06)`) + 3pt vertical `NSColor.separatorColor` bar INSIDE the card at ~4pt inset from leading edge. Multi-line blockquotes use per-fragment corner-rounding (`.only` / `.first` / `.middle` / `.last`) to render as ONE visually contiguous card. Mirrors `drawCodeBlockBackground`'s CGPath + bg-fill pattern (not `drawThematicBreak` anymore). `BlockquoteMetadata { sourceRange }` struct attribute payload (upgraded from `Bool`) lets each fragment know its position without re-scanning storage. Aligns the plan with what `Features/Pages.md` already documented as Pommora's blockquote visual. `paragraphStyle.headIndent = 20` (4pt card-edge → 3pt bar → 13pt clear → text). Phase 1 estimate ~25min → ~45min.

- **HR cursor-atom behavior added (Fix 2d).** The `---` source line stays in storage but the caret never plants inside it. `textViewDidChangeSelection` push-out (direction-aware nudge mirrors NSTextAttachment caret-skip), arrow keys skip past, smart-backspace from the line below deletes the whole `---\n` in one keystroke. Both interceptors guarded against `isProgrammaticEdit == true` so Stage 3.C table-cell splices don't trip them. Apple Notes parity. Phase 2 estimate ~30min → ~45min.

- **Tables — NSTextTable rejection documented + structural context menu added.** Round 5 re-tested the Apple-native option: `NSTextTable`/`NSTextBlock` exist since OS X 10.3 but were never promoted to TextKit 2 — Apple's own TextEdit silently downgrades to TextKit 1 when a table is inserted (Krzyzanowski "TextKit 2: The Promised Land," Aug 2025); Apple Notes uses a custom protobuf document model, not the AppKit text system. Adopting `NSTextTable` would forfeit the TextKit-2-native Writing Tools / Look Up / dynamic-color wins from Session 9. Core Graphics overlay drawn in `MarkdownTextLayoutFragment.draw` IS the 2026 Apple-native path. Stage 3.D added: right-click inside a `.pommoraTable` range → "Add Row Above / Below" + "Add Column Left / Right" via `TableStructureRewriter` AST splice + `Markup.format()` (does NOT open the popover — structural edits aren't in-cell edits; matches Apple Numbers/Pages/Notes pattern). Remove row/column deferred to a later patch.

- **Popover cell styling spec corrected against Apple docs.** Gemini-suggested recipe verified via Context7 + the `swiftui-expert-skill` — 2 of 4 points needed correction, 4 pieces were missing. Locked spec for each `cellField`: `.textFieldStyle(.plain) + .focusEffectDisabled() + .multilineTextAlignment(<from GFM columnAlignments>) + .lineLimit(1...10) + .focused + .onKeyPress(.return/.tab) + .padding (inner) + .frame (outer) + .background (header `.04` tint or clear) + .overlay (1pt accent focus border) + .contentShape(Rectangle()) + .onTapGesture (route to focus) + .onHover (NSCursor.iBeam push/pop)`. Notable corrections: `.plain` does NOT strip the focus ring (separate AppKit concern; need `.focusEffectDisabled()` explicitly); `.contentShape(Rectangle())` + wrapper-level `.onTapGesture` are required for click-on-padding-area to focus the cell; `.onKeyPress(.return)` (macOS 14+) is the canonical Return-to-commit pattern for `axis: .vertical` TextFields (NOT `.onSubmit`, which doesn't fire for vertical TextFields — newline-on-Return is by-design).

- **Version bump: v0.2.7.1 → v0.2.7.2 for this plan.** NavDropdown took v0.2.7.1; the originally-planned page editor v0.2.7.1 slot shifts. Sequence now reads cleanly: `v0.2.7.0` engine swap → `v0.2.7.1` NavDropdown → `v0.2.7.2` page editor fixes.

##### Plan-only deliverables (no source changes)

- 3-way plan file sync: canonical at `~//.claude//plans//frolicking-enchanting-perlis.md`, Studio mirror at `.claude//Planning//Page-Editor-Plan.md`, Nexus mirror at `//The Nexus//Pommora//Planning//Page-Editor-Plan.md`. All three byte-identical (modulo the Nexus mirror's supersession header). Obsidian-sync surfaces the plan on Nathan's phone.
- Docs updated for next session: `Handoff.md` (this file), `Framework.md` (v0.2.7.2 entry in roadmap reorders), `History.md` (Session 11 entry), `Features//PageEditor.md` (deferred patches table + v0.3.2 wikilinks correction), `Features//Pages.md` (stale v0.2.7.2 NavDropdown references corrected to v0.2.7.1), `PommoraPRD.md` (stack-language updated), `CLAUDE.md` Active Version section.

---

#### Prior state (end of 2026-05-19 — v0.2.7.1 NavDropdown SHIPPED, simplified and cleaned)

**NavDropdown is implemented, simplified, and functional — Nathan signed off.** v0.2.7.1 ships the Liquid Glass dropdown navigation surface (Pinned + Recents tabs, single-click select / double-click open in main detail pane, right-click Pin/Unpin context menu, back/forward arrows, persistent state.json). Build green, **226 unit tests pass** (227 baseline minus 3 deleted EntityRefTests plus 2 new NexusStateTests for backward-compat decode), `swift format lint --strict --recursive` exit 0.

**Versioning quirk:** `v0.2.7.2` is in git history as the first NavDropdown ship attempt (Session 10 first half, end of 2026-05-19). It landed with a standalone preview-window scene + hover-heart favorites + 22 commits of UIX iteration Nathan was unhappy with. The v0.2.7.1 simplification supersedes it. The v0.2.7.2 tag remains in history for archaeological reference; v0.2.7.1 is the canonical NavDropdown ship. The originally-planned v0.2.7.1 Page-editor-touch-ups slot shifts to a later patch number.

**`main` is at the v0.2.7.1 docs commit** (to be tagged + pushed at session close). GitHub CI removed in the same commit (Nathan: failure emails were noise).

##### What shipped in v0.2.7.1 (the simplification + cleanup)

The full feature spec lives at [`// Features//NavDropdown.md`](Features/NavDropdown.md). Headline changes from v0.2.7.2:

- **Standalone preview window machinery removed entirely.** `EntityRef.swift`, `EntityWindowHost.swift`, `EntityRefTests.swift`, and the `WindowGroup(id: "entity", for: EntityRef.self)` scene all deleted. Double-click in the dropdown now routes to the main detail pane via a direct closure from ContentView. A real cross-feature PreviewWindow primitive is a future job (see `Guidelines/CRUD-Patterns.md → Preview-window prerequisite`).
- **Favorites → Pinned, top-to-bottom rename.** Class `FavoritesManager` → `PinnedManager` (file renamed via `git mv`), JSON key `favorites` → `pinned` with backward-compat decode (reads legacy `favorites` as fallback; writes only `pinned`), tab label "Pinned", AppGlobals + ContentView + NavDropdownButton all updated. Two new `NexusStateTests` cover the legacy-key decode and the encoder-doesn't-emit-favorites contract.
- **Hover-heart replaced with right-click Pin/Unpin context menu.** `EntityRow` loses the `isFavorite` / `favoriteAction` params and the entire hover-heart Button. New `isPinned` / `pinAction` params drive a `.contextMenu { Button("Pin Page" | "Unpin Page") { pinAction() } }`. Hover state still tracked, but repurposed to drive a subtle row-background tint (`Color.primary.opacity(0.06)` in a 6pt rounded rect) instead of revealing chrome.
- **Click model: single = select, double = open.** Single-click updates List's native selection chrome (no action). Double-click triggers `.simultaneousGesture(TapGesture(count: 2)) { handleOpen(ref) }` which closes the popover and sets `sidebarSelection`. The `.simultaneousGesture` form is the macOS workaround for SwiftUI List rows where `.onTapGesture(count: 2)` is intercepted by the underlying NSTableView selection handler.
- **Collections wired into `SidebarSelection.init?(stateRef:)`** — leftover `case .collection: return nil` from the v0.2.7.2 "collections not wired" decision is now a real resolver that iterates `vaultManager.vaults.collections(in:)`. `SidebarDetailView` was already routing `.collection` → `CollectionDetailView`, so this single addition makes collection rows openable from the dropdown end-to-end.
- **Routing bypasses `MainWindowRouter` for the dropdown's open path.** `NavDropdownButton` gains an `onOpen: (SidebarSelection) -> Void` closure. `ContentView` constructs it with `{ sel in sidebarSelection = sel }`. The closure writes through SwiftUI's normal @State binding mechanism, which works reliably across view-host boundaries — same root cause as the empty-Recents bug that the snapshot pattern fixes. `MainWindowRouter` stays in place for the back/forward path (different code path, works fine via `bringToFrontTick` observation in ContentView's main view host).
- **Lazy-load fallback for unloaded collections.** When `SidebarSelection(stateRef:)` returns nil for a page (because the host collection hasn't been visited this session — ContentManager loads per-collection lazily per the design), `handleOpen` kicks off a `Task` that walks `vaultManager.vaults` calling `contentMgr.loadAll(for: vault)` + each collection, retrying SidebarSelection construction at each step. SQLite in v0.4.0 makes this O(1) and removes the walk.

##### What shipped in v0.2.7.1 (the additive scope)

- **Page + Item context menus inside Vault and Collection detail views.** Right-click on a Page or Item row in `VaultDetailView` or `CollectionDetailView` opens a menu with **Rename** (alert + TextField, routes to `ContentManager.renamePage` / `renameItem` based on vault-root vs collection parent), **Pin / Unpin {kind}** (toggles `AppGlobals.pinnedManager`), **Delete** (mirrors sidebar's no-confirmation pattern; routes to the right `deletePage` / `deleteItem` overload). `VaultDetailView` uses a `parent(for:)` helper that scans vault-root content first then iterates collections; `CollectionDetailView`'s parent is always the current collection. Collection rows in VaultDetailView intentionally have no context menu — the sidebar's CollectionRow is the canonical surface for collection rename/delete.
- **GitHub CI removed.** `.github/workflows/ci.yml` deleted. Nathan: the workflow doesn't work and just sends failure emails.
- **`Guidelines/CRUD-Patterns.md → Preview-window prerequisite` rule added.** Project-wide constraint: PreviewWindow primitive ships per kind before any "open in preview" UI for that kind is wired. CRUD lands independently. Locks in the lesson from the deleted EntityWindowHost.

##### Future implementation deferred for the dropdown (Nathan-flagged at ship time)

Documented in `Features/NavDropdown.md → Future implementation`. Four items, in order:

1. **Open-in-preview wiring** when the cross-feature PreviewWindow primitive is built for Pages, Vaults, Collections, Spaces, Topics, Sub-topics, Items, and Agenda items.
2. **Fix drag-to-reorder Pinned** — `.onMove` wiring is in place but drag-initiate inside the popover's List doesn't fire end-to-end. Needs investigation; likely a List + popover view-host interaction quirk.
3. **Remove type chip** — drop the trailing "Page / Vault / Topic" text and rely on the leading icon (kind-specific symbol per the project's planned symbol table).
4. **Segmented Pinned/Recents UI polish** — slight opacity / contrast pass on the picker pill.

##### Session 10 commit log (NavDropdown v0.2.7.1 — 8 commits)

| SHA | What |
|---|---|
| `4def823` | v0.2.7.2.1-a.1 — Strip NavDropdown standalone-window machinery (406 lines deleted) |
| `406e585` | v0.2.7.2.1-a.2 — Rename Favorites → Pinned (class, file, JSON key with backward-compat decode) |
| `d524b09` | v0.2.7.2.1-a.3 — EntityRow hover-accent + right-click Pin/Unpin |
| `9c96405` | v0.2.7.2.1-a.4 — Click model: single = select, double = open |
| `3f768cb` | v0.2.7.2.1-b.1 — Page + Item context menus in Vault/Collection detail views |
| `68d497e` | v0.2.7.2.1-a.5 — Fix double-click open: `.simultaneousGesture` + lazy-load fallback |
| `4ad9156` | v0.2.7.2.1-a.6 — Wire collections + bypass MainWindowRouter via direct closure |
| (next) | v0.2.7.1 ship: docs + GitHub CI removal + CRUD preview-window rule |

(The intra-commit version label `v0.2.7.2.1` was used during execution before the final tag decision; the canonical ship tag is **v0.2.7.1**.)

##### What shipped in v0.2.7.0 (Session 9 — prior)

The full editor feature spec lives at [`// Features//PageEditor.md`](Features/PageEditor.md). Headline: native TextKit-2 editor via vendored `swift-markdown-engine` at `External/MarkdownEngine/`, editable title TextField, 300ms debounced save, character-pair auto-pair, auto-unpair on backspace, Apple-AST supplemental styler for BlockQuote / Strikethrough / Table / ThematicBreak, expanded right-click menu, HR-as-real-line. 197/197 tests passed at that ship.

---

#### Next session priorities

Locked order this session:

##### (a) NEXT — Lists + Blockquotes (apply dynamic-syntax pattern to two more block constructs)

Nathan's call: extend the dynamic-syntax win from HR to two more constructs the editor already partially handles. Both should reuse the same architecture: AST-backed detection at draw time + caret-awareness service as sole writer of construct-specific visual attributes + service ownership across selection-change + post-restyle.

**Lists** (the immediate complaint):
- Currently, `- ` (dash + space) auto-transforms into a bullet item via `MarkdownLists.handleInsertion`. But pressing **Enter** on a line like `-` (no trailing space) does NOT trigger the transformation. Pommora editor surface should: pressing Enter at the end of a bare list-marker line (`-` / `*` / `1.` / etc.) commits the line as a list item the same way space does. Same for heading markers (`#` + Enter → H1 paragraph).
- **Shift+Space inserts a new list item** below the current one at the same nesting level. No current shortcut.
- Both will need: AST-aware detection of "am I in a list/heading paragraph?" + handlers in `MarkdownInputHandler` + wire-in to `shouldChangeTextIn`. Estimated ~1-2 hours each.

**Blockquotes** (the deferred Phase 1 from the original v0.2.7.2 plan):
- Replace the current weak `.backgroundColor` + `headIndent` styling with the **Apple Calendar event-card chrome** target: grey rounded-rect card (6pt corner radius, `Color.primary.opacity(0.06)` fill resolved as `NSColor.labelColor.withAlphaComponent(0.06)`) + 3pt `NSColor.separatorColor` vertical bar INSIDE the card at ~4pt inset from leading edge. Per-fragment corner-rounding (`.only` / `.first` / `.middle` / `.last`) for multi-line continuity. Apply via the new dynamic-syntax architecture: styler emits nothing, service is the sole writer.
- Original plan estimate ~45min; revised estimate ~1.5h given the divider rework needed 4h vs planned 45min. Plan should reuse the new pattern's helper structure from `NativeTextViewCoordinator+HRVisibility.swift` as the blueprint.
- Full original spec still in [`// Planning//Page-Editor-Plan.md → Phase 1`](Planning/Page-Editor-Plan.md). Most of the visual values transfer; the implementation approach needs to swap the original "attribute payload + custom-draw" pattern for the new "service-owned dynamic styling" pattern proven by the divider.

##### (b) DEFERRED but ASAP — Tables

Originally Phase 3 of v0.2.7.2 — ~6h across four stages (CG inline grid + drag-resize + frontmatter widths + double-click popover editor + structural context menu). Full spec still in [`// Planning//Page-Editor-Plan.md → Phase 3`](Planning/Page-Editor-Plan.md).

**Why deferred:** Nathan's read after the divider's 4h slog — "since a simple divider took 4 hours, tables will be a nightmare." Tables touch significantly more surface (inline grid drawing, hit-testing column boundaries, drag handlers, NSPopover hosting SwiftUI Grid, `MarkupRewriter` for cell edits, frontmatter persistence schema, structural context menu, multiple new test suites). Realistic estimate is now likely 10-15h with hotfix iterations, not 6h.

**ASAP framing:** Mark as the highest-priority deferred item. The current Table rendering (monospace font + faint bg tint + hidden pipes/separator row) is functional-but-ugly. Lists+blockquotes ship first, then table priority gets reassessed.

##### (c) Future options after lists + blockquotes ship

No order decided. Pick at session time based on appetite:

- **PreviewWindow primitive** — Build the cross-feature standalone-window surface for Pages / Vaults / Collections / Spaces / Topics / Sub-topics / Items / Agenda items. Once any kind has a wired PreviewWindow, the NavDropdown's open-in-preview affordance can be selectively lit up per kind. See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the contract.
- **v0.3.0 Properties (full data-layer chapter start)** — Full implementation spec at [`// Planning//v0.3.0-Properties-implementation.md`](Planning/v0.3.0-Properties-implementation.md) (14 locked decisions, 4 phases, file:line precision, ~5000 words). Companion uncertainty log at [`// Planning//v0.3.0-Properties-uncertainty-log.md`](Planning/v0.3.0-Properties-uncertainty-log.md). **v0.3.x sub-sequence locked RC-2026-05-19:** .0 Properties / .1 Items pane / .2 Page-wikilinks / .3 SQLite + querying. v0.3.0 verbatim resume prompt at the bottom of the implementation spec.
- **Sidebar + Vault/Collection drag-to-reorder** — Drag Pages between Vault Collections; reorder Spaces / Topics / Sub-topics within their parents; reorder Vaults at the root; reorder Pinned in the NavDropdown (the open follow-up #2 from the prior session). Uses SwiftUI's `.draggable(_:)` + `.dropDestination(for:)` with custom `Transferable` types per entity kind. Persists order via a new `_order: [<id>]` field on the parent's JSON sidecar.

##### (d) Sidebar + Vault/Collection drag-to-reorder (preserved from prior priorities)

Drag Pages between Vault Collections; reorder Spaces / Topics / Sub-topics within their parents; reorder Vaults at the root; reorder Pinned in the NavDropdown (the open follow-up #2 from this session). Uses SwiftUI's `.draggable(_:)` + `.dropDestination(for:)` with custom `Transferable` types per entity kind. Persists order via a new `_order: [<id>]` field on the parent's JSON sidecar (Vault's `_vault.json`, Collection's `_collection.json`, Tier-1 Spaces config). Filesystem reads remain authoritative; the order field is an overlay.

##### (c) v0.3.0 Properties

Full implementation spec at [`// Planning//v0.3.0-Properties-implementation.md`](Planning/v0.3.0-Properties-implementation.md) (14 locked decisions, 4 phases, file:line precision, ~5000 words). Companion uncertainty log at [`// Planning//v0.3.0-Properties-uncertainty-log.md`](Planning/v0.3.0-Properties-uncertainty-log.md). **v0.3.x sub-sequence locked RC-2026-05-19:** .0 Properties / .1 Items pane / .2 Page-wikilinks / .3 SQLite + querying. The v0.3.0 verbatim resume prompt lives at the bottom of the implementation spec — fire that into a fresh session when ready.

##### (d) PreviewWindow primitive

Build the cross-feature standalone-window surface for Pages / Vaults / Collections / Spaces / Topics / Sub-topics / Items / Agenda items. Once any kind has a wired PreviewWindow, the NavDropdown's open-in-preview affordance can be selectively lit up per kind. See `Guidelines/CRUD-Patterns.md → Preview-window prerequisite` for the contract.

---

#### Known follow-up debt (not blocking)

- **NavDropdown Pinned drag-to-reorder** — listed under Future implementation #2 above
- **NavDropdown Pinned tightening** — possible tightening of ojkect scope to only include pages, items, and agenda items (tasks). 
- **NavDropdown type chip removal** — listed under Future implementation #3 above
- **NavDropdown segmented picker polish** — listed under Future implementation #4 above
- **In-app Trash window** — `.trash//` data layer shipped v0.2.5; UI surface v0.4.0
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language** — outdated since v0.2.7 shipped on the swift-markdown path; sync with PageEditor.md or `git rm`
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.3.2 wikilink work depends on this

---

#### Document pointers

- **NavDropdown feature spec**: `.claude/Features/NavDropdown.md` — what shipped at v0.2.7.1 + future implementation
- **Editor feature spec**: `.claude/Features/PageEditor.md` — what shipped at v0.2.7.0 + what's deferred
- **Roadmap**: `.claude/Framework.md`
- **Session history**: `.claude/History.md`
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md`
- **Pages data model**: `.claude/Features/Pages.md`
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Locked specs**: `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns** (incl. new Preview-window prerequisite): `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts**: `.claude/Transcripts/`

---

#### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at the v0.2.7.1 commit, **`v0.2.7.1` tagged + pushed to origin (NavDropdown SHIPPED)**. 226 unit tests pass; build green; lint exit 0. **v0.2.7.2 page editor fixes plan is LOCKED — implementation-ready, ~7.5h across 3 phases / 4 stages.** Full spec at `.claude/Planning/Page-Editor-Plan.md` (mirrored to `~/.claude/plans/frolicking-enchanting-perlis.md` and `~/The Nexus/Pommora/Planning/Page-Editor-Plan.md`). Scope: Phase 1 Blockquote (Apple Calendar event-card chrome — grey rounded card + bar inside, per-fragment corner-rounding for multi-line continuity, ~45min) + Phase 2 HR (auto-transform + cursor-atom + right-click insert + width fix, ~45min) + Phase 3 Tables (Stage 3.A CG inline grid + Stage 3.B drag-resize + frontmatter `pommora_table_widths` + Stage 3.C double-click NSPopover cell editor with Round-6-locked SwiftUI styling recipe + Stage 3.D right-click add row/col structural context menu, ~6h). Phase commit cadence: each stage green standalone before the next; all commits on `main` directly. **Possible next priorities** (pick one): (a) **v0.2.7.2 page editor fixes** (recommended — plan-locked, implementation-ready); (b) Sidebar + Vault/Collection drag-to-reorder (also fixes NavDropdown's Pinned drag-reorder follow-up #2); (c) v0.3.0 Properties (full spec at `.claude/Planning/v0.3.0-Properties-implementation.md`); (d) PreviewWindow primitive build (unblocks NavDropdown follow-up #1). Branch policy: all commits on `main` directly (Nathan-locked). Every dispatched agent uses Opus 4.7. Builder subagent for `xcodebuild` calls (quirk #3). FILENAME-form test filter (quirk #1)."

---

#### Open questions

- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
- **PreviewWindow design** — what's the shared chrome look? Reuses main toolbar shape, or its own minimal one? Decision deferred until the primitive is built.
