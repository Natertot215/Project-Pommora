### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-11 — Views cluster DESIGNED: ratified spec + stress-tested 19-task plan; execution is next)

Session opened on `main` post-v0.4.1 (Sets merged, 1058 tests) with the standing direction "Views design pass, start from the findings ledger." The whole session is design + planning — zero Swift commits; the deliverables are docs, currently uncommitted in the working tree.

Key moments, in order: three exploratory agents (codebase / docs / SwiftUI platform) → a five-round interview locking ~20 decisions → Nathan's Figma screenshots flipped view-switching from roadmap "tabs" to a **toolbar Views dropdown**. Nathan rejected the first plan-mode exit and demanded deeper research; three find-docs/Context7 deep-research agents + two Sonnet codebase audits followed. The decisive SDK ground-truth find: **deployment target is macOS 26.4** (not 15), so the macOS 26 drag-session APIs (`onDropSessionUpdated` continuous location, `dragContainer` multi-drag) are un-gated — the drag stack flipped to native-first with the pure-gesture `visfitness` mechanics as a logged fallback. Custom table confirmed unavoidable (native `Table`: no row reorder, no width readback, Tahoe leak bugs; the Introspect rescue verifiably breaks SwiftUI's renderer; the two-axis-scroll + `pinnedViews` combo is an unfixed platform bug → axis-split nested ScrollViews + `safeAreaInset` column header). **Nuke** adopted for cover thumbnails. The spec was ratified in place (`Planning/06-11-Views-Spec.md`), then `/writing-plans` produced `Planning/06-11-Views-Plan.md` from three citation-grade Sonnet code maps (controller-verified, 35-point line check, 0 false agent claims) — then **two adversarial rounds (3 + 1 agents) surfaced ~14 genuine blockers** (hidden test-file consumers of `visibleProperties`, the `DetailRow`→`ViewItem` type bridge, route-deletion ordering, the self-contradictory cover write path, no headless Nuke-SPM procedure), all folded in. A confirmed pre-existing bug was found en route: `updateView`'s in-memory-first save clobbers `OrderPersister`'s disk-written `page_order` — plan Task 3 fixes it first.

Nathan's voice: *"wrong skill"* (docs-audit invoked before authoring a fresh spec — write it directly); *"Each line of code and location must be cited and confirmed accurate. Verify each agent's claim"*; *"As little hand-rolled mechanism as possible — bias and search for what Apple gives us for free ALWAYS"*; *"send these as background agents to save context and tokens"*; and the execution contract: *"once the plan starts I cannot provide more checkpoints until it's finished unless absolutely necessary, so any diversions or assumptions must be logged."* A round-2 clarification pass then reshaped the design: table = exact Apple defaults (26pt rows, subtler quinary zebra), group headers = native-style disclosure rows (not pinned bands), **Property Visibility moved to a new Layout pane** (Edit Properties is schema-only; tiers + Modified removed from it), cover is a per-view toggle (default OFF) that never appears in any properties UI, card property zones are fully interactive, banner area collapses when unset with a floating Add Banner button, new views are "Untitled View", and the Views toolbar button gets icon-only/labeled display modes.

Left off: HEAD `0137c0a` (sets-cleanup merge); working tree holds the uncommitted doc set — `Planning/06-11-Views-Spec.md` (ratified + round-2 amendments), `Planning/06-11-Views-Plan.md` (new), `Framework.md` (v0.5.0 restated), `Planning/README.md` — plus two `Superseded/` Contexts-Decoupling file deletions from a parallel cleanup (left untouched per quirk 10). Immediate next action: commit the doc set, then dispatch plan Task 1.

#### Lessons Learned

- **Read `MACOSX_DEPLOYMENT_TARGET` before concluding any platform constraint** — three research agents assumed a macOS 15 floor; the pbxproj says 26.4, which single-handedly eliminated the "system DnD lacks continuous hover location" limitation and flipped the drag architecture. **→ candidate CLAUDE.md quirk**
- **Plans must enumerate TEST-file consumers of renamed symbols** — `SavedView.visibleProperties` had four test files constructing it by label; the original plan listed only the two source consumers and would have failed its own first green-commit gate.
- **Adversarial rounds on plans earn their cost** — ~14 real blockers across two rounds, every one a would-be broken commit (route-deletion ordering, type bridges, write-path contradictions); and verify the adversaries too (one "blocker" claimed `PageFrontmatter.createdAt` doesn't exist — it does, line 17).
- **Mixed write paths are a standing hazard**: `updateView` (in-memory-first whole-struct save) silently clobbers `OrderPersister`'s disk read-modify-write `page_order`. Any new sidecar writer must use disk read-modify-write. **→ candidate CLAUDE.md quirk**
- `docs-audit-skill` is for auditing existing docs, not a gate before authoring a freshly-ratified spec (Nathan: "wrong skill").
- Cite ANCHOR LINE TEXT alongside line numbers in plans — line numbers drift task-by-task; two prose ranges in the first plan draft were wrong while the grep-verified anchors held.

#### Next Session

1. **Commit the Views doc set** (spec, plan, Framework, Planning README — explicit doc commit per quirk 4), then **dispatch plan Task 1** (SavedView v2) via superpowers:subagent-driven-development. First commit = `SavedViewV2Tests` red → green schema commit.
2. **Execute the plan under the autonomy protocol**: no Nathan checkpoints — controller verifies every gate hands-on (Task 7 layout spike, Task 11 parity, Task 14 drag feel) and appends every assumption/divergence to the plan's **Deviation Log**. HALT-for-Nathan conditions are enumerated in the plan's protocol section.
3. Nathan-side, non-blocking: Figma passes for the Layout pane UI and gallery card visuals slot in whenever ready (the plan builds functional stubs/structures meanwhile).

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

- **Column reorder broken** — scheduled: Views plan Task 10.
- **"Modified" not hideable** — scheduled: Views plan Tasks 8/18 (regression-tested in `SavedViewMutationsTests`).
- **Column layout not persisted** across sessions (+ property columns don't show icons) — scheduled: Views plan Tasks 8/10.
- **New property values aren't selectable until an app restart** — Views plan Task 18 investigates; fix if the cause is obvious (Nathan-confirmed scope), else stays open.
- **Inline-edit lag** — property value inline edit has a noticeable update buffer. Explicitly NOT in the Views cluster (cell-editor commit buffer untouched); carried forward.
- **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
- **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
- **Agenda description-cap doc mismatch** — specs claim a 1000-char cap; validators enforce none.
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Pinned-nav title staleness** — pinned-section titles don't refresh on page rename until re-pinned; likely resolved by a future file watcher. Non-issue for now.
- **Collection reorder limits** (investigated — not a bug): single-collection vaults can't reorder (`.onMove` needs ≥2 rows); collections can't interleave past root Pages (intentional v0.3.0 guard, `PageTypeRow.reorder` ~:317).
- **KNOWN ISSUE; NOTE TO FUTURE** — with relation properties replaced by contexts, future tasks + events lack a context-relation path; cross that bridge when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Active plan → `Planning/06-11-Views-Plan.md` (spec: `Planning/06-11-Views-Spec.md`; both carry the Deviation Log + autonomy protocol)
- Per-entity specs → `Features/*.md`
