### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md`.

 - **Two builds — this is the Swift handoff.** Project Pommora ships the same app two ways: **Swift** (this doc) and the **React + Electron** rebuild (`React/.claude/Handoff.md`). Working in React? Read that handoff instead. Both live on one `main`; a parallel React session works in the `pommora-main-preview` worktree — don't bundle its uncommitted work into Swift commits.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary

**6-21 (Swift, continued) — toolbar/Navigation reorg + Phases H/F/D/E of the refactoring program. 10 commits on `refactoring-phase-b` (NOT pushed); 1,294 tests green throughout.**

Opened post-compaction continuing the refactoring roadmap, with a parallel React session live in the `pommora-main-preview` worktree — its `MarkdownPM/Styles.css` plus Nathan's own one-line `NexusState.swift` comment trim sat uncommitted in the tree all session and were left untouched (never bundled into a Swift commit).

The arc, in order:
- **Toolbar + Navigation reorg** (`0d1dcd1`): extracted the window-toolbar surface into `Features/Toolbar/` (2 plumbing files + 4 toolbar buttons), then renamed the residual nav-domain folder `NavDropdown`→`Navigation` end-to-end — folder, `NavDropdownButton`→`NavigationButton` type, `.navigation` enum case, spec `NavDropdown.md`→`Navigation.md` + `[[wikilinks]]` + History/Framework/PRD prose. (Framework's unrelated "page-nav dropdown" wishlist item correctly left alone.)
- **Phase H closed** via a 4-lens simplification review (`94d7356` + `17ca4c6`): confirmed the `DispatchQueue`/`ConnectionScanner`/comparator items are intentional (left them), and executed the genuine wins it surfaced — Agenda title-sort DRY (`NameCollisionCandidate.sortedByTitle()`), a shared `InlineRenameFocus` responder-hop, a dropped single-use `View.if`, and a decorate-sort of `ViewSortComparator` (extract each key once). Roadmap updated (`ee02c38`).
- **Phase F dropped** (rationale recorded in the roadmap): a survey of all 21 hand-rolled `Codable` types invalidated the premise — synthesized `Decodable` *throws* on a missing in-CodingKeys key rather than using the property default, so the pervasive defensive `decodeIfPresent ?? default` can't be synthesized; deletable subset was ≤2 trivial types, nowhere near "−1,000 loc."
- **Phase D complete** (`4c4c1d0` + `cb4e23d`): built the `SidebarRow` content primitive and re-skinned all 7 sidebar rows onto it (4 simple/leaf + 3 disclosure containers), single-sourcing the inline-rename/selection/swap wiring; the row files shed 1139→648 lines. Bootstrap-verified (no `recursivelyDiffRows` regression).
- **Phase E core complete** (`468a0b6`, `ce7793e`, `f7706d8`, `54464f0`): `containerID`/`schemaTypeID` props on `ViewSettingsScope` + a `currentView` hoist onto `ActiveViewStore` (closes #1; the empty-state/error scaffolds were already components, and `schemaOptionValues` #3 didn't exist — both grounding findings); `collisionSafeName` hoisted to `Filesystem` and shared by `CoverAssetStore`/`AttachmentManager` (#4 — they legitimately stay separate importers, full-merge + fresh-token naming scoped out); and the Page-CRUD triplication (#2) routed through one scope-parameterized path — `createPage`/`renamePage(in: parent:)` + a shared `deletePageCore` — all 9 public signatures preserved so the CRUD suite gates neutrality (the file dropped 1209→965 lines).

**Nathan's voice:** he overrode my "bank it / do this fresh" recommendations *repeatedly* — "continue", "do it now", "No, I said stop pausing. Go and do the rest of the work" — and each push landed green; calibrate toward momentum on behaviour-neutral refactors. He flagged the `NexusState.swift` edit as his own ("I removed a bloated comment -- thats all"). I **declined** the roadmap's #4 "fresh-token" asset naming as a paradigm change that would regress filename legibility — pending his override.

**Where it left off:** HEAD `54464f0` on `refactoring-phase-b`; 10 commits this session, **none pushed**. Visual gate **closed** — Nathan eye-verified the right-click Rename/Change-Icon UX across all three detail surfaces ("IT works"), and reaching the container/context surfaces exercised the re-skinned sidebar rows live (render + select, no `recursivelyDiffRows` regression). Working tree: the parallel React `Styles.css` + Nathan's `NexusState.swift` trim, plus this Handoff + the roadmap status update (uncommitted). Immediate next action: Phase G, or push/merge the branch.

#### Lessons Learned

- **Every roadmap line is a hypothesis until grounded against code.** This session grounding repeatedly contradicted the roadmap — F's whole premise was false; E#3 (`schemaOptionValues`) didn't exist; E#1's scaffold/error were already components; E#4's "fresh-token" was paradigm-blocked. Open the file before executing the line.
- **Synthesized `Decodable` does NOT use property defaults for missing keys** — it throws `keyNotFound`; only excluded-from-CodingKeys properties use their default. So defensive `decodeIfPresent(…) ?? default` is un-synthesizable. (The fact that killed Phase F.) **→ candidate CLAUDE.md quirk.**
- **Load-bearing refactors are safest behind a stable public API.** Both the SidebarView re-skin and the Page-CRUD collapse stayed behaviour-neutral by preserving every public signature and leaning on the existing test suite as the gate — zero caller/test churn. Migrating callers + deleting shims is a separate, lower-risk follow-up.
- **Delegation is a valid marathon-tail DRY.** Route duplicated logic through one source and leave thin shims/aliases when full call-site migration is risky; logic single-sources immediately, shim cleanup is fresh follow-up.

#### Next Session

1. **Phase G — god-file splits.** Start with the non-tangled targets: `ViewSurface` (extract rename/delete/cover; simplify the `columns` copy-mutate force-show) and `GroupingPane` (reusable rows → `Components`). The **tangled** `NexusAdopter` + `PageTypeManager` splits are the harder tail (C-deferred for that reason).
2. **Phase E tail (optional polish).** Migrate the Page-CRUD callers (PageRow, ViewSurface, container rows, DetailScope) onto the unified `createPage`/`renamePage(in: parent:)` API + delete the labeled shims. Behaviour-neutral, low-risk.
3. **Push / merge `refactoring-phase-b`** — 10 commits unpushed; Nathan's call (push-to-origin vs merge-to-main).

#### Pending Focuses

- **[carried from 6-21]** `PropertyValue` datetime → `IndexDateFormat` — on-disk decode change (adds fractional seconds); needs ratification before touching.
- **[carried from 6-21]** **#4 fresh-token asset naming** — declined (keeps legible filenames); resurface only if Nathan wants React-style opaque tokens.
- **[carried]** The **Views build** (Gallery, sorting UIX, Layout-pane, Edit-Icon) — parked parallel focus.
- **[carried]** **Swift-improvements-from-React** slice (`Planning/Reference/…`) — dedicated session.
- **[carried]** **Nexus rename** live end-to-end pass — build-verified, not behaviour-verified.

#### Fix Log

- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **Table Links** non-clickable (no input handling); proposed single-click navigate + right-click edit.
- **Agenda description-cap** — specs say 1000, validators enforce none.
- **Pinned-nav title staleness** on rename until re-pinned — may already be fixed by the file-watcher; retest.
- **Relation properties replaced by Contexts** — future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor); `Review-Discipline.md` at the Studio-level `// The Studio //.claude//rules//` · sidebar spec → `Features/Sidebar.md` · Views spec → `Features/Views.md` · per-entity specs → `Features/*.md`
