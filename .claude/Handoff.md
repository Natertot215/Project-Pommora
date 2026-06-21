### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md`.

 - **Two builds — this is the Swift handoff.** Project Pommora ships the same app two ways: **Swift** (this doc) and the **React + Electron** rebuild (`React/.claude/Handoff.md`). Working in React? Read that handoff instead. Both live on one `main`; a parallel React session works in the `pommora-main-preview` worktree — don't bundle its uncommitted work into Swift commits.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary

**6-20/6-21 (Swift) — the codebase-health refactoring program executed through Phase C, all merged to `main` (local, not pushed); 1,291 tests green.**

1. **Phase B — test-support.** Shared fixtures consolidated into `PommoraTests/Support/` (`Fixtures` entity/page/agenda builders — **no separate target**, single test consumer). The Index/Connections suites migrated onto them; the three parallel Context-manager suites collapsed behind a **test-only** `TestableContextManager` protocol + `ContextCRUDChecks` (production managers stay separate — ratified headroom). `PropertyValue` decode-probe stress coverage seeded.
2. **Phase C — reorg + shared primitives.** New `Core/` absorbs the one-file folders (`CRUD`/`Ordering`/`Filesystem`) + `Core/Formatters/` (IndexDateFormat + TimeFormat + DateFormat); `FlowLayout` → `Components/Layout/`; `SavedConfig` → `Configuration/`, `ReservedTypeID` → `Agenda/`. Consolidations: `Core/ULIDAlphabet` single-sources the Crockford alphabet; `AppState`/`NexusIdentity` persist via `AtomicJSON`; `FilterBuilder` split out of `IndexQuery` → `IndexQueryFilter`. All behaviour-neutral + build-verified.
3. **Review + doc audit.** A 5-angle review/simplify pass (clean — one missed migration + comment trims). A full `.claude` doc audit: docs were mostly current; fixed the AreaColor-removal staleness (`Contexts.md`/`Sidebar.md`), a couple of moved-path refs, and completed-plan cleanup.

(Phase A — AreaColor removal, `SchemaVersion` registry, `opt_<ULID>` minting, `context_links`→ULID, FilenameSafety — landed earlier; see `History.md`.)

#### Lessons Learned

- **Folder moves within a module are free.** `git mv` + `PBXFileSystemSynchronizedRootGroup` auto-tracks; Swift references types by module, not path, so relocating a `.swift` file is compile-neutral (verified across the whole Phase C reorg). The only risk is a file dropping *out* of the synchronized root — the build catches that.
- **Collapse via a test-only protocol.** The three manager suites unified behind a protocol + conformances living in the **test target**, leaving production untouched — the seam already existed (identical CRUD surface), so it's extraction, not invented abstraction.
- **Docs-altitude pays off at audit time.** Because the specs describe durable decisions (not file paths), the Phase C moves produced almost zero stale doc references — the only real staleness was a *removed feature* (Area colors) the docs still narrated. Write at altitude and audits stay cheap.
- **Verify-before-acting, again.** The codebase audit's "easy" items had a high false-positive rate (tested code called "dead"; forced workarounds called "inconsistency") — reading the code first avoided breaking working things.

#### Next Session

- **Phase D — the `Row` primitive** (the marquee refactoring win): one `Components/Row` subsumes the 6-way-duplicated sidebar rows + the drag-ghost patch. **Med–high risk** — rewrites load-bearing `SidebarView` (quirks #8/#9: Section homogeneity, `SelectionChrome`, the launch-crash surface). Needs care + a post-build UIX check.
- **The C-deferred visual/paradigm items** (need Nathan's eyes): magic-numbers → `PUI` + `.hoverFill()` (silent pixel risk), `PropertyValue` datetime → `IndexDateFormat` (on-disk decode change), the full `Domain/Features` top-level grouping, the `NexusAdopter`/`PageTypeManager` god-file splits.
- **Phases E–H** (DRY non-divergent families · Codable→synthesized · god-file breakups · concurrency/typed-throws) — per `Planning/06-20-Refactoring-Roadmap.md`.
- **Push `main` → `origin`** (gated — the session's Swift work is committed locally, not pushed).

#### Pending Focuses

- **`main` is local-only** — the refactoring + the React MarkdownPM work are on local `main` but not pushed to `origin` (origin is well behind).
- **Refactoring D–H + the C-deferred items** — per the Roadmap (the live controller).
- **The Views build** (per `06-13-Views-UIX-Fixes.md`) — Gallery, sorting UIX, Layout-pane rework, Edit-Icon popover — a parallel focus; the toolbar/banner chrome is parked.
- **Swift improvements from the React data-layer slice** — `Planning/Reference/Swift-Improvements-from-React-Rebuild.md` distills concrete wins; reserve a dedicated session.
- **Nexus rename — live end-to-end pass** (the parent-grant prompt + folder rename; build-verified 6-19, not behaviour-verified).

#### Fix Log

- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **Table Links** non-clickable (no input handling); proposed single-click navigate + right-click edit.
- **Agenda description-cap** — specs say 1000, validators enforce none. (The stale `AgendaEventManagerError` built-in-property comment was corrected this session.)
- **Pinned-nav title staleness** on rename until re-pinned — may already be fixed by the file-watcher; retest.
- **Relation properties replaced by Contexts** — future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor); `Review-Discipline.md` at the Studio-level `// The Studio //.claude//rules//` · sidebar spec → `Features/Sidebar.md` · Views spec → `Features/Views.md` · per-entity specs → `Features/*.md`
