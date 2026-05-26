### Planning

Active plan documents live here. Completed plans move to `Superseded/` (preserved for posterity); a brief mention of the ship lands in `History.md`.

#### Active

- **`View-Settings-edit-properties-plan.md`** — SHIPPING 2026-05-26 (22 commits on `main` awaiting `git push`). Tasks 1-20 of 25 landed inline; Task 21 (PropertyEditorRow stub patches for relation/status/file in Item Window inspector) deferred to v0.3.1.1 — cell editor bypasses that dispatcher so headline UX shipped without it. Task 22 (this doc sweep) shipped. **Task 23 (`git push origin main` + Nexus mirror + plan retirement to Superseded) is the remaining auth-gated step.** Retire to `Superseded/2026-05-26-View-Settings-edit-properties-plan-COMPLETE.md` after push.
- **`View-Settings-button-chrome-plan.md`** — Chrome-only first slice of v0.3.1.x Storage View Redesign. Tasks 1-4 shipped 2026-05-25. Task 5 visual smoke implicitly covered by v0.3.1's full surface ship. **Retire to Superseded alongside the edit-properties plan at Task 23.**
- **`View-Settings-research-notes.md`** — Research findings (Notion UX patterns + SwiftUI primitives) — fed into both plans above; remains active for v0.3.1.2+ Sort / Filter / Group panes still ahead.

#### Superseded (shipped or no-longer-applicable)

- **`Superseded/2026-05-25-Items-Detail-Views-plan-COMPLETE.md`** — 11-task plan for the storage detail-view buildout (replace stubs + drag-reorder). Tasks 1-11 all shipped via parallel executor agents 2026-05-25 (commits `adcb66c` → `55bf8c3`). Plan documented for reference; will not be revisited.

#### Next plans likely to draft (queued behind v0.3.1)

- **v0.3.1.1 polish patch** — Task 21 (PropertyEditorRow stub patches for relation/status/file in Item Window inspector) + inline Relation cell editor (IndexQuery flow-through) + inline File cell editor (AttachmentManager flow-through) + SelectOptionsEditor + StatusGroupsEditor chevron-push refactor (lights up EditOptionPane via normal UX) + dual-relation reverse-mirror inside `updatePageProperty` + `updateItemProperty` + test coverage for the 11-type value-write paths. Test-runner stability investigation also lands here.
- **v0.3.1.2 Sort pane** — per-view multi-criterion sort. Wires `SavedView.sort: [SortCriterion]?` Codable stubs added in v0.3.1 Task 3.
- **v0.3.1.3 Filter pane** — equals / not-equals / contains / empty / not-empty operators; AND-grouped at first. Wires `SavedView.filter: FilterGroup?` stubs.
- **v0.3.1.4 Group pane** — single-property group-by; may defer to v0.5.0 alongside Board view.
- **v0.3.1.5 existing-property polish** — change-type + per-type-config edits on existing properties; relation scope reconfiguration via wizard inside the popover; Status per-group + per-option icons + Settings config (pre-v1 cleanup).
- **v0.5.0** — non-Table view renderers (board / list / cards / gallery) on top of the now-populated SavedView storage.
