### Pommora — Session Handoff

 - **Read first at session start.** Current state + next focuses + fix log only. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.
- 


#### Current state (2026-05-27)

Everything below is on **`origin/main`** — today's work (spanning multiple sessions) was just committed + pushed. First action next session: `git pull origin main`.

**Today shipped:**

1. **Document cleanup** — trimmed accumulated bloat across `.claude/` docs; established CLAUDE.md HARD RULES (Component Library is the source of design; exhaustive `switch`/`enum`; DRY).
2. **UIX refinement** — View Settings, the context menu, and the table view brought to spec (chip dropdowns pulled from the Component Library, tri-state status checkbox, unified field backdrop, etc.).
3. **Table-level reworking** — detail-view table rendering + inline cell editors.
4. **Bug fixes** — back/forward navigation; collection context menu.

**Open sessions:** this one + a parallel session on **table drag (row reordering)**. Both just pushed to `origin/main`.

#### Next focuses

1. **Item Windows** — build the real Item Window (in-window property editing was deferred off the placeholder).
2. **Page Previews** — standalone-window page preview (the cross-feature PreviewWindow primitive).
3. **Relations** — inline relation editor / picker.

#### Fix Log

Acknowledged, not-yet-fixed — address soon (keep current per Handoff Rules):

1. **Icon picker too large.** The icon picker in View Settings renders far too big; constrain its size.
2. **Settings popout sizing.** The View Settings popout should size to its content dynamically to avoid scrolling (currently pinned to a fixed max height; Nathan likes the min height).
3. **Column reorder broken.** Drag-reordering table columns doesn't work.
4. **"Modified" not hideable.** Last-Edited / "Modified" can't be toggled off in the visibility settings, but it should be.
5. **Schema changes need reload.** Changing "View As", adding properties, or other schema edits don't show until the view is reloaded — they should update live.
6. **Inline-edit lag.** Editing a property value inline has a noticeable performance + update buffer.
7. **Column layout not persisted.** Table column width/order adjustments don't survive across sessions.
8. **Handoff Skill.** Nathan wants to create an actual skill / command to handle the handoff documentation process rather than relying on listed rules or individual session judgement.

#### Handoff Rules

- **Keep the Fix Log current.** When an issue is acknowledged but not yet fixed, add it to the Fix Log above in 1–2 sentences; remove an entry once resolved. 
- **Maintain this file every session** — current state + next focuses + fix log only. Push spec/decisions to their canonical homes (`History.md` / `Framework.md` / `Features/*`); never accumulate per-session work logs here unless double-checked for importance or the work is not yet completed. 

#### Document pointers

- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
