### Pommora — Session Handoff

 - **Read first at session start.** Current state + next focuses + fix log only. Shipped history → `History.md`; roadmap → `Framework.md`; branch quirks + hard rules → `CLAUDE.md`; locked decisions → `History.md` + `Guidelines/Paradigm-Decisions.md`.

#### Current state (2026-05-28)

Working tree on `main`. The Relations Redesign is the active deliverable.

**Relations Redesign — Phases 0–16 + 18 SHIPPED to `main`; relation rendering = plain icon+title (done, `88911fe`). Remaining: 17 (just the `LinkedFromDropdown` stub — 17.1 env-inject is OBSOLETE, index is param-threaded), 19 migration (LARGE — 12 tasks), 20 finalize (`tier_links` drop), 21 docs, 22 deferred-log; + fixes #23 (legacy-sheet Relation dead-end) / #24 (edit-side mirror). ONE session owns all of it (no parallel session — see note below).** Subagent-driven execution: implementer writes → background `xcodebuild` verify → hand-review → commit; never commits red to `main`. **Read the plan's "Reconciliation pass" section first** (`// Planning//Relations-Redesign-Plan.md`) — it supersedes stale plan-body premises.

**Shipped (0–10):** foundational types (`ReservedPropertyID`/`ReservedTypeID`/`MigrationEvent`); `reverseName`/`reverseIcon` on `PropertyDefinition`; `BuiltInRelationProperties.merge` + `resolvedProperties(tierConfig:)` + `TierConfigManager` env injection (tier rows surface in the Type Settings list); `PropertyValue.relation` → `[String]` always-multi + `allowsMultiple` dropped; **tier value adapter** (`relationIDs`/`setRelationIDs` — the root↔property translator on all 4 entities); `RelationScope`→`RelationTarget` rename + Agenda cases + dual-key decode tolerance; `DualRelationCoordinator` supports Agenda targets + paired creation resolves all 4 target kinds (cross-side + Agenda); index layer (`@Observable PommoraIndex`, `entitiesByTarget`, `incomingRelations`, shared `RelationTargetKind` — incl. correct `target_kind` on incremental writes via `PropertyDefinition.indexConfigJSON`); **single-pane relation editor** (create/edit; home + mirror name + icon all persist; reverse name via the `reverseName` field) + retired `RelationPropertyWizard` (+ its protocol/mock). Phases 2 & 4 were found already-done in the live tree (rescoped/obsolete). Also landed: **XCTest launch-modal guard** (`NexusManager.loadOnLaunch` early-returns under test — fixed the test-host permission prompts + runner hangs; quirk #17) + CLAUDE.md quirks #17/#18.

**Shipped since (12–16):** 12 validator cascade (`validate(_:in:nexus:)`, retire Rule 6); 13 relation value picker on the shared ChipDropdown chrome; 14 `PropertyCellEditor` relation case → `RelationPicker`; 16 tier columns in Tables (read/write tier values via the Phase-6.5 adapter). **Remaining (17–22):** 17 — 17.1 env-injection OBSOLETE (index is param-threaded from `NexusManager.currentIndex`, not `@Environment`); 17.2 `LinkedFromDropdown` stub still to do; 18 Context-delete cascade (`unlinkTier` via the adapter, NOT `properties["_tierN"]`); 19 migration/adoption (**+ tier-label stale-default heal "Sub-topic(s)"→"Project(s)"**; Agenda `LegacyProperty` tolerance already covers old configs); 20 `tier_links` retirement (route tier-emit into `relations`, backfill, drop the table); 21 docs rewrite (forward-only); 22 deferred-items log. **Sequencing:** Phase 20's tier-emit-into-`relations` precedes Phase 18 — `unlinkTier` uses `incomingRelations` (queries `relations`), but tiers currently land only in `tier_links` (being fixed now).

> **⚠ Feature docs are mid-flight / OUTDATED.** `Features/*` specs (esp. `Properties.md`, `Pages.md`, `Contexts.md`, `Items.md`, `Agenda.md`, `PageTypes.md`) still describe the PRE-redesign Relations shape and stay outdated until **Phase 21** rewrites them. Until then trust the **code + the plan's Reconciliation pass** over the feature docs for anything Relations-related.

**Ratified this session (paradigm):** relations always-multi (single-pick dropped); deleting a Context auto-removes its tag (source-side cascade); Agenda Tasks/Events ARE relation targets in v1; flat value pickers (hierarchy deferred).

**Relation rendering (interim — this plan):** relations display as the target object's **icon + title in plain styled text, NOT chips** — in the value picker and every display surface. `RelationChip`'s pill body is a placeholder; icon + title is the current standard until a real relation chip is designed.

**No parallel session (corrected 2026-05-29):** earlier uncommitted changes attributed to a "parallel session" were actually THIS session's own work — pre-compact leftovers + partially-applied edits from dispatches that looked rejected + small helper edits. There is ONE session; it owns EVERYTHING — backend AND the relation picker/chip rendering + the display surfaces (`ChipDropdown`, `RelationPicker`, `RelationChip`, PropertyPanel/PropertiesPulldown/FrontmatterInspector/ItemWindow/PropertyCellDisplay). Interim relation rendering (Nathan): object **icon + title plain text, NOT chips** — `ChipDropdown.labelStyle` (`.plainText`) scaffolding shipped (`8277b5b`) but the picker still renders `RelationChip` rows; wiring the picker/display to plain icon+title is an open task (full RelationChip pill design deferred until designed).

**Intentionally deferred:** **relation chip visual design** (future — when designed, restyle the single `RelationChip` primitive; interim is icon + title plain text); source-side editing of an EXISTING relation's mirror name/icon (edit it from the target Type for now — create-side sets both fully); `LinkedFromDropdown` real Context-side surface (bare stub → future Context-views plan); hierarchical value pickers (post-v1).

#### Next focuses

1. **Relations Redesign execution** — Phase 18 cascade fully shipped (`393e2d8` core + `f244674` live-wiring); relation rendering = plain icon+title (`88911fe`); index tier-emit→`relations` + Agenda reconcile (`4ec3430`, `1f76f9b`). **Next: Phase 19 — Migration + Adoption (LARGE, ~12 tasks)** per `// Planning//Relations-Redesign-Plan.md`: value-shape wrap (single `$rel`→array), `allows_multiple` strip, `relation_scope`→`relation_target` on-disk key rename, `page_collection`/`item_collection`→parent type via a Collection-parent map, `context_tier`-scoped-property drop (with explicit `AdoptionPreviewView` acknowledgment — the only lossy event), Agenda `LegacyProperty` read-tolerance confirm, **+ a tier-label stale-default heal `Sub-topic(s)`→`Project(s)` guarded to the exact old default**, broaden `needsMigration` (detect legacy field names; bump schemaVersion→2), surface all `MigrationEvent` kinds in `AdoptionPreviewView`. High-stakes (data migration on a real nexus) — verify with strong adoption tests. Then 20 finalize (`tier_links` DDL drop — emit already routes tiers into `relations`; a full rebuild backfills), 21 docs (forward-only rewrite per the Rewrite Rule), 22 deferred-log. Open fixes: 17.2 `LinkedFromDropdown` stub; legacy-sheet Relation dead-end (Fix Log #10); edit-side relation mirror name/icon.
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
