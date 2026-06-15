### Pommora — Session Handoff

 - **Read first at session start.** Maintained via `/handoff` — Session Summary + Lessons Learned + Next Session + Pending Focuses + Fix Log. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

> ⚡ **CORNERSTONE — must remain; carry into every session, emphasized for the next (Nathan's voice).**
>
> *"This whole session started because I'm sick of one pattern: you claim something is true, write a plan around that claim, then later review it and find the claim was never true — and we thrash for hours. **That stops. You do NOT guess, you LOOK, you ASK. You open the file and LOOK AT THE CODE before you assert anything. You ASK ME when unsure.** A plan built on an unverified claim is a liability, not progress. Treat every doc, every `file:line`, every "it works like X" as a hypothesis until you've read the code that proves it."* ASK ME when you're unsure! Honesty is key; confidence must be earned through evidence.

#### Session Summary

Two threads of work are live: **(1) the Views + toolbar UIX** (SwiftUI — the focus of this session) and **(2) the React + TypeScript rebuild** (the exploratory contingency — `Planning/06-14-React-Rebuild-Roadmap.md`, backed by a Pommora-React Figma library and a partial app scaffold).

On the Views/toolbar thread, the toolbar/banner docs were first truthed-up to reflect that the toolbar, Views button, and banner are **actively-changing, not settled**. The Views button only *"looks"* good — at unknown cost, via methods we're not sure are best or even correct; the inspector folds the Views pill in when toggled (a deviation from Apple-native), the blast radius of the Views-button chrome choices on the rest of the toolbar is unmapped, and whether the banner's edge-to-edge bleed interacts with the toolbar is untested. Reframed `Features/Views.md`, `Planning/06-13-Views-UIX-Fixes.md`, and `Guidelines/Design.md` "Chrome animation"; committed as `283865b`.

The toolbar-wide **"Icon Only / Icon and Text" right-click menu was then found and suppressed.** A live `NSToolbar` introspection probe confirmed it is the **native macOS toolbar display-mode menu** — a stock `NSToolbar` with `allowsDisplayModeCustomization == true` — not app code (an exhaustive grep found zero; Mail and Finder show the same menu with extra items). It was never ours; it surfaced more once the toolbar moved off the default-closed inspector. Suppressed via `WindowToolbarConfigurator`, which sets `allowsDisplayModeCustomization = false` once the toolbar exists and re-asserts on toolbar rebuilds (navigation adds/removes the conditional Views pill, rebuilding the `NSToolbar` and resetting the property). **Confirmed working in production** and committed (`eecdf9f`) — `WindowToolbarConfigurator.swift` + the one-line `ContentView` wiring.

With the native menu gone, the open thread is **button-specific menus in the toolbar.** Right now the banner's "Change Banner / Remove Banner" `.contextMenu` fires when right-clicking toolbar buttons — the banner's `backgroundExtensionEffect()` bleeds it (with its menu) under the toolbar, and the buttons consume only left-clicks, so right-clicks fall through. We're exploring a workaround using the codebase's frame-bound `SecondaryClickMenu` / `onSecondaryClick` overlays (`DesignSystem/SecondaryClickCatcher.swift`): swallow right-clicks on the toolbar buttons so the banner menu fires only on the banner, and use the same overlays to give specific buttons (e.g. the Views button) their own menus. To be wired + validated next session.

**Where it left off.** `main` is clean — the menu fix (`eecdf9f`), the factual doc rewrite, and the Planning-docs reorganization (shipped `Superseded/` plans removed, `06-12-Views-V2-Plan.md` reclassified to `Reference/`) are all committed. The current detail table in the app is `ViewOutlineTable` (`Detail/Table/`).

#### Lessons Learned

- **The toolbar-wide "Icon / Text" menu is the native `NSToolbar` display-mode menu, not app code.** Suppress with `allowsDisplayModeCustomization = false`, applied *after* the toolbar exists and re-asserted on rebuilds (SwiftUI resets it). The earlier "leaked context menu" theory was a conflation that cost days. **→ candidate CLAUDE.md quirk.**
- **A live introspection probe beats grep-and-guess for "is this our code or the OS?"** Reading the actual `NSToolbar`'s properties into a verdict file settled in minutes what guessing couldn't — exactly the LOOK-don't-guess the cornerstone demands.
- **The banner menu reaches toolbar buttons** because `backgroundExtensionEffect()` bleeds the banner (carrying its `.contextMenu`) under the toolbar while the buttons consume only left-clicks. Frame-bound AppKit overlays (`SecondaryClickMenu` / `onSecondaryClick`) are the codebase's tool for scoping a right-click to one view.
- **Trust `xcodebuild`, not SourceKit** (reaffirmed): the "Cannot find `NexusManager` / `SidebarSelection`" same-module squiggles during the toolbar edits were all false; builds were green (1,214 tests).

#### Next Session — ViewsV2 continuation

1. Mark the toolbar menu **RESOLVED** in `06-13-Views-UIX-Fixes.md` (the fix shipped as `eecdf9f`).
2. **Button-specific toolbar menus:** confine the banner menu to the banner — swallow right-clicks on the toolbar buttons (Views pill, trio, back-forward) via the frame-bound overlays — and establish the per-button menu pattern (Views button as the example; its menu *content* is the deferred display-toggle feature). Validate live.
3. Continue the `06-13` Views/toolbar UIX sequence — the in-flux toolbar/banner items, then Gallery, grouping/sorting, the Layout-pane rework.

The React thread continues in parallel as the contingency exploration.

#### Pending Focuses

- **Toolbar / Views-button / banner chrome is actively-changing** (flux docs: `Features/Views.md`, `Planning/06-13-Views-UIX-Fixes.md`, `Guidelines/Design.md`): the Views button "looks" good at unknown cost via unknown-if-best methods; the inspector-adoption deviation; the untested banner↔toolbar bleed interaction.
- **Button-specific toolbar menus + banner-menu confinement** — the next-session task above.
- **Views-button display toggle — DEFERRED** ("Display as Icon Only / Icon + Title"); this is the intended content for the future Views-button right-click menu, blocked until the per-button menu pattern is settled.
- **Title baseline-on-icon (Fix 2 polish)** — the detail title text should baseline on the icon's bottom edge; a plain `Label` centers them. Not yet applied.

#### Fix Log

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
- Auto-loaded rules → `// rules//` (`MarkdownPM.md` scoped to the editor); `Review-Discipline.md` moved up to the Studio-level `// The Studio //.claude//rules//` — applies across all projects · Views spec-as-fact (toolbar/banner sections in flux) → `Features/Views.md` · per-entity specs → `Features/*.md`
