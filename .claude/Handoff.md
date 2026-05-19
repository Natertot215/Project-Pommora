### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's priorities here.

#### Current State (end of 2026-05-18 — Session 9 close: v0.2.7 SHIPPED with Phase 3 deferred to v0.2.7.1)

**v0.2.7 Page editor ships native TextKit 2.** Pommora now uses the vendored swift-markdown-engine (local Swift Package at [`External/MarkdownEngine/`](../External/MarkdownEngine/)) as its body editor. The Pallepadehat fork is stripped from the codebase. Apple swift-markdown 0.8.0 is pinned as an engine dep — currently unused; ready for Phase 3's AST-walking tokenizer/styler rewrite (deferred to v0.2.7.1).

**`main` is at `9756f68`** (v0.2.7-h.5: docs ship-out). **197/197 unit tests pass** (prior "198" doc references were off-by-one; current XCTest count verified via diverse-suite spot-check). `xcodebuild build` green. `swift format lint --strict --recursive` exit 0. Engine builds standalone via `cd External/MarkdownEngine && swift build`. Not yet pushed — Nathan pushes manually.

##### Session 9 execution path (6 commits on `main`)

| SHA | Tag | What |
|---|---|---|
| `1c6e270` | v0.2.7-h.0 | Docs repair — reconciled Session-8 engine-swap decision across Handoff/History/Framework/CLAUDE; pruned obsolete plans |
| `3d23f52` | v0.2.7-h.1 | Stripped Pallepadehat fork (6 pbxproj entries + Package.resolved pin + `network.client` entitlement + External/PageEditorMD/ clone removed); PageEditorView body swapped to Phase-4 placeholder Text |
| `ad2b879` | v0.2.7-h.2 | Vendored swift-markdown-engine @ `e683a62` as local SPM at `External/MarkdownEngine/` (Apache 2.0, 46 .swift files); added swift-markdown 0.8.0 SPM dep to Pommora target; minimal `@MainActor` patches to engine sources for Swift 6 compatibility (see NOTICE.md) |
| `4fafed0` | v0.2.7-h.3 | Wired PageEditorView body to `NativeTextViewWrapper(text: $viewModel.body, configuration: .default, fontName: "SF Pro Text", fontSize: 15, documentId: viewModel.page.id)`; editable title TextField preserved exactly; added swift-markdown 0.8.0 as engine-side dep (groundwork for deferred Phase 3) |
| `b7a2535` | v0.2.7-h.4 | Character-pair auto-pair `**`/`__`/`[[`/`` `` `` added to engine's `MarkdownInputHandler.handleCharacterPairAutoPair(...)`; wired into NSTextViewDelegate's `shouldChangeTextIn` chain; suppressed inside code blocks and when next char is already the close marker |
| `9756f68` | v0.2.7-h.5 | Final doc ship-out — Handoff/Framework/History/CLAUDE rewritten to reflect v0.2.7 LIVE state + plan deviations enumerated + v0.2.7.1 verbatim resume prompt; test count corrected 198 → 197 |

##### Plan deviations from `// Planning//v0.2.7-engine-swap.md`

The plan was a 6-phase comprehensive rewrite. Session 9 shipped Phases 0, 1, 2, 4, 4.5 cleanly. Phase 3 (Apple-AST tokenizer/styler rewrite) and parts of Phase 4.5 (selection-wrap + auto-exit-on-space + 11-test suite) deferred to v0.2.7.1. Three architectural deviations:

1. **Engine location**: `External/MarkdownEngine/` (local Swift Package) instead of `Pommora/Pommora/PageEditor/Engine/` (raw source vendoring). Rationale: Pommora is Swift 6 strict-concurrency + ExistentialAny; the engine is Swift 5.9. The package boundary isolates the engine's concurrency contract, avoiding cascading `@MainActor` annotations through 46 vendored files. The engine is still fully editable — Pommora owns the vendored copy in External/.

2. **Phase 3 deferred to v0.2.7.1**: the plan's body-swap of `MarkdownTokenizer.parseTokens(in:)` to walk Apple AST + `MarkdownStyler.styleAttributes` replacement with `PommoraMarkdownStyler` (and the associated `PommoraInlineScanner` / `SourceRangeToNSRange` / `MarkersShrinker` Pommora-side files) is deferred. The Apple swift-markdown 0.8.0 SPM dep is wired (in engine's Package.swift) as groundwork. Engine ships v0.2.7 with its existing regex-based tokenizer + styler — table/blockquote/strikethrough/ThematicBreak support arrives with Phase 3 fill-in.

3. **Phase 4.5 trimmed**: basic character-pair auto-pair ships (`**` → `**|**`, etc.). Selection-wrap (typing `*` with selected text → `*text*`) and auto-exit-on-whitespace (typing space at fresh-pair boundary jumps past close marker) defer to v0.2.7.1. The 11-test auto-pair test suite also defers.

##### v0.2.7.1 follow-up patch (next session priorities)

- **Phase 3 substantive**: rewrite engine's `MarkdownTokenizer.parseTokens(in:)` body to walk `Document(parsing: text)` AST + emit `[MarkdownToken]` shims; rewrite `MarkdownStyler.styleAttributes` to walk same AST; delete `MarkdownTokenizer+Emphasis.swift` + 6 `MarkdownStyler+*` extensions. Apple swift-markdown 0.8.0 dep already wired in `External/MarkdownEngine/Package.swift`. Adds Table / BlockQuote / ThematicBreak / Strikethrough support.
- **Phase 4.5 polish**: selection-wrap + auto-exit-on-space for character-pair auto-pair + 11-test suite at `Pommora/Pommora/PommoraTests/PageEditor/MarkdownInputHandlerAutoPairTests.swift`.
- **Phase 6 docs split**: `.claude/Features/Pages.md` → split editor-UX content into new `.claude/Features/PageEditor.md`.
- **PommoraWikiLinkResolver**: engine has a `WikiLinkResolver` service protocol; v0.2.10 wikilink autocomplete + rename cascade will plug Pommora's resolver into the engine's `WikiLinkService` dual-form transform. v0.2.7 uses the engine's default no-op resolver (wikilinks render but don't auto-resolve to Page IDs yet).
- **NativeTextViewWrapper.swift:213 warning**: pre-existing actor-isolation warning in the engine (`updateCodeBlockSelection` called from synchronous nonisolated context). Not blocking; non-error in Swift 5.9 mode. Fix in the same Phase 3 pass.

##### Phase A-G commit table (carried forward — all stay in git history)

| SHA | Tag | What |
|---|---|---|
| `1df93a6` | v0.2.7-a | SPM dep on `Natertot215/PageEditorMD` (branch=main) — the Pallepadehat fork |
| `ca33210` | v0.2.7-b | Domain layer: PageRef + ContentManager.updatePage + PageEditorViewModel (300ms debounce + flushOnContextLoss + PageSaver protocol) + 10 new tests + icon migration |
| `74d1ea9` | v0.2.7-c1 | Pommora.entitlements + CODE_SIGN_ENTITLEMENTS (4 sandbox keys; `network.client` later stripped in h.1) |
| `14e1c8a` | v0.2.7-c2 | AppGlobals + AppState.pageInspectorOpen + PommoraApp.init bootstrap |
| `62f4b7b` | v0.2.7-c3 | Editor end-to-end: FrontmatterInspector + PageEditorView (wrapping Pallepadehat EditorWebView) + PageEditorHost + sidebar wire |
| `599ee2f` | v0.2.7-c4 | Inspector dedupe + title banner (read-only) |
| `454d153` | v0.2.7-c5 | Editable title (TextField → ContentManager.renamePage) + inspector at NavigationSplitView level |
| `dcb1ab0` | v0.2.7-c5.1 | Inspector toggle moved INSIDE `.inspector(...)` content closure |
| `6882ea9` | v0.2.7-c5.2 | Sidebar page-switching regression fix (`@State` → `@Bindable` + `.id()`) |
| `2226fbe` | v0.2.7-g | Phase G fork polish #1 (Apple typography overhaul + auto-pair + transparent bg) |
| `1989fac` | v0.2.7-g.2 | Fork bump to `addaa23` + Pommora-side `.background(Color.clear)` defensive layer |
| `152609c` | docs Session 7 | Milkdown decision documentation (superseded) |
| `1c6e270` → `9756f68` | v0.2.7-h.0 → h.5 | Session-9 engine swap execution (see table above) |

---

#### Verbatim resume prompt for v0.2.7.1 patch session

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at `9756f68` (v0.2.7-h.5: docs ship-out; v0.2.7 fully shipped). v0.2.7 native TextKit-2 editor is live — Pages open + edit + persist via the vendored MarkdownEngine local SPM at `External/MarkdownEngine/`. 197/197 tests pass; build green; swift format lint exit 0. **Next: v0.2.7.1 patch landing the deferred Phase 3 work** — replace `External/MarkdownEngine/Sources/MarkdownEngine/Parser/MarkdownTokenizer.swift`'s regex body with an Apple-AST walk emitting `[MarkdownToken]` shims (Apple swift-markdown 0.8.0 already wired as engine dep in Package.swift). Same surgery on `MarkdownStyler.styleAttributes` + delete `MarkdownTokenizer+Emphasis.swift` and the 6 `MarkdownStyler+*` extensions. Adds Table / BlockQuote / ThematicBreak / Strikethrough. Also: ship Phase-4.5 selection-wrap + auto-exit-on-space polish + the 11-test auto-pair test suite. Plan reference: `// Planning//v0.2.7-engine-swap.md` Phases 3 + 4.5 polish. Branch policy: all commits on `main` directly (Nathan-locked). Every dispatched agent uses Opus 4.7."

---

#### Known follow-up debt (not blocking)

- **Apple-Notes-style table grid** — Session-9 follow-up (h.8/h.9) shipped pipe-hidden + monospace-aligned table cells, but cells still render as plain text columns, not as a real grid with editable borders. Apple-Notes-quality requires a custom `NSTextLayoutFragment` subclass that detects Table source ranges and replaces cell drawing with a true grid (cell rects + 1pt borders + per-cell click-to-edit). Substantial TextKit-2 work; queued for v0.2.7.1+.
- **HR auto-transform on typing `---`** — currently the dashes auto-render as a horizontal line via fragment-side drawing, but typing more `-` chars after `---` just extends the dash run rather than locking the line and rejecting further dashes. Want: when user types `---` on its own line + Enter (or moves caret away), the line becomes "locked" — further `-` input is rejected (or appended to a new line). Hooks into `MarkdownInputHandler.shouldChangeTextIn` chain.
- **Phase 3 work** — Apple-AST tokenizer/styler full rewrite (the supplemental styler from h.8 covers BlockQuote/Strikethrough/Table/ThematicBreak rendering as a starter, but `MarkdownTokenizer.parseTokens(in:)` and `MarkdownStyler.styleAttributes` still use regex internally; full body swap would unify the parser).
- **Phase 4.5 polish** — selection-wrap (typing `*` with selected text → `*text*`) + auto-exit-on-space + the 11-test auto-pair test suite.
- **PommoraWikiLinkResolver** — Pommora-side conforming to engine's `WikiLinkResolver`; v0.2.10 wikilink work depends on this.
- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns; cosmetic.
- **In-app Trash window** — `.trash//` data layer shipped v0.2.5; UI surface v0.4.0.
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language + `Pages.md` leading-candidate framing** — sync at Phase 6 docs split (deferred to v0.2.7.1).
- **`working-directory: .` on CI format-check step** — redundant; harmless.

---

#### Document pointers

- **Active plan**: `.claude/Planning/v0.2.7-engine-swap.md` — Phases 0-2 + 4 + 4.5 shipped; Phase 3 + 6 + Phase-4.5 polish deferred to v0.2.7.1
- **Roadmap**: `.claude/Framework.md`
- **Session history**: `.claude/History.md` — full Session 1-9 narratives
- **Engine vendor docs**: `External/MarkdownEngine/NOTICE.md` — upstream SHA + per-file modification log
- **Pages feature spec**: `.claude/Features/Pages.md` — editor-UX content to split into `Features/PageEditor.md` at Phase 6
- **Sidebar feature spec**: `.claude/Features/Sidebar.md`
- **Locked specs**: `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry**: `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns**: `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts**: `.claude/Transcripts/`

---

#### Open questions

- **CI `runs-on: macos-26` runner availability** — first push (whenever Nathan signals) is the smoke test.
- **When to delete snapshot branches** (`paradigm-scaffolding`, `v0.2.2-coderabbit`, `v0.2.3-ci`) — Nathan's call.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **External-edit detection on Page save** — relies on v0.4.0 file watcher.
- **HighlighterSwift + SwiftMath bridges** — deferred per plan; opt-in later if Pommora wants code-block syntax highlighting + LaTeX rendering.
- **Pommora-brand theme overlay** — engine uses SwiftUI semantic colors via default `MarkdownEditorConfiguration`; Pommora-brand theme deferred per plan.

---

#### Legacy session summaries

Pre-Session-9 narratives consolidated into `History.md` (Sessions 1-9). The Pallepadehat fork (at `https://github.com/Natertot215/PageEditorMD`) is no longer referenced by Pommora — it remains in fork history for archaeological reference.
