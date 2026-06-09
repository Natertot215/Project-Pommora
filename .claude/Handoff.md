### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-08 — Item Window UIX sweep executed on the NSPanel platform; cleanup done; real-build review OPEN)

> **Resume prompt (next session):** *"Resume the Item Window on `itemsv2-interactive-window` (HEAD `170f7c9`). The design is LOCKED to my Figma (file `V3wKMilXkoceCL1Q2J9kf4`, node `474-9432`): fixed-size non-activating `NSPanel`, v1 ✕ chrome, body-fills, unified flat-hairline inspector (contexts → properties, red Delete bottom-right), status-applies-on-click. T1–T6 are SHIPPED + a post-review cleanup landed. **The next REQUIRED action is applying the remaining UIX fixes from my real-build review** — the title is the first (I asked for lighter/larger; re-check it) — then Phase F (full tests + swift format + merge to main). You do NOT guess — you LOOK, you ASK, you verify against my build. The runtime behaviors (non-activating focus, zero-dimming, fixed-size layout, status popover) are RUNTIME-only — I verify them."*

**Where it started.** Opened at `91e53b3` (the non-activating `NSPanel` platform, build-green) with the UIX sweep S1–S4 queued in `Planning/06-08-ItemWindow-UIX-Sweep.md`.

**Key moments.** Interviewed Nathan branch-by-branch to lock the design, grounding every decision in code + his Figma (pulled directly via the Figma MCP — `V3wKMilXkoceCL1Q2J9kf4`/`474-9432`). The interview corrected the prior plan in four places (close = v1 ✕ not native dot; no meta at all; title = standard-window not large; tiers ARE labeled). Rewrote the spec (`06-08-ItemWindow-UIX-Sweep.md`) + authored a task-by-task plan (`06-08-ItemWindow-UIX-Plan.md`) after 4 code-explorer agents + self-verification. Executed the sweep via the subagent loop (implementer → background `builder` hard-verify → read diff → green-commit): **T1** fixed size 800×560 + v1 ✕ chrome (`5e5bb95`), **T2** zero-dimming via `.environment(\.controlActiveState, .active)` — verified WRITABLE on macOS 26 (`6e72915`), **T3** body fills (`10abd55`), **T4** property-bar placeholder cells (`df3ee48`), **T5** unified hairline inspector (`042da60`), **T6** status apply-on-click in `PropertyEditorRow` (`51468de`). Then a full code-sweep cleanup (4 parallel `/simplify` agents + my verification): stale comments, `filledIDs` dedup, `ItemWindowSceneRoot.swift`→`ItemWindowHost.swift` rename, + the title fix from the real-build review (`.headline`→`.title2.weight(.medium)`) — `170f7c9`. Docs updated this session (`Features/Items.md` § Item Window + `PommoraPRD.md`) to the NSPanel model.

**Nathan's voice.** Cornerstone in action: he sent the Figma URL ("Use my figma design DIRECTLY") + a real-build vs Figma screenshot ("compare and contrast… explain the fixes"), corrected me to not defer comment cleanup ("DONT defer in-line comment cleanup"), and flagged the select-always-open bug from a screenshot. Two verifications paid off: `controlActiveState` is writable on macOS 26 (an agent guessed it might be get-only; the builder proved it compiles), and the "dead" archetype/PreviewWindow code is actually queued scaffolding (the docs proved it — removed nothing).

**Where it left off.** HEAD `170f7c9` — clean tree, 7 green commits this session, 18 `ItemWindowViewModelTests` passing throughout. The design is built + cleaned. **OPEN: the real-build UIX review — Nathan is sitting with the build.** The title fix is applied (awaiting his re-check); further UIX fixes from his review are the immediate, required next action (see Next Session #1).

#### Lessons Learned

- **Verify "dead code" against the ROADMAP, not in-file comments.** `partition`/`reorderPromoted`/`ItemWindowLayouts`/`ItemWindowZoneConfig`/`PreviewWindow` all read as orphaned, but `History.md` + Paradigm-Decision #15 prove they're queued scaffolding (deferred archetype rendering, the Templates pane, the Page-preview primitive). Confirm against the docs before deleting tested code.
- **`controlActiveState` IS writable on macOS 26** (get-only on older macOS). `.environment(\.controlActiveState, .active)` on an `NSHostingController` root keeps panel content rendering active even when non-key — the clean zero-dimming fix, no AppKit hack. **→ candidate CLAUDE.md quirk.**
- **`isKeyWindow` override is the WRONG lever for non-key dimming** — only one window can be key, so claiming key would dim the MAIN window. Force the content's `controlActiveState` instead (no key-window claim).
- **Don't defer comment cleanup** (Nathan's correction) — clean stale comments in the same pass as the code, not in a later doc-sweep.
- **The Figma MCP grounds design** — pull the actual frame (`get_screenshot`/`get_metadata`) rather than reconstructing from memory.

#### Next Session

1. **Apply the remaining Item Window UIX fixes from the real-build review (REQUIRED — first).** Title is applied (`.title2.weight(.medium)`); re-check weight/size against Nathan's eye, and apply whatever else his review surfaces (focus/dimming behavior, fixed-size layout, inspector spacing, status popover, chrome). Each via the subagent loop → green-commit; runtime behaviors are Nathan-verified.
2. **Phase F → merge.** Full `-only-testing:PommoraTests` green + `swift format` (quirk #11) → add the History.md merge entry (Features/Items.md + PRD already updated) → merge `itemsv2-interactive-window` → `main`. Amend Paradigm #15 if the NSPanel model changes it.
3. **E1 + E2 — Item Templates pane** (carried). WYSIWYG promoted-property pane + pooled-cap muting + `property_layout`. Spec `Planning/06-07-ItemsV2-Spec-V5.md`.

#### Pending Focuses

- **[carried from 06-07] E1 + E2 — Item Templates pane.** The queued consumer of `partition` / `reorderPromoted` / `ItemWindowZoneConfig.muteReason` / `ItemWindowLayouts`. Spec `Planning/06-07-ItemsV2-Spec-V5.md`, plan `Planning/06-07-ItemsV2-Plan-V3.md`.
- **[carried from 06-08]** `markerRanges[0]/[1]` in `styleItemLinks` — no bounds guard (can't crash today; the tokenizer always emits 2). Add `guard token.markerRanges.count >= 2` if refactored.
- **[carried from 06-03]** Push `folder-exclusion` → origin (~30+ commits ahead). (carried 3×+ — confirm still wanted.)
- **[carried from 06-03]** Delete the merged `markdownpm-rehome` branch. (carried 3×+ — confirm still wanted.)
- **Nathan: add `excluded_folders` entries + rebuild once** — `The Nexus/.nexus/settings.json`: `"Claude"`, `"Pommora/CLAUDE.md"`, `"Pommora/Handoff.md"`.
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

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Item Window (REBUILT — non-activating `NSPanel`; T1–T6 + cleanup shipped on branch, HEAD `170f7c9`; real-build UIX review OPEN) →** spec `Features/Items.md` § Item Window (updated this session); locked design + sweep `Planning/06-08-ItemWindow-UIX-Sweep.md`; task plan `Planning/06-08-ItemWindow-UIX-Plan.md`; Figma `V3wKMilXkoceCL1Q2J9kf4`/`474-9432`. Key types: `FloatingItemPanel` · `ItemWindowPanelManager` (on `NexusEnvironment`, reached via `AppGlobals.current`) · `ItemWindowHost` · `ItemWindowRenderer` · `ItemInspector` · `PropertyFieldBar` · `PropertyEditorRow`. Data/VM spec `Planning/06-07-ItemsV2-Spec-V5.md` still holds; `06-07-ItemsV2-Plan-V3.md` E1/E2 + Phase F remain.
- **ItemsV2 data model (SHIPPED 2026-06-03) →** Paradigm-Decision #15 (`template_config` / `LayoutArchetype`); as-built `Planning/06-03-ItemsV2-Implemented.md`. Non-standard archetype rendering + the Templates pane are DEFERRED (their scaffolding lives in `ItemWindowLayouts`, `partition`/`reorderPromoted`, `ItemWindowZoneConfig`).
- **Connections (PAGE-LEVEL COMPLETE 2026-06-07) →** spec `Features/Connections.md`; item-chip click → `AppGlobals.presentItemAction` → `itemWindowPanelManager.open(ref)`.
- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Per-entity specs → `Features/*.md` · CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md` · review discipline → `Guidelines/Review-Discipline.md`
- Branch quirks + hard rules → `CLAUDE.md`
