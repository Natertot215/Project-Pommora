### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (2026-06-10 — PagesV2 EXECUTED IN FULL, P0→P10, overnight run)

**PagesV2 is complete.** The Items→Pages collapse executed end-to-end on `itemsv2-interactive-window`, every phase a clean-room-verified green commit. Pommora now has **one operational entity** (Pages, beside Agenda): Items deleted from code, schema (v11 — nine tables), settings, tests, and docs; `{{ }}` retired to plain text; `Class` never written; **PagePreview** (in-window draggable Liquid Glass card) + per-vault **`open_in`** + **user sidebar sections** shipped. Net: roughly **−16k lines**; the suite reshaped from 1,246 item-era tests to **985 page-native, 0 failures**. Plans archived to `// Planning//Superseded//`; collapse entry in `History.md`; the sanctioned "What Items Were" retrospective lives in `PommoraPRD.md`.

Key commits: P1 `caaae19` · P2 `9120047` · P2.5 `424ccce` · P4 `9815ebd` · P3 `e9c8430` · P7 `477d82e` · P5 `67ee817`+`85b2ba4`+`58b4296` · P6 `c50ff49` · P8 `da2d223` · P9 `c7f48c7` · P10 `fc289b6`.

Mid-run plan revisions (all Nathan-ratified): **V6** stop-and-ask became a binding obligation; **V7** `{{ }}` retirement got its own phase (P2.5) with the chip visual surviving as the one dormant Component Library design file; **V8** the PagePreview primitive became an in-window draggable card (no window scene); overnight amendments — P5 reconciled to the transcript (inspector defaults open; unlock reveals an Open affordance; ✕ close), and the PRD "What Items Were" section became the third sanctioned survivor.

#### Lessons Learned

- **Type-safe ≠ runtime-safe (CR-9):** dropping an error-mapper branch while its `LocalizedError` extension still delegated into it compiled clean and crashed 902 tests via infinite recursion. The test gate caught what the build gate cannot.
- **Invert, don't delete:** retired behaviors are pinned by inverted tests — `{{` never scans/styles/pairs, `Class` never written, item tables absent from `sqlite_master`. Regression guards instead of lost coverage.
- **Executed-count reconciliation works:** every phase's test delta was predicted and reconciled (±1 between agents is parser variance; more is a finding).
- **NotchNook owns the menu-bar/toolbar hit-zone** for computer-use clicks — driving Pommora's toolbar needs it quit or coordinates below the notch strip.

#### Next Session (Nathan's morning review list)

1. **PagePreview screenshot** — launch against `~//Test`, set a vault to Compact (View Settings footer toggle), tap a page; compare against `// Planning//Assets//PagePreview-Figma-V8.jpg`. Code parity is done; this is the owed visual confirmation. Check: inspector opens by default, unlock reveals Open, ✕ close capsule.
2. **One manual sidebar-section create** — exercises the populated-outline path headless tests can't (quirk #8). Add Section via the Vaults header context menu → inline rename → Move to Section on a vault row.
3. **Gate-allowlist sanctions (P10 flags, Nathan's call):** archive `06-05-Connections-Plan.md` + `Contextv2.md` to Superseded/ (shipped; the largest remaining grep noise) and allowlist `Transcripts//` + `ReactInfo//` + `skills//` in the no-trace gate.
4. **Prospect check:** "Per-page open-in override" reframes Item↔Page promotion in `Prospects.md` — swap if something else was meant. Also new prospects: drag-reorder within user sections; section-rename duplicate validation.

#### Pending Focuses

- Agenda compact-panel surface: hosting surface intentionally undecided post-PreviewWindow-elimination (noted in `Agenda.md` + `Framework.md`).
- Launch-tail indexing contract (now documented in `Architecture.md`): a page Finder-dropped onto a current-stamped index arrives via CRUD or forced rebuild, not the launch scan — revisit if same-launch pickup is ever expected.
- Settings full editing UI remains v0.6.0.

#### Fix Log

- CR-9: `ItemTypeManagerError` LocalizedError recursion — extension deleted on the error side (P1, Nathan's ruling).
- P9 reorder-offset translation: the filtered default Vaults section's `.onMove` maps back to full-array indices (order-corruption guard).
- `AdoptionPreviewView` wrapper-dissolve string: "Pages/Items/Agenda" → "Pages/Agenda" (last production item string, P10).
- Stale claims fixed en route: index has **9** data tables at v11 (plan said 8); `Wiki-Link.md` doesn't exist (Document Map → `Connections.md`); Settings-UI version drift aligned to v0.6.0; Planning README phantom entries removed.
