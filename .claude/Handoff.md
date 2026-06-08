### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-08 — ItemsV2 **Phase D built** (D0–D5b) + a **card-visual design loop**; paused for sign-off)

> **Resume prompt (next session):** *"Resume the Item Window on `itemsv2-interactive-window` (HEAD `05c605a`). Phase D is built — D0–D5b committed + a card-visual revision checkpoint (`05c605a`, pending my sign-off). The ONE open thread is MY feedback on the card visuals (last shown: grab5). When I sign off: finalize the card commit, then **REVERT the throwaway snapshot harness** (uncommitted: `PommoraApp` `POMMORA_SNAPSHOT` gate + `ItemWindow/ItemWindowSnapshotScene.swift` + `PommoraTests/Items/ItemWindowSnapshot.swift`), then RESUME the core mandate per `Planning/06-07-ItemsV2-Plan-V3.md`: **D7 (inspector toggle) → E1/E2 (Templates pane; E1 design-gated) → Phase F (full green → UIX review → docs → prose sweep) → merge to `main`.** Hold the loop: subagent authors → background `builder` hard-verifies (NON-ZERO count, TYPE-name selector) → green-commit. For card visuals: build → real-app screenshot (`POMMORA_SNAPSHOT=1` launch + `screencapture`) → self-review → fix → show me. You do NOT guess — you LOOK and ASK. Agents lie; the build, the diff, and the screenshot don't."*

**Where it started.** Resumed at `0c821c6` / `1b4ab3a` (Phases B + C shipped, tree clean, paused for Figma). Directive: execute Phases D/E via the verified subagent loop — build each design-gated task's non-visual scaffolding first, then STOP and ask for the Figma before any visuals; clean checkpoint per task; "do it right and thorough."

**Key moments.** Built Phase D's non-visual + reused-component zones first — D0 scaffold + PUI constants (`08f5c50`), D1 VM-in-scene with re-resolving manager seams + flush-on-close (`ce91617`), D3 editable body (`50a9056`), D6 footer/delete (`59ef9dc`) — each background-builder-verified (non-zero) + green-committed. Hit the design gate, presented a batched ask, and Nathan handed over the Figma → built the gated zones: D-foundation (liquid-glass window via `.glassEffect`, per-column footer; `914b329`), D2 header (`1c44369`), D4 segmented `PropertyFieldBar` (`48d8be3`), D5a unified tier fields (`b9eacf6`), D5b inspector property rows (`30c6d13`), plus A5 cap 4→6 (`b901bd0`). Then a **card-visual design loop** opened: the off-screen `ImageRenderer` render came back broken (SF Symbols as yellow placeholders, flat glass, blank body), so a throwaway `POMMORA_SNAPSHOT=1` scene + `screencapture` gave real-build grabs that drove ~3 revision rounds against Nathan's exact specs — bar → native-segmented (full fixed width = textbox, 28pt, content-variable cells via a custom `SegmentedTrackLayout`, vertical hairline dividers, `quaternarySystemFill` matching the body), body → fixed 310pt + 6pt gaps, card sizes to content (the "gap" was a snapshot-harness `minHeight: 600` artifact, not a production bug). Checkpointed at `05c605a` (pending sign-off).

**Nathan's voice.** Drove the card hard: *"the properties panel bar is wrong"* → *"Figma is the wrong workflow — diagnose what's clearly wrong yourself ... Before making the fix I want to be certain YOU know why it's incorrect"* (made me articulate the WHY before touching code); *"Don't use custom fields when the figma design uses a proprietary component"*; *"the full width must be fixed, same as the textbox; the individual cells are variable"*; *"the textbox must be fixed size LOOK"*; exact specs *"310pt ... 6pt ... segmented controls must use the same color as the text field"*; and the standing mandate *"Screenshot your work before claiming complete, then address issues that screenshot finds."* Praised the header — title field, exit, inspector toggle *"implemented correctly and i'm pleasantly surprised."* Flagged the **fork**: don't let the card-visual loop distract from the plan's core mandate (D7/E/F).

**Where it left off.** HEAD `05c605a` (card-visual checkpoint, pending sign-off). Working tree holds ONLY the throwaway snapshot harness (uncommitted: `PommoraApp` gate + `ItemWindowSnapshotScene.swift` + `ItemWindowSnapshot.swift`) — kept for re-grabs, MUST be reverted before merge. Awaiting Nathan's feedback on grab5; that's the one open thread before resuming D7/E/F.

#### Lessons Learned

- **Build-green ≠ visually correct.** The screenshot self-review (Nathan's mandate) caught what the green build missed: a dead layout gap, a bar/body color mismatch, wrong divider orientation. Screenshot every visual task + self-review before claiming complete. **→ candidate CLAUDE.md quirk.**
- **`ImageRenderer` can't faithfully render this card off-screen** — SF Symbols become yellow "prohibited" placeholders, `.glassEffect` falls flat, the TextKit body is blank. For a faithful capture, launch the real app (a throwaway `POMMORA_SNAPSHOT=1` debug scene replacing the main `WindowGroup`) + `screencapture`. **→ candidate CLAUDE.md quirk.**
- **The app / XCTest host is sandboxed** — it cannot write to `/tmp`; write side-effect files to `FileManager.default.temporaryDirectory` (the app container) and copy them out via the non-sandboxed builder shell.
- **`.quaternary` (hierarchical style) ≠ `Color(.quaternarySystemFill)` (semantic fill)** — they render different shades. When two surfaces must read as one material, match the exact fill (the body uses `quaternarySystemFill`).
- **Figma MCP:** `get_design_context` needs a live desktop SELECTION (errors "nothing selected" given only a node-id); `get_metadata` / `get_screenshot` resolve by node-id via the API. Nathan called the Figma route "the wrong workflow" here — diagnosing the render against his text specs was faster.
- **A fixed-size body in a two-column card** must let the card size to content (or fill to match the taller column) — a fixed-small body under a fixed-tall card leaves dead space, and that space can be a snapshot-scaffold `minHeight` artifact rather than a production bug. Distinguish scaffold artifacts from real layout faults before "fixing" the production code.

#### Next Session

1. **Land Nathan's card-visual sign-off** (grab5, or iterate the same way: fix → real-app screenshot → self-review → show). On approval: finalize the card commit (refine/squash `05c605a`) and **REVERT the throwaway snapshot harness** (`PommoraApp` gate + delete `ItemWindowSnapshotScene.swift` + `ItemWindowSnapshot.swift`).
2. **D7 — inspector-collapse toggle.** Single-column `PUI.ItemWindow.mainWidth` when `vm.inspectorShown == false`; the header's `sidebar.trailing` toggle already flips it. Build green, commit.
3. **E1 + E2 — Templates pane.** Grouped-by-type checkbox pane + pooled-cap muting (**design-gated**: the two muted states) + the `property_layout` control; E1 re-implements the captured legacy-pin-collapse.
4. **Phase F → merge.** Full `-only-testing:PommoraTests` green + `swift format lint` → standing post-functional UIX review → docs (`Features/Items.md` + Paradigm #15 amend + `History.md`) → prose doc-sweep → merge `itemsv2-interactive-window` to `main`.

#### Pending Focuses

- **[carried from 06-08] Item Window — Phase D built; D7/E/F remain.** D0–D5b + card-visual checkpoint shipped (HEAD `05c605a`); **throwaway snapshot harness must be reverted before merge.** Spec `Planning/06-07-ItemsV2-Spec-V5.md`, plan `Planning/06-07-ItemsV2-Plan-V3.md` (top-banner execution status + corrections).
- **[carried from 06-07]** `markerRanges[0]/[1]` in `styleItemLinks` — no bounds guard (can't crash today; the tokenizer always emits 2). Add `guard token.markerRanges.count >= 2` if it's refactored.
- **[carried from 06-03]** Push `folder-exclusion` → origin — no upstream, ~30+ commits ahead. (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch.
- **Nathan: add `excluded_folders` entries + rebuild once** (meta-file leak) — `The Nexus/.nexus/settings.json`: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`; confirm whether `History.md` / `Framework.md` / `Resources.md` are also non-content.
- **Latent (review-flagged):** pages nested ≥2 folders deep in a collection are missing from the launch index scan (`IndexBuilder` non-recursive vs `loadAll` recursive). Fix when it bites.

#### Fix Log

1. **Column reorder broken** — drag-reordering table columns; folds into v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show icons); folds into v0.7.0.
5. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — decide separately.
6. **Backspace on a checkbox / list item** should auto-delete the syntax — confirmed UNIMPLEMENTED; a feature-add.
7. **Agenda description-cap doc mismatch** — specs claim a 1000-char cap but validators enforce none; decide the intended cap or drop the doc claim.
8. **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
9. **Item Window inspector — non-tier `.relation` rows guess their scope.** D5b's `InspectorPropertyRow` defaults a `.relation` property's `ContextValueEditor` scope to `.contextTier(1)` when `relationTarget` is nil — fine for tiers, wrong for a real non-tier relation. Revisit if non-tier relations surface in the inspector (flag at F2).
10. **`bodyZone` cap-comment imprecise.** The comment calls the description cap a "non-blocking WARN," but per Spec-V5 in-app over-cap saves ARE rejected (only already-over-cap-on-load is non-blocking). Tighten in the F4 doc-sweep.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **ItemsV2 interactive Item Window (Phases A–C + D0–D5b BUILT; card-visual checkpoint `05c605a` pending sign-off; D7/E/F pending) →** spec `Planning/06-07-ItemsV2-Spec-V5.md`; plan `Planning/06-07-ItemsV2-Plan-V3.md` (top banner = execution status + corrections); review discipline `Guidelines/Review-Discipline.md`. Built on `itemsv2-interactive-window` (`14760b0..05c605a`). **A throwaway snapshot harness is uncommitted (revert before merge).** Paradigm #15 amend deferred to Plan-V3 Task F3.
- **ItemsV2 (SHIPPED 2026-06-03, archetype model — RETIRED) →** as-built `Planning/06-03-ItemsV2-Implemented.md`; the archetype/mockup/display path was torn out in Phase C1.
- **Connections (PAGE-LEVEL COMPLETE 2026-06-07) →** spec `Features/Connections.md`; plan `Planning/06-05-Connections-Plan.md`. Item chip click path (`onItemLinkClick` → `ItemLinkOpener.loadItem` → `AppGlobals.presentItemAction`) is the entry to the Item Window.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
