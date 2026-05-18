### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + tomorrow's resume here.

#### Current State (end of 2026-05-17 session)

**`main` is at v0.2.3 completed**, all pushed to `origin/main`:

| SHA | Version | Description |
|---|---|---|
| `e3daedb` | v0.2.0 | Merge commit (paradigm-scaffolding + sidebar UX polish; 83 underlying commits preserved for bisect) |
| `3bcf328` | v0.2.1 | Parallel-session sidebar UX tweaks + page selection wiring (16 Swift files; `case page(PageMeta)` + placeholder `PageDetailView`) |
| `2e140ed` | v0.2.2 | CodeRabbit tightening (`ItemWindow` refetch recovery + 2 `ContentManagerTests` filesystem assertions) |
| `56efd68` | v0.2.3 | CI baseline (`.github/workflows/ci.yml`: `xcodebuild build` + `xcodebuild test -only-testing:PommoraTests` on `runs-on: macos-26`, push to any branch + PR to main) |
| pending | v0.2.x-docs | This Handoff + Framework restructure + Page-Editor-Plan softening + Paradigm-Decisions + History 5-17 entry. Committing at session close. |

Snapshot refs retained for archive: `paradigm-scaffolding` (`0bc4c8d`), `v0.2.2-coderabbit` (`e462681`), `v0.2.3-ci` (`b746481`), `v0.2.4-swift-format` (empty, `=b746481`).

**Build state at end-of-5-17:** `xcodebuild build` → BUILD SUCCEEDED, 0 source warnings. `xcodebuild test -only-testing:PommoraTests` → **182/182 unit tests pass.** Sandbox entitlements present.

**App when launched today:** every CRUD flow lands real files. Sidebar shows four-section layout (Saved / Spaces / Topics / Vaults) with right-click context-menu CRUD; section disclosure chevrons + secondary-styled headers + hover-only `+` buttons; full-row click selection with grey rounded chrome. Pages disclosed under Vaults/Collections with `doc.text` icon. **Page selection IS wired** — clicking a Page opens a placeholder `PageDetailView` ("Page editor coming v0.2.7") in the detail pane. ItemWindow opens for Item editing. Detail pane shows hierarchical Tables for Vaults + Collections; vault-root content surfaces. Homepage + Agenda schema + tier-config + saved-config auto-seed.

**CI status:** workflow file just landed. **First push to main triggers the first CI run** — verify on the GitHub Actions tab that the `runs-on: macos-26` runner label resolves. If not yet available, fix is a one-line patch swapping to `macos-latest` + explicit Xcode 26 path.

---

#### What we did 2026-05-17

A long session: Framework audit + semver conversion + Pages/Tabs reorder + three patches landed on main. Four phases:

**Phase 1 — Framework audit + pressure test.** Dispatched 3 Explore agents in parallel to verify Yams 5.x / GRDB 7.5+ / EventKit / WebView / FSEventStream compatibility against macOS 26 / Swift 6. Surfaced Framework-level pressure points: SQLite/Watcher placement at v0.8 was too late; Vault views at v0.10 contradicted v0.9 Contexts editor's embedded-view block; Agenda UI dormant for 5 versions; v0.12 customization overscoped as its own version.

**Phase 2 — Semver conversion.** All version refs migrated to `major.minor.patch`. Minor (`v0.X.0`) = completed feature; patch (`v0.0.X`) = touch-up or addition; major (`vX.0.0`) reserved for `v1.0.0`. Internal phases like `v0.3a/b/c` retired.

**Phase 3 — End-of-session reorder (locked):** Pages + Tabs ship as v0.2.x patches, NOT as v0.3.0 / v0.4.0 minor versions. v0.3.0 becomes Properties (the next substantial feature after Pommora becomes writable). Agenda UI ships hand-in-hand with EventKit at v0.6.0 (not split). Tiptap demoted from "locked" to "leading candidate" — editor library choice reopens at v0.2.7 implementation start. See Framework.md "Roadmap reorders" + Paradigm-Decisions.md.

**Phase 4 — Patches to main.** Committed v0.2.1 (parallel-session Swift) + v0.2.2 (CodeRabbit) + v0.2.3 (CI baseline) + v0.2.x-docs to main. Verified combined state green (182/182 tests).

**Mid-session incident:** While branching for v0.2.x patches I stashed the .claude/* doc accumulation before switching branches. Nathan saw docs revert to days-old state when his working view followed me to feature branches off `main` (which had the old doc state). Recovered cleanly via `git stash pop`. **Lesson logged in CLAUDE.md quirk #4:** `.claude/*` IS included in commits going forward.

---

#### Tomorrow's plan

**1. v0.2.4 — `swift-format` baseline** (first commit of next session)

- Cut `v0.2.4-swift-format` off updated `main` (the existing branch ref at `b746481` is stale; latest main has v0.2.1 + v0.2.2 + v0.2.3 on top).
- Create `.swift-format` config at repo root per `~/.claude/plans/read-all-the-handoff-glistening-moler.md` v0.2.4 section.
- Run: `swift format format --in-place --recursive Pommora/Pommora Pommora/PommoraTests Pommora/PommoraUITests`. Expect a wide noop diff. No semantic changes.
- Add a format-check step to `.github/workflows/ci.yml` after the "Show toolchain" step.
- Verify locally: lint exits 0; `xcodebuild build` + `xcodebuild test` still green.
- Commit message: `v0.2.4: swift-format baseline — config + formatter pass + CI format-check`

**2. v0.2.5 — `.trash//` data foundation** (next after v0.2.4)

- `Filesystem.moveToTrash(url: URL, in: nexus)` + `NexusPaths.trashDir(in:)` + timestamp-suffix collision resolution.
- Swap all 10 manager `delete*` call sites from `Filesystem.deleteFolder/deleteFile` to `Filesystem.moveToTrash`.
- New tests at `PommoraTests/AtomicIO/FilesystemTrashTests.swift` (~4 tests).
- v0.2.5 will also update v0.2.2's `deletes` test assertions (files now at `.trash/...`).
- In-app Trash window is a separate follow-up (v0.4.0 per current Framework).
- Plan section in `~/.claude/plans/read-all-the-handoff-glistening-moler.md` v0.2.5.

**3. Continue toward Pages (v0.2.7) + Tabs (v0.2.8)**

After v0.2.4 + v0.2.5 land, the substrate is ready. Pre-v0.2.7 sub-steps:

- **Editor library decision: reopen.** Candidates: Tiptap (leading), Milkdown, BlockNote, CodeMirror 6. Decide before bundle scaffold lands.
- **v0.2.6 — Spec catch-up** (small commit): fix stale literal version strings in code; doc passes on Pages.md (remove Option 1 / Option 2 framing) + Sidebar.md (right-click table refresh).
- **v0.2.7 = Pages editor.** Start with `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` (mirrors `updateItem` shape). Then bundle scaffold, `WKURLSchemeHandler`, `PageEditorBridge`, `PageEditorViewModel`, `PageEditorView`, theme bridge, bubble menu, detail-pane dispatch, `WindowGroup(for: PageRef.self)`.
- **v0.2.8 = Tabs.** Multi-tab navigation toolbar; `+` / `×` / `⌘T` / `⌘W` chrome; persistence via `.nexus/state.json`. Order with v0.2.7 is interchangeable.
- **v0.2.9 + v0.2.10** = directives + wikilinks (Pages-editor additions).

End of v0.2.x: Pommora is writable + multi-instance + linkable. v0.3.0 = Properties begins.

---

#### Framework reorder locked 2026-05-17

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
| `.trash//` data layer | unscoped | **v0.2.5 (safety net)** |
| `.trash//` UI window | unscoped | **v0.4.0 (with infrastructure layer)** |

Net: 7 minor versions to v1.0.0 (v0.3.0 → v0.8.0 + v1.0.0). v0.2.x is the long "infrastructure + Pages + Tabs" patch family.

---

#### Page editor — editor stack STILL UNDER DECISION

`// Planning//Page-Editor-Plan.md` previously read as "Tiptap LOCKED." Nathan corrected end-of-5-17: **Tiptap is the leading candidate, not solidified.** Open considerations for v0.2.7:

- **Tiptap (ProseMirror, vanilla TS, MIT)** — leading. WYSIWYG, ~250 KB bundle.
- **Milkdown (ProseMirror, remark-based, MIT)** — better Markdown round-trip than Tiptap. ~400 KB.
- **BlockNote (React + multi-column GPL/commercial)** — blocks-first conflicts with prose-flow aesthetic; license issue.
- **CodeMirror 6** — paradigm switch to source-with-decorations / Live Preview. Pages.md spec would need rewrite.

`// Guidelines//Paradigm-Decisions.md` Decision #7 demoted from "locked" to "leading direction, awaiting v0.2.7 confirmation."

**Architecture stays stack-agnostic** regardless: WKWebView + MarkEdit-pattern native shell + 7-message JSON bridge + `WKURLSchemeHandler` for `pommora-editor://` bundle. Swap effort: 1-2 days for sibling ProseMirror editors, 3-5 days for paradigm switch (CodeMirror).

---

#### Paradigm-solidifying decisions (registry → `.claude/Guidelines/Paradigm-Decisions.md`)

1. `PropertyValue.relation` tagged `{"$rel": "<ULID>"}` (2026-05-16)
2. Collections persist minimal `_collection.json` sidecar (2026-05-16)
3. SymbolPicker via SPM dep wrapped behind `IconPickerSheet` (2026-05-16)
4. Stub-and-progressively-replace execution strategy (2026-05-17)
5. Sidebar UX: right-click context menus replace `+ New` buttons (2026-05-17)
6. Sidebar selection chrome via `.listRowBackground` at row file level (2026-05-17)
7. **Pages editor stack — LEADING DIRECTION (NOT LOCKED):** Tiptap in WKWebView + MarkEdit-pattern + vanilla TS (2026-05-17, downgraded end-of-session)
8. Item creation surfacing deferred to v0.3.0 with Properties (2026-05-17)
9. **Pages + Tabs as v0.2.x patches, NOT v0.3.0 / v0.4.0 minor versions** (2026-05-17 end-of-session)
10. **Agenda UI ships hand-in-hand with EventKit at v0.6.0** (2026-05-17 end-of-session)

---

#### Project quirks (carry forward)

1. **Test filter uses FILENAME, not @Suite name.** `-only-testing:PommoraTests/<FilenameWithTests>`.
2. **Both targets use `PBXFileSystemSynchronizedRootGroup`** — new Swift files auto-include.
3. **Prefer the `builder` subagent for xcodebuild calls.**
4. **`.claude/*` IS included in commits** (corrected 2026-05-17). Prior rule prevents unilateral doc bundling into Swift commits, NOT explicit doc commits.
5. **Trust `xcodebuild`, not SourceKit squiggles** — IDE diagnostics frequently stale.
6. **Swift 6 strict concurrency + ExistentialAny ON.** `any Decoder`/`any Encoder`. Errors: `(any Error)?`.
7. **Every commit must land** — verify `git log -1 --oneline`.
8. **UI test flake** — `PommoraUITestsLaunchTests/testLaunch` occasionally times out. CI runs unit tests only.
9. **Xcode auto-reorders SymbolPicker/Yams pbxproj entries on build** — incidental noop. Revert via `git restore Pommora/Pommora.xcodeproj/project.pbxproj` before commit.
10. **`Pommora.Collection` qualification required** when `Collection` appears in field declarations / type signatures.
11. **Section structure in SidebarView is load-bearing** — changes risk regressing the launch crash.
12. **Sidebar selection chrome belongs at row file level via `.listRowBackground`**.
13. **Push to feature branches by default; `main` only on explicit Nathan go-ahead.**

---

#### Document pointers

- **Roadmap:** `.claude/Framework.md`
- **Page editor plan:** `.claude/Planning/Page-Editor-Plan.md` — **Tiptap as leading candidate, NOT locked**
- **Locked specs:** `.claude/Planning/Contexts-Vaults-spec.md`
- **v0.2.x patch plan:** `~/.claude/plans/read-all-the-handoff-glistening-moler.md`
- **Paradigm-decision registry:** `.claude/Guidelines/Paradigm-Decisions.md`
- **CRUD patterns:** `.claude/Guidelines/CRUD-Patterns.md`
- **Sidebar feature spec:** `.claude/Features/Sidebar.md`
- **Session transcripts:** `.claude/Transcripts/`

---

#### Verbatim resume prompt for tomorrow

> Open of session 2026-05-18. `main` is at v0.2.3 completed (`56efd68`). Today's focus: **v0.2.4 swift-format baseline** + **v0.2.5 `.trash//` data foundation**. Sequence: (1) cut `v0.2.4-swift-format` off latest `main` (NOT the stale `b746481` ref); (2) create `.swift-format` config per `~/.claude/plans/read-all-the-handoff-glistening-moler.md` v0.2.4 section; (3) run `swift format format --in-place --recursive Pommora/Pommora Pommora/PommoraTests Pommora/PommoraUITests`; (4) add CI format-check step; (5) verify build + tests green; (6) commit + push to feature branch. Then **v0.2.5 `.trash//`** per the plan's v0.2.5 section: `Filesystem.moveToTrash` + `NexusPaths.trashDir` + 10 manager call-site swaps + tests. Use `subagent-driven-development` skill. Push to feature branches only; `main` merges only on explicit Nathan go-ahead. **After v0.2.4 + v0.2.5:** prepare for v0.2.7 Pages editor — reopen editor-library decision first, then v0.2.6 spec catch-up commit, then `ContentManager.updatePage` lands as v0.2.7 opening commit.

---

#### Open questions

- **Editor library final pick** — Tiptap leading, but reopen at v0.2.7 prep.
- **CI `runs-on: macos-26` runner availability** — first push is the smoke test.
- **When to delete snapshot branches** — Nathan's call. Not blocking.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **External-edit detection on Page save** — relies on v0.4.0 file watcher.
