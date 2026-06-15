### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary (toolbar `»`-overflow saga CLOSED + finalized · full `bb6817a..HEAD` review · `.claude/rules/` introduced)

> ⚠️ **Update (06-14, later — supersedes the "finalized" claim above).** The toolbar / Views-button / banner area has been **REOPENED as actively-changing**; "finalized" was over-confident. The Views dropdown only **"looks" good** — we do not know **at what cost**, nor whether it was achieved through the **best (or even correct) methods**. It carries unresolved quirks (it follows into the inspector when toggled — Apple-native apps don't) and **assumed-but-unmapped side effects** on the rest of the toolbar. A "Icon Only / Icon + Text" right-click menu surfaces across the *entire* toolbar region — an exhaustive grep found **no app code that creates it**, so its mechanism is unresolved. The docs were truthed-up to flux framing: `Features/Views.md`, `// Planning//06-13-Views-UIX-Fixes.md`, `Guidelines/Design.md` "Chrome animation". Nothing about the toolbar/banner is settled truth for the future.

**Where it started.** The prior handoff left the toolbar `»` overflow as the open headline — macOS-26's primary-action cluster folding into the `»` menu, with host-anchoring an *unconfirmed* hypothesis and a freshly-committed Fix-2 banner working point. Working tree was the 0.4.2 Views-UIX line on `main`.

**Key moments.** The saga closed. The "squished Views button" resolved to one line: `.buttonStyle(.plain)` on `ViewsDropdownButton` was stripping the default toolbar sizing — *removing* it (not adding frames/padding, which "fought the system") was the fix; height is system-owned for native toolbar buttons, only width is explicit. Final design: two Liquid Glass capsules (**Views** pill | **settings·nav·inspector** trio) at a tight `PUI.Spacing.md` gap, hosted on the **detail column** (host-anchoring now CONFIRMED — `.primaryAction` is leading-edge, so on the split-view root it measured against the sidebar's narrow budget and folded), with `.sharedBackgroundVisibility(.hidden)` killing the "reaching." Nathan blessed the baseline (`ced9dd3`), then directed a full teardown: `3a70f14` (dead scaffolding incl. the dormant `views_button_style` persistence), `70fe2b1` (redundant `GlassEffectContainer` dropped, gap tokenized), `fc613ca` (comment/doc truth-up). A `bb6817a..HEAD` review — two convergent passes (first-party + an independent agent) — came back **merge-quality, zero bugs**; its one DRY finding (the toolbar-glyph triple copy-pasted across 5 buttons) shipped as the `.toolbarGlyph(width:)` modifier + `PUI.Icon.toolbar*` tokens (`b958cbd`). Confirmed unchanged via a render-neutral diff + a non-disruptive live window capture.

**Then a docs-infra thread.** Created `.claude/rules/` (Claude Code natively auto-loads it) and migrated two guideline docs — `Review-Discipline.md` (no frontmatter → always-on) and the page-editor rulebook (renamed `Markdown.md` → `MarkdownPM.md`, `paths: ["**/MarkdownPM/**"]` → loads only near the editor). Commits `8f7b32e` + `9ae4b58`; refs repointed, README updated, Paradigm-Decisions left in Guidelines per Nathan. The `~/.claude/scripts/cross-file-mirroring` launchd script (the Nexus mirror) was made frontmatter-aware — it now preserves each side's own frontmatter and syncs body-only, so the rules mirror to the Nexus `II. Rules` folder without stripping the `paths:` scoping. Daemon restarted clean; vault orphans cleaned.

**Nathan's voice.** Hands-on through the mirror wiring — corrected me twice when I hunted in the wrong place ("No, the mirror is a python script"; "it's at the desktop level"), then "oh it mirrors to II. Rules, not Rules" (the `II.` prefix convention), and "keep it only body area, just like the others" (the body-only-but-frontmatter-preserved reconcile). On scope he was tight: "the rest can stay in guidelines where I manually point where relevant."

**Where it left off.** Clean HEAD `9ae4b58` on `main`, my work fully committed. Working tree carries a **parallel session's** uncommitted `Planning/06-14-React-Rebuild-Roadmap.md` + its `Planning/README.md` index entry (surfaced, NOT bundled), plus my `06-13-Views-UIX-Fixes.md` checkoff (committed alongside this handoff). Immediate next action is Nathan's direction call — see Next Session.

#### Lessons Learned

- **Toolbar host-anchoring CONFIRMED** (was unconfirmed): `.primaryAction` resolves leading-relative to its host — split-view root → anchors to the narrow sidebar → folds into `»`; the **detail column** is the correct host. **→ candidate CLAUDE.md quirk.**
- **The "squish" was `.buttonStyle(.plain)`** stripping default toolbar sizing — for native toolbar buttons height is system-owned; explicit `.frame(height:)`/padding fights the system.
- **Trust `xcodebuild`, not SourceKit** (reaffirmed): a wave of "Cannot find 'PUI'" / "Image has no member 'toolbarGlyph'" false positives during the modifier extraction; the build was green.
- **`.claude/rules/` frontmatter is `paths:`-only** (no `description`/`alwaysApply` — that's Cursor): no frontmatter = always-loaded; `paths:` globs = loads only when a matching file is read. Keep each rule < 200 lines; for heavy task-specific content prefer a skill.
- **The Nexus mirror strips frontmatter toward `.claude/`** by design — any `.claude/` file that NEEDS frontmatter (a rule's `paths:`) requires the reconcile to preserve it, or it's silently stripped on the next 1s pass.

#### Next Session

> ⚠️ **Direction call first.** A parallel session is actively exploring a **React + TS rebuild** (`Planning/06-14-React-Rebuild-Roadmap.md`) per the contingency — Nathan has a full Pommora-React Figma library and has scaffolded part of the app. The two-days-on-a-button toolbar/banner cost is a live motivator. The SwiftUI items below stand only if the next push stays SwiftUI; confirm direction before picking them up.

If SwiftUI continues, the toolbar/banner area is **reopened as actively-changing** — resolve it before resuming Views proper:

1. **Finish the remaining UIX-fixes log** (`// Planning//06-13-Views-UIX-Fixes.md`).
2. **Identify + remove the toolbar-wide "Icon / Icon + Text" right-click menu** — appears across every toolbar button + the empty title-bar space; an exhaustive grep found NO app code creating it, so the mechanism is unresolved (native NSToolbar display-mode menu vs. a leaked app menu). Settle with a live right-click test first.
3. **Resolve the underlying toolbar uncertainties** — the Views button "looks" good but we don't know at what cost or whether the methods are right: the inspector-adoption deviation, the unmapped blast radius of the Views-button chrome choices, and the untested banner↔toolbar bleed interaction.
4. **Then** resume Views: menus → Gallery → grouping/sorting UIX → Fix 3 (Layout pane).

#### Pending Focuses

- **[carried from 06-14]** Toolbar / Views-button / banner area is **reopened as actively-changing** (NOT closed): the Views button "looks" good but at unknown cost via unknown-if-best methods, the toolbar-wide right-click menu (no app code found) is unresolved, the inspector-adoption deviation persists, and the banner↔toolbar bleed is untested. Settle these before resuming the tactical sequence (menus → Gallery → grouping/sorting → Fix 3). Contingent on the direction call above.
- **[carried from 06-14]** Title baseline-on-icon (Fix 2 polish) — the detail title text should baseline on the icon's bottom edge; a plain `Label` centers them. Not yet applied.

#### Fix Log

- **Toolbar-wide right-click menu** — a "Icon Only / Icon + Text" display-mode menu surfaces on every toolbar button + the empty title-bar area, not just the Views button; an exhaustive grep found no app code that creates it, mechanism unresolved. → `// Planning//06-13-Views-UIX-Fixes.md`.
- **Inline-edit lag** — property-value inline edit has a noticeable commit buffer.
- **Stale property options** — newly-added Select/Status options aren't selectable until restart; needs a running-build repro to pin the picker path.
- **Backspace on checkbox / list item** should auto-delete the syntax — UNIMPLEMENTED (feature-add).
- **In-line code doesn't render color** within a textblock; italics/bolds don't auto-pair.
- **Agenda doc mismatches** — `AgendaEventManagerError._status` doc-vs-guard; description-cap (specs say 1000, validators enforce none).
- **Pinned-nav title staleness** on rename until re-pinned (likely a future file-watcher fix).
- **NOTE TO FUTURE** — relation properties are replaced by contexts, so future tasks/events lack a context-relation path; cross when reached.

#### Handoff Rules

- **Keep the Fix Log current.** Acknowledged-but-not-yet-fixed issues get a 1–2 sentence entry; remove on resolve.
- **Maintain this file every session** — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log only. Push spec/decision content to its canonical home.

#### Document pointers

- Roadmap → `Framework.md` · ship log → `History.md` · PRD → `PommoraPRD.md` · branch quirks + hard rules → `CLAUDE.md`
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor; `Review-Discipline.md` always-on) · Views spec-as-fact → `Features/Views.md` · per-entity specs → `Features/*.md`
