### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess. You open the file and LOOK AT THE CODE before you assert anything.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."*
>
> Reinforced again this session, two ways: (1) a grep-only doc audit reported "clean," but Nathan flagged *"prose may describe without exact words"* — reading the prose confirmed it (and found `PageEditor.md` already aligned to the new behavior). (2) A data-loss fix scoped to the two *reported* entities (Pages/Items) was caught by code-review as **incomplete** — Agenda Tasks/Events and the cross-container move paths shared the same `filename = title` substrate and were still vulnerable. **The cornerstone extends: a fix verified for the reported case is only a hypothesis about the whole bug class until you've enumerated every entity/path sharing the mechanism.**

#### Session Summary

Opened on a graphify request and ended deep in a data-loss hardening + refactor pass — none of it committed yet. Inherited state: `main` carrying the parallel session's page-header-icon + checkbox-canonicalization work (`607ebed`…`0b59e71`), plus the prior session's still-uncommitted `.claude` doc pass.

- **Graph + skeptic review.** Built a knowledge graph over Pommora + MarkdownEngine + `.claude` (graphify), then ran a four-agent skeptical architecture review. Findings live in `Planning/2026-06-01-Architecture-Skeptic-Review.md` — headline: Pommora "builds two of things that are one thing" (the Items/Pages fork ≈ 7,700 LOC of near-duplication; "files are canonical" is half load-bearing identity / half expensive assumption — the SQLite mirror + ~27% of the test budget exist to prop it up; the editor is the right native bet but over-polished). Nathan chose to act on the two concrete bugs first.
- **Two fixes Nathan green-lit** (*"1,2 are things I DON'T understand, so I'm going to trust you"*). **(1) Title-collision data-loss bug** — a same-name create/rename silently overwrote a sibling's file (`filename = title` + an overwriting atomic write). Nathan probed *"if UID is already its own mechanism, why can't we allow duplicate titles?"* — answered (the title does double duty as the on-disk filename, and the OS forbids two same-named files in a folder), and he chose **reject** for now (true independent titles = a future title-field Prospect). **(2) `NexusEnvironment`** — collapsed `ContentView`'s ~16 hand-wired manager injects into one container + a single `.injectNexusEnvironment(_:)` modifier, killing the missing-inject `EXC_BREAKPOINT` crash class (quirk #15).
- **Code-review (3 graphify-equipped agents) caught the fix as incomplete.** Agenda Tasks/Events were still clobberable; a **case-recase regression** the fix itself introduced (a no-overwrite guard blocking `notes`→`Notes` on case-insensitive APFS); and a **move-via-`SchemaTransaction` clobber vector**. Nathan: *"Don't leave anything deferred."* So coverage was extended to **all file-backed entities on create / rename / move**, the recase guard rewritten to compare inode identity, the 6 container validators de-duped onto the shared `NameCollisionValidator`, the dead `@Observable` dropped, `AppGlobals.publish` collapsed, and the `debounceCoalescesRapidEdits` flake fixed deterministically.
- **Docs + housekeeping.** Synced Domain-Model / Pages / Properties / CRUD-Patterns / CLAUDE quirks #15+#5 / Paradigm-Decisions (#13) / History to the reject behavior. Moved the `graphify` skill Studio→global (now invocable as `/graphify`). Removed the stale `graphify-out/`.

Left off: **everything uncommitted in `main`'s working tree, verified green — 1073 tests, 0 failures, the debounce flake fixed and stable across two full runs.** ~20 Swift files + 7 `.claude` docs changed; two new test files (`NameCollisionTests`, `AgendaNameCollisionTests`). Safety-net git worktrees under `.claude/worktrees/` hold the *original* two-fix commits (stale, pre-extension). Immediate next action: decide the commit (branch-first), then clean up those worktrees.

#### Lessons Learned

- **A bug rooted in a shared substrate lives in every entity that shares it.** The silent-overwrite bug was "fixed" for Pages/Items, but Agenda Tasks/Events + the move paths shared `filename = title` + overwriting writes and stayed vulnerable — code-review caught all three. Enumerate the whole class, not the reported case. **→ candidate CLAUDE.md quirk**
- **No-overwrite guards on a case-insensitive volume must compare file identity, not name presence.** `fileExists(newURL)` returns true for a self-recase (`notes`→`Notes`) and wrongly blocks it; compare `fileResourceIdentifierKey` (inode) instead. **→ candidate CLAUDE.md quirk**
- **Wall-clock test timing is a load-sensitive flake.** `debounceCoalescesRapidEdits` slipped under full-suite parallelism even at 800ms; the fix is poll-for-event + read the VM's real interval, never sleep-and-guess.
- **Search "clean" under-reports — for prose too.** A token search misses behavior described in different words; reading the prose is the only audit that counts (extends the cornerstone).
- **`/code-review` earned its keep:** three real gaps the implementation missed. Treat "fix done + tests pass" as a hypothesis until an adversarial pass enumerates the blast radius.

#### Next Session

1. **Commit the working tree** (branch-first off `main`) — the title-collision data-loss fix (all entities + moves) + `NexusEnvironment` + the synced docs + the scrutiny-review doc. Verified green (1073/0). Then remove the stale `.claude/worktrees/` safety-net worktrees + their branches.
2. **Pick the lead architecture thread** from `Planning/2026-06-01-Architecture-Skeptic-Review.md` — **Items+Pages unification** (the middle path: unify the type system, keep both serializations) is the highest-ROI candidate — or proceed with the v0.4.0 roadmap (Symbols / Settings / Trash / Wikilinks; note a parallel session is already on Wikilinks).

#### Pending Focuses

- **[carried from 05-31]** Live smoke (Nathan's manual): vault/type tables display-only + mirror sidebar; collection/set reorder; relation `type_id` reconcile heals drifted collections; relation Mirror name/icon propagation; Edit Icon from popover / sidebar / detail-table.
- **[carried from 05-31]** Commit the prior **doc pass** (Framework realign + History trim + cross-doc version fixes) — still uncommitted, now bundled into this session's larger uncommitted tree; fold into the Next Session #1 commit.
- **[carried from 06-01]** **v0.4.0 kickoff** (unshipped — this session pivoted to graphify + the data-loss/refactor work). Symbols / Settings / Trash / Wikilinks + file-watcher + FTS5.

#### Fix Log

1. **Column reorder broken** — drag-reordering table *columns* (distinct from rows); folds into the v0.7.0 view-system work.
2. **"Modified" not hideable** in the visibility settings.
3. **Inline-edit lag** — property value inline edit has a noticeable update buffer.
4. **Column layout not persisted** across sessions (+ property columns don't show their icons); folds into v0.7.0.
5. **Relation-add dead-end in legacy sheets** — "Relation" in the Vault/Type Settings sheets silently cancels; hide it or route to the View Settings editor.
6. **Settings popout sizing** — should size to content dynamically (Nathan likes the min height).
7. **`AgendaEventManagerError._status` doc-vs-guard mismatch** — the error's doc says events have no `_status`, yet the delete guard still blocks it; decide separately.
8. **Backspace on a checkbox / list item** should auto-delete the syntax (not just the render); also render bullets as label + secondary rather than primary.
9. **CLAUDE.md quirk #11 claims an in-repo CI lint step that doesn't exist** — no `.github/workflows`, no CI script invoking `swift format`; only the `.swift-format` config. Either CI was removed or it's Xcode-Cloud-only (unconfirmable from the repo). Consequence: nothing auto-catches lint — 44 pre-existing violations in `ItemContentManager+CRUD.swift` went uncaught. Correct the quirk or confirm CI scope.

#### Maintained via `/handoff`

Spec: Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Route locked decisions to `History.md` / `Guidelines/Paradigm-Decisions.md`, spec content to `Features/*`, roadmap detail to `Framework.md`. Don't hand-edit beyond the Fix Log unless the spec contract is preserved.

#### Document pointers

- **Planning →** `Planning/2026-06-01-Architecture-Skeptic-Review.md` (this session's review — seeds the Items/Pages-unification + DB-canonical threads) · `Planning/2026-05-31-vault-table-displayonly-interim.md` (per-view-ordering deferral). Note: `Planning/Pommora-Wikilink.md` + `Features/Wiki-Link.md` are a parallel session's wikilink work (untracked) — left untouched (quirk #10).
- Roadmap → `Framework.md` (realigned to `Nexus//Pommora//Pommora Tasks.md`) · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
