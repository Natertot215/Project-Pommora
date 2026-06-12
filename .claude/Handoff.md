### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-12 — Views cluster IMPLEMENTED, then ABANDONED on hands-on review; reverted to `main`)

The full v0.5.0 Views cluster (the 19-task plan) was executed end-to-end on a feature branch, then **abandoned**. The branch is preserved as **`views-FAILED-custom-table`** (tip `e3f9c72`) as a post-mortem record; `main` was restored to the pre-execution state (`6f79a38`) — native `Table` intact, no Nuke, no Views code.

What was built and how it died: all 19 tasks landed as green commits — SavedView v2 schema, the pure pipeline (filter/sort/group), a custom SwiftUI table, gallery + covers/banners (Nuke), the macOS-26 drag engine, the Views dropdown, the View-Settings panes — **1229 tests passing**, host bootstrapping clean. It then survived two full code-review rounds and a dedicated edge-case pass (every finding fixed and re-verified). Despite all that green, the moment Nathan ran it, the verdict was immediate: *"absolutely terrible… there's no fixing this, we need to retry our approach."* The custom table rendered as heavy dark disclosure bands (not native), a whole-pane blue focus ring on selection, broken page-icon glyphs, a blue-link Add Banner — a from-scratch reimplementation that visibly was not a native macOS table. Test-green did not mean right; the tests never asserted the thing that mattered (does it look and feel native), and the controller-deferred "visual/feel gates" were exactly where it failed.

**Why it failed — and it is obvious in the design itself.** The spec's **decision #15** is the governing principle, verbatim: *"Native-first bias: prefer what Apple gives us for free over hand-rolled mechanics, always — custom only where the SDK verifiably can't deliver"* (`Planning/06-11-Views-Spec.md:29`), echoing Nathan's standing rule *"as little hand-rolled mechanism as possible — bias and search for what Apple gives us for free ALWAYS."* Yet **decision #1** did the polar opposite: *"a visual 1-1 duplicate of native macOS `Table`"* hand-built from nested `ScrollView`s + `LazyVStack` + manually reimplemented columns, selection, focus, keyboard, disclosure rows, alternating fills, and drag (`:15`, `:74`). That is the *maximum* hand-rolled mechanism — a direct violation of the design's own top principle. The rejected-alternatives list (`:110`) considered SwiftUI `Table`, SwiftUIX, SwiftUI-Introspect, and AdvancedCollectionTableView — **but never the obvious native answer: `NSTableView` / `NSOutlineView` wrapped via `NSViewRepresentable`**, which Pommora *already uses* for the page editor (NSTextView/TextKit) and the splitter (NSSplitView). The reasoning leapt from "SwiftUI `Table` can't reorder rows / read back widths" straight to "hand-roll the whole table in SwiftUI," skipping the first-party AppKit control that delivers — natively, for free — every single thing the 19 tasks laboriously rebuilt: real disclosure groups (the exact "traditional macOS disclosure rows" Nathan asked for, because they ARE the native ones), row selection + focus, column resize/reorder/width-persistence, alternating backgrounds, keyboard navigation, and drag-reorder. A from-scratch SwiftUI fake of a native control cannot match native polish; the harder it faked, the more the seams showed. The failure was structural, not a matter of more bug-fixing.

Left off: on `main`, working tree clean, at `6f79a38`. The implementation + its full git history (incl. the review/edge-case/UI-fix rounds) lives entirely on `views-FAILED-custom-table` for salvage and reference. Nothing of the failed approach is on `main`.

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
