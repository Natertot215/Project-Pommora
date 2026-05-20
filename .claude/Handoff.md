### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (end of 2026-05-19 — Session 10 close: **v0.2.7.2 NavDropdown SHIPPED**)

**NavDropdown is implemented and functional — Nathan is satisfied with the feature, not fully happy with the UIX yet.** v0.2.7.2 ships the full Liquid Glass dropdown navigation surface (Recents + Favorites tabs, drag-to-reorder, persistent state.json, back/forward arrows, standalone-window preview gate). Build green, **227 unit tests pass** (198 baseline + 29 new for the data layer), `swift format lint --strict --recursive` exit 0. Editor work from v0.2.7.0 (Session 9) remains intact.

**`main` is at `b13f9a5`** (v0.2.7.2 final NavDropdown UI polish). v0.2.7.0 still tagged on origin at `9a0b383`. **v0.2.7.2 to be tagged + pushed end-of-this-session.**

##### What shipped in v0.2.7.2

The full feature spec lives at [`// Features//NavDropdown.md`](Features/NavDropdown.md). One-line summary per shipped capability:

- **Data layer** — `EntityStateRef` (flat wire-record), `NexusState` (top-level `state.json` shape), `RecentsManager` (LRU @500-store / 100-dropdown cap + cursor for back/forward), `FavoritesManager` (toggle + drag-reorder + atomic persist). 29 unit tests cover the layer; all green.
- **`<nexus>/.nexus/state.json` per-nexus persistence** — first per-nexus state file in Pommora's history. Atomic-write via `AtomicJSON`. Read-modify-write protects cross-manager (Recents + Favorites share the file).
- **`EntityRef` enum + `WindowGroup(id: "entity", for: EntityRef.self)` scene** — standalone-window preview surface for Pages/Vaults/Spaces/Topics/Subtopics. `EntityWindowHost` resolves the ref via AppGlobals managers and renders the matching detail view.
- **`AppGlobals` extension + `MainWindowRouter` @Observable** — cross-scene bridge so standalone-window Expand action can push selection back to the main window (NotificationCenter-free, Swift 6 clean).
- **NavDropdown trigger button** in the toolbar (`square.on.square` icon), `⌘T` keyboard shortcut, popover panel containing the segmented Favorites/Recents picker + entity list.
- **EntityRow component** — icon + title + type chip + hover-heart for favoriting. Heart is heart-filled on Favorites tab, hover-revealed outline-heart on Recents tab.
- **Drag-to-reorder favorites** via SwiftUI `.onMove(perform:)`.
- **Back/Forward arrows in toolbar** (`‹` / `›` + `⌘[` / `⌘]`) — walk through Recents history without breaking LRU order (layered protection via `MainWindowRouter.pendingIntent` enum + `RecentsManager.isNavigatingHistory` flag).
- **Recents recording triggers**: sidebar selection change (`ContentView.onChange(of: sidebarSelection)`), ItemWindow `.onAppear`, Expand from standalone window.
- **Snapshot pattern for dropdown lists** — `recentsSnapshot` / `favoritesSnapshot` @State refreshed on popover open + after favorites mutations. Bypasses an `@Observable`-through-popover-host edge case where source-side mutations weren't reaching the popover view tree.
- **Empty-state copy** for both Favorites and Recents tabs so empty isn't ambiguous.

##### UIX deferrals (Nathan-flagged for follow-up)

Nathan iterated extensively on toolbar chrome + popover visual styling during this session. Multiple approaches were tried (per-button glass, segmented-pill glass, plain/borderless variants, hide+replace system sidebar toggle). Final state is functional but not fully where Nathan wants it. Known items deferred:

1. **Standalone EntityRef window chrome** — reverted to default `WindowGroup` chrome. Nathan iterated on traffic-light removal (`.windowStyle(.plain)`) + custom X close button + Expand button positioning, then asked to revert. The window currently has system traffic lights + title; the toolbar's Expand button was stripped pending a clearer design direction.
2. **System sidebar toggle styling** — on macOS 26, `NavigationSplitView`'s sidebar-collapsed re-open button uses Liquid Glass chrome that can't be restyled directly. The hide+replace path (`.toolbar(removing: .sidebarToggle)` + custom borderless button) was added but Nathan wants a path that adjusts the existing system toggle rather than replacing — no SwiftUI API exists for that. Left as-is.
3. **Toolbar segmented controls (back/fwd, NavDropdown+Inspector)** — multiple iterations between glass-on-background vs per-button glass vs flat. Final state: glass on outer HStack for both pairs, borderless inner buttons. Not Nathan's preferred final look but functional.
4. **NavDropdown popover panel chrome** — outer background fill iterated (Color.clear vs Color.black.opacity(0.25-0.3)). Final state per Nathan's manual edits: minHeight 300 / maxHeight 400, Color.clear background. Empty-state Texts center via `.frame(maxWidth: .infinity, maxHeight: .infinity)`.

These are all stylistic refinements. The functional layer (data + persistence + triggers + drag-reorder + back/forward) is shipped and working.

##### Session 10 commit log (NavDropdown v0.2.7.2 — 22 commits)

| Phase | Commits |
|---|---|
| Phase 0 (docs) | `fa51430` (NavDropdown.md heart+drag+v0.2.7.2), `5c8863b` (hover-stars miss), `98d2263` (PRD + cross-doc sweep) |
| Phase 1 (data layer) | `600b302` (EntityStateRef), `37f3e0e` (NexusPaths helper), `35d3416` (NexusState), `84d0d49` (RecentsManager), `cdfc285` (FavoritesManager) |
| Phase 2 (Entity+Window) | `4f16ddc` (EntityRef enum), `e4f2b1a` (AppGlobals + MainWindowRouter), `1a00124` (ContentView managers), `a52f636` (WindowGroup + EntityWindowHost) |
| Phase 3 (triggers) | `cdda396` (sidebar→Recents), `46ff1e7` (ItemWindow→Recents) |
| Phase 4 (UI) | `2508598` (NavDropdownButton + EntityRow + popover), `4ff9eba` (placement fix d.1.1), `c8e55ac` + `b794a07` revert (d.1.2), `94dfc7d` + `6593bd2` revert (d.1.3), `61f8861` (Item bridge d.2), `3f44d2f` (segmented controls d.3) |
| Phase 6 (Back/Forward) | `109611c` (back/fwd + cursor + Intent enum) |
| Polish | `20c4312` (d.4), `9721a6e` (d.5), `8ffa404` (d.6), `de8e933` (d.7 debug), `dd679fc` (d.8 sidebar), `2e8a3ad` (d.8 Recents snapshot), `b13f9a5` (v0.2.7.2 final polish) |

##### What shipped in v0.2.7.0 (Session 9 — prior)

The full editor feature spec lives at [`// Features//PageEditor.md`](Features/PageEditor.md). One-line summary per shipped capability:

- **Native body editor** — `NativeTextViewWrapper(text: $viewModel.body, configuration: .pommora, fontName: "SF Pro Text", fontSize: 15, documentId: viewModel.page.id)` wired into `PageEditorView`.
- **Editable title TextField** — 28pt bold; Enter commits rename via `ContentManager.renamePage` AND shifts focus to the body via `@FocusState + makeFirstResponder` walk.
- **Body indent** — 24pt textInsets matches title's `.padding(.horizontal, 24)` so body text aligns under the title (scrollbar stays at outer edge).
- **300ms debounced save** — keystroke → `viewModel.body` → `scheduleSave()` → `ContentManager.updatePage` → `PageFile.save` → `AtomicYAMLMarkdown.write` (atomic temp + rename). Page-switch flush, window-close flush, `⌘S`, `NSApplication.willTerminate` all wired.
- **Frontmatter preservation** — editor binds ONLY to body; YAML never visible; re-serialized from the typed struct on save.
- **Character-pair auto-pair** — `**`/`__`/`[[`/`` `` `` insert close marker with caret-between; suppressed inside code blocks and when next char is already the close.
- **Auto-unpair on backspace** — backspace inside `*|*` / `**|**` / `[[|]]` / `` `|` `` deletes BOTH halves (single undo step).
- **Apple-AST supplemental rendering** — BlockQuote / Strikethrough / Table / ThematicBreak walked from Apple's `Document(parsing:)` AST and styled on top of the engine's primary regex tokenizer/styler. BlockQuote gets dimmed-text + bg tint + 20pt indent; Strikethrough gets `NSAttributedString.Key.strikethroughStyle`; Table gets monospace font + hidden `|` pipes + hidden separator row; ThematicBreak (`---`) renders as a real 1pt horizontal line via custom NSTextLayoutFragment drawing (`NSColor.separatorColor` at 80% alpha).
- **Expanded right-click menu** — Format submenu (Bold / Italic / Strikethrough / Inline Code / Link) + Heading submenu (H1–H4; H5/H6 omitted as smaller than body) + Lists submenu + new Block submenu (Blockquote / Code Block / Table / Horizontal Rule).
- **All 197 existing tests pass** — domain wiring (PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, inspector + sidebar lifecycle) untouched.

##### Session 9 commit log (7 commits, `1c6e270` → `9a0b383`, all on `main`)

| SHA | Tag | What |
|---|---|---|
| `1c6e270` | v0.2.7-h.0 | Docs repair reconciling Session-8 engine-swap decision; pruned obsolete plans |
| `3d23f52` | v0.2.7-h.1 | Stripped Pallepadehat fork (6 pbxproj entries + Package.resolved pin + `network.client` entitlement + External/PageEditorMD/ clone) |
| `ad2b879` | v0.2.7-h.2 | Vendored swift-markdown-engine @ `e683a62` as local SPM at `External/MarkdownEngine/` (46 .swift files); Apple swift-markdown 0.8.0 SPM dep added |
| `4fafed0` | v0.2.7-h.3 | PageEditorView body swapped to `NativeTextViewWrapper`; editable title preserved exactly |
| `b7a2535` | v0.2.7-h.4 | Character-pair auto-pair |
| `9756f68` | v0.2.7-h.5 | Initial Session-9 docs ship-out |
| `9b97393` | v0.2.7-h.6 | Docs self-correction (commit count + main SHA) |
| `9e13c95` | v0.2.7-h.7 | UX fixes: title-body padding (4→20pt), body 24pt textInsets, auto-unpair on backspace |
| `54d1ddd` | v0.2.7-h.8 | Apple-AST supplemental styler (BlockQuote/Strikethrough/Table/ThematicBreak) + expanded right-click menu |
| `6719e11` | v0.2.7-h.9 | HR-as-real-line via custom NSTextLayoutFragment draw; table pipes/separator hidden; Enter→body focus shift |
| `9a0b383` | v0.2.7-h.10 | HR draw-detection fixed (enumerateAttribute scan); title focus via @FocusState; H5/H6 removed |

---

#### v0.3.0 spec ready (RC-2026-05-19)

**v0.3.0 Properties has a complete implementation spec** ready for execution after v0.2.7.x patches ship. Full spec at [`// Planning//v0.3.0-Properties-implementation.md`](Planning/v0.3.0-Properties-implementation.md) (14 locked decisions, 4 phases, file:line precision, ~5000 words). Companion uncertainty log at [`// Planning//v0.3.0-Properties-uncertainty-log.md`](Planning/v0.3.0-Properties-uncertainty-log.md) — top 5 blockers, SwiftUI patterns confirmed (`TableColumnForEach`, `TableColumnCustomization`, `KeyPathComparator`, drag-between-Sections), 7 open design questions for user, edge case enumeration, 16 new files + 15 file modifications inventoried.

**v0.3.x sub-sequence locked:**
- v0.3.0 — Properties (this spec)
- v0.3.1 — Items pane (Item Window redesign per WIP sketch)
- v0.3.2 — Page-wikilinks (autocomplete + click + rename cascade; backlinks-as-derived-property)
- v0.3.3 — SQLite + querying (six-table index; FTS5 schema wired; transparent picker/sort backend swap)

**Roadmap reorder spec:** [`// Planning//Roadmap-Reorder-Tier-Model.md`](Planning/Roadmap-Reorder-Tier-Model.md) — RC-2026-05-19 tier model framing (polish → foundation → interaction).

The v0.3.0 verbatim resume prompt lives at the bottom of the implementation spec — fire that into a fresh session after v0.2.7.x patches ship.

#### Next session priorities — remaining v0.2.7.x patches + UIX polish

##### v0.2.7.2 UIX polish (deferred from Session 10)

Nathan iterated extensively on the NavDropdown chrome during shipping and ended in a functional-but-not-final state. Open items for a future polish pass:

- **Standalone EntityRef window** — currently default `WindowGroup` chrome (system traffic lights + title). Nathan tried `.windowStyle(.plain)` with custom X (top-left) + Expand (top-right) and reverted. Re-approach: probably the right answer is `WindowGroup` with `.windowToolbarStyle(.unified)` showing the entity title, plus a single `ToolbarItem(.primaryAction)` X close button (or Expand, depending on which action is primary). Open question: keep the standalone-window Expand-to-main-pane functionality, or simplify to "popup is preview, click on main sidebar to commit"?
- **NavDropdown popover panel** — outer fill (`Color.clear` vs `Color.black.opacity(0.x)` vs glass), modePicker chrome, list trough styling. Nathan kept iterating, settled mid-state. Worth a clean restart with the Figma mockup at `.claude/Features/assets/NavDropdown-mockup.png` (still needs to be saved manually) as reference.
- **Toolbar segmented controls** — back/fwd + NavDropdown+Inspector pairs. Currently `.glassEffect()` on outer HStack, borderless inner buttons. Nathan considered abandoning the segmented pattern entirely in favor of independent per-button glass; deferred.
- **System sidebar toggle non-glass** — on macOS 26, NavigationSplitView's collapsed-sidebar re-open button uses Liquid Glass chrome. Nathan wants it flat. The only path is hide+replace (`.toolbar(removing: .sidebarToggle)` + custom borderless replacement); Nathan rejected that approach but no other SwiftUI API exists to restyle the system one in place.

##### v0.2.7.1 — Page editor touch-ups *(still queued)*

Small, well-scoped polish on the shipped editor. Both items are replicable from what Apple Notes / Apple TextEdit ship natively, so neither is research-grade — just careful TextKit-2 work.

- **Blockquote (`>`) rendering** — currently rendered with dimmed text + bg tint + indent via attribute composition (h.8 supplemental styler), but it doesn't *look* like Apple Notes' blockquote. Apple Notes draws a vertical accent bar on the leading edge of the quoted block + heavier bg shading. Implement via the existing `MarkdownTextLayoutFragment.draw` path (add `drawBlockquote(at:in:)` analogous to `drawCodeBlockBackground`). Mark blockquote ranges with a new `.pommoraBlockquote: true` attribute from the supplemental styler.
- **Divider (HR / `---`) rendering** — the line draws but a few rough edges remain:
   - **HR auto-transform on typing**: when user types `---` on its own line, the line should "lock" as an HR — further `-` keystrokes should be rejected (or routed to a new line). Currently typing extra dashes just extends the source string.
   - **Visual width / inset**: HR currently spans the full text container width including the textInsets. Apple Notes insets the HR to roughly the body text width (not full container). Trim by `textInsets.horizontal` in `drawThematicBreak`.
   - **Color**: currently `NSColor.separatorColor` at 80% alpha. Confirm with Nathan whether to keep or swap (already the macOS-recommended divider color).

##### v0.2.7.3 — Tables custom (Apple-Notes-style grid)

Real per-cell grid rendering with click-to-edit cells. Currently table source is hidden (pipes + separator row invisible) and cells use monospace + tinted bg so columns align — clean but not a true grid. Requires substantial TextKit-2 work: custom `NSTextLayoutFragment` subclass that detects Apple-AST `Table` source ranges and replaces cell drawing with a true grid (cell rects + 1pt borders + per-cell click hit-testing). Substantial — own its own patch.

##### v0.2.7.4 — Sidebar re-ordering + drag

Drag Pages between Vault Collections; reorder Spaces / Topics / Sub-topics within their parents; reorder Vaults at the root. Uses SwiftUI's `.draggable(_:)` + `.dropDestination(for:)` modifiers with custom `Transferable` types for each entity kind. Persists order via a new `_order: [<id>]` field on the parent's JSON sidecar (Vault's `_vault.json`, Collection's `_collection.json`, Tier-1 `Spaces` config, etc.). Filesystem reads remain authoritative; the order field is an overlay.

---

#### Known follow-up debt (not blocking)

- **Phase 3 substantive** — wholesale-rewrite engine's `MarkdownTokenizer.parseTokens(in:)` body to walk Apple AST + emit `[MarkdownToken]` shims; same for `MarkdownStyler.styleAttributes`; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. The h.8 supplemental styler covers BlockQuote/Strikethrough/Table/ThematicBreak rendering as a starter; the full body swap would unify everything onto Apple AST. Lower-priority since v0.2.7.0 ships without it.
- **Phase 4.5 polish** — selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-whitespace + the 11-test auto-pair test suite. Bundle into v0.2.7.1 if scope allows.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.2.10 wikilink work depends on this.
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic.
- **In-app Trash window** — `.trash//` data layer shipped v0.2.5; UI surface v0.4.0.
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language** — outdated since v0.2.7 shipped on the swift-markdown path; sync with PageEditor.md or `git rm`.
- **`working-directory: .` on CI format-check step** — redundant; harmless.

---

#### Document pointers

- **Editor feature spec**: `.claude/Features/PageEditor.md` — what shipped + how it's wired + what's deferred
- **Roadmap**: `.claude/Framework.md`
- **Session history**: `.claude/History.md` — full Session 1-9 narratives
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md` — upstream SHA + per-file modification log
- **Pages data model**: `.claude/Features/Pages.md` — on-disk shape, frontmatter, opening behavior
- **NavDropdown spec**: `.claude/Features/NavDropdown.md` — full implementation spec for v0.2.7.2
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Locked specs**: `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns**: `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts**: `.claude/Transcripts/`

---

#### Verbatim resume prompt for next session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at `b13f9a5`, **`v0.2.7.2` tagged + pushed to origin (NavDropdown SHIPPED)**. 227 unit tests pass; build green; lint exit 0. **NavDropdown is functional but UIX polish was deferred** — see Handoff `Next session priorities → v0.2.7.2 UIX polish` for the open items (standalone EntityRef window chrome, popover panel chrome, toolbar segmented-control finalization, system sidebar toggle). **Possible next priorities**: (a) v0.2.7.1 Page editor touch-ups (blockquote real chrome + HR auto-lock — see Handoff for spec); (b) v0.2.7.2 UIX polish pass on NavDropdown chrome; (c) v0.3.0 Properties (full spec at `.claude/Planning/v0.3.0-Properties-implementation.md` — fire its verbatim resume prompt). Branch policy: all commits on `main` directly (Nathan-locked). Every dispatched agent uses Opus 4.7."

---

#### Open questions

- **NavDropdown version number** — RESOLVED end-of-Session-10 (Phase 0 sweep): NavDropdown.md, PRD, Framework, CLAUDE.md all reconciled to v0.2.7.2.
- **CI `runs-on: macos-26` runner availability** — first push happened end-of-Session-9; verify on GitHub Actions tab whether the macos-26 label resolves. If not, one-line fix to `macos-latest` + explicit Xcode 26 path.
- **When to delete snapshot branches** (`paradigm-scaffolding`, `v0.2.2-coderabbit`, `v0.2.3-ci`) — Nathan's call.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock. Engine theme currently uses SwiftUI semantic colors.
- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if code-block syntax highlighting + LaTeX rendering become priorities.
