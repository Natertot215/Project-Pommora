### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's resume here.

#### Current State (end of 2026-05-18 — Session 8 close: engine-swap architecture LOCKED, plan ACCEPTED, awaiting execution)

**Editor library decision is closed.** v0.2.7 implementation queued. Next session executes the accepted plan in one go.

**`main` is at `152609c`** (the Session-7 docs commit; no Swift changes on top). Code state is identical to Phase G.2 (`1989fac`): Pallepadehat fork still wired in code, 198/198 tests passing, build green. **Documentation reflects the post-Session-8 architecture decision.** The Pallepadehat work + the Milkdown documentation are both preserved in git history but will be stripped by Phase 1 of the next session's execution.

**Active plan:** [`// Planning//v0.2.7-engine-swap.md`](Planning/v0.2.7-engine-swap.md) — comprehensive single-session implementation covering Strip → Vendor → Reimplement-parser → Wire-view → Auto-pair → Verify. Iteratively refined with Nathan across Session 8 and accepted at session close. No code committed this session; next session executes.

##### Architecture pivot (locked Session 8)

After Phase G's smoke test failed Nathan's visual baseline AND a brief consideration of Milkdown + Crepe, Nathan asked for a 3-way comparison: Milkdown+Crepe vs. Apple's `swift-markdown` vs. `nodes-app/swift-markdown-engine`. The demo of `swift-markdown-engine`'s native TextKit 2 editor (built + launched on Nathan's Mac by manual Terminal commands — auto-mode classifier blocked the builder agent from /tmp paths) sealed it.

**Locked architecture:**

| Layer | Source |
|---|---|
| **Parser** (Heading/Strong/Emphasis/Strikethrough/BlockQuote/Table/ThematicBreak/CodeBlock/InlineCode/Link/Lists/ListItem/Image/LineBreak/SoftBreak/HTMLBlock/BlockDirective) | Apple `swift-markdown` (SPM dep on `swiftlang/swift-markdown`) |
| **Renderer** (font, color, paragraph styling, link rendering, selection, find, native context menu, Writing Tools, spell-check, autocorrect, IME) | Apple `NSAttributedString` + `NSTextView` + `NSTextLayoutManager` |
| **Live-preview substrate** (NSTextView UX polish, custom NSTextLayoutFragment for inline image rendering, paragraph-scoped restyle loop) | `swift-markdown-engine` (selectively vendored at `Pommora/Pommora/PageEditor/Engine/`) |
| **Load-bearing engine contributions** | (1) Dynamic syntax — markers shrink when caret leaves the AST node, expand when entered (Bear/Notion/iA Writer pattern); (2) Markdown-aware typing helpers — list continuation + block auto-wrap (engine ships) + character-pair auto-pair `**`/`__`/`[[`/`` ` `` with auto-exit-on-space (Pommora adds in Phase 4.5) |
| Domain wiring | Survives unchanged from Phase A-G (PageRef, PageFile, ContentManager.updatePage, PageEditorViewModel, PageEditorHost, AppGlobals, AppState.pageInspectorOpen, 198 tests, inspector + sidebar + lifecycle observers) |

**Critical scoping discovery:** the engine's `MarkdownToken` type is load-bearing — 11 non-styling files (every coordinator extension, ContextMenu, SpellingPolicy, Input handlers) reach through it for cache / selection / detection. The plan **preserves the type + API** of `MarkdownToken`/`MarkdownTokenizer`/`MarkdownDetection` and **rewrites their internals** to back onto Apple AST: `MarkdownTokenizer.parseTokens(in:)` walks `Document(parsing: text)` and emits `[MarkdownToken]` shims. Only `MarkdownStyler.styleAttributes` gets a full body swap (replaced by `PommoraMarkdownStyler` walking the same Apple AST).

##### Phase A-G commit table (carried forward — all stay in git history)

| SHA | Tag | What |
|---|---|---|
| `1df93a6` | v0.2.7-a | SPM dep on `Natertot215/PageEditorMD` (branch=main) — the Pallepadehat fork |
| `ca33210` | v0.2.7-b | Domain layer: PageRef + ContentManager.updatePage + PageEditorViewModel (300ms debounce + flushOnContextLoss + PageSaver protocol) + 10 new tests + Nathan's icon migration bundled |
| `74d1ea9` | v0.2.7-c1 | Pommora.entitlements + CODE_SIGN_ENTITLEMENTS wiring (4 sandbox keys including `network.client` — that key gets STRIPPED in engine-swap Phase 1; no longer needed without WKWebView) |
| `14e1c8a` | v0.2.7-c2 | AppGlobals + AppState.pageInspectorOpen + PommoraApp.init bootstrap |
| `62f4b7b` | v0.2.7-c3 | Editor end-to-end: FrontmatterInspector + PageEditorView (wrapping Pallepadehat EditorWebView) + PageEditorHost + sidebar wire |
| `599ee2f` | v0.2.7-c4 | Inspector dedupe + title banner (read-only) |
| `454d153` | v0.2.7-c5 | Editable title (TextField → ContentManager.renamePage) + inspector at NavigationSplitView level |
| `dcb1ab0` | v0.2.7-c5.1 | Inspector toggle moved INSIDE `.inspector(...)` content closure (fixes left-side placement) |
| `6882ea9` | v0.2.7-c5.2 | Sidebar page-switching regression fix (`@State` → `@Bindable` + `.id()`) |
| `2226fbe` | v0.2.7-g | Phase G fork polish #1 (Apple typography overhaul + auto-pair + transparent bg) |
| `1989fac` | v0.2.7-g.2 | Fork bump to `addaa23` + Pommora-side `.background(Color.clear)` defensive layer |
| `152609c` | docs Session 7 | Milkdown decision documentation (now superseded — but commit stays for history) |

**Fork** at `https://github.com/Natertot215/PageEditorMD` (local clone at `External/PageEditorMD/`, currently untracked):
- `4fd91d6` — Phase G #1: drop active-line, custom fold chevron, markdown-autopair.ts, Apple typography, transparent bg CSS
- `a146a28` — Swift triple-clear (drawsBackground KVC + underPageBackgroundColor + NSView layer bg)
- `addaa23` — `!important` on transparent bg rules

**Smoke test verdict (Nathan, after clean build):** Phase G's Apple typography + WKWebView bg work didn't ship the Notion-like polish Pommora needs. Same outcome forecast for Milkdown + Crepe — both are still WKWebView paths.

**Build state at end-of-Session-7 (unchanged through Session 8):** `xcodebuild build` SUCCEEDED. `xcodebuild test -only-testing:PommoraTests` → **198/198 pass**. `swift format lint --strict --recursive` → exit 0.

---

#### Verbatim resume prompt for post-compact session (Nathan compacts, then session executes)

> "Pommora at `/Users/nathantaichman/The Studio/Projects/Project Pommora`. `main` is at `152609c` (Session 7 docs); code state is identical to `1989fac` (Phase A-G of v0.2.7 on Pallepadehat fork, 198/198 tests passing). Session 8 produced and Nathan accepted the **engine-swap plan** at [`.claude/Planning/v0.2.7-engine-swap.md`](.claude/Planning/v0.2.7-engine-swap.md): swap to Apple `swift-markdown` (parser + rendering source-of-truth) + selectively-vendored `swift-markdown-engine` (live-preview chassis). All Phases 0-5 ship in ONE session post-compact; Phase 6 (docs split) defers to a v0.2.7.1 patch. Locked decisions: vendor engine into `Pommora/Pommora/PageEditor/Engine/` (Apache 2.0, ~4500 LOC after planned deletions); SPM-dep Apple swift-markdown; PRESERVE type-API of `MarkdownToken`/`MarkdownTokenizer`/`MarkdownDetection` (11 coordinator-extension files depend on them) — replace bodies with Apple-AST walks; REPLACE `MarkdownStyler` wholesale with Pommora-side `PommoraMarkdownStyler`; extend `MarkdownInputHandler` with character-pair auto-pair (`**`/`__`/`[[`/`` ` ``) + auto-exit-on-space; defer HighlighterSwift + SwiftMath bridges to later patches; defer Pommora-brand theme; defer `:::callout`/`@Columns` (v0.2.9) and `[[wikilink]]` autocomplete + rename cascade (v0.2.10). Editable title TextField at `PageEditorView.swift:54-64` PRESERVED EXACTLY. Branch policy: all commits on `main` directly (Nathan-locked override of quirk #13). Every dispatched agent uses model `claude-opus-4-7` (Opus 4.7). External/PageEditorMD/ gets `git rm -rf` in Phase 1. **Start with Phase 0 (documentation verification) then proceed through Phases 1-5.**"

---

#### Historical session detail

Full Session 5 / 6 / 7 / 8 narratives live in `History.md`. Pre-v0.2.7 commit chain (`e3daedb` v0.2.0 → `7b17d1d` v0.2.6) + snapshot branches (`paradigm-scaffolding`, `v0.2.2-coderabbit`, `v0.2.3-ci`) are documented there. Phase A-G of v0.2.7 (`1df93a6` → `1989fac`) + Session 7 docs (`152609c`) commits are in the table at the top of this file.

**CI status:** workflow runs build + format-check + unit tests on every push to any branch + PRs targeting `main`. **`main` hasn't been pushed yet** — first push triggers the first CI run. Verify on the GitHub Actions tab that the `runs-on: macos-26` runner label resolves. If not yet available, fix is a one-line patch swapping to `macos-latest` + explicit Xcode 26 path.

---

#### Known follow-up debt (not blocking the engine-swap execution)

- **`do { try await … } catch { … }` rewrap in SidebarView.swift + IconPickerSheet.swift** — ~12 single-line patterns got formatted to `} catch\n{ … }` shape in v0.2.4. Cosmetic-only; structural fix (extract `runDelete(_:)` helpers) recommended when SidebarView is next touched.
- **In-app Trash window** — `.trash//` data layer shipped at v0.2.5; UI surface lands at v0.4.0 with SQLite watcher. Until then, browse trash via Finder.
- **`// Planning//Page-Editor-Plan.md` Tiptap-locked language + `Pages.md` leading-candidate framing** — sync at engine-swap Phase 6 (the docs split into `Features/PageEditor.md`).
- **`working-directory: .` on CI format-check step** — redundant. Harmless; prune if a follow-up CI edit happens.

---

#### Document pointers

- **Active plan:** `.claude/Planning/v0.2.7-engine-swap.md` — single-session execution covering Strip → Vendor → Reimplement-parser → Wire-view → Auto-pair → Verify
- **Roadmap:** `.claude/Framework.md`
- **Session history:** `.claude/History.md` — full Session 1-8 narratives
- **Pages feature spec:** `.claude/Features/Pages.md` — Tiptap-era leading-candidate framing; sync at engine-swap Phase 6
- **Sidebar feature spec:** `.claude/Features/Sidebar.md`
- **Locked specs:** `.claude/Planning/Contexts-Vaults-spec.md`
- **Paradigm-decision registry:** `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns:** `.claude/Guidelines/CRUD-Patterns.md`
- **Session transcripts:** `.claude/Transcripts/`

---

#### Open questions (post-engine-swap-decision)

- **CI `runs-on: macos-26` runner availability** — first push (whenever Nathan signals) is the smoke test.
- **When to delete snapshot branches** (`paradigm-scaffolding`, `v0.2.2-coderabbit`, `v0.2.3-ci`) — Nathan's call. Not blocking.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **External-edit detection on Page save** — relies on v0.4.0 file watcher.

---


---

#### Legacy session summaries

Pre-Session-8 narratives consolidated into `History.md` (Sessions 1-8). The earlier Pallepadehat-fork sub-plan + Milkdown-swap sub-plan are removed from the Planning folder (the latter by Nathan as no-longer-needed); the Pallepadehat-era `v0.2.7-editor-polish.md` is marked SUPERSEDED. The active `Page-Editor-Plan.md` 3-option inventory may still read as Tiptap-leaning in places — sync at engine-swap Phase 6 alongside the `Pages.md` → `PageEditor.md` split.
