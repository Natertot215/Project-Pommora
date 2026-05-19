### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's resume here.

#### Current State (end of 2026-05-18 — second long session, Phase A-G of v0.2.7 + Milkdown pivot decision)

**`main` is at `1989fac`** — Phase A through Phase G.2 of v0.2.7 shipped on top of the Pallepadehat fork. Then Nathan smoke-tested + decided to **swap to Milkdown + Crepe** instead. The Pallepadehat work is preserved in git history but will be stripped by the next session.

| SHA | Tag | What |
|---|---|---|
| `1df93a6` | v0.2.7-a | SPM dep on `Natertot215/PageEditorMD` (branch=main) — the Pallepadehat fork |
| `ca33210` | v0.2.7-b | Domain layer: PageRef + ContentManager.updatePage (collection + vault-root variants, body-only + frontmatter-preserve atomic write) + PageEditorViewModel (300ms debounce + flushOnContextLoss + PageSaver protocol) + 10 new tests + Nathan's icon migration bundled |
| `74d1ea9` | v0.2.7-c1 | Pommora.entitlements + CODE_SIGN_ENTITLEMENTS wiring (4 sandbox keys: app-sandbox / user-selected.read-write / bookmarks.app-scope / network.client — last new for WKWebView) |
| `14e1c8a` | v0.2.7-c2 | AppGlobals (lifecycle VM registry + lifecycle flush) + AppState.pageInspectorOpen + PommoraApp.init bootstrap |
| `62f4b7b` | v0.2.7-c3 | Editor end-to-end: FrontmatterInspector + PageEditorView (wrapping Pallepadehat EditorWebView) + PageEditorHost (page-switch flush via `.task(id:)`) + sidebar wire |
| `599ee2f` | v0.2.7-c4 | Inspector dedupe (removed legacy ContentView inspector) + title banner (read-only) |
| `454d153` | v0.2.7-c5 | Editable title (TextField → ContentManager.renamePage → in-place file rename) + inspector restructured to NavigationSplitView level |
| `dcb1ab0` | v0.2.7-c5.1 | Inspector toggle moved INSIDE `.inspector(...)` content closure (fixes left-side placement bug) |
| `6882ea9` | v0.2.7-c5.2 | Sidebar page-switching regression fix: `@State var viewModel` → `@Bindable` + `.id(vm.page.id)` on PageEditorView (the @State was preserving stale VM reference across page changes) |
| `2226fbe` | v0.2.7-g | Package.resolved bump to fork `4fd91d6` — Phase G #1 (active-line drop + Notes-style fold chevron + markdown auto-pair + tighter heading spacing + Apple typography + transparent bg) |
| `1989fac` | v0.2.7-g.2 | Package.resolved bump to fork `addaa23` + Pommora-side `.background(Color.clear)` defensive layer on TextField + EditorWebView + VStack |

**Fork** at `https://github.com/Natertot215/PageEditorMD` (local clone at `External/PageEditorMD/`, untracked per `.gitignore`):
- `4fd91d6` — Phase G #1: drop active-line, custom fold chevron, markdown-autopair.ts, Apple typography overhaul, transparent bg CSS
- `a146a28` — Swift triple-clear (drawsBackground KVC + underPageBackgroundColor + NSView layer bg)
- `addaa23` — `!important` on transparent bg rules to win over xcodeLight/xcodeDark

**Smoke test verdict (Nathan, after clean build):** Phase G's Apple typography + WKWebView bg work didn't ship the Notion-like polish Pommora needs. Decision to swap editor lib.

**Build state at end-of-session:** `xcodebuild build` SUCCEEDED. `xcodebuild test -only-testing:PommoraTests` → **198/198 pass** (was 186 + 12 new across Phase B). `swift format lint --strict --recursive` → exit 0. Bundled `editor.html` verified to contain Phase G content (6 occurrences of `transparent !important`).

---

#### Decision: Swap editor library → Milkdown + Crepe (locked end-of-session)

After Phase G shipped with comprehensive Apple typography CSS + auto-pair + transparent-bg triple-layer + clean rebuild verification, the visual baseline still didn't satisfy. Decision to swap to **Milkdown + Crepe**.

**Locked choices:**

1. **Vendored, not SPM-dep'd.** Wrapper as **source files inside Pommora's own tree** (probable: `Pommora/Pommora/PageEditor/` for Swift + `Pommora/Pommora/PageEditor/web/` for the JS bundle source). Nathan wants every line visible in Pommora's repo for inspection + iteration.
2. **Crepe with default macOS `frame` theme as baseline.** Custom Pommora styling layers AFTER baseline lands.
3. **Stay with WYSIWYG / Live Preview editing model** — Crepe defaults.
4. **Defer Pommora extensions:** `:::callout` + `@Columns` → v0.2.9 (via `remark-directive`). `[[wikilinks]]` → v0.2.10 (5-component plugin pattern).
5. **Round-trip trade-off accepted:** ProseMirror serializer normalizes list-marker / fence / heading style. Body on save is stylistically-normalized canonical, not byte-perfect.

**Full sub-plan + research areas at `// Planning//v0.2.7-milkdown-swap.md`.** Three research areas for plan mode to cover: **Strip** (Pallepadehat removal), **Milkdown setup** (vendored Vite+Crepe wrapper), **Construct styling** (frame default + transparent bg + Pommora-brand layer).

**What survives the swap:** all Pommora domain code (PageRef, PageFile, PageMeta, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen). All 198 tests. The Pommora.entitlements (still need network.client for WKWebView).

**What gets stripped:** the 6 pbxproj SPM entries for `MarkdownEditor`, Package.resolved entry for PageEditorMD, `import MarkdownEditor` references, `pommoraEditorConfig` constant, Pallepadehat-specific `EditorWebView(...)` call. `External/PageEditorMD/` working clone stays (untracked) as reference.

**Effort estimate (Claude-time):** ~2.5–3 sessions (Strip ~30 min + Milkdown setup ~1 session + Construct styling ~1 session + verify round-trip ~30 min + full re-verify ~30 min).

---

#### Verbatim resume prompt for post-compact session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at `1989fac` with Phase A-G of v0.2.7 shipped on the Pallepadehat fork (`Natertot215/PageEditorMD@addaa23`). Nathan smoke-tested Phase G and decided to swap to **Milkdown + Crepe** for a better default UI. Decisions locked at `.claude/Planning/v0.2.7-milkdown-swap.md`: vendor the wrapper as source files inside Pommora (not SPM dep, not fork); use Crepe's `frame` theme as default macOS-native baseline; custom styling AFTER baseline ships; defer `:::callout`/`@Columns`/`[[wikilinks]]` to v0.2.9-v0.2.10. **Enter plan mode** and produce an implementation plan covering the three research areas in that document: **Strip** (remove Pallepadehat), **Milkdown setup** (vendored wrapper + Vite + Crepe), **Construct styling** (frame default + transparent bg + Pommora-brand layer). The 198 existing tests + Pommora domain layer survive the swap unchanged. The fork at Natertot215/PageEditorMD is preserved in git history but the SPM dep gets removed in the Strip phase."

---

#### Legacy state — pre-v0.2.7 (preserved for context)

**`main` is at v0.2.6 completed**, all committed locally (NOT pushed — Nathan reviews + pushes):

| SHA | Version | Description |
|---|---|---|
| `e3daedb` | v0.2.0 | Paradigm scaffolding + sidebar UX polish (83-commit merge from `paradigm-scaffolding`) |
| `3bcf328` | v0.2.1 | Parallel-session sidebar UX tweaks + page selection wiring |
| `2e140ed` | v0.2.2 | CodeRabbit tightening (ItemWindow refetch + ContentManagerTests filesystem) |
| `56efd68` | v0.2.3 | CI baseline (GitHub Actions xcodebuild build + tests, push/PR triggers) |
| `3b72dae` | v0.2.x-docs | End-of-5-17 doc sweep (Framework audit + semver + reorder + Pages/Tabs as patches) |
| `60e2ef6` | v0.2.4 | swift-format baseline (`.swift-format` config + formatter pass over 97 files + CI lint step + `OneCasePerLine` fix in Recurrence.swift) |
| `9f56fbe` | v0.2.5 | `.trash//` data foundation (`Filesystem.moveToTrash` + 10 manager delete-site swaps + 4 new `FilesystemTrashTests`) |
| `25de7c6` | v0.2.5.1 | Trash cleanup (UUID-discriminated timestamp + tighter `#expect(throws:)` pattern match) |
| `7b17d1d` | v0.2.6 | Spec catch-up (5 stale version strings + `Pages.md` Tiptap demotion + `Sidebar.md` hover-+ acknowledgement) |
| pending | docs-end-5-18 | This Handoff rewrite + Framework "Current Focus" update + CLAUDE.md version table + History.md session entry. Committing at session close. |

Snapshot refs retained for archive: `paradigm-scaffolding` (`0bc4c8d`), `v0.2.2-coderabbit` (`e462681`), `v0.2.3-ci` (`b746481`), `v0.2.4-swift-format` (empty, `=b746481`).

**Build state at end-of-5-18:** `xcodebuild build` → BUILD SUCCEEDED, 0 source warnings. `xcodebuild test -only-testing:PommoraTests` → **186/186 unit tests pass** (was 182 at end-of-5-17; +4 from `FilesystemTrashTests`). `swift format lint --strict --recursive` → exit 0. Sandbox entitlements present.

**App when launched today:** every CRUD flow lands real files; deletes now move to `<nexus>/.trash/` instead of hard-deleting. Sidebar shows four-section layout (Saved / Spaces / Topics / Vaults) with right-click context-menu CRUD; section disclosure chevrons + secondary-styled headers + hover-only `+` buttons (now correctly reflected in `// Features//Sidebar.md`); full-row click selection with grey rounded chrome. Pages disclosed under Vaults/Collections with `doc.text` icon. Page selection IS wired — clicking a Page opens a placeholder `PageDetailView` ("Page editor coming v0.2.7", up from the previous stale "v0.6"). ItemWindow opens for Item editing. Detail pane shows hierarchical Tables for Vaults + Collections; vault-root content surfaces. Homepage + Agenda schema + tier-config + saved-config auto-seed.

**CI status:** workflow runs build + format-check + unit tests on every push to any branch + PRs targeting `main`. **`main` hasn't been pushed yet** — first push triggers the first CI run. Verify on the GitHub Actions tab that the `runs-on: macos-26` runner label resolves. If not yet available, fix is a one-line patch swapping to `macos-latest` + explicit Xcode 26 path.

---

#### What we did 2026-05-18 (continued — editor research second half)

After the v0.2.4 → v0.2.6 patch sequence + doc sweep landed, Nathan reopened the editor library decision and pushed for an honest evaluation of native AppKit / TextKit 2 against the prior Tiptap-leaning framing. Research session, no code committed.

- **Skills invoked:** `superpowers:brainstorming` (decision framing), `swiftui-expert-skill` (TextKit 2 / AttributedString / macOS-views references), `context7` (`/swiftlang/swift-markdown` API + source-range tracking + GFM tables + visitor patterns). Explore agent (background) covered WWDC25 Session 280, Bear 2, Drafts, MarkEdit, the user-shared Reddit thread, plus open-source precedents.

- **Linchpin clarifier:** Nathan confirmed Live Preview (Obsidian/Bear pattern — markers fade by cursor proximity) AND pure WYSIWYG are both acceptable — "as long as Markdown syntax isn't always visible and the page looks like a page rather than a file." Removes the constraint that drove Tiptap-over-CodeMirror earlier in the branch.

- **Deep-dive on `Pallepadehat/MarkdownEditor`** (cloned + read full source). 3,010 LOC total (~1,300 Swift, ~1,700 TypeScript). MIT, v1.0.1 (Feb 11 2026), 26★. WKWebView + CodeMirror 6 + `@codemirror/lang-markdown` + `@lezer/markdown` GFM. Ships Live Preview marker fading (`syntax-hiding.ts`, 185 LOC), slash menu (`command-palette/`, ~500 LOC), KaTeX, Mermaid, inline images, Xcode-themed light/dark, smart calculator, `@codemirror/search`. Pre-built `editor.html` ships as SPM Resource (no JS toolchain needed in consumer build). Doesn't ship: wikilinks, `:::callout`, `@Columns`, visual table rendering, heading fold, bubble menu, Pommora theme — all addable as TypeScript widget files following the existing pattern in `CoreEditor/src/widgets/`.

- **Reference for native path:** [`nodes-app/swift-markdown-engine`](https://github.com/nodes-app/swift-markdown-engine) (Apache 2.0, 455★, v0.4.0 May 2026, pre-1.0). NSTextView + TextKit 2 + SwiftUI bridge. Ships wikilinks with `[[Name|<id>]]` round-trip (matches Pommora's spec), LaTeX, code highlight, task checkboxes, Writing Tools. Doesn't ship tables/multi-column/callouts.

- **Three options now in `// Planning//Page-Editor-Plan.md`** (rewrote it from the prior Tiptap-locked plan into an objective inventory — 169 lines, no recommendations in the doc):
  1. **Native Swift** (swift-markdown + TextKit 2; optionally wrapping `nodes-app/swift-markdown-engine`)
  2. **JS editor library + macOS shell we build** (Tiptap / Milkdown / BlockNote inside a WKWebView shell we author — shell itself is ~1–2 sessions of standard WebKit work)
  3. **Fork `Pallepadehat/MarkdownEditor`** (CodeMirror 6 + WKWebView; the fork is ours after fork; we add Pommora widgets to it)

- **Swap costs** documented in the plan (in Claude sessions): all transitions are 1–2 sessions for the shell/wrapper swap + 1 session per Pommora widget needing porting. `.md` file format is the firewall — user data is portable across all transitions. Reversibility roughly symmetric.

- **Recommendation (chat-only, not in the doc):** Try Option 3 first. Cheapest experiment (v0.2.7 prose ships in 1 session); surfaces the WKWebView-feel question fast; bus factor mitigated by forking. Concrete session-1 deliverable spec captured in the resume prompt below.

- **StudioMD updated** with new "Effort estimates use Claude-time" rule (Nexus source → Studio deploy). Mandates Claude sessions/hours framing — never weeks/months — since Claude is the implementer and calendar time isn't the cost unit.

- **Nexus mirror** of `Page-Editor-Plan.md` to `//The Nexus//Topics//Pommora//Planning//` for mobile viewing.

---

#### What we did 2026-05-18

A long execution session: shipped four code patches + one doc sweep, end-of-day at v0.2.6 — Pommora now has CI + formatter + trash + clean spec docs, ready for the editor-library decision and v0.2.7 Pages.

**Phase 1 — v0.2.4 swift-format baseline (`60e2ef6`).** Created `.swift-format` config at repo root (lineLength 120 / 4-space indent / `respectsExistingLineBreaks: true` / `NeverForceUnwrap: false` per project deliberate `try!` use / `OrderedImports: true`). Ran `swift format format --in-place --recursive` over `Pommora/Pommora` + `Pommora/PommoraTests` + `Pommora/PommoraUITests` — 97 files modified (+593/-422 net, mechanical whitespace + import-ordering only). Also fixed 2 pre-existing `OneCasePerLine` violations in `Recurrence.swift` (the `Kind` and `Day` enums) since the formatter can't auto-fix that rule. Added a `swift format lint --strict --recursive` step to `.github/workflows/ci.yml` after "Show toolchain" — fail-fast before the expensive build/test gates.

**Phase 2 — v0.2.5 `.trash//` data foundation (`9f56fbe`).** Five new APIs in `AtomicIO/`: `NexusPaths.trashDir(in: nexus)` returns `<nexus>/.trash/`; `Filesystem.moveToTrash(_:in:)` preserves the deleted entity's relative path under nexus root, creates intermediate `.trash` dirs, resolves collisions via timestamp suffix; `Filesystem.suffixedWithTimestamp(_:)` private helper for the timestamp format; `FilesystemError.sourceNotInNexus(source:, nexus:)` case (new `LocalizedError` enum since no pre-existing type to extend); file-private `String.removingPrefix(_:)` helper. Swapped 10 manager delete call-sites from `deleteFolder`/`deleteFile` → `moveToTrash`: SpaceManager.delete / TopicManager.deleteTopic + deleteSubtopic / VaultManager.deleteVault + deleteCollection / ContentManager+CRUD.deletePage (×2) + deleteItem (×2) / AgendaManager.deleteItem. All 10 managers already held a `nexus` reference — no threading required. Pre-existing `pendingError` flow preserved unchanged. New `Pommora/PommoraTests/AtomicIO/FilesystemTrashTests.swift` with 4 tests (movesFile / movesFolder / collisionAddsTimestampSuffix / rejectsExternalSource). Extended v0.2.2's `ContentManagerTests.deletes` + `VaultManagerTests.deleteVault`/`deleteCollection` assertions to also check trash-side existence — the cross-patch coordination flagged in the plan.

**Phase 3 — v0.2.5.1 trash cleanup (`25de7c6`).** Addressed three Minor items from the v0.2.5 code quality review: (a) `suffixedWithTimestamp` now appends a 4-char hex discriminator (UUID prefix) after the UTC timestamp — guarantees uniqueness for same-second-collision edge case (`Notes.20260518-093215-A3F2.md` shape) without loop ceremony; (b) `rejectsExternalSource` test tightened to pattern-match the specific `FilesystemError.sourceNotInNexus` case via the closure form `throws: { error in case … }` matching existing test convention; (c) UTC documentation comment folded into the suffix function's docstring.

**Phase 4 — v0.2.6 spec catch-up (`7b17d1d`).** Five Swift literal version strings updated to align with the locked Framework reorder: `ItemWindow.swift` `"Property-panel relation editor coming v0.5"` → `"Property panel coming v0.3.0"`; `PropertyEditorRow.swift` `"Relation editor coming v0.5"` → `"Relation editor coming v0.3.0"`; `ContextDetailPlaceholder.swift` `"Composed view coming v0.9"` → `"Composed view coming v0.7.0"` (+ matching doc comment synced); `SidebarDetailView.swift` `"Saved view coming v0.5"` → `"Saved view coming v0.6.0"`; `SidebarDetailView.swift` `"Page editor coming v0.6"` → `"Page editor coming v0.2.7"`. Doc passes: `// Features//Pages.md` softened from "Tiptap LOCKED" framing to "leading candidate; final pick reopens at v0.2.7 prep" with a structured candidate list (Tiptap / Milkdown / BlockNote / CodeMirror 6) and stack-agnostic architecture restated; `// Features//Sidebar.md` updated the right-click table's Page row entry to reference v0.2.7 and replaced the "discoverability deferred to quick-capture" section with a "hover-icon `+` complement + quick-capture" section acknowledging the hover-only `+` buttons that actually shipped in v0.2.0.

**Phase 5 — End-of-session doc sweep (pending commit).** This Handoff rewrite + Framework "Current Focus" update + CLAUDE.md Active Version table + History.md Session 5 entry. The PommoraPRD.md and Paradigm-Decisions.md required no changes — paradigm-decision #7 (Tiptap demoted) already reflects the current state, and the PRD is intentionally version-agnostic.

**SourceKit observation (re-confirmed quirk #3):** During this session SourceKit emitted false "Cannot find type X" diagnostics for same-module types (`Nexus`, `Space`, `NexusPaths`, `Filesystem`, etc.) and "No such module 'Testing'" after both v0.2.5 and v0.2.5.1 and v0.2.6 landed. xcodebuild + `xcodebuild test` consistently passed. This is the documented IDE-staleness pattern; the squiggles clear after re-indexing. No action needed — quirk #3 in CLAUDE.md already covers this.

---

#### Next session's plan

**1. Push v0.2.4 → v0.2.6 to origin/main (first CI smoke-test)**

`main` is 5 commits ahead of origin. First push triggers the first GitHub Actions run on `runs-on: macos-26`. Surface result; if the runner label doesn't resolve, fall back to `macos-latest` + explicit Xcode 26 path as a one-line patch.

**2. v0.2.7 — Pages editor — Nathan picks editor option, implement immediately**

The editor library decision has been researched and narrowed to three options inventoried at `// Planning//Page-Editor-Plan.md`. Nathan picks one of:

- **Option 1 — Native Swift** (swift-markdown + TextKit 2; optionally wrap `nodes-app/swift-markdown-engine`)
- **Option 2 — JS editor library + macOS shell we build** (Tiptap / Milkdown / BlockNote)
- **Option 3 — Fork `Pallepadehat/MarkdownEditor`** (CodeMirror 6 + WKWebView; recommended for first try per end-of-5-18 chat)

Once picked, implement immediately — no further brainstorming round. The plan doc covers what each option provides, what we'd build, and swap costs (in Claude sessions) if reversal needed later.

**Common to all three options — `ContentManager.updatePage` lands first.** Two variants (`_:in:vault:` for Collection-scoped Pages + `_:inVaultRoot:` for vault-root Pages) mirroring `updateItem(_:in:vault:)` + `(_:inVaultRoot:)` at the existing call sites. Atomicity rollback + `pendingError` CRUD pattern from v0.2.0. Tests: happy-path + validator failure + IO failure surfacing via `pendingError`. This is editor-agnostic.

**If Nathan picks Option 3 (Pallepadehat fork) — concrete session-1 deliverable:**

1. Add `Pallepadehat/MarkdownEditor` to `Package.swift` SPM deps (or via Xcode "Add Package Dependencies" → `https://github.com/Pallepadehat/MarkdownEditor.git`, pin to `from: "1.0.0"`).
2. `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` per above.
3. New `Pommora/Pages/PageEditorView.swift` — SwiftUI view wrapping `EditorWebView(text: $body, configuration: pommoraConfig)` with `hideSyntax: true` (Obsidian-style Live Preview default). Loads `PageFile`; routes `editorDidChangeContent` via VM to `ContentManager.updatePage`.
4. New `Pommora/Pages/PageEditorViewModel.swift` — `@MainActor @Observable`. Owns the loaded `PageFile`, 300ms debounce on body changes, surfaces errors via `pendingError`. Tests use a `BridgeProtocol` stub (no WKWebView in tests).
5. `SidebarDetailView` learns to render `PageEditorView` when sidebar selection is `.page(PageMeta)` — replaces the existing v0.2.6 `PageDetailView` placeholder ("Page editor coming v0.2.7").
6. App Sandbox: enable Outgoing Connections (Client) entitlement (required by WKWebView XPC). Verify on `Pommora.entitlements`.
7. Standalone window via `WindowGroup(for: PageRef.self)` + `⌥⌘O` shortcut + right-click "Open in New Window" menu item.
8. Tests: `PageEditorViewModelTests` for debounce + save flow + error surfacing.
9. Manual gold-path: create Page → click in sidebar → editor opens in detail pane → type prose → switch Pages → switch back → body persisted on disk. Right-click → Open in New Window → edit in standalone → close + reopen main window → body matches.

Scope for v0.2.7 on Option 3: prose editing (paragraphs, headings, lists, blockquotes, code blocks, hr, links, inline marks), Live Preview marker fading. Tables parsed by GFM but rendered as syntax-highlighted source (no visual grid widget yet — that's v0.2.9 work or later). No directives, no wikilinks, no slash menu — those are v0.2.9 + v0.2.10.

**If Nathan picks Option 1 or 2 — concrete session-1 deliverable lives in `Page-Editor-Plan.md` per-option section.** Same `ContentManager.updatePage` commit lands first; editor wrapper structure differs per option. Read the relevant section of the plan, then proceed.

**3. v0.2.8 — Tabs (interchangeable order with v0.2.7)**

Multi-tab navigation toolbar; `+` / `×` / `⌘T` / `⌘W` / `⌃Tab` / `⌃Shift+Tab` chrome; persistence via `.nexus/state.json`. Vault + Collection detail views also tab-able. Standalone-window path from v0.2.7 continues to work in parallel.

**4. v0.2.9 + v0.2.10 — Pages-editor additions**

- v0.2.9: directives (`:::callout` node, `:::columns` / `@Columns` CSS Grid) + heading-fold chevrons + slash menu.
- v0.2.10: wikilinks autocomplete + `Wikilink` inline node + click routing + body-scan rename rewrite. (If v0.4.0 SQLite has shipped by then, swap to indexed lookup.)

**End of v0.2.x:** Pommora is writable + multi-instance + linkable. v0.3.0 = Properties begins.

---

#### Framework reorder still in effect (locked end-of-5-17, unchanged this session)

Cumulative changes — full detail in `// Framework.md` "Roadmap reorders":

| Decision | Old | New |
|---|---|---|
| Pages + Tabs placement | v0.3.0 / v0.4.0 | **v0.2.7 / v0.2.8 (patches; interchangeable order)** |
| Editor library | Tiptap LOCKED | **Leading candidate; final pick at v0.2.7 prep** |
| Properties | v0.5.0 | **v0.3.0** |
| SQLite + Watcher | v0.8.0 | **v0.4.0** |
| Vault views | v0.10.0 | **v0.5.0** |
| EventKit + Agenda UI | scattered | **v0.6.0 — together (Nathan-locked: hand-in-hand)** |
| Accessibility + perf + onboarding + Settings + accent customization | scattered / v0.12.0 | **v0.6.0 (consolidated polish + integration)** |
| `.trash//` data layer | unscoped | **v0.2.5 (safety net) — SHIPPED** |
| `.trash//` UI window | unscoped | **v0.4.0 (with infrastructure layer)** |

Net: 7 minor versions to v1.0.0 (v0.3.0 → v0.8.0 + v1.0.0). v0.2.x is the long "infrastructure + Pages + Tabs" patch family. Three remaining v0.2.x patches: v0.2.7 + v0.2.8 + v0.2.9 + v0.2.10 (interchangeable v0.2.7/v0.2.8 order).

---

#### Page editor — three options inventoried, awaiting Nathan's pick

End-of-5-18 research narrowed the editor decision to three honest options, fully documented at `// Planning//Page-Editor-Plan.md`:

1. **Native Swift** — `swift-markdown` + TextKit 2 + `NSTextView`. Optionally wrap `nodes-app/swift-markdown-engine` (Apache 2.0, 455★, ships wikilinks matching Pommora's spec). Inherits all native AppKit behavior (caret, scroll, Look Up, Services, Dictation, Writing Tools). Tables/multi-column/callouts each need custom `NSTextAttachment` work — no native primitive ships.
2. **JS editor library + macOS shell we build** — Tiptap (WYSIWYG, ~250KB, MIT) or Milkdown (better Markdown round-trip, ~400KB, MIT) inside a WKWebView shell we author. Shell itself is ~1–2 Claude sessions of standard WebKit work; no Swift Package wrapper exists for these libraries.
3. **Fork `Pallepadehat/MarkdownEditor`** — CodeMirror 6 + WKWebView wrapped as a Swift Package. MIT, v1.0.1, ships Live Preview + slash-menu shell + KaTeX + Mermaid + images + Xcode themes + Cmd-F search. We fork to add Pommora widgets (wikilinks, `:::callout`, `@Columns`, tables, bubble menu, brand theme).

Chat-only recommendation at end of session: **Option 3 first.** Cheapest experiment (v0.2.7 prose ships in 1 session), surfaces the WKWebView-feel question fast, reversibility is high (Pallepadehat dep is a clean SPM cut). Concrete session-1 deliverable spec is in "Next session's plan" section above.

`// Features//Pages.md` editor section updated this session to point at `Page-Editor-Plan.md` as the canonical inventory (no library named as leading in the feature spec anymore).

`// Guidelines//Paradigm-Decisions.md` Decision #7 (Tiptap leading direction) is now superseded by the three-option inventory; sync at v0.2.7 implementation start once the pick lands.

`.md` file format is the architectural firewall — user data is portable across all three options. Swap costs (in Claude sessions) documented in the plan: 1–2 sessions for any wrapper swap + 1 session per Pommora widget needing porting. Reversibility roughly symmetric.

---

#### Paradigm-solidifying decisions (registry → `.claude/Guidelines/Paradigm-Decisions.md`)

No new decisions this session — purely execution + spec hygiene. Existing registry (10 entries, last updated end-of-5-17) remains current.

---

#### Project quirks (carry forward)

1. **Test filter uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include.
3. **Prefer the `builder` subagent for xcodebuild calls.** Confirmed twice this session: SourceKit emits false "Cannot find type X" / "No such module" for same-module types after Edit/Write tool runs; xcodebuild is the authoritative truth. If `builder` subagent isn't reachable, pipe `xcodebuild` to a log file and surface only summary lines.
4. **`.claude/*` IS included in commits** (corrected 2026-05-17). Prior rule prevents unilateral doc bundling into Swift commits, NOT explicit doc commits.
5. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale. Re-confirmed multiple times this session.
6. **Swift 6 strict concurrency + ExistentialAny ON.** `any Decoder`/`any Encoder`. Errors: `(any Error)?`.
7. **Every commit must land** — verify `git log -1 --oneline`.
8. **UI test flake** — `PommoraUITestsLaunchTests/testLaunch` occasionally times out. CI runs unit tests only.
9. **Xcode auto-reorders SymbolPicker/Yams pbxproj entries on build** — incidental noop. Revert via `git restore Pommora/Pommora.xcodeproj/project.pbxproj` before commit.
10. **`Pommora.Collection` qualification required** when `Collection` appears in field declarations / type signatures.
11. **Section structure in SidebarView is load-bearing** — changes risk regressing the launch crash.
12. **Sidebar selection chrome belongs at row file level via `.listRowBackground`**.
13. **Push to feature branches by default; `main` only on explicit Nathan go-ahead.** (Nathan overrode this session-locally with "keep it on this branch" — but the default still holds for future sessions absent a similar override.)
14. **`swift format` is invoked as a subcommand** (`swift format format`, `swift format lint`) via Xcode 26's bundled toolchain — the direct `swift-format` binary is not on `$PATH`. CI uses the same form. Locked at v0.2.4.
15. **Parallel-session caveat** — Nathan may have a separate session running small UI tweaks. Pommora/* working tree is not guaranteed clean between subagent dispatches. Never revert unattributed working-tree changes; surface in report rather than bundling or discarding.

---

#### Known follow-up debt (not blocking)

- **`do { try await … } catch { /* … */ }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns got formatted to `} catch\n{ … }` shape in v0.2.4. `respectsExistingLineBreaks: true` can't preserve single-line catch bodies that span the `{` brace. Cosmetic-only; structural fix (extract `runDelete(_:)` helpers) recommended when SidebarView is next touched (likely during v0.2.7 work since the editor wires into detail-pane dispatch). Not config-driven.
- **In-app Trash window** — `.trash//` data layer shipped at v0.2.5; the UI surface lands at v0.4.0 with the SQLite watcher per the Framework reorder. Until then, users browse trash via Finder.
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language** — may still read as locked in places. Sync at v0.2.7 prep alongside the actual editor-library decision.
- **`working-directory: .` on CI format-check step** — redundant (it's already the default for `actions/checkout@v4`). Harmless; prune if a follow-up CI edit happens.

---

#### Document pointers

- **Roadmap:** `.claude/Framework.md`
- **Page editor plan:** `.claude/Planning/Page-Editor-Plan.md` — **may still read as Tiptap-locked; sync at v0.2.7 prep**
- **Pages feature spec:** `.claude/Features/Pages.md` — updated v0.2.6 to leading-candidate framing
- **Sidebar feature spec:** `.claude/Features/Sidebar.md` — updated v0.2.6 with hover-+ acknowledgement
- **Locked specs:** `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry:** `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns:** `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts:** `.claude/Transcripts/`
- **v0.2.x patch plan (largely complete):** `~/.claude/plans/read-all-the-handoff-glistening-moler.md`

---

#### Verbatim resume prompt for next session

> Open of next session. `main` is at v0.2.6 completed (`7b17d1d`), all locally committed but NOT pushed. End-of-5-18 research narrowed the editor library decision to three options, fully documented at `// Planning//Page-Editor-Plan.md`. **First action: confirm whether Nathan wants v0.2.4 → v0.2.6 pushed to origin/main now** (first CI run on `runs-on: macos-26` — surface runner-availability result; fall back to `macos-latest` + Xcode 26 path if needed). **Second: confirm Nathan's pick among the three editor options** (chat-only end-of-5-18 recommendation was Option 3 — fork Pallepadehat/MarkdownEditor — for cheapest v0.2.7 experiment with high reversibility). **Third: implement v0.2.7 immediately** — no further brainstorming. The Handoff "Next session's plan" section above contains the concrete session-1 deliverable spec for Option 3 (the recommended path) and points at `Page-Editor-Plan.md` per-option sections for Options 1 and 2. Common to all options: `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` lands first, mirroring `updateItem`. Use `subagent-driven-development` skill. Project quirk #13 holds: push to feature branches by default; `main` only on explicit Nathan go-ahead.

---

#### Open questions

- **Editor library final pick — Nathan picks one of three options** at v0.2.7 start. Inventory at `// Planning//Page-Editor-Plan.md`. Recommendation: Option 3 (Pallepadehat fork). All three documented with per-option setup + swap costs (in Claude sessions).
- **CI `runs-on: macos-26` runner availability** — first push (whenever Nathan signals) is the smoke test.
- **When to delete snapshot branches** — Nathan's call. Not blocking.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **External-edit detection on Page save** — relies on v0.4.0 file watcher.
