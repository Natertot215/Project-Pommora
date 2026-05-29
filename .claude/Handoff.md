### Pommora — Session Handoff

 - **Read first at session start.** Current state + next focuses + fix log only. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

#### Current state (2026-05-28)

Working tree on `main`. The Relations Redesign is the active deliverable.

**Relations Redesign — Phases 0–14 + 16 SHIPPED to `main`; 17–22 remain. Phase 15 + the relation picker/chip UI are a parallel session's lane (see "Parallel-session division").** Subagent-driven execution: implementer writes → background `xcodebuild` verify → hand-review → commit; never commits red to `main`. **Read the plan's "Reconciliation pass" section first** (`// Planning//Relations-Redesign-Plan.md`) — it supersedes stale plan-body premises.

**Shipped (0–10):** foundational types (`ReservedPropertyID`/`ReservedTypeID`/`MigrationEvent`); `reverseName`/`reverseIcon` on `PropertyDefinition`; `BuiltInRelationProperties.merge` + `resolvedProperties(tierConfig:)` + `TierConfigManager` env injection (tier rows surface in the Type Settings list); `PropertyValue.relation` → `[String]` always-multi + `allowsMultiple` dropped; **tier value adapter** (`relationIDs`/`setRelationIDs` — the root↔property translator on all 4 entities); `RelationScope`→`RelationTarget` rename + Agenda cases + dual-key decode tolerance; `DualRelationCoordinator` supports Agenda targets + paired creation resolves all 4 target kinds (cross-side + Agenda); index layer (`@Observable PommoraIndex`, `entitiesByTarget`, `incomingRelations`, shared `RelationTargetKind` — incl. correct `target_kind` on incremental writes via `PropertyDefinition.indexConfigJSON`); **single-pane relation editor** (create/edit; home + mirror name + icon all persist; reverse name via the `reverseName` field) + retired `RelationPropertyWizard` (+ its protocol/mock). Phases 2 & 4 were found already-done in the live tree (rescoped/obsolete). Also landed: **XCTest launch-modal guard** (`NexusManager.loadOnLaunch` early-returns under test — fixed the test-host permission prompts + runner hangs; quirk #17) + CLAUDE.md quirks #17/#18.

**Shipped since (12–16):** 12 validator cascade (`validate(_:in:nexus:)`, retire Rule 6); 13 relation value picker on the shared ChipDropdown chrome; 14 `PropertyCellEditor` relation case → `RelationPicker`; 16 tier columns in Tables (read/write tier values via the Phase-6.5 adapter). **Remaining (17–22):** 17 — 17.1 env-injection OBSOLETE (index is param-threaded from `NexusManager.currentIndex`, not `@Environment`); 17.2 `LinkedFromDropdown` stub still to do; 18 Context-delete cascade (`unlinkTier` via the adapter, NOT `properties["_tierN"]`); 19 migration/adoption (**+ tier-label stale-default heal "Sub-topic(s)"→"Project(s)"**; Agenda `LegacyProperty` tolerance already covers old configs); 20 `tier_links` retirement (route tier-emit into `relations`, backfill, drop the table); 21 docs rewrite (forward-only); 22 deferred-items log. **Sequencing:** Phase 20's tier-emit-into-`relations` precedes Phase 18 — `unlinkTier` uses `incomingRelations` (queries `relations`), but tiers currently land only in `tier_links` (being fixed now).

> **⚠ Feature docs are mid-flight / OUTDATED.** `Features/*` specs (esp. `Properties.md`, `Pages.md`, `Contexts.md`, `Items.md`, `Agenda.md`, `PageTypes.md`) still describe the PRE-redesign Relations shape and stay outdated until **Phase 21** rewrites them. Until then trust the **code + the plan's Reconciliation pass** over the feature docs for anything Relations-related.

**Ratified this session (paradigm):** relations always-multi (single-pick dropped); deleting a Context auto-removes its tag (source-side cascade); Agenda Tasks/Events ARE relation targets in v1; flat value pickers (hierarchy deferred).

**Relation rendering (interim — this plan):** relations display as the target object's **icon + title in plain styled text, NOT chips** — in the value picker and every display surface. `RelationChip`'s pill body is a placeholder; icon + title is the current standard until a real relation chip is designed.

**Parallel-session division:** a separate session owns the relation picker/chip + display styling — `ChipDropdown` (`labelStyle`), `RelationPicker`, `RelationChip`, and the tier-row displays in PropertyPanel / PropertiesPulldown / FrontmatterInspector / ItemWindow / PropertyCellDisplay. This session owns the backend (validator, tier columns, cascade, migration, index, docs). Each lane stages only its own files.

**Intentionally deferred:** **relation chip visual design** (future — when designed, restyle the single `RelationChip` primitive; interim is icon + title plain text); source-side editing of an EXISTING relation's mirror name/icon (edit it from the target Type for now — create-side sets both fully); `LinkedFromDropdown` real Context-side surface (bare stub → future Context-views plan); hierarchical value pickers (post-v1).

#### Next focuses

1. **Relations Redesign execution** — Phases 0–14, 16 shipped + index tier-emit→`relations`/Agenda reconcile (`4ec3430`, `1f76f9b`) + **Phase 18b cascade CORE** (`393e2d8`): `unlinkTier(contextID:tier:index:)` on all 4 content managers (resolves each referencing entity via `IndexQuery.entityContainer` for Page/Item + flat-folder title derivation for Agenda → load → `setRelationIDs` remove → atomic save → re-upsert index), plus `IndexQuery.entityContainer`, `ReservedPropertyID.tierPropertyID`, `UnlinkTierTests` (7, green). Co-developed with the parallel session (it did the Page side + index helpers; this session did Item/Agenda + tests). **Next: Phase 18c — make the cascade LIVE** (the `unlinkTier` methods exist but nothing calls them yet). In the `SidebarView` sub-view holding `confirmationButtons` (env at `SidebarView` ~:4-9 — has SpaceManager/TopicManager/PageTypeManager/ItemTypeManager/PageContentManager/SettingsManager), ADD `@Environment` for `ItemContentManager`/`AgendaTaskManager`/`AgendaEventManager`/`NexusManager` (sibling sub-views already inject them, so it's safe), and in each delete `Task` call `unlinkTier` on ALL 4 content managers (pass `nexusManager.currentIndex`, guard non-nil; DRY into a helper) BEFORE the Context file delete: deleteSpace→tier 1, deleteTopic→tier 2, deleteProject→tier 3. **Nuance:** Topic "Delete All" (`promotingProjects: false`) ALSO deletes child Projects → unlink tier 3 for each (list them via TopicManager BEFORE the delete). Ordering: unlink MUST precede the Context delete (else `incomingRelations` no longer finds the refs). Then 19 migration (LARGE — 12 tasks), 20 finalize (`tier_links` drop), 21 docs, 22 deferred-log. **Parallel-session note:** the other session is co-developing the cascade BACKEND too (it owns `SidebarView`-adjacent + cascade files now) — coordinate before touching `SidebarView`/cascade. Pending fixes: legacy-sheet Relation dead-end (Fix Log #10); edit-side relation mirror name/icon (parallel-adjacent).
2. **Item Windows** — build the real Item Window (in-window property editing was deferred off the placeholder).
3. **Page Previews** — standalone-window page preview (cross-feature PreviewWindow primitive).

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
10. **Relation-add dead-end in legacy sheets.** Picking "Relation" in the Vault/Type Settings sheets (the context-menu schema editors) now silently cancels — relations are created via the View Settings popover editor. Hide the Relation option in those sheets (or route it to the editor) so it isn't a no-op. (Introduced retiring the wizard, Phase 10.4.)

#### Handoff Rules

- **Keep the Fix Log current.** When an issue is acknowledged but not yet fixed, add it to the Fix Log above in 1–2 sentences; remove an entry once resolved. 
- **Maintain this file every session** — current state + next focuses + fix log only. Push spec/decisions to their canonical homes (`History.md` / `Framework.md` / `Features/*`); never accumulate per-session work logs here unless double-checked for importance or the work is not yet completed. 

#### Document pointers

- Roadmap → `Framework.md` · decisions + ship log → `History.md` · PRD → `PommoraPRD.md`
- Active plan → `Planning/Relations-Redesign-Plan.md`
- Properties spec → `Features/Properties.md` · per-entity specs → `Features/*.md`
- CRUD → `Guidelines/CRUD-Patterns.md` · paradigm registry → `Guidelines/Paradigm-Decisions.md`
- Branch quirks + hard rules → `CLAUDE.md`
- Figma (property editor) → `https://www.figma.com/design/V3wKMilXkoceCL1Q2J9kf4/Pommora-Swift?node-id=474-9432`
