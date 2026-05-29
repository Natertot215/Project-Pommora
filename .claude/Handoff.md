### Pommora — Session Handoff

 - **Read first at session start.** Current state + next focuses + fix log only. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

#### Current state (2026-05-29)

Working tree on `main`, green (only the known `PageEditorViewModelTests.debounceCoalescesRapidEdits` editor-timing flake fails).

**Relations Redesign — COMPLETE (Phases 0–22).** Relations and tiers are one linking system: tiers flow through the relation pipeline and the SQLite `relations` table (the `tier_links` table is retired); relations are always-multi (`[{"$rel":"<ULID>"}]`); `RelationTarget` covers Page Type / Item Type / Agenda Tasks / Agenda Events (+ internal `context_tier`); a single-pane editor creates/edits both sides (home + reverse name + reverse icon); deleting a Context cascades source-side; Agenda Tasks/Events are relation targets. The Lean adoption migration normalizes legacy sidecars on a one-time re-save (Type sidecar `schemaVersion` 1→2; index DB `currentSchemaVersion` 2→3 forces a rebuild that backfills tiers) — lossless changes apply silently, and the one lossy step (dropping a context-tier-targeted property) is gated behind an acknowledgment in the adoption preview. Relation values render as the target's **icon + title** in styled colored text (interim — chip visual is Next focus #1). Full play-by-play → `History.md` (2026-05-29 entry); paradigm decisions #8–#12 → `Guidelines/Paradigm-Decisions.md`; `Features/*` specs rewritten forward-only (Phase 21).

#### Next focuses

1. **Relation chips + hierarchical value pickers (asap — Nathan's priority).**
   - **Relation chip visual.** Design and build the real relation chip, then restyle the single `RelationChip` primitive (interim is plain icon + title); it propagates to every relation display surface. Fold the target icon into the tier-row panel surfaces (PropertyPanel / PropertiesPulldown / FrontmatterInspector / ItemWindow) as part of this — see Fix Log #11.
   - **Hierarchical relation value pickers.** Replace the v1 flat `ChipDropdown` rows with tree pickers: Vaults expand to Collections → member Pages; Item Types expand to Sets → member Items (root entities at top). A generic `HierarchicalEntityMenu` primitive powers both.
2. **Item Windows** — build the real Item Window (in-window property editing was deferred off the placeholder).
3. **Page Previews** — standalone-window page preview (cross-feature PreviewWindow primitive).

Open relation fixes: legacy Vault/Type Settings "Relation" dead-end (Fix Log #10); edit-side editing of an existing relation's reverse name/icon (create-side sets both; no source-side edit path yet); `LinkedFromDropdown` real Context-side surface (bare stub → logged in `Prospects.md`).

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
9. **Chip Colors.** Teal + Purple render as the exact same color as blue and violet on chips; needs fixing.
10. **Relation-add dead-end in legacy sheets.** Picking "Relation" in the Vault/Type Settings sheets (the context-menu schema editors) silently cancels — relations are created via the View Settings popover editor. Hide the Relation option in those sheets (or route it to the editor) so it isn't a no-op.
11. **Tier-row panels may show title-only.** The tier-row displays (PropertyPanel / PropertiesPulldown / FrontmatterInspector / ItemWindow) render the target's title but may omit its icon (the table cells + picker already show icon + title). Fold in with the relation-chip work (Next focus #1).

#### Handoff Rules

- **Keep the Fix Log current.** When an issue is acknowledged but not yet fixed, add it to the Fix Log above in 1–2 sentences; remove an entry once resolved.
- **Maintain this file every session** — current state + next focuses + fix log only. Push spec/decisions to their canonical homes (`History.md` / `Framework.md` / `Features/*`); never accumulate per-session work logs here unless double-checked for importance or the work is not yet completed.

#### Document pointers

- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Active plan → none. Relations Redesign complete — `Planning/Relations-Redesign-Plan.md` ready to archive to `Planning/Superseded/`.
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
