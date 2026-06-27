## Handoff — Pommora (Swift)

The Swift / SwiftUI native build. Read first at session start; shipped history → `History.md`, roadmap → `Framework.md`, branch quirks + hard rules → `CLAUDE.md`, locked decisions → `History.md`.

**Session ID:** — (standing Swift doc; the next Swift `/handoff` stamps its session ID + per-session metadata)
**Dates:** 06-21-2026 → 06-26-2026

> ⚡ **Cornerstone — must remain; carry into every handoff, unchanged (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

> **React lives in its own handoff.** This doc is Swift-only — the React + Electron build's session log is `React/.claude/Handoff.md` (start there for React work). One `main`, one PRD, one on-disk paradigm; only Swift-relevant cross-build items (parity ports to do on Swift, shared on-disk format) surface here.

#### Session Summary

Recent Swift work: a cross-build `modified_at` fix, the Collections/Sets rename finishing with on-disk auto-migration, then the toolbar/Navigation reorg closing out the A–H refactoring program.

**`modified_at` — frontmatter canonical, mtime the fallback (06-25 → 06-26, impacts both builds):** Two fixes making Last-Edited sync-safe and cross-build-consistent. (06-25) `modified_at` is no longer a hard decode requirement on any entity sidecar — `AtomicJSON` injects the file's mtime and each model decodes `(try? …) ?? file-mtime ?? now`; a sidecar lacking it (e.g. one written by the React build, which doesn't stamp it) previously threw `keyNotFound` and silently dropped the whole entity, surfacing as empty Collections + a "data couldn't be read" error when a React-touched nexus opened in Swift. (06-26) Pages now resolve it the same way — stored frontmatter value wins, file mtime at load is the fallback (the lenient loader had dropped the field, so managers held `nil` and the index reached for raw mtime); `updatePage` bumps the stamp on every body save (the editor previously left frontmatter untouched, so text edits never moved Last-Edited), and the SQLite index mirrors the resolved value in both incremental + rebuild paths so a live session and a full rebuild agree. **Why:** mtime is clobbered by sync / git / copy, so it can't anchor Last-Edited in a files-are-canonical, synced model; the stored stamp survives and matches the React build, which already stamps on body edits — external (Obsidian / vim) edits no longer move a Page's Last-Edited. **React parity landed the same day:** one `resolveModifiedAt` helper across pages / collections / sets / agenda in `index/build.ts`, stored-wins-never-`max`, guard-tested both directions. Regression-tested Swift-side in `ModifiedAtFallbackTests` + `PageContentManagerUpdatePageTests`. → `History.md` + `React/.claude/History.md`.

**Collections/Sets rename + auto-migration, merged to `main` (06-24):** The long-running "Page Types / Vaults → Collections" rename is fully done — code, tests, docs, nothing left half-renamed. The headline is **auto-migration**: the first open on a pre-change Nexus quietly upgrades the hidden config files on disk (`_pagetype.json` → `_pagecollection.json`; every Set folder at any depth unified to `_pageset.json`), copying the affected files to a temp backup first and deleting it only once the rename succeeds (kept on failure) — real data migrates itself safely, no manual step. With every Nexus on one naming scheme, the old "read both formats" code was dropped. Came with it: ~500 leftover internal `vault`/`type` names swept to `collection`/`set` (cosmetic, behaviour-identical, 1,347 tests green); a real folder-adopter bug the rename exposed (two internal cases pointed at one filename, deleting legitimate Sets — caught by the suite, fixed); and docs + mirror cleanup (PRD/specs that still described the retired three-tier model corrected; the Obsidian mirror script now moves orphaned notes to `.trash` instead of leaving them). → `History.md`.

**Toolbar/Navigation reorg + A–H refactoring program complete (06-21):** Extracted the window-toolbar surface into `Features/Toolbar/` and renamed the nav-domain folder `NavDropdown` → `Navigation` end-to-end (`0d1dcd1`). The A–H program then closed: **Phase H** via a 4-lens simplification (Agenda title-sort DRY, a shared `InlineRenameFocus` responder-hop, a decorate-sort `ViewSortComparator`); **Phase F dropped** (premise false — synthesized `Decodable` *throws* `keyNotFound` on a missing in-CodingKeys key rather than using the property default, so the pervasive defensive `decodeIfPresent ?? default` is un-synthesizable); **Phase D** built the `SidebarRow` primitive and re-skinned all 7 rows (1139→648 lines); **Phase E** added `ViewSettingsScope` props + routed the Page-CRUD triplication through one scope-parameterized path (1209→965 lines), every public signature preserved so the CRUD suite gates neutrality; **Phase G** split ViewSurface. Branch consolidated to `main` + pushed, worktrees collapsed to `main` + `pommora-react`; 1,294→1,347 tests green throughout. → `History.md`, `// Planning//Reference//06-20-Refactoring-Program.md`.

**Lessons Learned**

- **Every roadmap line is a hypothesis until grounded against code.** This session's grounding repeatedly contradicted the roadmap — F's whole premise was false; E#3 (`schemaOptionValues`) didn't exist; E#1's scaffold/error were already components; E#4's "fresh-token" was paradigm-blocked. Open the file before executing the line.
- **Synthesized `Decodable` does NOT use property defaults for missing keys** — it throws `keyNotFound`; only excluded-from-CodingKeys properties use their default. So defensive `decodeIfPresent(…) ?? default` is un-synthesizable. (The fact that killed Phase F.) → candidate `CLAUDE.md` quirk.
- **Load-bearing refactors are safest behind a stable public API.** The SidebarView re-skin and the Page-CRUD collapse stayed behaviour-neutral by preserving every public signature and leaning on the test suite as the gate — zero caller/test churn. Delegation is a valid marathon-tail DRY: route duplicated logic through one source, leave thin shims when full call-site migration is risky, clean the shims as a fresh follow-up.

**Session Pointers**

- Nathan overrode "bank it / do this fresh" recommendations repeatedly ("continue", "do it now", "No, I said stop pausing") and each push landed green — calibrate toward momentum on behaviour-neutral refactors. The #4 "fresh-token" asset naming was **declined** as a paradigm change that regresses filename legibility (pending his override).

---

### Working Notes

- **Commit `.claude/*` explicitly** to the active branch — don't auto-bundle docs into Swift commits, don't let them vanish on branch switches. Xcode reorders Yams/GRDB in the pbxproj on every build — revert before committing.
- **Document pointers:** roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md` · auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor) + Studio-level `Review-Discipline.md` · per-entity specs → `Features/*.md`.

### Next Session

1. **Gallery view — the immediate focus.** Pick up the parked Views-UIX build (active plan → `// Planning//06-13-Views-UIX-Fixes.md`): the Gallery renderer, the Layout-pane rework, the sorting / grouping UIX.
2. **Port the React-side QoL wins to Swift:** the `cover`-compatible **page banners** (quick-add), the **sidebar storage-row click** behaviour (empty-row click toggles disclosure; main view only on textfield/icon click), and the **Icon-Picker UIX** rework.

### Pending Focuses

- **Adopted-ID consolidation** — unify the adopted-Page `SHA256(path)[:16]` + `adopted-` marking into one ID scheme; on-disk shape, ratify first.
- **`PropertyValue` datetime → `IndexDateFormat`** — on-disk decode change (fractional seconds); needs ratification before touching.
- **#4 fresh-token asset naming** — declined (keeps legible filenames); resurface only if React-style opaque tokens are wanted.
- **Nexus rename live end-to-end pass** — build-verified, not behaviour-verified.
- **React → Swift parity ports** — `cover`-compatible page banners + the sidebar storage-row click behaviour + the Icon-Picker UIX (all proven on React; to be built on Swift).
- **Unsorted bin → folder + sidecar (paradigm, ratify first)** — Nathan's looking into moving "unsorted" off a config file and onto a real `Unsorted/` folder carrying an `_unsortedconfig.json` sidecar (the folder-with-sidecar pattern the rest of the model uses). The win is interop: another Markdown-based app with its own unsorted bin could point at the same folder and share it, rather than each app hiding the list in a private config. Cleaner now that `Class: item` vs `page` is no longer a discriminator (PagesV2 collapse) — the bin holds plain entities, no kind to sort by. On-disk shape, so ratify before building.

### Fix Log

- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED on Swift (React already has it).
- **Agenda description-cap** — specs say 1000, validators enforce none.
- **Pinned-nav title staleness** on rename until re-pinned — may already be fixed by the file-watcher; retest.
- **Relation properties replaced by Contexts** — future tasks/events lack a context-relation path; cross when reached.
- **Dual-Delete autocompleted syntax** — typing `{{` and having the mirror `}}` deleted too regressed from baseline across both Swift + React; likely a simple fix, prioritize.

### Handoff Rules

- **Resolve = delete + route, never tag.** When an entry here (Pending Focus, Landmine, Uncertain, Fix Log) is genuinely done, push its real outcome to the canonical doc (`History.md` / `Features/*` / `Framework.md`) and delete the line — no `(Resolved)` / `(Superseded)` tombstones. A stale-but-tagged line is still a false line the next agent re-reads and discounts; deleting what's no longer true beats annotating it. In parallel, you may delete a resolved Landmine/Uncertain from another session's block (removal only, on real resolution) even though the rest of their block stays frozen.
- **Keep the Fix Log current.** Acknowledged-but-unfixed issues get a 1–2 sentence entry; remove on resolve.
- **One block per session, updated in place.** A session keeps one block; push spec/decision content to its canonical home (`History.md` / `Features/*` / `Framework.md`), carry still-open Pending Focuses forward. Never accumulate per-session work logs.
- **Swift-only.** React work + its session log live in `React/.claude/Handoff.md`; keep this doc to Swift + Swift-relevant cross-build items, not a React change log.
- Selecting multiple lines, then using the context menue to turn them into listed items only makes the first one a listed item. 
