### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-12 — Views cluster SHIPPED on branch `views`; awaiting hands-on review + merge)

The entire v0.5.0 Views cluster — the 19-task plan written last session — was executed end to end via subagent-driven-development. Branch `views` (off `main` `0137c0a`) now carries Tasks 1–19 as green commits: SavedView v2 schema + GroupConfig, the pure view pipeline (Filter/Sort/Group), the custom Table renderer (nested-scroll, 26pt quinary rows, disclosure group rows, resizable/reorderable/hideable columns, selection + keyboard), the Gallery (Nuke covers, interactive card zones), covers + banners with a `.nexus/assets/` store, the macOS 26 drag engine (reorder/move/property-rewrite with a live insertion preview), the toolbar Views dropdown + multi-view CRUD, the four View-Settings panes + schema-only Edit Properties, and the retirement of native `Table` / `DetailRow` / `PropertyColumnBuilder`. **1217 tests green, host bootstraps clean.** Docs landed: `Features/Views.md` (spec-as-fact), updated `PageTypes.md` / `Properties.md`, `History.md` v0.5.0 entry, Paradigm-Decisions #20; the spec + plan moved to `Planning/Superseded/`.

Execution ran under the **autonomy protocol** (no per-task Nathan checkpoints). Every task was controller-verified hands-on: a background `builder` agent ran `-only-testing:PommoraTests` after each, with non-zero executed counts confirmed and the diff read against the plan before each commit. The cornerstone earned its keep repeatedly — the builder twice misdiagnosed a real compile break (`PageMeta.isPinned`) as an "unrelated pre-existing baseline"; it was actually the retired `DetailRow.swift`'s `PageMeta` pin extension, which had to be relocated to `Detail/Table/PageMetaPin.swift`. Verifying directly, not trusting the report, caught it.

Nathan's voice: a mid-flight correction worth carrying — *"done with concerns always means you must fix"* and *"do not defer the drag issue in t14."* Task 14 had shipped with the live drag insertion-line preview flagged as "may not render" and deferred to a feel-gate; that was wrong. It was fixed (driven off `DropSession.location` + a `.global` frame registry), and the same was then built for the Gallery (`GalleryDropGeometry`). Lesson saved to memory: a subagent's `DONE_WITH_CONCERNS` is unfinished work — fix it or prove it's another task's scope; never launder it into the Deviation Log. (Nathan reviewed Task 15's snap-to-slot line and accepted it — *"t15 is fine"* — the one explicitly-adjudicated exception.)

Left off: branch `views` at the docs commit, working tree clean, 1217 green. **Not merged to `main`.** The cluster's subjective gates were verified structurally (compile + bootstrap) but NOT by Nathan's eye — they wait for him. Immediate next action: Nathan's hands-on review of the deferred gates, then merge to `main` as v0.5.0.

#### Lessons Learned

- **A subagent's `DONE_WITH_CONCERNS` is NOT done.** Fix the concern (or prove it's genuinely another task's scope); never commit a degraded deliverable with the degradation logged. Surface it to Nathan; he adjudicates the rare acceptable ones. Saved to memory. **→ candidate CLAUDE.md quirk**
- **Verify the builder's diagnosis, not just its pass/fail.** A `builder` agent twice attributed a real retirement-caused compile break to an "unrelated baseline." Deleting a file deletes everything in it — including incidental `extension X` blocks that live code depends on. Grep the deleted file's *contents*, not just references to its primary type. **→ candidate CLAUDE.md quirk**
- **Native macOS 26 drag-session APIs deliver continuous hover location** (`DropSession.location`) but it's element-local — lift it to a shared (`.global`) space against a frame registry to drive insertion previews. The `dragContainer` family needs `Transferable` items; per-row `.draggable` + a payload-carried selection is the simpler path when the item type isn't `Transferable`.
- **`SortComparator` collides with Foundation** — side-prefix view types that shadow stdlib names (used `ViewSortComparator`). Same discipline as the `AgendaTask`-not-`Pommora.Task` rule.

#### Next Session

1. **Nathan reviews the deferred gates hands-on, then merge `views` → `main` (v0.5.0).** The subjective gates never got Nathan's eye: Table visual parity vs the Figma collection-table frame (26pt rows, quinary zebra); the nested-scroll diagonal-trackpad FEEL (Task 7 spike is staged in the Component Library under Components → "Detail Views"); drag feel (table + gallery insertion previews); the Views dropdown vs its Figma frame; the Layout/Gallery card visuals (functional stubs pending a Figma pass). Each has a logged fallback if rejected.
2. **The stale-options bug** (Fix Log) — reproduce against the running build to pin the failing path; the static investigation found no obvious snapshot-vs-live cause.
3. Nathan-side, non-blocking: Figma passes for the Layout pane + gallery card visuals slot in whenever ready.

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

- **Stale property options** — newly-added Select/Status option values aren't selectable in pickers until an app restart. Investigated in the Views cluster (Task 18): every confirmed option-write path publishes to the `@Observable` `types` array, so no obvious snapshot-vs-live cause was found; needs a running-build repro to pin the failing picker path. OPEN.
- **Inline-edit lag** — property value inline edit has a noticeable update buffer (cell-editor commit buffer). Untouched by the Views cluster; carried forward.
- **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
- **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
- **Agenda description-cap doc mismatch** — specs claim a 1000-char cap; validators enforce none.
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Pinned-nav title staleness** — pinned-section titles don't refresh on page rename until re-pinned; likely resolved by a future file watcher. Non-issue for now.
- **KNOWN ISSUE; NOTE TO FUTURE** — with relation properties replaced by contexts, future tasks + events lack a context-relation path; cross that bridge when reached.
- *Closed this session (Views cluster): "Column reorder broken", "Column layout not persisted", "property columns don't show icons" (Tasks 8/10), "Modified not hideable" (Task 18).*

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Views spec-as-fact → `Features/Views.md` (the cluster's spec + plan are archived in `Planning/Superseded/`, carrying the full Deviation Log)
- Per-entity specs → `Features/*.md`
