### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Current State (2026-06-12 — Views custom-table approach FAILED; reverted to `main`; retry pending)

**Where things stand.** `main` is restored to the pre-execution state (`6f79a38` + docs) — native `Table` intact, no Nuke, no Views code, working tree clean. The entire failed implementation (all 19 tasks, two code-review rounds, an edge-case pass, the UI-fix attempts, full git history) is preserved on branch **`views-FAILED-custom-table`** (tip `e3f9c72`) for salvage and reference. Three artifacts on `main` drive the retry: this post-mortem (`Handoff.md`), the reusable inventory (`Planning/Views-Salvage-Manifest.md`), and the rewritten **solution-neutral spec** (`Planning/06-11-Views-Spec.md`). Nothing of the failed approach is on `main`.

**Why it failed.** The v0.5.0 Views cluster was executed end-to-end: SavedView v2 schema, the pure filter/sort/group pipeline, a hand-rolled SwiftUI table, gallery + covers/banners, a drag engine, the Views dropdown, the settings panes — **1229 tests passing**, host bootstrapping clean, survived two review rounds + an edge-case pass. Yet the moment Nathan ran it, the verdict was immediate: *"absolutely terrible… there's no fixing this, we need to retry our approach."* The table rendered as heavy dark disclosure bands (not native), a whole-pane blue focus ring on selection, broken page-icon glyphs — a from-scratch reimplementation that visibly was not a native macOS table. The root cause is obvious in the design itself: the spec's **decision #15** stated the governing rule verbatim — *"native-first bias: prefer what Apple gives us for free over hand-rolled mechanics, always"* — and **decision #1** did the exact opposite, hand-building a "1-1 duplicate of native macOS `Table`" from SwiftUI primitives (manually reimplementing columns, selection, focus, keyboard, disclosure rows, alternating fills, drag). It never evaluated the obvious native answer — **`NSTableView`/`NSOutlineView` via `NSViewRepresentable`**, which Pommora already uses for the editor (NSTextView) and the splitter (NSSplitView) — which delivers every one of those behaviors natively, for free. A SwiftUI fake of a native control cannot match native polish; the harder it faked, the more the seams showed. Test-green ≠ correct, because nothing asserted native look/feel and the visual gates were deferred to the very end. The failure was structural, not a bug-fixing matter.

**The retry.** Wrap the native AppKit table (`NSOutlineView` for disclosure groups, or `NSTableView` with row-groups) via `NSViewRepresentable` — get disclosure groups, selection/focus, column resize+reorder+width-persistence, alternating rows, keyboard nav, and drag-reorder FROM the platform, not hand-rolled. **Salvage, don't rewrite,** the sound data layer from the failed branch (SavedView v2 schema, the SwiftUI-free pipeline, the `updateView` clobber fix, covers/banners storage, view CRUD, active-view persistence — full inventory in `Views-Salvage-Manifest.md`); only the renderer was wrong. Sequence: (1) a short native-approach brainstorm with Nathan — confirm `NSOutlineView` vs `NSTableView` and get a rendered screenshot in front of him EARLY, before building outward; (2) branch `views-v2` off `main`, port the salvageable data layer + its tests; (3) build the native-table wrapper fed by the resolved-groups pipeline; (4) re-host the detail views and layer the gallery / panes / dropdown back in. Do NOT re-run the old plan.

#### Lessons Learned

- **A "native-first / no hand-rolled mechanism" principle is violated the instant you decide to rebuild a native control from primitives.** The Views design wrote that principle down (spec decision #15) and then broke it in decision #1. When a SwiftUI control falls short, the next question is **"can we wrap the AppKit control?"** — NOT "can we hand-roll it in SwiftUI?" `NSViewRepresentable(NSTableView/NSOutlineView)` was never even evaluated, despite Pommora already using `NSViewRepresentable` twice. **→ candidate CLAUDE.md / Paradigm rule.**
- **Green tests + passing reviews ≠ correct, for UI.** 1229 tests, two review rounds, and an edge-case sweep all passed while the actual product was unusable — because nothing asserted native look/feel, and the visual/feel gates were deferred to the end. For a UI rebuild, get eyes on the *rendered result early* (a real screenshot in front of Nathan after the first renderer spike), not after 19 tasks. The Task-7 "layout spike" gated scroll mechanics but never the native *appearance*.
- **An adversarially-hardened plan can still be hardening the wrong thing.** Two adversarial rounds + an edge-case pass made a doomed approach *robust*, not *right*. Adversarial review checks "is this plan internally sound," never "is this the right approach at all" — that question belongs to a human gate before execution, not after.
- **Reusable from the failed branch (the data layer was sound; only the renderer was wrong):** the SavedView v2 schema + GroupConfig, the pure SwiftUI-free pipeline (`FilterEvaluator` / `SortComparator` / `GroupResolver` / `ViewItemSource`), the `updateView` disk-clobber fix, cover/banner storage + `CoverAssetStore`, and the View-Settings pane *logic* are all model/logic, not renderer, and port cleanly onto a native-table approach.

#### Next Session

1. **Re-approach the table as `NSViewRepresentable(NSOutlineView)` (or `NSTableView` with native row-groups).** This is the retry. Get native disclosure groups, selection/focus, columns (resize + reorder + width persistence), alternating rows, keyboard nav, and drag-reorder FROM AppKit — do not reimplement them. Build a thin SwiftUI wrapper driven by the (salvageable) pure pipeline. Spike the *rendered look* first and put a screenshot in front of Nathan before building outward.
2. **Salvage, don't rewrite, the data layer.** Cherry-pick / port from `views-FAILED-custom-table`: SavedView v2 schema, the pipeline engines, the `updateView` clobber fix, cover/banner + asset store. Re-spec only the renderer + the dropdown/banner UI to native patterns (Add Banner = the page Add-Icon affordance; Views = a clearly separate toolbar pill).
3. **Before any of this: a short design pass / brainstorm with Nathan on the native approach** — confirm `NSOutlineView` vs `NSTableView`, how the pipeline feeds it, and what genuinely still needs custom work (gallery is a real SwiftUI `LazyVGrid` and may be fine as-is). Do NOT re-run the old plan.

#### Pending Focuses

- Agenda compact-panel surface: hosting decided by the v0.6.0 Agenda UIX work (the PagePreview window pattern is the likely template).
- Launch-tail indexing contract (documented in `Architecture.md`): Finder-dropped pages arrive via CRUD or forced rebuild, not the launch scan.
- `LaunchTrace` breadcrumbs (DEBUG-only) at the container's `tmp/launch-trace.log` — keep until a few clean weeks of launches, then consider removing.
- Settings full editing UI ships v0.7.0 (post-renumber).

#### Fix Log

> These were "scheduled into" the failed Views plan and are NOT actually fixed on `main` (the fixes exist only on `views-FAILED-custom-table`). They return to OPEN; carry them into the native-table retry.

- **Column reorder broken** — open (a native-table approach gets this from AppKit for free).
- **Column layout (widths) not persisted across sessions** + **property columns don't show icons** — open.
- **"Modified" column not hideable** — open.
- **New property options aren't selectable until an app restart** — open; the failed branch's investigation found every option-write path publishes to the `@Observable` `types`, so the cause is likely a SwiftUI observation-scope boundary while the editor overlay is presented — needs a live repro.
- **Inline-edit lag** — property value inline edit has a noticeable update buffer (cell-editor commit buffer). Open.
- **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
- **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
- **Agenda description-cap doc mismatch** — specs claim a 1000-char cap; validators enforce none.
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Pinned-nav title staleness** — pinned-section titles don't refresh on page rename until re-pinned; likely resolved by a future file watcher. Non-issue for now.
- **KNOWN ISSUE; NOTE TO FUTURE** — with relation properties replaced by contexts, future tasks + events lack a context-relation path; cross that bridge when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Views design (the abandoned plan + spec) → `Planning/06-11-Views-Spec.md` + `Planning/06-11-Views-Plan.md`; the executed-but-failed implementation → branch `views-FAILED-custom-table`
- Per-entity specs → `Features/*.md`
