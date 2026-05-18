### Pommora — Session Handoff

> **Read this first at session start.** Branch + state + next session's resume here.

#### Current State (end of 2026-05-18 session)

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

**1. Editor library decision (brainstorming, before v0.2.7 scaffolding)**

Tiptap is the leading candidate but NOT locked (Paradigm-Decision #7 demoted to "leading direction"). Reopen at the START of v0.2.7 work. Candidates and trade-offs:

| Library | Stack | Markdown round-trip | License | Bundle | Notes |
|---|---|---|---|---|---|
| **Tiptap** | ProseMirror, vanilla TS | Good (custom serializer) | MIT | ~250 KB | Leading; node-component model maps cleanly to `:::callout` / `@Columns` |
| **Milkdown** | ProseMirror, remark-based | Near-perfect | MIT | ~400 KB | Better round-trip than Tiptap if directive fidelity matters more than bundle size |
| **BlockNote** | React + block-first | OK | GPL/commercial | larger | Blocks-first conflicts with prose-flow aesthetic; license concern |
| **CodeMirror 6** | Source-with-decorations | N/A (source view) | MIT | varies | Paradigm switch — would rewrite Pages.md spec around Live-Preview model |

Use `superpowers:brainstorming` skill to make the call. Architecture stays stack-agnostic regardless: WKWebView + MarkEdit-pattern native shell + 7-message JSON bridge + `WKURLSchemeHandler` for `pommora-editor://` bundle. Swap effort: 1-2 days for sibling ProseMirror editors, 3-5 days for CodeMirror.

**2. v0.2.7 — Pages editor (the big one)**

Pre-work:
- Reopen editor-library decision (above).
- Confirm WKWebView bundle scaffold approach matches the locked architecture.

Implementation order:
- `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` lands first (mirrors `updateItem` shape — atomicity rollback + `pendingError` CRUD pattern from v0.2.0).
- Then bundle scaffold under `.app/Contents/Resources/Editor/` (`index.html` + `bundle.js` + `bundle.css`).
- `WKURLSchemeHandler` for `pommora-editor://` registration.
- `PageEditorBridge` (Swift side of the 7-message JSON bridge).
- `PageEditorViewModel` + `PageEditorView`.
- Theme bridge + bubble menu.
- Detail-pane dispatch routes `.page(PageMeta)` selection to `PageEditorView` (replaces the v0.2.1/v0.2.6 placeholder).
- Standalone window via `WindowGroup(for: PageRef.self)` + `⌥⌘O`.

Scope: WYSIWYG prose with paragraphs, headings (H1–H5), lists, code blocks, GFM tables, blockquotes (filled box + left bar), horizontal rules. Bubble menu on selection. Markdown round-trips edge-to-edge.

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

#### Page editor — editor stack STILL UNDER DECISION

`// Planning//Page-Editor-Plan.md` may still read in places as if Tiptap is locked. `// Features//Pages.md` was updated this session (v0.2.6) to reflect the demoted-to-leading-candidate framing. `Page-Editor-Plan.md` itself is a separate sync pass — fold into v0.2.7 prep, after the editor decision actually lands.

`// Guidelines//Paradigm-Decisions.md` Decision #7 is "leading direction, awaiting v0.2.7 confirmation" — current.

**Architecture stays stack-agnostic** regardless: WKWebView + MarkEdit-pattern native shell + 7-message JSON bridge + `WKURLSchemeHandler` for `pommora-editor://` bundle. Swap effort: 1-2 days for sibling ProseMirror editors, 3-5 days for paradigm switch (CodeMirror).

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

> Open of next session. `main` is at v0.2.6 completed (`7b17d1d`), all locally committed but NOT pushed. **First action: confirm whether Nathan wants v0.2.4 → v0.2.6 pushed to origin/main now** (so CI runs for the first time on `runs-on: macos-26` — surface the runner-availability smoke-test result, fall back to `macos-latest` + Xcode 26 path if needed). Then **reopen the editor library decision** via `superpowers:brainstorming` skill (Tiptap leading; Milkdown / BlockNote / CodeMirror 6 reopen) before any v0.2.7 scaffolding lands. Once editor is picked: **v0.2.7 Pages editor** per `// Planning//Page-Editor-Plan.md` — opening commit is `ContentManager.updatePage(_:in:vault:)` + `(_:inVaultRoot:)` mirroring `updateItem`. Then bundle scaffold → `WKURLSchemeHandler` → `PageEditorBridge` → `PageEditorViewModel` → `PageEditorView` → theme bridge + bubble menu → detail-pane dispatch → `WindowGroup(for: PageRef.self)`. Use `subagent-driven-development` skill. Project quirk #13 holds: push to feature branches by default; `main` only on explicit Nathan go-ahead.

---

#### Open questions

- **Editor library final pick** — Tiptap leading, but reopens at v0.2.7 prep.
- **CI `runs-on: macos-26` runner availability** — first push (whenever Nathan signals) is the smoke test.
- **When to delete snapshot branches** — Nathan's call. Not blocking.
- **Brand accent value** — Xcode default stands in; final accent hue at design lock.
- **External-edit detection on Page save** — relies on v0.4.0 file watcher.
