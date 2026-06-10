## Contexts Decoupling — Spec

Ratified via brainstorming 2026-06-10. Strips the Topic→Project containment and resets context→context relations to zero: Spaces, Topics, and Projects become three structurally identical, free-standing tiers. The future relation layer (contexts linking upward via their settings, page roll-up) is intentionally out of scope — it gets its own brainstorming and spec later; this branch strips and disconnects first so that layer can be designed fresh.

### Locked Decisions

1. **Projects are free-standing tier-3 contexts** — no containment, no parent requirement, no formal restriction to Topics.
2. **Context→context relations fully reset.** `parents` (Topic + Project), `project_links`, `project_order`, parent validation, the Edit Parents sheet, parent-space dots, and Project→Topic promotion are all deleted. The relation layer returns in a later design pass, edited via each context's settings surface.
3. **All three tiers are folders with config sidecars** (future-proofing for member files): `_space.json` / `_topic.json` / `_project.json`. Spaces change shape from flat `<Title>.space.json` files to folders.
4. **`blocks` stays** on all three schemas as an empty array; the composed-blocks surface is designed later. `ContextBlock` is shared with Homepage and survives regardless.
5. **Three sibling managers** — a new `ProjectManager` beside `SpaceManager` / `TopicManager`; no unified ContextManager.
6. **Sidebar: tier disclosure rows.** Spaces / Topics / Projects each render as a disclosure row (`square.grid2x2`), expand/collapse only, with flat leaf children.
7. **No migration.** Greenfield — zero configured contexts exist.
8. **Untouched:** pages' `tier1`/`tier2`/`tier3` frontmatter links, `BuiltInContextLinkProperties`, ContextPicker, the `context_links` index table, cascade unlink on delete, and the settings-renameable tier labels.
9. **Docs rewritten at branch end** as spec-style locked statements, not change narrative.

### On-Disk Model

```
.nexus//
  spaces//<Title>//_space.json       id, tier 1, color, icon, blocks, modified_at
  topics//<Title>//_topic.json       id, tier 2, icon, blocks, modified_at
  projects//<Title>//_project.json   id, tier 3, icon, blocks, modified_at
```

- Filename = title: the folder name is the title; rename = folder rename. No `title` field.
- Removed fields: Topic `parents` + `project_order`; Project `parents` + `project_links`. No fields added.
- Mirrors the vault pattern (folder + `_pagetype.json` sidecar) — contexts and vaults now share one structural idiom.

### Managers

- **ProjectManager (new):** clone of SpaceManager's shape — `loadAll` (folder scan + defensive index sync per quirk #14), `create`, `rename`, `delete`, `updateIcon`, `reorder` via a flat `OrderPersister` project order. Registered on `NexusEnvironment` (one stored property + one `.environment` line).
- **TopicManager:** deletes `projectsByParent`, `projects(in:)`, `createProject`, `renameProject`, `moveProject`, `deleteProject`, `updateProjectIcon`, `reorderProjects`, `promoteProjectToTopic`, and `updateTopicParents`; `loadAll` stops scanning for project files.
- **SpaceManager:** switches to the folder + `_space.json` layout.
- **NexusPaths:** `projectFileURL(forTitle:inTopicTitled:in:)` retired; symmetric per-tier folder/sidecar URL helpers across all three tiers.
- **NexusContext:** `lookupProject` becomes a flat array lookup.

### Index

- `contexts` table drops `parent_topic_id` and `idx_contexts_parent_topic` → schema v12, full regenerate (the index is disposable).
- IndexBuilder walks `spaces//`, `topics//`, `projects//` symmetrically.
- `context_links` (page→context) unchanged.

### Validators

- **ProjectValidator:** drops missing-parent, too-many-parents, parent-resolution, and folder-match checks; keeps title and file-shape checks, updated to the `_project.json` sidecar shape.
- **TopicValidator:** drops parent-resolution checks.
- Space validation updates to the new folder shape; validator status surfaces follow.

### Sidebar

- `SpacesSection` + `TopicsSection` are replaced by one headerless `Section` (ContextsSection) holding exactly three disclosure rows — homogeneous siblings (quirk #8); selection chrome stays at row-file level (quirk #9).
- **Tier row:** `DisclosureGroup`; label = `square.grid2x2` + the settings-renameable tier label; no `.tag` — never selectable, clicking anywhere toggles disclosure; right-click menu offers "New <Tier>"; hover "+" in the trailing slot with the same fade-in behavior the section headers had.
- **Children:** `SpaceRow` (visuals unchanged), `TopicRow` flattened (DisclosureGroup, chevron, `ParentSpaceTags`, and "Edit Parents" removed), `ProjectRow` (drops `parentTopic`). Per-tier `.onMove` reorder kept; creation keeps the `CreateWithInlineEdit` stub-and-rename flow.
- **Deletion:** a single "Delete" confirmation for all three tiers; cascade unlink of the tier's page links retained; the "Delete & Promote Projects" flow deleted. `EditTopicParentsSheet` and its `SidebarSheet` case deleted.
- `SavedSection`, `VaultsSection`, and user vault sections untouched.
- **Sidebar search bar removed.** The `SidebarSearchField` is a dead control — its bound query is consumed by nothing. The field, its dead state, and the `safeAreaInset` that spaced it above the first section all go; the sidebar's top edge starts at the pinned rows.

### Detail Pane

- `SidebarDetailView`: the Topic placeholder drops its "Parents: …" line (and `parentSpaceNames`); all three tiers render the same placeholder shape.

### Tests

- TopicManager project-CRUD suites become ProjectManager suites with flat semantics.
- Validator tests trim parent cases; add `_space.json` / `_project.json` shape coverage.
- `LoadAllIndexSyncTests` extends to projects.
- Sidebar verified by `xcodebuild test` actually bootstrapping (quirk #8); test filters must match `@Suite` names (quirk #1).

### Docs Phase (Branch End)

Rewrite as locked spec, not change narrative: `// Features//Contexts.md`, `PommoraPRD.md` (domain model, on-disk layout, SQLite schema), `Framework.md`, `// Features//Sidebar.md`; supersede entry in `// Guidelines//Paradigm-Decisions.md` for the retired containment decision; `History.md` entry on ship. The deferred relation/roll-up intent stays out of these docs until its own brainstorming logs it.

### Deferred — Future Brainstorming

- Context→context relation layer: Topics link to Spaces, Projects link to Topics and Spaces, edited via each context's settings surface.
- Transitive page roll-up (page → project → topic → space aggregation).
- Composed-blocks surfaces for contexts (the `blocks` field is inert until then).
