### Planning

Active plan documents live here. Completed plans move to `Superseded/` (preserved for posterity); a brief mention of the ship lands in `History.md`.

#### Active

- **`View-Settings-edit-properties-plan.md`** — APPROVED 2026-05-26. v0.3.1 ships properties end-to-end: schema CRUD via popover (Edit Properties pane Notion-format with chevron-push option editing + Duplicate/Delete footer) + dynamic property-value columns in all 4 storage detail-view Tables + click-to-edit popovers for all 11 property types + Property Visibility pane activated alongside. 25 tasks across 9 phases — each phase ships green standalone per quirk #8. Includes data layer additions (`DisplayVariant` / `dateFormat` / `singular` / `SavedView` real fields / `views[]` on Collections), three new chip primitives (`RelationChip` / `FileChip` / `LinkChip`), PropertyChipColor cleanup (12 cases / 10-color 5×2 selection grid), new manager methods (`updatePageProperty` / `updateItemProperty` / `duplicateProperty`), wires the existing-but-unused `RelationPicker` into PropertyEditorRow. **Use `superpowers:subagent-driven-development` to execute.**
- **`View-Settings-button-chrome-plan.md`** — Chrome-only first slice of the v0.3.1.x Storage View Redesign. Tasks 1-4 (button + popover shell + scope wiring + ContentView insertion) shipped 2026-05-25; **Task 5 (visual-approval smoke on all 9 surfaces) is the remaining open item** before retirement to Superseded. Will be moved to Superseded by Task 22 of the edit-properties plan.
- **`View-Settings-research-notes.md`** — Research findings (Notion UX patterns + SwiftUI primitives) — fed into both plans above; remains active for v0.3.1.2+ Sort / Filter / Group panes still ahead.

#### Superseded (shipped or no-longer-applicable)

- **`Superseded/2026-05-25-Items-Detail-Views-plan-COMPLETE.md`** — 11-task plan for the storage detail-view buildout (replace stubs + drag-reorder). Tasks 1-11 all shipped via parallel executor agents 2026-05-25 (commits `adcb66c` → `55bf8c3`). Plan documented for reference; will not be revisited.

#### Next plans likely to draft (after v0.3.1 ships)

- **v0.3.1.2 Sort pane** — per-view multi-criterion sort (Manual / Alphabetical / Reverse alphabetical and beyond). Wires to `SavedView.sort: [SortCriterion]?` Codable stubs already added in v0.3.1 Task 3.
- **v0.3.1.3 Filter pane** — minimum viable operators (equals / not-equals / contains / empty / not-empty) AND-grouped. Wires to `SavedView.filter: FilterGroup?` stubs.
- **v0.3.1.4 Group pane** — single-property group-by, may defer to v0.5.0 with Board view.
- **v0.3.1.5 update-on-existing-property gaps** — change-type + per-type-config edits on existing properties via `updateProperty(id:in:transform:)`; activate Property Visibility on `_modified_at`-aware reserved properties; relation cell edit if not full in v0.3.1.
- **v0.5.0** — non-Table view renderers (board/list/cards/gallery) on top of the now-populated `SavedView` storage.
