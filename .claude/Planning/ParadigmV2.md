### ParadigmV2 — Operational-Layer Domain Model Refactor

> **For agentic workers:** Use [[superpowers:subagent-driven-development]] (recommended) or [[superpowers:executing-plans]] to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. All dispatched agents use Opus 4.7. **All work happens in the Studio canonical files (`/Users/nathantaichman/The Studio/Projects/Project Pommora/`). No Nexus-first workflow.**

**Goal:** Refactor Pommora's operational layer from "kind-agnostic Vaults containing Pages + Items" to a symmetric model with distinct **Page side** (Page Type → Page Collection → Page `.md`) and **Item side** (Item Type → Item Collection → Item `.json`), split the Agenda into **Tasks** and **Events**, rename **Sub-topics → Projects**, and establish a **Settings scaffold** for user-overridable labels + accent color.

**Architecture:** Schema lives on the typed container (Page Type / Item Type), organization lives in the sub-folder layer (Page Collection / Item Collection). Schema sidecar files unify to `_schema.json` across all typed containers. Each entity-type pair (Pages, Items, Agenda) gets its own root-level wrapper folder (`<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`). The wrappers are disk-layout only — the sidebar renders Page Types / Item Types / Agenda Tasks / Agenda Events directly under section headings without a wrapper-folder row. **User-renameable labels** flow through a single SettingsManager so every UI label source is overridable.

**Tech Stack:** Swift 6 + SwiftUI + AtomicJSON + AtomicYAMLMarkdown + per-entity `@MainActor @Observable` managers. No new SPM deps.

**Execution sequence:** Docs first (directly in Studio), then foundational code (sidecar rename + struct renames), then per-subsystem refactors in dependency order, ending with user-data migration of Nathan's own Nexus.

---

#### Spec recap (the locked model)

##### The symmetric structure

| Layer | Pages side | Items side | Generic prose term |
|---|---|---|---|
| Schema-bearing container | **Page Type** (Swift: `PageType`) | **Item Type** (Swift: `ItemType`) | **Type** |
| Organizational sub-folder | **Page Collection** (Swift: `PageCollection`) | **Item Collection** (Swift: `ItemCollection`) — UI label: **"Set"** | **Collection** |
| Leaf file | **Page** (`.md`) | **Item** (`.json`) | (use specific) |

**Naming convention — three layers** (code is symmetric; UI vocabulary diverges per side):

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` / `ItemType` / `ItemCollection` — Swift type names, Codable field names, on-disk references. No `Pommora.X` qualification needed (every name is side-prefixed and unambiguous). |
| **Docs prose** | "Page Type" / "Item Type" / "Page Collection" / "Item Collection" when side-specific; "Type" / "Collection" as generic conceptual terms |
| **UI label (default)** | **"Vault"** / **"Collection"** (Pages-side); **"Type"** / **"Set"** (Items-side). All user-renameable via the Settings scaffold (Phase 7). |

The UI asymmetry is intentional: each side has one signature word and one shared word, so vocabulary diverges visibly between Pages-side and Items-side without echoing. Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". The code layer stays symmetric — only the UI labels diverge.

##### "Pommora" prohibited in on-disk schemas + Swift namespace qualifications

New paradigm rule: the brand name "Pommora" must NOT appear in:
- On-disk JSON field names (no `pommora_*` keys)
- Swift type qualifications used as a discriminator pattern (no `Pommora.X` workarounds for naming collisions; use side-prefixed names instead — e.g., `AgendaTask` rather than `Pommora.Task`)

Acceptable usage:
- Module name (`Pommora` is the Swift module — fundamental)
- App branding (window titles, About box)
- Doc references and code comments (descriptive prose)
- Existing `pommora_table_widths` frontmatter key in page editor — grandfathered for v0.3.0; address when Tables ship

This rule retires `Pommora.Collection` quirk #6 as part of ParadigmV2 (bare-unambiguous side-prefixed names need no qualification). Future schema additions follow the new rule.

##### On-disk shape

```
<nexus>/
  Pages/                                ← organizational wrapper, NOT shown as sidebar row
    Assignments/                        ← Page Type (folder name = Type title)
      _schema.json                      ← schema sidecar (carries properties, views, sort, ordering)
      Spring 2026/                      ← Page Collection (folder name = Collection title)
        _schema.json                    ← per-Collection metadata (id + ordering — schema inherited)
        Essay 1.md                      ← Page
      Final Project.md                  ← Page directly in Page Type (no Collection)
  Items/                                ← organizational wrapper, NOT shown as sidebar row
    Bookmarks/                          ← Item Type (folder name = Type title)
      _schema.json                      ← schema sidecar
      Tech/                             ← Item Collection (folder name = Collection title; UI label: "Set")
        _schema.json                    ← per-Collection metadata
        Swift evolution.json            ← Item
      Hacker News.json                  ← Item directly in Item Type (no Collection)
  Agenda/                               ← shown as sidebar section heading
    Tasks/
      _schema.json                      ← AgendaTask schema (EKReminder-aligned)
      Submit grant proposal.task.json
    Events/
      _schema.json                      ← AgendaEvent schema (EKEvent-aligned)
      Team standup.event.json
  .nexus/                               ← hidden config (unchanged location)
    settings.json                       ← NEW: user-overridable labels + accent (Phase 7)
    tier-config.json                    ← existing tier labels (unchanged)
    saved-config.json                   ← existing saved-section labels (unchanged)
    topics/                             ← Contexts tier 2 + tier 3 (Projects)
      Productivity/
        _topic.json
        Atomic Habits.project.json     ← renamed from .subtopic.json
    spaces/
      Personal.space.json
    homepage.json
```

##### Schema sidecar — unified filename, per-kind contents

Every typed container carries a `_schema.json` sidecar. The **filename** is what unifies — the **contents** differ per kind. Each Codable struct (`PageType`, `ItemType`, `PageCollection`, `ItemCollection`, `AgendaTaskSchema`, `AgendaEventSchema`) defines its own field set. The shared fields are `id`, `icon`, `properties`, `views`, `modified_at`; per-kind extras follow:

**Page Type — `<nexus>/Pages/<Title>/_schema.json`:**

```json
{
  "id": "01H...",
  "icon": "folder",
  "properties": [ /* PropertyDefinition[] */ ],
  "views": [],
  "modified_at": "2026-05-22T...",
  "collection_order": ["..."],
  "page_order": ["..."]
}
```

**Item Type — `<nexus>/Items/<Title>/_schema.json`:**

```json
{
  "id": "01H...",
  "icon": "tray.full",
  "properties": [ /* PropertyDefinition[] */ ],
  "views": [],
  "modified_at": "2026-05-22T...",
  "collection_order": ["..."],
  "item_order": ["..."],
  "template_config": null
}
```

`template_config` is reserved for the post-v1 per-Item-Type template feature (see [[Prospects]]); always `null` in v0.3.0.

**Page Collection — `<nexus>/Pages/<Type>/<Title>/_schema.json`:**

```json
{
  "id": "01H...",
  "type_id": "01H...",
  "modified_at": "2026-05-22T...",
  "page_order": ["..."]
}
```

Page Collections don't carry their own `properties` or `views` — schema is inherited from the parent Page Type.

**Item Collection — `<nexus>/Items/<Type>/<Title>/_schema.json`:**

```json
{
  "id": "01H...",
  "type_id": "01H...",
  "modified_at": "2026-05-22T...",
  "item_order": ["..."]
}
```

Same inheritance pattern as Page Collections — properties + views live on the parent Item Type.

Field name `type_id` is consistent across both Collection kinds — both sides reference their parent Type via the same key (the *target* type differs per side).

##### File extension summary

| Entity | Old (pre-ParadigmV2) | New |
|---|---|---|
| Page | `.md` | `.md` (unchanged) |
| Item | `.json` | `.json` (unchanged) |
| Page Type sidecar (was Vault) | `_vault.json` | **`_schema.json`** |
| Page Collection sidecar (was Collection) | `_collection.json` | **`_schema.json`** |
| Item Type sidecar | n/a — Items lived in Vaults | **`_schema.json`** (new file pattern) |
| Item Collection sidecar | n/a | **`_schema.json`** (new file pattern) |
| Agenda Task | `.agenda.json` (kind-conflated) | **`.task.json`** |
| Agenda Event | `.agenda.json` (kind-conflated) | **`.event.json`** |
| Task schema | `_agenda.json` (shared) | **`_schema.json`** (inside `Tasks/`) |
| Event schema | `_agenda.json` (shared) | **`_schema.json`** (inside `Events/`) |
| Sub-topic / Project | `.subtopic.json` | **`.project.json`** |
| Settings (new) | n/a | **`.nexus/settings.json`** |

##### Migration approach (Option γ — clean break, no in-app migration code)

Pommora has zero shipped users; Nathan is the only person with a real Nexus. Therefore:

- No in-app migration logic written.
- No "legacy mode" support — the new file shapes are the only shapes the new code understands.
- Nathan's own data (`/Users/nathantaichman/The Nexus/Pommora/`) is migrated via a one-shot script (Phase 10). The script is a one-time tool, not shipped with Pommora.
- Phase ordering ensures the in-app build is green at every commit — Nathan's data migration happens AFTER all code phases ship, so day-to-day usage stays unbroken.

##### Sidebar shape

Items section sits ABOVE Pages — Items are quicker-capture entities and benefit from sidebar prominence above the prose-heavy Pages side. Agenda has NO sidebar section — Agenda Tasks + Agenda Events surface via the Calendar pin entry (Calendar UI lands in a follow-up plan; data layer ships in v0.3.0).

```
Pinned (heading-less)            ← Homepage / Calendar / Recents
Spaces                           ← tier-1 Contexts (flat rows)
Topics                           ← tier-2 with chevron disclosure to Projects (tier-3)
Items                            ← section heading; Item Types directly underneath
  ├─ Bookmarks                   ← Item Type row (UI label: "Type"; chevron discloses Sets; Items NOT shown)
  │   └─ Tech                    ← Item Collection row (UI label: "Set")
  └─ Books
Pages                            ← section heading (renameable via Settings); Page Types directly underneath
  ├─ Assignments                 ← Page Type row (UI label: "Vault"; chevron discloses Collections + root Pages)
  │   └─ Spring 2026             ← Page Collection row (UI label: "Collection")
  │       └─ Essay 1             ← Page row (leaf)
  └─ Notes
```

Items do NOT appear as leaves in the sidebar — they live in detail-pane Tables under their Item Type. Agenda Tasks + Events live in the Calendar view, not the sidebar.

##### Code-level naming summary

Renamed Swift types (file rename + content update):
- `Vault.swift` → `PageType.swift`
- `VaultManager.swift` → `PageTypeManager.swift`
- `VaultValidator.swift` → `PageTypeValidator.swift`
- `VaultDetailView.swift` → `PageTypeDetailView.swift`
- `VaultRow.swift` → `PageTypeRow.swift`
- `NewVaultSheet.swift` → `NewPageTypeSheet.swift`
- `VaultView.swift` → `SavedView.swift` (struct represents saved view config — shared by Page Types AND Item Types; rename eliminates the "Vault" legacy)
- `Collection.swift` → `PageCollection.swift`
- `CollectionValidator.swift` → `PageCollectionValidator.swift`
- `CollectionRow.swift` → `PageCollectionRow.swift`
- `NewCollectionSheet.swift` → `NewPageCollectionSheet.swift`
- `CollectionDetailView.swift` → `PageCollectionDetailView.swift`
- `Subtopic.swift` → `Project.swift`
- `SubtopicValidator.swift` → `ProjectValidator.swift`
- `SubtopicRow.swift` → `ProjectRow.swift`
- `NewSubtopicSheet.swift` → `NewProjectSheet.swift`
- `ContentManager.swift` → `PageContentManager.swift`
- `ContentManager+CRUD.swift` → `PageContentManager+CRUD.swift`

New Swift types (created):
- `ItemType.swift` (parallel to PageType.swift)
- `ItemTypeManager.swift`
- `ItemTypeValidator.swift`
- `ItemTypeDetailView.swift`
- `ItemTypeRow.swift`
- `NewItemTypeSheet.swift`
- `ItemCollection.swift` (parallel to PageCollection.swift; bare-unambiguous, no qualifier)
- `ItemCollectionValidator.swift`
- `ItemCollectionDetailView.swift`
- `ItemCollectionRow.swift`
- `NewItemCollectionSheet.swift` (UI title reads from SettingsManager — defaults to "New Set")
- `ItemContentManager.swift`
- `ItemContentManager+CRUD.swift`
- `Settings.swift` (Phase 7)
- `SettingsManager.swift` (Phase 7)
- `SettingsScene.swift` (Phase 7)

Split Swift types (AgendaItem → two parallel structs; prefixed with `Agenda` to avoid `Task` / `Event` Swift stdlib collisions):
- `AgendaItem.swift` → split into `AgendaTask.swift` + `AgendaEvent.swift`
- `AgendaSchema.swift` → split into `AgendaTaskSchema.swift` + `AgendaEventSchema.swift`
- `AgendaManager.swift` → split into `AgendaTaskManager.swift` + `AgendaEventManager.swift`
- `AgendaValidator.swift` → split into `AgendaTaskValidator.swift` + `AgendaEventValidator.swift`

**Why `AgendaTask` / `AgendaEvent`?** Swift's `_Concurrency.Task` is in the standard library — a bare `struct Task` would shadow it. Per the "no `Pommora.X` qualification" rule, the alternative `Pommora.Task` is rejected; side-prefixed naming (`AgendaTask`) is the canonical pattern. UI labels remain "Task" and "Event" (renameable via Settings).

Retired Swift naming patterns:
- `Pommora.Collection` qualification (quirk #6) — no longer needed
- `Pommora.Set` qualification — never created
- `Vault` as a generic container term in code (refers exclusively to legacy/historical contexts after ParadigmV2)

---

#### Phase ordering + dependency graph

```
Phase 1 (Docs: Studio direct)                      ← independent; ships first
   │
   ├─→ Phase 2 (PageType + PageCollection renames)
   │      │
   │      ├─→ Phase 5 (New ItemType + ItemCollection subsystem)
   │      │      │
   │      │      └─→ Phase 6 (Pages/Items wrappers + NexusAdopter)
   │      │             │
   │      │             └─→ Phase 7 (Settings scaffold — storage + manager + label wiring)
   │      │                    │
   │      │                    └─→ Phase 8 (Sidebar/Detail/Sheet UI — reads labels from Settings)
   │      │
   │      └─→ Phase 8 (UI also depends on Phase 2 renames)
   │
   ├─→ Phase 3 (Subtopic → Project rename)         ← parallel to Phase 2
   │
   └─→ Phase 4 (AgendaItem split)                  ← parallel to Phase 2
                                                       │
                                                       └─→ Phase 8 (UI)

Phase 9 (Tests consolidation + Properties reconciliation)  ← rolling alongside each phase
Phase 10 (Nathan's user-data migration)                    ← AFTER all code green
Phase 11 (Cleanup + Framework reconciliation + ship)       ← FINAL
```

Phases 2 / 3 / 4 can ship in any order. Phase 5 depends on Phase 2. Phase 6 depends on Phase 5. Phase 7 depends on Phase 6 (Items/Pages wrappers must exist before Settings labels meaningfully attach to entity types). Phase 8 depends on Phases 2 + 4 + 5 + 7. Phase 10 depends on EVERYTHING.

---

### Phase 1 — Doc rewrites (Studio direct)

**Goal:** Update all `.claude/` docs to reflect ParadigmV2 — directly in the Studio canonical location. No Nexus-first sync workflow; Nathan can re-mirror to his Obsidian Nexus separately if/when he wants visual review there.

**Files affected:** `/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/` — `Features/`, `Guidelines/`, root docs.

#### Task 1.1 — Rewrite `Features/Domain-Model.md`

**Files:**
- Edit: `.claude/Features/Domain-Model.md`

- [ ] **Step 1: Update PARA mapping table** — rename tier-3 row "Sub-topics" to "Projects":

```markdown
| (workspace) | **Nexus** | Root |
| Areas | **Spaces** (tier 1) | Organization |
| Projects | **Topics** (tier 2) | Organization |
| (specifics) | **Projects** (tier 3) | Organization |
| Resources | **Page Types + Item Types + Agenda** | Operational |
```

PARA's "Projects" maps to Pommora tier-3 "Projects" — same word, intentional alignment.

- [ ] **Step 2: Rewrite Organization-layer Contexts section** — three tiers: Spaces / Topics / **Projects**. Tier-3 row in rules table updated. Sub-topic file extension → `.project.json`.

- [ ] **Step 3: Rewrite Operational-layer section** — replace the existing 3-row table with the symmetric model:

```markdown
##### Operational layer — Pages

| Entity | Role | On disk |
|---|---|---|
| **Page Type** | Schema-bearing container for Pages | `<nexus>/Pages/<Title>/_schema.json` |
| **Page Collection** | Organizational sub-folder inside a Page Type | `<nexus>/Pages/<Type>/<Title>/_schema.json` |
| **Page** | Markdown document with prose + frontmatter | `<nexus>/Pages/<Type>/<Collection>/Page.md` |

##### Operational layer — Items

| Entity | Role | On disk | Default UI label |
|---|---|---|---|
| **Item Type** | Schema-bearing container for Items | `<nexus>/Items/<Title>/_schema.json` | "Type" |
| **Item Collection** | Organizational sub-folder inside an Item Type | `<nexus>/Items/<Type>/<Title>/_schema.json` | **"Set"** |
| **Item** | Row-shaped JSON record with properties + 250-char description | `<nexus>/Items/<Type>/<Collection>/Item.json` | "Item" |

##### Operational layer — Agenda

| Entity | Role | On disk |
|---|---|---|
| **Agenda Task** | EKReminder-shaped: due date, completion, priority | `<nexus>/Agenda/Tasks/_schema.json` + `<title>.task.json` |
| **Agenda Event** | EKEvent-shaped: start + end, location | `<nexus>/Agenda/Events/_schema.json` + `<title>.event.json` |
```

- [ ] **Step 4: Add "Naming convention" sub-section**:

```markdown
##### Naming convention — three layers

Pommora's domain model has three layers of naming that intentionally diverge:

| Layer | Use |
|---|---|
| **Code + data** | `PageType` / `PageCollection` / `ItemType` / `ItemCollection` — always exact, side-prefixed, unambiguous. JSON keys, sidecar fields, file references all use these literal names. |
| **Docs prose** | "Type" + "Collection" as generic terms; "Page Type" / "Item Type" / etc. when side-specific |
| **UI label (default)** | Pages-side: "Type" + "Collection". Items-side: "Type" + **"Set"** (intentional divergence). All labels user-renameable via the Settings scaffold ([[Pommora.Settings.scaffold]] — Phase 7). |

The on-disk file shape is identical across sides (every typed container has a `_schema.json`); only the UI label and the Swift type differ.
```

- [ ] **Step 5: Update Linking model table** — rename `Sub-topic` references to `Project`; file path examples → `.project.json`.

- [ ] **Step 6: Update "Sidebar shape" sub-section** to the new sidebar layout (Pages / Items / Agenda as section headings; wrappers NOT shown as rows; Item Collections labeled "Set" in UI by default).

- [ ] **Step 7: Append "What changed (ParadigmV2)" bullet**:

```markdown
- **ParadigmV2 (2026-05-22)** — Operational layer made symmetric: Page Type + Page Collection on the Pages side; Item Type + Item Collection on the Items side. Agenda split into Tasks + Events (EKReminder vs EKEvent aligned). Schema sidecars unified to `_schema.json` across all typed containers. Sub-topics renamed to Projects. UI label divergence: Item Collections render as "Set" by default (renameable via Settings scaffold). "Pommora" prohibited in on-disk schemas + Swift namespace qualifications.
```

- [ ] **Step 8: Verify wikilinks** — `[[Vaults]]` references continue to resolve via the new stub created in Task 1.11.

#### Task 1.2 — Rename + rewrite `Features/Vaults.md` → `Features/PageTypes.md`

**Files:**
- Rename: `.claude/Features/Vaults.md` → `.claude/Features/PageTypes.md`
- Edit (new file): full content rewrite

- [ ] **Step 1: Rename file**:

```bash
mv "/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Features/Vaults.md" \
   "/Users/nathantaichman/The Studio/Projects/Project Pommora/.claude/Features/PageTypes.md"
```

- [ ] **Step 2: Rewrite intro**:

```markdown
### Page Types

The operational layer's **Pages-side** schema-bearing container. A Page Type is a folder containing a `_schema.json` sidecar that defines the property schema shared by every Page inside. Page Collections are organizational sub-folders within a Page Type (sharing the Type's schema; no schema of their own).

**UI label divergence:** Page Types render as **"Vault"** in the Pommora app by default; Page Collections render as **"Collection"**. (Doc prose continues to say "Page Type" / "Page Collection" for conceptual clarity — only the UI label diverges.) Both labels renameable via the Settings scaffold (Phase 7).

Items have a parallel structure on the Items side — see [[Items]] for **Item Type** (UI: "Type") and **Item Collection** (UI: "Set"). Each side has one signature UI word + one shared UI word — Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". In generic prose discussing properties or queries, the term "Type" covers both; "Collection" covers both.

Maps to PARA's "Resources" alongside Item Types and Agenda.
```

- [ ] **Step 3: Update Two-tier shape table** — "Vault" to "Page Type"; clarify Content is Pages-only.

- [ ] **Step 4: Update On-disk example block**:

```
<nexus-root>/
  Pages/
    Assignments/                      ← Page Type
      _schema.json                    ← shared schema sidecar
      Spring-2026/                    ← Page Collection
        _schema.json                  ← per-Collection metadata
        Essay-1.md                    ← Page
      Final-Project.md                ← Page directly in Page Type root
```

- [ ] **Step 5: Update `_schema.json` example block** — show Page Type schema fields (`collection_order`, `page_order`); remove any Items-related fields.

- [ ] **Step 6: Update Vault Settings sheet section** — rename to "Page Type Settings sheet"; update path references; UI text stays user-friendly ("Page Type Settings…").

- [ ] **Step 7: Rewrite "Content inside a Page Type" section**:

```markdown
##### Content inside a Page Type

Pages — `.md` files with YAML frontmatter; prose-bearing. See [[Pages]].

Items are NOT inside Page Types — they live on the Items side inside an [[Items|Item Type]] (the parallel schema-bearing container). The kind-agnostic Vault model from pre-ParadigmV2 is gone.

Tasks and Events live in `<nexus>/Agenda/Tasks/` and `<nexus>/Agenda/Events/` respectively — see [[Agenda]].
```

- [ ] **Step 8: Update Page Collections section** — Collections are Pages-only sub-folders inside Page Types. Sidecar filename `_schema.json`. Schema inherited from parent Page Type; the Collection's sidecar carries only `id` + `type_id` + ordering + `modified_at`.

- [ ] **Step 9: Update Adopting existing folders section** — top-level folders under `<nexus>/Pages/` with `_schema.json` are adopted as Page Types. Folders at nexus root outside `Pages/` are NOT adopted — the wrapper is required.

- [ ] **Step 10: Verify all wikilinks resolve.**

#### Task 1.3 — Rewrite `Features/Items.md`

**Files:**
- Edit: `.claude/Features/Items.md`

This doc covers BOTH the Item leaf format AND the Item Type / Item Collection container layer (asymmetric with Pages-side which splits Pages.md + PageTypes.md; Items leaf concerns are smaller).

- [ ] **Step 1: Update intro**:

```markdown
### Items

An Item is a **row-shaped record** stored as a `.json` file: properties + relations + a 250-char plain-text description, opened in an **Item Window** (popover, Calendar-event-detail pattern).

Items live inside an **Item Type** — the schema-bearing container parallel to a [[PageTypes|Page Type]] on the Pages side. **Item Collections** are organizational sub-folders inside an Item Type, parallel to Page Collections on the Pages side.

**UI label divergence:** the Pommora app renders Item Types as **"Type"** and Item Collections as **"Set"** by default — Items-side gets the generic word for container + distinctive word for sub-folder. The Pages-side inverts this: Page Types render as **"Vault"** (distinctive) and Page Collections as **"Collection"** (generic). Each side has one signature word + one shared word; the asymmetry visually reinforces which side you're on. Code, data, and on-disk references always say "ItemType" / "ItemCollection"; only the UI label diverges. All labels renameable via the Settings scaffold (Phase 7).

**Tasks and calendar events are NOT Items** — they are Agenda Tasks (`.task.json`, EKReminder-shaped) or Agenda Events (`.event.json`, EKEvent-shaped). See [[Agenda]]. (Agenda surfaces via the Calendar pin entry, not a dedicated sidebar section.)

In generic prose discussing properties or queries, the term "Type" covers both Page Type and Item Type; "Collection" covers both Page Collection and Item Collection.
```

- [ ] **Step 2: Add "Item Type + Item Collection" section** documenting the container layer (~150 words). Item Type = folder + `_schema.json`. Item Collection = sub-folder + `_schema.json` (id + type_id + ordering only; schema inherited). Quick-capture by Type ("New Bookmark"). Item Window opens an Item; properties inherited from parent Item Type.

- [ ] **Step 3: Update On-disk example block**:

```
<nexus-root>/
  Items/
    Bookmarks/                  ← Item Type
      _schema.json              ← shared schema sidecar
      Tech/                     ← Item Collection (UI label: "Set")
        _schema.json            ← per-Collection metadata
        Swift-evolution.json    ← Item
      Hacker-News.json          ← Item directly in Item Type root
```

- [ ] **Step 4: Update "When to use Items vs Pages vs Agenda" section** — replace "decide per-entry inside a Vault" framing with per-Type framing. Pick Type (Item Type vs Page Type) at creation.

- [ ] **Step 5: Update "Capabilities" section** — "parent Item Type's schema" replaces "parent Vault's schema." Item Collections are organizational only.

- [ ] **Step 6: Update "Constraints" section** — "An Item belongs to exactly one Item Type." Move-strip rule now applies cross-Item-Type.

- [ ] **Step 7: Add "Item Templates (reserved for post-v1)" section** — document `template_config` field on Item Type's `_schema.json`. v0.3.0 ships every Item with standard 250-char description; per-Type customization (window layout, character cap overrides, default description text) ships later.

- [ ] **Step 8: Update "Why Items exist" section**:

```markdown
#### Why Items exist as a separate paradigm from Pages

Notion conflates "row in a database" with "page with a body" — every database entry is a full page. Pommora keeps them as separate paradigms: **Items are pure rows** (properties + 250-char description, no Markdown body); **Pages are prose-bearing** (Markdown body + frontmatter properties). The parallel container structure (Item Type + Item Collection vs Page Type + Page Collection) means each side has its own schema mechanics without forcing one to absorb the other.

This:
- Keeps the nexus scannable — Item `.json` is small and EditorViewer-friendly
- Maps cleanly to cloud sync (parallel `items` / `pages` tables keyed by type ID)
- Preserves agent legibility (each Item is its own openable JSON file)
- Lets quick-capture scope to a Type ("New Bookmark") rather than to a container ("New Item in X Vault")
```

- [ ] **Step 9: Verify wikilinks.**

#### Task 1.4 — Rewrite `Features/Agenda.md`

**Files:**
- Edit: `.claude/Features/Agenda.md`

- [ ] **Step 1: Update intro**:

```markdown
### Agenda

The operational layer's calendar-anchored side. Splits into two distinct entity types:

- **Agenda Tasks** — EKReminder-aligned: due date (optional), completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` inside `<nexus>/Agenda/Tasks/`.
- **Agenda Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` inside `<nexus>/Agenda/Events/`.

Both share the property catalog used elsewhere (Number / Select / Status / Relation / etc.) and both carry `tier1` / `tier2` / `tier3` Context relations.

The split matches EventKit's own API split — separate access permissions, separate predicates, separate data models. EventKit sync at v0.6.0 maps each side cleanly: Agenda Task → EKReminder, Agenda Event → EKEvent.

In code, the Swift types are `AgendaTask` and `AgendaEvent` (prefixed to avoid `Task` / `Event` Swift stdlib collisions — per the ParadigmV2 "no Pommora.X qualification" rule). UI labels remain "Task" and "Event" by default (renameable via Settings).
```

- [ ] **Step 2: Update On-disk example**:

```
<nexus-root>/
  Agenda/
    Tasks/
      _schema.json                          ← AgendaTask schema
      Submit grant proposal.task.json
    Events/
      _schema.json                          ← AgendaEvent schema
      Team standup.event.json
```

- [ ] **Step 3: Rewrite "Schema" section** — split into "Agenda Task schema" + "Agenda Event schema" with separate field tables:

```markdown
##### Agenda Task schema (`<nexus>/Agenda/Tasks/_schema.json`)

Built-in (non-deletable) properties:
- `type` (Select) — Task type (Task / To-do / Phase / custom)
- `status` (Status, ships v0.3.0) — 3-group EventKit-aligned (Upcoming / In Progress / Done)

Built-in fields (not user-creatable):
- `due_at` (Date & Time, optional) — EKReminder.dueDateComponents
- `due_floating` (Bool) — true = no timezone
- `due_all_day` (Bool) — true = strip hour/minute/second
- `start_at` (Date & Time, optional) — EKReminder "not before"
- `completed` (Bool) — EKReminder.isCompleted
- `completed_at` (Date & Time, optional) — EKReminder.completionDate
- `priority` (Number 0-9) — EKReminder.priority
- `recurrence` — EKRecurrenceRule mirror
- `alarm_offsets` (Number[]) — negative seconds before due
- `tier1` / `tier2` / `tier3` — Context relations

##### Agenda Event schema (`<nexus>/Agenda/Events/_schema.json`)

Built-in (non-deletable) properties:
- `type` (Select) — Event type (Event / Meeting / Conference / custom)

Built-in fields (not user-creatable):
- `start_at` (Date & Time, required) — EKEvent.startDate
- `end_at` (Date & Time, required) — EKEvent.endDate
- `all_day` (Bool) — strip time
- `location` (String) — EKEvent.location
- `recurrence` — EKRecurrenceRule mirror
- `alarm_offsets` (Number[]) — negative seconds before start
- `alarm_absolute` (Date & Time[]) — fixed-time alarms
- `tier1` / `tier2` / `tier3` — Context relations

**Note:** Agenda Events do NOT carry `status` — completion isn't an event concept.
```

- [ ] **Step 4: Update "EventKit mapping" section** — split mapping table by file type.

- [ ] **Step 5: Update Item Window section** — same Item Window UX applies to AgendaTasks and AgendaEvents. Per-side UI variations ship with v0.3.1 redesign.

- [ ] **Step 6: Verify wikilinks.**

#### Task 1.5 — Rewrite `Features/Pages.md`

**Files:**
- Edit: `.claude/Features/Pages.md`

- [ ] **Step 1: Update intro**:

```markdown
### Pages

A Page is one Markdown file inside a [[PageTypes|Page Type]]. Pages are the only Markdown-file entity in Pommora and the only entity that holds prose content. A Page **belongs to one Page Type** (the Type whose folder it physically lives in). Pages conform to their Page Type's property schema.

The parallel Items-side entity is the Item — a row-shaped JSON record without body. See [[Items]] for details.
```

- [ ] **Step 2: Update tier reference language** — `[<subtopic-id>]` → `[<project-id>]`; "Sub-topics" → "Projects."

- [ ] **Step 3: Verify wikilinks.**

#### Task 1.6 — Rewrite `Features/Contexts.md`

**Files:**
- Edit: `.claude/Features/Contexts.md`

- [ ] **Step 1: Rename "Sub-topics" → "Projects"** globally, preserving case.

- [ ] **Step 2: Update on-disk file extension** — `.subtopic.json` → `.project.json`. Folder location stays.

- [ ] **Step 3: Update tier-config example** — singular/plural → "Project"/"Projects."

- [ ] **Step 4: Add "What changed (ParadigmV2)" section.**

- [ ] **Step 5: Verify wikilinks.**

#### Task 1.7 — Rewrite `Features/Properties.md`

**Files:**
- Edit: `.claude/Features/Properties.md`

- [ ] **Step 1: Update "Model" section** — schemas live in **a Type's `_schema.json`**. Replace "Vault" with "Type" in generic prose; "Page Type" / "Item Type" when side-specific.

- [ ] **Step 2: Update "Relation scope" section**:
  - `page_type(id)` (Pages-side container targets)
  - `item_type(id)` (Items-side container targets) — NEW
  - `page_collection(id)` (Pages-side sub-folder)
  - `item_collection(id)` (Items-side sub-folder) — NEW
  - `context_tier(N)` (unchanged)

Dual-relation mandatory for the four container/sub-folder scopes; one-way for `context_tier`.

- [ ] **Step 3: Update example `_vault.json` references** to `_schema.json`.

- [ ] **Step 4: Update "Where Status is built-in" section** — Status built-in on AgendaTask schema (required, EventKit-aligned). NOT on AgendaEvent schema. NOT auto-seeded on Page Types or Item Types (user adds via Settings).

- [ ] **Step 5: Verify wikilinks.**

#### Task 1.8 — Rewrite `Features/Architecture.md`

**Files:**
- Edit: `.claude/Features/Architecture.md`

- [ ] **Step 1: Update "What survives a rebuild" bullets** — file formats include `.task.json`, `.event.json`, `.project.json` (not `.subtopic.json` or `.agenda.json`). Schema sidecars unify to `_schema.json`.

- [ ] **Step 2: Update Domain model bullet**:

```markdown
- **Domain model** — 2-layer model with PARA-aligned naming: Contexts (Spaces tier 1 / Topics tier 2 / Projects tier 3) in the organization layer; **Page Types + Page Collections + Pages** on the Pages side, **Item Types + Item Collections + Items** on the Items side, and **Agenda Tasks + Agenda Events** as calendar-anchored entities in the operational layer; Homepage as singleton dashboard. Settings scaffold (`.nexus/settings.json`) provides per-Nexus user-overridable UI labels + accent color. UI label divergence: Item Collections render as "Set" by default.
```

- [ ] **Step 3: Update "Property type catalog" bullet** — schema substrate unifies; `PropertyDefinition` shape applied across Page Types, Item Types, AgendaTask schema, AgendaEvent schema.

- [ ] **Step 4: Add bullet** for the "no Pommora in on-disk schemas" rule under "Practical discipline":

```markdown
- **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for module name, app branding, and documentation; not allowed in JSON field names (`pommora_*`) or as a Swift type discriminator (`Pommora.X`). Side-prefixed names are the canonical pattern when collisions arise (e.g., `AgendaTask` not `Pommora.Task`).
```

- [ ] **Step 5: Verify wikilinks.**

#### Task 1.9 — Rewrite `Features/Prospects.md`

**Files:**
- Edit: `.claude/Features/Prospects.md`

- [ ] **Step 1: Update "Item ↔ Page promotion / demotion" Prospect** — promotion is now "Item under Item Type X" → "Page under Page Type Y." Strip-on-promote rule applies.

- [ ] **Step 2: Add "Item Templates" Prospect** — document per-Item-Type `template_config` (window layout, character cap, default description). Reserved in v0.3.0; UI ships post-v1.

- [ ] **Step 3: Add "Full Settings UI" Prospect** — Settings scaffold (Phase 7) ships storage + label wiring; full editing UI (accent color picker, label rename forms, tier-config consolidation) ships v0.6.0.

#### Task 1.10 — Rewrite `Features/Sidebar.md`

**Files:**
- Edit: `.claude/Features/Sidebar.md`

- [ ] **Step 1: Update top-level group list**:

```markdown
Five top-level groups (all labels renameable via Settings scaffold — Phase 7):
- **Pinned (heading-less, at top)** — Homepage / Calendar / Recents
- **Spaces** — flat rows for tier-1 Contexts
- **Topics** — chevron-disclosure for tier-2 with file-nested Projects (tier-3)
- **Items** (default label) — chevron-disclosure showing Item Types (UI label "Type"); each Type discloses Item Collections (UI label "Set")
- **Pages** (default label) — chevron-disclosure showing Page Types (UI label "Vault"); each Vault discloses Pages + Page Collections (UI label "Collection")
```

Items sits above Pages — quicker-capture entities ride higher in the visual hierarchy. Agenda Tasks + Agenda Events surface via the Calendar entry in the Pinned section, not via a dedicated sidebar heading. Calendar wires the Agenda data layer in a follow-up plan.

- [ ] **Step 2: Update right-click context menu table** — add entries for Item Type rows (no menus in v0.3.0; stub rows), Item Collection rows (same), Page Type rows ("New Collection" + "New Page" + "Rename" + "Delete"), Page Collection rows ("New Page" + "Rename" + "Delete"). NO Agenda menu rows.

- [ ] **Step 3: Add note about wrapper-folder visibility** — `<nexus>/Pages/`, `<nexus>/Items/`, and `<nexus>/Agenda/` folders NOT shown as sidebar rows; the section heading IS the visual representation for Pages + Items. Agenda has no sidebar visualization at all (Calendar pin shows it).

- [ ] **Step 4: Verify wikilinks.**

- [ ] **Step 5: Add a "v0.3.0 implementation status" note** at the bottom of Sidebar.md:

```markdown
> **v0.3.0 status:** The Pages-side ships fully designed per this spec — Page Type rows (labeled "Vault" by default), Page Collection rows, context menus, sheet wiring. The Items-side ships as minimal stubs: `ItemTypeRow` + `ItemCollectionRow` render as plain selectable rows (no context menus, no quick-actions). Click-through lands on a `ContentUnavailableView` placeholder; the Items table UI lands in a follow-up plan. Agenda has no sidebar section — Agenda Tasks + Agenda Events surface via the Calendar pin entry (data layer ships in v0.3.0; Calendar UI is a follow-up plan).
```

#### Task 1.11 — Update stubs + sweep-replace `[[Vaults]]` wikilinks

**Files:**
- Edit: `.claude/Features/Spaces.md`
- Edit: `.claude/Features/Collections.md`
- Sweep-edit: every `.claude/**/*.md` file containing `[[Vaults`

**Why no Vaults.md stub:** The pre-ParadigmV2 "Vault" concept is renamed, not aliased. Sweep-replacing `[[Vaults]]` references gives a cleaner repo state than leaving a redirect file. Future references should point at the right entity directly.

- [ ] **Step 1: Spaces.md stub** — no content changes needed (Spaces still tier-1 Contexts).

- [ ] **Step 2: Collections.md stub** — update redirect text:

```markdown
### Collections — see [[PageTypes|Page Types]] (for Pages) or [[Items]] (for Items)

Page Collections (Pages-side organizational sub-folders) → [[PageTypes]]. Item Collections (Items-side, UI label "Set" by default) → [[Items]]. In generic prose, "Collection" covers both.
```

- [ ] **Step 3: Sweep-replace `[[Vaults]]` wikilinks**:

```bash
grep -rn '\[\[Vaults' .claude --include='*.md'
```

For each match, replace with `[[PageTypes]]`, `[[Items]]`, or `[[PageTypes|Page Types]]` / `[[Items|Item Types]]` based on context. If a doc references the legacy kind-agnostic concept generically (rare), use `[[PageTypes]] / [[Items]]` to convey the split. Do NOT create a `Vaults.md` stub redirect file.

After the sweep, verify zero remaining matches:

```bash
grep -rn '\[\[Vaults' .claude --include='*.md' | grep -v 'History.md\|Planning/ParadigmV2.md'
```

Acceptable residuals: occurrences inside `History.md` (history entry quoting the old name) and inside `Planning/ParadigmV2.md` (this plan documenting the rename).

#### Task 1.12 — Update root docs

**Files:**
- Edit: `.claude/CLAUDE.md`
- Edit: `.claude/PommoraPRD.md`
- Edit: `.claude/Framework.md`
- Edit: `.claude/Handoff.md`
- Edit: `.claude/History.md`

- [ ] **Step 1: CLAUDE.md Overview section**:

```markdown
A simpler Notion that's also a more capable Obsidian. **2-layer PARA-aligned domain model**:

- **Organization layer — Contexts** (3 tiers): Spaces (1) / Topics (2) / **Projects** (3). All three are composed-blocks surfaces. Per-tier labels user-configurable per Nexus.
- **Operational layer — Items + Pages + Agenda**:
  - **Items** — `.json` files inside Item Types; Item Collections organize within. Items-side UI labels: **"Type"** + **"Set"**.
  - **Pages** — `.md` files inside Page Types; Page Collections organize within. Pages-side UI labels: **"Vault"** + **"Collection"**.
  - **Agenda** — split into Agenda Tasks (`.task.json`, EKReminder-shaped) and Agenda Events (`.event.json`, EKEvent-shaped). Data layer ships v0.3.0; sidebar surfacing is consolidated into the Calendar pin entry (no separate Agenda sidebar heading).
- **Singleton — Homepage**: composed-blocks dashboard at `.nexus/homepage.json`.
- **Settings scaffold** (`.nexus/settings.json`): per-Nexus user-overridable UI labels + accent color (Phase 7 — storage + label wiring; editing UI ships v0.6.0).

**Code layer is symmetric** (PageType / PageCollection / ItemType / ItemCollection — same shape, different content). **UI vocabulary diverges per side** — Pages get the distinctive "Vault" + generic "Collection"; Items get the generic "Type" + distinctive "Set". Each side has one signature word and one shared word. All UI labels renameable via Settings.
```

- [ ] **Step 2: CLAUDE.md "Files are canonical" bullet**:

```markdown
- **Files are canonical (≠ everything is Markdown).** Pages = `.md` (inside a Page Type's Page Collection sub-folder, or directly in a Page Type). Items = `.json` (inside an Item Type's Item Collection sub-folder, or directly in an Item Type). Page Type = folder + `_schema.json`; Item Type = folder + `_schema.json`. Page Collection / Item Collection = sub-folder + `_schema.json` (carries id + type_id + ordering). Agenda Tasks = `.task.json` inside `<nexus>/Agenda/Tasks/`. Agenda Events = `.event.json` inside `<nexus>/Agenda/Events/`. Projects (tier-3 Contexts) = `.project.json` inside `.nexus/topics/<TopicFolder>/`. Settings = `.nexus/settings.json` (Phase 7). SQLite is regeneratable index — no user data trapped in it.
```

- [ ] **Step 3: CLAUDE.md "Move-strip rule" bullet**:

```markdown
- **Move-strip rule.** Moving a Page across Page Types, or an Item across Item Types, strips properties not in the destination schema — Notion-style; no quarantine. Confirmation warning lists what's stripped. Within the same Page Type (between Page Collections) or same Item Type (between Item Collections), no strip — schema is shared. Cross-side promotion (Item ↔ Page) is a post-v1 Prospect.
```

- [ ] **Step 4: Add new Core Principle bullet** for the Pommora ban:

```markdown
- **"Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for the module name (`Pommora` Swift module), app branding, and documentation. NOT allowed in:
  - On-disk JSON field names (no `pommora_*` keys)
  - Swift type qualifications used as a discriminator pattern (no `Pommora.X` workarounds for stdlib collisions; use side-prefixed names like `AgendaTask` instead of `Pommora.Task`)

  Existing `pommora_table_widths` (page editor) is grandfathered for v0.3.0; rename when Tables ship.
```

- [ ] **Step 5: CLAUDE.md Document Map section** — update:
- Remove: `Vaults.md` from active doc list (renamed to `PageTypes.md`; no stub redirect kept)
- Add: `PageTypes.md` to active doc list
- Note Subtopic → Project rename
- Note `Settings.md` (new doc, optional — could combine with Architecture.md)

- [ ] **Step 6: CLAUDE.md "Active branch quirks" section** — mark quirk #6 retired:

```markdown
6. ~~**`Pommora.Collection` qualification** required~~ — **RETIRED in ParadigmV2.** `Collection` Swift struct renamed to `PageCollection`; new Items-side `ItemCollection` is bare-unambiguous. Quirk no longer applies.
```

- [ ] **Step 7: PommoraPRD.md** — update Storage Model + Cloud-sync mapping sections. Mirror Domain-Model.md structure.

- [ ] **Step 8: Framework.md "Current Focus" section** — append "ParadigmV2 in flight" note. Update v0.3.0 description.

- [ ] **Step 9: Handoff.md** — append "ParadigmV2 in progress" section pointing to this plan.

- [ ] **Step 10: History.md** — add new entry at the top:

```markdown
**ParadigmV2 (2026-05-22)** — Operational-layer domain model refactor. Vault becomes Pages-only as Page Type; Item Type introduced as parallel Items-side container; Page Collection (Pages) + Item Collection (Items) as parallel organizational sub-folders. AgendaItem split into AgendaTask + AgendaEvent (matching EKReminder + EKEvent). Sub-topics renamed to Projects. Schema sidecars unified to `_schema.json` across all typed containers. On-disk wrapper folders introduced: `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/`. UI label divergence locked: Item Collections render as "Set" by default; renameable via Settings. Settings scaffold (`.nexus/settings.json` + `SettingsManager` + label wiring across UI) lays groundwork for v0.6.0 Settings UI. New paradigm rule: "Pommora" prohibited in on-disk schemas + Swift namespace qualifications. Retires `Pommora.Collection` quirk #6. Plan: `// Planning//ParadigmV2.md`.
```

#### Task 1.13 — Update Guidelines docs

**Files:**
- Edit: `.claude/Guidelines/CRUD-Patterns.md`
- Edit: `.claude/Guidelines/Design.md`
- Edit: `.claude/Guidelines/Paradigm-Decisions.md`

- [ ] **Step 1: CRUD-Patterns.md** — rewrite the Codable entity load/save section:
- `Vault` → `PageType` in code examples
- `_vault.json` → `_schema.json` in example file paths
- Add parallel Item Type example

- [ ] **Step 2: CRUD-Patterns.md sheet enum example**:

```swift
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newProject(parent: Topic)
    case newPageType
    case newPageCollection(type: PageType)
    case newPage(collection: PageCollection?, type: PageType)
    case newItemType
    case newItemCollection(type: ItemType)
    case newItem(collection: ItemCollection?, type: ItemType)
    // No `newAgendaTask` / `newAgendaEvent` — Agenda has no sidebar entry;
    // Calendar plan adds its own sheet enum when it builds Agenda UI.
    case editTopicParents(Topic)
    case editIcon(IconTarget)
    case editColor(Space)
    ...
}
```

- [ ] **Step 3: CRUD-Patterns.md — drop quirk #6 section** — `Pommora.Collection` qualification retires; replace with a brief note that ParadigmV2 retired it.

- [ ] **Step 4: Paradigm-Decisions.md** — append new locked decisions:

```markdown
- **2026-05-22 — ParadigmV2 symmetric operational-layer model.** Vault becomes Pages-only as "Page Type" with sidecar renamed `_vault.json` → `_schema.json`. New "Item Type" struct parallels Page Type for the Items side; "Item Collection" parallels "Page Collection." Schema sidecars unify to `_schema.json` everywhere. Items move from `<vault>/<collection>/item.json` to `<nexus>/Items/<type>/<collection>/item.json`. AgendaItem splits into AgendaTask + AgendaEvent with separate file extensions and schemas. Sub-topics renames to Projects (`.subtopic.json` → `.project.json`). On-disk wrapper folders `<nexus>/Pages/` and `<nexus>/Items/` introduced. UI label divergence: Item Collections render as "Set" in the app; code and data always say "Collection"; both renameable via Settings scaffold. Retires Pommora.Collection quirk #6.

- **2026-05-22 — Agenda Task/Event split locked.** Agenda becomes two distinct entities: AgendaTask (EKReminder-shaped) and AgendaEvent (EKEvent-shaped). Separate file extensions, separate schemas, separate managers. Swift type names are `AgendaTask` and `AgendaEvent` (prefixed to avoid `_Concurrency.Task` and `Event` stdlib collisions); UI labels remain "Task" and "Event" by default.

- **2026-05-22 — "Pommora" prohibited in on-disk schemas + Swift namespace qualifications.** Brand name reserved for module name, app branding, documentation. NOT allowed in JSON field names or as a Swift type qualification (`Pommora.X`) workaround. Side-prefixed names are the canonical pattern for collision resolution. Existing `pommora_table_widths` (page editor) grandfathered for v0.3.0; rename when Tables ship.

- **2026-05-22 — Settings scaffold introduces `.nexus/settings.json` as the per-Nexus user-preference store.** Carries accent color + UI labels for all renameable surfaces (sidebar sections, Type labels, Collection labels per side, Project, AgendaTask, AgendaEvent). SettingsManager is the single read source for UI label sites — every label-rendering view reads from settingsManager.labels.X rather than hardcoded strings. Existing `.nexus/tier-config.json` and `.nexus/saved-config.json` stay separate (consolidation reserved for v0.6.0). Settings editing UI ships v0.6.0; v0.3.0 scope is storage + manager + label wiring + stub Settings scene reachable via Cmd+,.

- **2026-05-22 — UI label divergence locked.** Pages-side UI renders as **"Vault"** (PageType) / **"Collection"** (PageCollection). Items-side UI renders as **"Type"** (ItemType) / **"Set"** (ItemCollection). The code layer stays universally Type / Collection (PageType, PageCollection, ItemType, ItemCollection — no Swift renames). The asymmetry intentionally gives each side one signature word + one shared word, making the vocabulary visibly distinct without echoing across sides. Sidebar order locked: Items above Pages (quicker-capture entities ride higher).

- **2026-05-22 — Agenda has no dedicated sidebar section.** Agenda Tasks + Agenda Events surface via the Calendar pin entry, not a separate sidebar heading. Data layer (AgendaTask + AgendaEvent + their managers + on-disk shape) still ships v0.3.0; the Calendar UI that consumes them is a follow-up plan. The Phase 4 AgendaItem-split is unaffected by this decision.
```

- [ ] **Step 5: Verify wikilinks.**

#### Task 1.14 — Commit Phase 1 doc rewrites

**Files:**
- All edited files above

- [ ] **Step 1: Diff sanity check** — confirm internally consistent. Spot-check 3 docs visually.

- [ ] **Step 2: Verify build still passes** — `xcodebuild build` (docs don't affect compilation, but worth confirming no source file directly references a now-renamed doc):

```bash
cd "/Users/nathantaichman/The Studio/Projects/Project Pommora"
xcodebuild -scheme Pommora -destination 'platform=macOS' build
```

- [ ] **Step 3: Commit**:

```bash
git add .claude/
git status   # verify only doc changes staged
git commit -m "$(cat <<'EOF'
docs: ParadigmV2 model rewrite (PageType + ItemType + Agenda split)

Operational-layer domain model refactor:
- Vault becomes Pages-only as Page Type (Vaults.md → PageTypes.md;
  no stub redirect — [[Vaults]] wikilinks swept to [[PageTypes]] / [[Items]])
- New Item Type parallels Page Type for Items side
- Page Collection + Item Collection as parallel sub-folders (UI label
  "Set" by default for Item Collections; code always says "Collection")
- Schema sidecars unified to _schema.json everywhere
- AgendaItem splits into AgendaTask + AgendaEvent
- Sub-topics renamed to Projects (.subtopic.json → .project.json)
- Disk wrappers introduced: <nexus>/Pages/, <nexus>/Items/
- Settings scaffold introduced (.nexus/settings.json) for user-
  overridable labels + accent color
- "Pommora" prohibited in on-disk schemas + Swift namespace qualifications
- Pommora.Collection quirk #6 retires

Code implementation phases follow per ParadigmV2.md plan.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Phase 2 — Foundational code: Schema sidecar rename + PageType + PageCollection renames

**Goal:** Rename `_vault.json` → `_schema.json` for Vault and `_collection.json` → `_schema.json` for Collection. Rename `Vault` Swift struct to `PageType`. Rename `Collection` Swift struct to `PageCollection`. After this phase, Vaults are conceptually Page Types but Item Types don't exist yet (Phase 5).

#### Task 2.1 — Schema sidecar filename constants

**Files:**
- Modify: `Pommora/Pommora/AtomicIO/NexusPaths.swift`

- [ ] **Step 1: Locate the existing constants**:

```bash
grep -rn '"_vault\.json"\|"_collection\.json"' Pommora/Pommora --include='*.swift'
```

- [ ] **Step 2: Add new constants in NexusPaths.swift**:

```swift
extension NexusPaths {
    /// Unified schema sidecar filename — used by Page Types, Page Collections,
    /// Item Types, Item Collections, AgendaTask schema, AgendaEvent schema.
    /// Replaces per-kind names per ParadigmV2.
    static let schemaSidecarFilename = "_schema.json"
}
```

- [ ] **Step 3: Replace all `"_vault.json"` literals** with `NexusPaths.schemaSidecarFilename` in production code (NOT tests yet).

- [ ] **Step 4: Replace all `"_collection.json"` literals** with `NexusPaths.schemaSidecarFilename` in production code.

- [ ] **Step 5: Build verification** (delegate to builder agent):

```bash
xcodebuild -scheme Pommora -destination 'platform=macOS' build
```

- [ ] **Step 6: Skip test run for now** — tests reference old filenames; fixed in Task 2.2.

- [ ] **Step 7: Commit**:

```bash
git add Pommora/Pommora/
git commit -m "$(cat <<'EOF'
refactor(paradigmV2): unify schema sidecar filename to _schema.json

Adds NexusPaths.schemaSidecarFilename = "_schema.json" and replaces
all production-code occurrences of "_vault.json" and "_collection.json".

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

#### Task 2.2 — Update test fixtures for schema sidecar rename

- [ ] **Step 1: Find test sites + update each occurrence**:

```bash
grep -rn '"_vault\.json"\|"_collection\.json"' Pommora/PommoraTests --include='*.swift'
```

- [ ] **Step 2: Run test suite** (via builder agent; quirk #1 filename-form filters):

```bash
xcodebuild test -scheme Pommora -destination 'platform=macOS' -only-testing:PommoraTests
```

- [ ] **Step 3: Fix any failures + commit.**

#### Task 2.3 — Rename Vault → PageType

**Files:**
- Rename: `Pommora/Pommora/Vaults/Vault.swift` → `PageType.swift`
- Rename: `VaultManager.swift` → `PageTypeManager.swift`
- Rename: `VaultView.swift` → `SavedView.swift` (struct represents saved view config; shared by Page Types AND Item Types)
- Rename: `VaultValidator.swift` → `PageTypeValidator.swift`
- Rename: `VaultDetailView.swift` → `PageTypeDetailView.swift`
- Rename: `VaultRow.swift` → `PageTypeRow.swift`
- Rename: `NewVaultSheet.swift` → `NewPageTypeSheet.swift`

- [ ] **Step 1: Inventory grep**:

```bash
grep -rn '\bVault\b\|\bVaultManager\b\|\bVaultView\b\|\bVaultValidator\b\|\bVaultRow\b\|\bNewVaultSheet\b\|\bVaultDetailView\b' Pommora/Pommora --include='*.swift' | wc -l
```

- [ ] **Step 2: Rename + rewrite Vault.swift → PageType.swift**:

```bash
mv "Pommora/Pommora/Vaults/Vault.swift" "Pommora/Pommora/Vaults/PageType.swift"
```

Update the file:

```swift
import Foundation

/// Page Type — folder + `_schema.json` sidecar that defines the property
/// schema shared by every Page inside. The Pages-side schema-bearing container,
/// parallel to ItemType on the Items side (introduced Phase 5).
struct PageType: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var icon: String?
    var properties: [PropertyDefinition]
    var views: [SavedView]
    var modifiedAt: Date

    var collectionOrder: [String]?
    var pageOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case modifiedAt = "modified_at"
        case collectionOrder = "collection_order"
        case pageOrder = "page_order"
    }

    // Codable init + encoder — same pattern as old Vault.swift, types updated
}

extension PageType {
    static func load(from metadataURL: URL) throws -> PageType {
        var t = try AtomicJSON.decode(PageType.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 3: Rename + rewrite VaultManager.swift → PageTypeManager.swift**:

```bash
mv "Pommora/Pommora/Vaults/VaultManager.swift" "Pommora/Pommora/Vaults/PageTypeManager.swift"
```

In the file:
- `class VaultManager` → `class PageTypeManager`
- Internal mention of `Vault` (type) → `PageType`
- Method renames: `createVault` → `createPageType`, `renameVault` → `renamePageType`, `updateVaultIcon` → `updatePageTypeIcon`, `deleteVault` → `deletePageType`, `reorderVaults` → `reorderPageTypes`
- Storage: `vaults: [Vault]` → `types: [PageType]`, `collectionsByVault` → `collectionsByType`

- [ ] **Step 4: Rename VaultView.swift → SavedView.swift**:

```bash
mv "Pommora/Pommora/Vaults/VaultView.swift" "Pommora/Pommora/Vaults/SavedView.swift"
```

Update: `struct VaultView` → `struct SavedView`. Doc: "A saved view configuration — applies to Page Types and Item Types."

- [ ] **Step 5: Rename remaining files**:

```bash
mv "Pommora/Pommora/Validation/VaultValidator.swift" "Pommora/Pommora/Validation/PageTypeValidator.swift"
mv "Pommora/Pommora/Detail/VaultDetailView.swift" "Pommora/Pommora/Detail/PageTypeDetailView.swift"
mv "Pommora/Pommora/Sidebar/VaultRow.swift" "Pommora/Pommora/Sidebar/PageTypeRow.swift"
mv "Pommora/Pommora/Sidebar/Sheets/NewVaultSheet.swift" "Pommora/Pommora/Sidebar/Sheets/NewPageTypeSheet.swift"
```

Update each file's struct/class/view name + internal references.

- [ ] **Step 6: Sweep all other Swift files for `Vault` references**:

```bash
grep -rln '\bVault\b\|\bVaultManager\b\|\bVaultView\b\|\bVaultValidator\b\|\bVaultRow\b\|\bNewVaultSheet\b\|\bVaultDetailView\b' Pommora/Pommora --include='*.swift'
```

Update each file: `Vault` → `PageType`, `VaultView` → `SavedView`. Also sweep camelCase compounds like `pagesByVaultRoot` → `pagesByTypeRoot`, `inVaultRoot` → `inTypeRoot` (these don't match `\bVault\b` due to word boundary, so manual update needed).

- [ ] **Step 7: Build verification** (trust xcodebuild over SourceKit per quirk #3):

```bash
xcodebuild -scheme Pommora -destination 'platform=macOS' build
```

- [ ] **Step 8: Iterate until build succeeds + commit.**

#### Task 2.4 — Rename Collection → PageCollection

**Files:**
- Rename: `Collection.swift` → `PageCollection.swift`
- Rename: `CollectionValidator.swift` → `PageCollectionValidator.swift`
- Rename: `CollectionDetailView.swift` → `PageCollectionDetailView.swift`
- Rename: `CollectionRow.swift` → `PageCollectionRow.swift`
- Rename: `NewCollectionSheet.swift` → `NewPageCollectionSheet.swift`

- [ ] **Step 1: Inventory grep**:

```bash
grep -rn '\bPommora\.Collection\b\|\bCollection\b' Pommora/Pommora --include='*.swift' | head -40
```

- [ ] **Step 2: Rename + rewrite Collection.swift → PageCollection.swift**:

```bash
mv "Pommora/Pommora/Vaults/Collection.swift" "Pommora/Pommora/Vaults/PageCollection.swift"
```

In the file:
- `struct Collection` → `struct PageCollection`
- `var vaultID: String` → `var typeID: String` (parent is PageType)
- CodingKeys: `case vaultID = "vault_id"` → `case typeID = "type_id"`
- Drop `itemOrder` (Page Collections hold Pages only)
- `extension Collection` → `extension PageCollection`

- [ ] **Step 3: Rename remaining files** (CollectionValidator / CollectionDetailView / CollectionRow / NewCollectionSheet) + update internal references.

- [ ] **Step 4: Sweep `Pommora.Collection` + bare `Collection`**:

```bash
grep -rln '\bPommora\.Collection\b\|: Collection\b\|<Collection>\|in Collection\b' Pommora/Pommora --include='*.swift'
```

For each file:
- `Pommora.Collection` → `PageCollection`
- `: Collection` → `: PageCollection`
- `[Collection]` → `[PageCollection]`
- `[String: [Collection]]` → `[String: [PageCollection]]`

- [ ] **Step 5: Update CLAUDE.md quirk #6** (Studio side) — mark retired (parallel to Phase 1.12 Step 6 update).

- [ ] **Step 6: Build verification + commit.**

#### Task 2.5 — Update tests for PageType + PageCollection renames

- [ ] **Step 1: Find test sites**:

```bash
grep -rln '\bVault\b\|\bCollection\b\|\bPommora\.Collection\b' Pommora/PommoraTests --include='*.swift'
```

- [ ] **Step 2: Rename test files** + update content (class names, type refs, fixture data, field names vaultID → typeID).

- [ ] **Step 3: Run + commit.**

---

### Phase 3 — Subtopic → Project rename

**Goal:** Rename Subtopic to Project across code, on-disk file extension, and validators. Independent of Phase 2; can ship in parallel.

#### Task 3.1 — Rename Subtopic struct → Project

**Files:**
- Rename: `Subtopic.swift` → `Project.swift`
- Rename: `SubtopicRow.swift` → `ProjectRow.swift`
- Rename: `SubtopicValidator.swift` → `ProjectValidator.swift`
- Rename: `NewSubtopicSheet.swift` → `NewProjectSheet.swift`

- [ ] **Step 1: Inventory grep**:

```bash
grep -rn '\bSubtopic\b\|\bsubtopic\b' Pommora/Pommora --include='*.swift' | wc -l
```

- [ ] **Step 2: Rename Subtopic.swift → Project.swift + update content**:

```bash
mv Pommora/Pommora/Contexts/Subtopic.swift Pommora/Pommora/Contexts/Project.swift
```

Update: `struct Subtopic` → `struct Project`. File extension constant: `"subtopic.json"` → `"project.json"`.

- [ ] **Step 3: Rename remaining files** + update internal references.

- [ ] **Step 4: Update TopicManager.swift methods**:
- `createSubtopic` → `createProject`
- `renameSubtopic` → `renameProject`
- `deleteSubtopic` → `deleteProject`
- `moveSubtopic` → `moveProject`
- `subtopics(forTopicID:)` → `projects(forTopicID:)`
- State dict `subtopicsByParent` → `projectsByParent`

- [ ] **Step 5: Update Topic.swift** — change subtopic references to project.

- [ ] **Step 6: Update SidebarSheet enum** — `case newSubtopic(parent: Topic)` → `case newProject(parent: Topic)`. IconTarget enum: `case subtopic(Subtopic)` → `case project(Project)`.

- [ ] **Step 7: Update SidebarSelection / SelectionTag** — `.subtopic(id)` → `.project(id)`.

- [ ] **Step 8: Sweep all other call sites**:

```bash
grep -rln 'Subtopic\|subtopic' Pommora/Pommora --include='*.swift'
```

- [ ] **Step 9: Add to NexusPaths.swift**:

```swift
extension NexusPaths {
    static let projectFileExtension = "project.json"
}
```

Replace literal `"subtopic.json"` references.

- [ ] **Step 10: Build verification + commit.**

#### Task 3.2 — Update tests for Project rename

- [ ] **Step 1: Rename test files + update content** (same pattern as Phase 2.5).

- [ ] **Step 2: Run tests + commit.**

---

### Phase 4 — AgendaItem split into AgendaTask + AgendaEvent

**Goal:** Split unified `AgendaItem` struct into separate `AgendaTask` and `AgendaEvent` structs with distinct schemas, file extensions, managers. Each has only the fields semantically relevant to its kind.

**Critical naming note:** Swift's standard library has `_Concurrency.Task`. Per the "no `Pommora.X` qualification" paradigm rule, our Swift type is `AgendaTask` (side-prefixed). Same for `AgendaEvent`. UI labels remain "Task" and "Event."

#### Task 4.1 — Define AgendaTask + AgendaEvent structs

**Files:**
- Create: `Pommora/Pommora/Agenda/AgendaTask.swift`
- Create: `Pommora/Pommora/Agenda/AgendaEvent.swift`

- [ ] **Step 1: Create AgendaTask.swift**:

```swift
import Foundation

/// Agenda Task — EKReminder-aligned. Lives at `<nexus>/Agenda/Tasks/<title>.task.json`.
/// Has due date (optional), completion flag, priority, optional start ("not before") date.
///
/// Swift name prefixed (`AgendaTask`) to avoid `_Concurrency.Task` shadow per
/// the ParadigmV2 "no Pommora.X qualification" rule. UI label: "Task" (renameable).
struct AgendaTask: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var icon: String?
    var description: String

    // EKReminder fields
    var dueAt: Date?
    var dueFloating: Bool
    var dueAllDay: Bool
    var startAt: Date?
    var completed: Bool
    var completedAt: Date?
    var priority: Int

    var recurrence: Recurrence?
    var alarmOffsets: [TimeInterval]

    // Sync state
    var calendarID: String?
    var eventkitUUID: String?

    // Shared
    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var createdAt: Date
    var modifiedAt: Date
    var properties: [String: PropertyValue]

    enum CodingKeys: String, CodingKey {
        case id, icon, description, completed, priority, recurrence
        case tier1, tier2, tier3, properties
        case dueAt = "due_at"
        case dueFloating = "due_floating"
        case dueAllDay = "due_all_day"
        case startAt = "start_at"
        case completedAt = "completed_at"
        case alarmOffsets = "alarm_offsets"
        case calendarID = "calendar_id"
        case eventkitUUID = "eventkit_uuid"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    // Codable init + encoder — follow Item.swift pattern
}

extension AgendaTask {
    static func load(from url: URL) throws -> AgendaTask {
        var t = try AtomicJSON.decode(AgendaTask.self, from: url)
        let filename = url.lastPathComponent
        if filename.hasSuffix(".task.json") {
            t.title = String(filename.dropLast(".task.json".count))
        } else {
            t.title = url.deletingPathExtension().lastPathComponent
        }
        return t
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 2: Create AgendaEvent.swift** with parallel shape but EKEvent fields:

```swift
import Foundation

/// Agenda Event — EKEvent-aligned. Lives at `<nexus>/Agenda/Events/<title>.event.json`.
/// Has required start_at + end_at, location, all-day flag. NO completion concept.
struct AgendaEvent: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var icon: String?
    var description: String

    // EKEvent fields
    var startAt: Date
    var endAt: Date
    var allDay: Bool
    var location: String?
    var recurrence: Recurrence?
    var alarmOffsets: [TimeInterval]
    var alarmAbsolute: [Date]

    var calendarID: String?
    var eventkitUUID: String?

    var tier1: [String]
    var tier2: [String]
    var tier3: [String]
    var createdAt: Date
    var modifiedAt: Date
    var properties: [String: PropertyValue]

    enum CodingKeys: String, CodingKey {
        case id, icon, description, location, recurrence
        case tier1, tier2, tier3, properties
        case startAt = "start_at"
        case endAt = "end_at"
        case allDay = "all_day"
        case alarmOffsets = "alarm_offsets"
        case alarmAbsolute = "alarm_absolute"
        case calendarID = "calendar_id"
        case eventkitUUID = "eventkit_uuid"
        case createdAt = "created_at"
        case modifiedAt = "modified_at"
    }

    // Codable init + encoder — follow AgendaTask.swift pattern
}

extension AgendaEvent {
    static func load(from url: URL) throws -> AgendaEvent {
        var e = try AtomicJSON.decode(AgendaEvent.self, from: url)
        let filename = url.lastPathComponent
        if filename.hasSuffix(".event.json") {
            e.title = String(filename.dropLast(".event.json".count))
        } else {
            e.title = url.deletingPathExtension().lastPathComponent
        }
        return e
    }

    func save(to url: URL) throws {
        try AtomicJSON.write(self, to: url)
    }
}
```

- [ ] **Step 3: Add file extension constants + agenda path helpers to NexusPaths.swift**:

```swift
extension NexusPaths {
    static let taskFileExtension = "task.json"
    static let eventFileExtension = "event.json"

    static func agendaWrapperDir(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent("Agenda")
    }
    static func tasksDir(in nexus: Nexus) -> URL {
        agendaWrapperDir(in: nexus).appendingPathComponent("Tasks")
    }
    static func eventsDir(in nexus: Nexus) -> URL {
        agendaWrapperDir(in: nexus).appendingPathComponent("Events")
    }
    static func taskFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        tasksDir(in: nexus).appendingPathComponent("\(title).\(taskFileExtension)")
    }
    static func eventFileURL(forTitle title: String, in nexus: Nexus) -> URL {
        eventsDir(in: nexus).appendingPathComponent("\(title).\(eventFileExtension)")
    }
}
```

- [ ] **Step 4: Build verification + commit.**

#### Task 4.2 — Define AgendaTaskSchema + AgendaEventSchema

**Files:**
- Create: `AgendaTaskSchema.swift`
- Create: `AgendaEventSchema.swift`

- [ ] **Step 1: Create AgendaTaskSchema.swift**:

```swift
import Foundation

/// `_schema.json` for `<nexus>/Agenda/Tasks/`. Defines built-in `type` property
/// + user-defined additions + saved views.
///
/// Status property will be added in Phase 9.2 (v0.3.0 reconciliation) once
/// PropertyDefinition.StatusGroup exists.
struct AgendaTaskSchema: Codable, Equatable, Hashable, Sendable {
    var schemaVersion: Int
    var icon: String?
    var properties: [Property]
    var views: [SavedView]
    var modifiedAt: Date

    struct Property: Codable, Equatable, Hashable, Sendable {
        var name: String
        var type: PropertyType
        var options: [PropertyDefinition.SelectOption]?
        var builtin: Bool
        var defaultValue: String?

        enum CodingKeys: String, CodingKey {
            case name, type, options, builtin
            case defaultValue = "default"
        }
    }

    static func defaultSeed() -> AgendaTaskSchema {
        AgendaTaskSchema(
            schemaVersion: 1,
            icon: "checkmark.circle",
            properties: [
                Property(
                    name: "type",
                    type: .select,
                    options: [
                        .init(value: "Task", label: "Task", color: .blue),
                        .init(value: "To-Do", label: "To-Do", color: .yellow),
                        .init(value: "Phase", label: "Phase", color: .purple),
                    ],
                    builtin: true,
                    defaultValue: "Task"
                ),
                // Status seeding deferred to Phase 9.2 (v0.3.0 reconciliation)
            ],
            views: [],
            modifiedAt: Date()
        )
    }
}
```

- [ ] **Step 2: Create AgendaEventSchema.swift** with parallel shape; NO Status (events don't carry completion).

- [ ] **Step 3: Build + commit.**

#### Task 4.3 — Split AgendaManager into AgendaTaskManager + AgendaEventManager; delete legacy

**Files:**
- Create: `AgendaTaskManager.swift`
- Create: `AgendaEventManager.swift`
- Create: `AgendaTaskValidator.swift`
- Create: `AgendaEventValidator.swift`
- Delete: `AgendaItem.swift`, `AgendaSchema.swift`, `AgendaManager.swift`, `AgendaValidator.swift`

- [ ] **Step 1: Create AgendaTaskManager.swift** mirroring the existing AgendaManager pattern but typed on AgendaTask only. Full load + CRUD methods.

- [ ] **Step 2: Create AgendaEventManager.swift** with parallel shape on AgendaEvent.

- [ ] **Step 3: Create AgendaTaskValidator + AgendaEventValidator** — split the old AgendaValidator.

- [ ] **Step 4: Update ContentView's manager construction** — instantiate AgendaTaskManager + AgendaEventManager. Remove AgendaManager.

- [ ] **Step 5: Update every call site of the old types**:

```bash
grep -rln '\bAgendaItem\b\|\bAgendaSchema\b\|\bAgendaManager\b\|\bAgendaValidator\b' Pommora/Pommora --include='*.swift'
```

- [ ] **Step 6: Delete legacy files**:

```bash
rm Pommora/Pommora/Agenda/AgendaItem.swift
rm Pommora/Pommora/Agenda/AgendaSchema.swift
rm Pommora/Pommora/Agenda/AgendaManager.swift
rm Pommora/Pommora/Validation/AgendaValidator.swift
```

- [ ] **Step 7: Build + commit.**

#### Task 4.4 — Update Agenda tests for split

- [ ] **Step 1: Split AgendaItem*Tests.swift into AgendaTask*Tests.swift + AgendaEvent*Tests.swift.**

- [ ] **Step 2: Run tests + commit.**

---

### Phase 5 — New ItemType + ItemCollection subsystem

**Goal:** Introduce the Items-side container structures parallel to PageType / PageCollection.

**Depends on:** Phase 2.

#### Task 5.1 — Define ItemType struct

**Files:**
- Create: `Pommora/Pommora/Items/` folder
- Create: `Pommora/Pommora/Items/ItemType.swift`

- [ ] **Step 1: Create folder + ItemType.swift**:

```bash
mkdir -p Pommora/Pommora/Items
```

```swift
import Foundation

/// Item Type — folder + `_schema.json` sidecar that defines the property
/// schema shared by every Item inside. The Items-side schema-bearing container,
/// parallel to PageType on the Pages side.
struct ItemType: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var title: String
    var icon: String?
    var properties: [PropertyDefinition]
    var views: [SavedView]
    var templateConfig: ItemTemplateConfig?
    var modifiedAt: Date

    var collectionOrder: [String]?
    var itemOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id, icon, properties, views
        case templateConfig = "template_config"
        case modifiedAt = "modified_at"
        case collectionOrder = "collection_order"
        case itemOrder = "item_order"
    }

    // Codable init + encoder — follow PageType.swift pattern
}

/// Reserved for post-v1 per-Item-Type template feature.
struct ItemTemplateConfig: Codable, Equatable, Hashable, Sendable {
    var layout: String?
    var descriptionCap: Int?
    var defaultDescription: String?
}

extension ItemType {
    static func load(from metadataURL: URL) throws -> ItemType {
        var t = try AtomicJSON.decode(ItemType.self, from: metadataURL)
        t.title = metadataURL.deletingLastPathComponent().lastPathComponent
        return t
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 2: Build + commit.**

#### Task 5.2 — Define ItemCollection struct

```swift
import Foundation

/// Item Collection — sub-folder inside an Item Type. Parallel to PageCollection.
/// UI label: "Set" by default (renameable via Settings); code always says "Collection."
struct ItemCollection: Codable, Equatable, Identifiable, Hashable, Sendable {
    var id: String
    var typeID: String
    var title: String
    var folderURL: URL
    var modifiedAt: Date

    var itemOrder: [String]?

    enum CodingKeys: String, CodingKey {
        case id
        case typeID = "type_id"
        case modifiedAt = "modified_at"
        case itemOrder = "item_order"
    }
}

extension ItemCollection {
    static func load(from metadataURL: URL) throws -> ItemCollection {
        var c = try AtomicJSON.decode(ItemCollection.self, from: metadataURL)
        let folderURL = metadataURL.deletingLastPathComponent()
        c.folderURL = folderURL
        c.title = folderURL.lastPathComponent
        return c
    }

    func save(to metadataURL: URL) throws {
        try AtomicJSON.write(self, to: metadataURL)
    }
}
```

- [ ] **Step 1: Build + commit.**

#### Task 5.3 — Define ItemTypeManager

Mirror PageTypeManager. Add NexusPaths helpers (`itemsWrapperDir`, `itemTypeFolderURL`, `itemTypeMetadataURL`, `itemCollectionFolderURL`, `itemCollectionMetadataURL`).

- [ ] **Step 1: Create ItemTypeManager.swift + path helpers.**

- [ ] **Step 2: Build + commit.**

#### Task 5.4 — Define ItemTypeValidator + ItemCollectionValidator

Mirror PageTypeValidator + PageCollectionValidator.

- [ ] **Step 1: Create both validators + commit.**

#### Task 5.5 — Split ContentManager into PageContentManager + ItemContentManager

**Files:**
- Rename: `ContentManager.swift` → `PageContentManager.swift`
- Rename: `ContentManager+CRUD.swift` → `PageContentManager+CRUD.swift`
- Create: `Pommora/Pommora/Items/ItemContentManager.swift`
- Create: `Pommora/Pommora/Items/ItemContentManager+CRUD.swift`

- [ ] **Step 1: Rename + de-Item-ize PageContentManager**: remove `itemsByCollection`, `itemsByVaultRoot` → `itemsByTypeRoot`, `items(in:)`, `items(inVaultRoot:)`, Item CRUD methods. Rename `pagesByVaultRoot` → `pagesByTypeRoot`.

- [ ] **Step 2: Create ItemContentManager.swift** + ItemContentManager+CRUD.swift. Mirror PageContentManager pattern, typed on Item + ItemType + ItemCollection.

- [ ] **Step 3: Update PageParent.swift** — Pages-only enum. Create new `ItemParent.swift` for Items-side.

- [ ] **Step 4: Update ContentView's manager construction** — instantiate both managers with their own contextProvider closures.

- [ ] **Step 5: Build + commit.**

#### Task 5.6 — Tests for ItemType + ItemCollection + ItemContentManager

- [ ] **Step 1: Create new test files** for ItemType / ItemCollection / ItemTypeManager / ItemContentManager.

- [ ] **Step 2: Rename ContentManagerTests → PageContentManagerTests** + remove Item tests.

- [ ] **Step 3: Run + commit.**

---

### Phase 6 — Pages/Items wrapper folders + NexusAdopter update

**Goal:** Move Page Types under `<nexus>/Pages/` wrapper; Item Types under `<nexus>/Items/`. Update NexusAdopter.

**Depends on:** Phase 5.

#### Task 6.1 — Update NexusPaths + PageTypeManager for wrapper layout

- [ ] **Step 1: Add wrapper helpers** (`pagesWrapperDir`, `itemsWrapperDir`, `agendaWrapperDir`).

- [ ] **Step 2: Update PageType path helpers** to use `pagesWrapperDir`.

- [ ] **Step 3: Update PageTypeManager.loadAll()** — read from `pagesWrapperDir(in:)`, remove sibling filters.

- [ ] **Step 4: Build + commit.**

#### Task 6.2 — Update NexusAdopter for new layout

- [ ] **Step 1: NexusAdopter.scan** — survey three wrapper dirs.

- [ ] **Step 2: NexusAdopter.apply** — create missing wrappers + sidecars. Legacy folders (with `_vault.json`) at root NOT adopted; logged as skipped.

- [ ] **Step 3: AdoptionPreviewView** — updated counts grouped by entity type.

- [ ] **Step 4: Build + commit.**

#### Task 6.3 — Update tests for new layout

- [ ] **Step 1: NexusPathsTests + NexusAdopterTests** updated for new layout.

- [ ] **Step 2: Run + commit.**

---

### Phase 7 — Settings scaffold (storage + manager + label wiring + stub UI)

**Goal:** Establish the user-settings infrastructure so future user-overridable UI labels + accent color flow through a single SettingsManager. Every UI label-rendering site reads from settings rather than hardcoded strings. v0.3.0 ships storage + manager + label wiring + a minimal Settings scene; full editing UI ships v0.6.0.

**Depends on:** Phase 6 (entity types fully renamed).

**Affected UI surfaces** (every label-rendering site shifts to settings):
- Sidebar section headers (Pages / Items / Agenda)
- New-X sheet titles ("New Set" / "New Collection" / "New Type" / etc.)
- Context menu items
- Detail-pane breadcrumbs
- Empty-state copy

#### Task 7.1 — Define Settings + SettingsLabels Codable structs

**Files:**
- Create: `Pommora/Pommora/Configuration/Settings.swift`

- [ ] **Step 1: Create Settings.swift**:

```swift
import Foundation

/// Per-Nexus user preferences. On disk at `<nexus>/.nexus/settings.json`.
/// Loaded by SettingsManager; consumed by every UI label-rendering site.
///
/// Existing `tier-config.json` and `saved-config.json` stay separate for v0.3.0
/// (consolidation deferred to v0.6.0 Settings UI work).
struct Settings: Codable, Equatable, Hashable, Sendable {
    var version: Int
    var accentColor: SettingsAccentColor?
    var labels: SettingsLabels
    var modifiedAt: Date

    enum CodingKeys: String, CodingKey {
        case version
        case accentColor = "accent_color"
        case labels
        case modifiedAt = "modified_at"
    }

    static func defaultSeed() -> Settings {
        Settings(
            version: 1,
            accentColor: nil,                    // nil = system default
            labels: SettingsLabels.defaults(),
            modifiedAt: Date()
        )
    }
}

struct SettingsLabels: Codable, Equatable, Hashable, Sendable {
    var sidebarSections: SidebarSectionLabels
    var pageType: LabelPair
    var pageCollection: LabelPair
    var itemType: LabelPair
    var itemCollection: LabelPair
    var project: LabelPair
    var agendaTask: LabelPair
    var agendaEvent: LabelPair

    enum CodingKeys: String, CodingKey {
        case sidebarSections = "sidebar_sections"
        case pageType = "page_type"
        case pageCollection = "page_collection"
        case itemType = "item_type"
        case itemCollection = "item_collection"
        case project
        case agendaTask = "agenda_task"
        case agendaEvent = "agenda_event"
    }

    static func defaults() -> SettingsLabels {
        SettingsLabels(
            sidebarSections: SidebarSectionLabels.defaults(),
            pageType: LabelPair(singular: "Vault", plural: "Vaults"),
            pageCollection: LabelPair(singular: "Collection", plural: "Collections"),
            itemType: LabelPair(singular: "Type", plural: "Types"),
            itemCollection: LabelPair(singular: "Set", plural: "Sets"),
            project: LabelPair(singular: "Project", plural: "Projects"),
            agendaTask: LabelPair(singular: "Task", plural: "Tasks"),
            agendaEvent: LabelPair(singular: "Event", plural: "Events")
        )
    }
}

// UI label divergence: Pages-side renders "Vault" / "Collection" (distinctive + generic);
// Items-side renders "Type" / "Set" (generic + distinctive). Each side has one signature
// word + one shared word — visual asymmetry signals which side you're on without echo.
// agendaTask + agendaEvent labels are kept here for Calendar's eventual UI consumption;
// they're dormant in v0.3.0 (no sidebar Agenda section per Phase 8.3).

struct SidebarSectionLabels: Codable, Equatable, Hashable, Sendable {
    var pages: String
    var items: String
    // No `agenda` field — Agenda has no sidebar section. Agenda Tasks + Agenda Events
    // surface via the Calendar pin entry; Calendar UI ships in a follow-up plan.

    static func defaults() -> SidebarSectionLabels {
        SidebarSectionLabels(pages: "Pages", items: "Items")
    }
}

struct LabelPair: Codable, Equatable, Hashable, Sendable {
    var singular: String
    var plural: String
}

enum SettingsAccentColor: String, Codable, CaseIterable, Hashable, Sendable {
    case red, orange, yellow, green, blue, purple, pink, gray
}
```

- [ ] **Step 2: Add settings path helper to NexusPaths.swift**:

```swift
extension NexusPaths {
    static func settingsFileURL(in nexus: Nexus) -> URL {
        nexus.rootURL.appendingPathComponent(".nexus").appendingPathComponent("settings.json")
    }
}
```

- [ ] **Step 3: Build + commit.**

#### Task 7.2 — Define SettingsManager

**Files:**
- Create: `Pommora/Pommora/Configuration/SettingsManager.swift`

- [ ] **Step 1: Create SettingsManager.swift**:

```swift
import Foundation
import Observation

@MainActor
@Observable
final class SettingsManager {
    private(set) var settings: Settings = .defaultSeed()
    var pendingError: (any Error)?

    private let nexus: Nexus

    init(nexus: Nexus) {
        self.nexus = nexus
    }

    func loadOrSeed() async {
        let url = NexusPaths.settingsFileURL(in: nexus)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                self.settings = try AtomicJSON.decode(Settings.self, from: url)
            } catch {
                self.pendingError = error
                self.settings = .defaultSeed()
            }
        } else {
            self.settings = .defaultSeed()
            do {
                try AtomicJSON.write(settings, to: url)
            } catch {
                self.pendingError = error
            }
        }
    }

    func updateAccentColor(_ color: SettingsAccentColor?) async {
        var s = settings
        s.accentColor = color
        s.modifiedAt = Date()
        await persist(s)
    }

    func updateLabel<T>(_ keyPath: WritableKeyPath<SettingsLabels, T>, to newValue: T) async {
        var s = settings
        s.labels[keyPath: keyPath] = newValue
        s.modifiedAt = Date()
        await persist(s)
    }

    private func persist(_ newSettings: Settings) async {
        do {
            let url = NexusPaths.settingsFileURL(in: nexus)
            try AtomicJSON.write(newSettings, to: url)
            self.settings = newSettings
        } catch {
            self.pendingError = error
        }
    }
}
```

- [ ] **Step 2: Update ContentView's manager construction** — instantiate SettingsManager alongside others. Load on app start via `.task { await settingsManager.loadOrSeed() }`.

- [ ] **Step 3: Build + commit.**

#### Task 7.3 — Wire UI labels for sidebar sections

**Goal:** Replace every hardcoded sidebar section label with a SettingsManager lookup.

- [ ] **Step 1: Update SidebarView.swift section headers**:

```swift
// Before:
Section("Pages") { ... }

// After:
@Environment(SettingsManager.self) private var settingsManager
// ...
Section(settingsManager.settings.labels.sidebarSections.pages) { ... }
```

Apply to Pages / Items / Agenda section headers.

- [ ] **Step 2: Verify Spaces / Topics labels** — these come from TierConfigManager (existing). No change needed.

- [ ] **Step 3: Build + commit.**

#### Task 7.4 — Wire UI labels for sheet titles + context menus (Pages-side designed; Items-side + Agenda sheets exempt)

**Stubs exemption:** Phase 8.2 ships `NewItemTypeSheet` + `NewItemCollectionSheet` as `ContentUnavailableView` stubs that explicitly do NOT read SettingsManager labels — their placeholder text is static. The Agenda creation sheets (`NewAgendaTaskSheet` / `NewAgendaEventSheet`) do NOT ship in ParadigmV2 at all (no sidebar Agenda section means no entry point; Calendar plan introduces its own flow). So Phase 7.4 only wires SettingsManager labels into the designed Pages-side + Project sheets.

**Files:**
- Modify: `NewPageCollectionSheet.swift`, `NewPageTypeSheet.swift`, `NewProjectSheet.swift`
- Modify: Pages-side row views' `.contextMenu { Button("New X") ... }` sites (PageTypeRow / PageCollectionRow)
- Exempt (do NOT modify): `NewItemTypeSheet.swift` + `NewItemCollectionSheet.swift` (stubs); `ItemTypeRow.swift` + `ItemCollectionRow.swift` (stubs without context menus)

- [ ] **Step 1: Update NewPageCollectionSheet** to read its title from SettingsManager:

```swift
struct NewPageCollectionSheet: View {
    let type: PageType
    @Environment(\.dismiss) private var dismiss
    @Environment(PageTypeManager.self) private var typeManager
    @Environment(SettingsManager.self) private var settingsManager
    @State private var title: String = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("New \(settingsManager.settings.labels.pageCollection.singular)")
                .font(.headline)
            TextField("Name", text: $title)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Create") {
                    Task {
                        try? await typeManager.createPageCollection(title: title, in: type)
                        dismiss()
                    }
                }
                .disabled(title.isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
    }
}
```

Renders as "New Collection" with the default SettingsLabels.

- [ ] **Step 2: Apply parallel pattern** to:
  - `NewPageTypeSheet` reads `labels.pageType.singular` → renders "**New Vault**" by default
  - `NewProjectSheet` reads `labels.project.singular` → renders "New Project" by default

  Items-side sheets (`NewItemTypeSheet`, `NewItemCollectionSheet`) are stubs — do NOT add SettingsManager environment or label reads. They ship the static placeholder text from Phase 8.2.

- [ ] **Step 3: Update Pages-side row context menus** — every `Button("New X")` reads from SettingsManager. Example in PageTypeRow.swift:

```swift
.contextMenu {
    Button("New \(settingsManager.settings.labels.pageCollection.singular)") {
        presentedSheet = .newPageCollection(type: type)
    }
    Divider()
    Button("Rename") { ... }
    Button("Delete", role: .destructive) { ... }
}
```

Renders the "New Collection" + Rename + Delete menu on a Vault row. Apply parallel pattern to `PageCollectionRow` (its menu offers "New Page" + Rename + Delete). Items-side rows (`ItemTypeRow` / `ItemCollectionRow`) are stubs — no context menus at all in v0.3.0 (Phase 8.5).

- [ ] **Step 4: Build + verify each designed sheet's title displays correctly + commit.**

#### Task 7.5 — Accent color reading (wire inside ContentView, not PommoraApp)

**Files:**
- Modify: `Pommora/Pommora/ContentView.swift`

**Wiring rationale:** SettingsManager is a per-nexus manager — `init(nexus: Nexus)`. Every other per-nexus manager (Space/Topic/Vault/Content/Agenda/Homepage/Tier/Saved/Recents/Pinned) is instantiated inside `ContentView.constructManagers(for: Nexus?)` at [ContentView.swift:245](Pommora/Pommora/ContentView.swift#L245). SettingsManager follows the same pattern. The earlier plan draft proposed wiring at `PommoraApp` scope, but `PommoraApp` has no Nexus handle and no instantiation path — that wiring would leave `settingsManager` permanently nil. Keep `SettingsScene` (Task 7.6) at PommoraApp scope since it's a static Scene that needs no manager handle.

- [ ] **Step 1: Add SettingsManager state + construction in ContentView.swift**:

In the `@State` declarations block (around line 30 of `ContentView.swift`, alongside `@State private var spaceManager`, etc.):

```swift
@State private var settingsManager: SettingsManager?
```

In `constructManagers(for nexus: Nexus?)`:

```swift
// In the nil-nexus reset branch:
settingsManager = nil

// In the construction branch, alongside the other `let xMgr = …` lines:
let settingsMgr = SettingsManager(nexus: nexus)

// Assignment:
self.settingsManager = settingsMgr

// Parallel-load Task:
async let _ = settingsMgr.loadOrSeed()
```

- [ ] **Step 2: Apply `.tint(currentAccent)` to the NavigationSplitView** in `ContentView.body`:

```swift
NavigationSplitView { ... } detail: { ... }
    .tint(currentAccent)
    // ... rest of existing modifiers
```

Add the computed property to `ContentView`:

```swift
private var currentAccent: Color {
    guard let manager = settingsManager,
          let color = manager.settings.accentColor else {
        return .accentColor   // system default
    }
    switch color {
    case .red:    return .red
    case .orange: return .orange
    case .yellow: return .yellow
    case .green:  return .green
    case .blue:   return .blue
    case .purple: return .purple
    case .pink:   return .pink
    case .gray:   return .gray
    }
}
```

- [ ] **Step 3: Inject `.environment(settingsMgr)`** into the sidebar / inspector / detail builders alongside the other manager environments (Phase 7.3/7.4 label sites depend on this).

- [ ] **Step 4: Build + verify accent color responds + commit.**

#### Task 7.6 — Settings scene scaffold

**Files:**
- Create: `Pommora/Pommora/Configuration/SettingsScene.swift`

**Intentionally a minimal stub.** Designed Settings UI ships in a follow-up plan; v0.3.0 only proves the Cmd+, hook works and the storage layer is reachable. The follow-up plan replaces `SettingsSheetPlaceholder` in-place with the real Settings UI.

- [ ] **Step 1: Create SettingsScene.swift**:

```swift
import SwiftUI

struct SettingsScene: Scene {
    var body: some Scene {
        Settings {
            SettingsSheetPlaceholder()
        }
    }
}

struct SettingsSheetPlaceholder: View {
    var body: some View {
        ContentUnavailableView(
            "Settings UI coming in v0.6.0",
            systemImage: "gearshape",
            description: Text("""
                The full Settings panel — accent color, custom labels, EventKit sync, \
                tier-config — ships in v0.6.0. The storage scaffold is live in v0.3.0 so \
                future Settings UI work is purely additive.

                Until then, edit `<nexus>/.nexus/settings.json` directly to override labels \
                or accent color.
                """)
        )
        .frame(width: 480, height: 320)
        .padding()
    }
}
```

- [ ] **Step 2: Add SettingsScene to PommoraApp** — see Task 7.5 Step 1 example.

- [ ] **Step 3: Verify Cmd+, opens the Settings window** + commit.

#### Task 7.7 — Tests for Settings scaffold

**Files:**
- Create: `Pommora/PommoraTests/Configuration/SettingsTests.swift`
- Create: `Pommora/PommoraTests/Configuration/SettingsManagerTests.swift`

- [ ] **Step 1: SettingsTests** — Codable round-trip + defaults.

- [ ] **Step 2: SettingsManagerTests** — load+seed flow (file missing creates default; file present decodes); update flow (updateAccentColor persists; updateLabel persists); error handling.

- [ ] **Step 3: Run + commit.**

---

### Phase 8 — Sidebar / Detail / Sheet UI restructure

**Goal:** Update sidebar to render the new sections + Item Types + Item Collections. Add sheets for new entity creation. Update detail-pane views. All UI labels source from SettingsManager (Phase 7).

**Depends on:** Phases 2 + 4 + 5 + 7.

#### Task 8.1 — Update SidebarSheet enum + SelectionTag + IconTarget

- [ ] **Step 1: Update SidebarSheet enum** with new cases (newPageType / newPageCollection / newItemType / newItemCollection / newItem / newProject). **Do NOT add** `newAgendaTask` or `newAgendaEvent` — Agenda has no sidebar entry in ParadigmV2; Calendar plan adds its own sheet enum when it builds Agenda UI.

- [ ] **Step 2: Update SidebarSelection + SelectionTag** with new cases (pageType / pageCollection / itemType / itemCollection / project). **Do NOT add** `agendaTasks` or `agendaEvents` — no sidebar selection target for Agenda.

- [ ] **Step 3: Update IconTarget enum** to include `.pageType(PageType)` + `.itemType(ItemType)`.

- [ ] **Step 4: Update every call site** referencing old enum cases.

- [ ] **Step 5: Build + commit.**

#### Task 8.2 — Create new sheet views (Items + Agenda ship as stubs; Pages-side ships designed)

**Stub directive:** Items-side and Agenda-side creation sheets ship as minimal placeholders. They exist so `SidebarSheet` enum cases route somewhere build-clean, but the designed UI (form fields, validation, SettingsManager-driven titles) lands in a follow-up plan. Pages-side sheets (`NewPageTypeSheet`, `NewPageCollectionSheet`, `NewProjectSheet`) ship fully designed — Phase 7.4 already wires their SettingsManager label reads.

**Stub shape (apply to each of the four files in Steps 1–3):**

```swift
import SwiftUI

/// Minimal stub — designed UI ships in a follow-up plan. Routes the
/// SidebarSheet enum case to a build-clean destination.
struct NewItemTypeSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            ContentUnavailableView(
                "Create Item Type",
                systemImage: "tray.full",
                description: Text("UI ships in a follow-up plan. Data layer is live; create stub entities via tests or by editing the nexus folder directly.")
            )
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding()
        .frame(width: 380, height: 240)
    }
}
```

- [ ] **Step 1: Create NewItemTypeSheet.swift** as a minimal stub per the shape above. Does NOT read SettingsManager labels yet — that wiring lands with the follow-up plan that designs the UI.

- [ ] **Step 2: Create NewItemCollectionSheet.swift** as a minimal stub (title text: "Create Item Collection"; symbol: `"tray"`). Does NOT read SettingsManager labels yet.

- [ ] **Step 3: Agenda creation sheets — DO NOT CREATE.** ParadigmV2 ships no `NewAgendaTaskSheet` or `NewAgendaEventSheet` (not even as stubs). With no sidebar Agenda section, there's no entry point that would route to them. The Calendar plan (which surfaces Agenda Tasks + Agenda Events via the Calendar pin entry) introduces its own creation sheets when it builds the Calendar UI. The data layer (AgendaTask + AgendaEvent structs, managers, on-disk shape) still ships in Phase 4 — only the creation UI defers.

- [ ] **Step 4: Build + commit.**

#### Task 8.3 — Update SidebarView sections

**Stub note:** Items and Agenda sub-sections render their headers + the stub rows from Task 8.5. Click-through detail-pane responses are the stub views from Task 8.4. Sheets opened from context menus are the stubs from Task 8.2. Pages-side is fully designed end-to-end.

**Pre-edit inventory step:** This task's sheet-routing code (Step 2) presupposes a structure that may already differ from `main`. Before editing, the executor must:

```bash
grep -n 'presentedSheet\|\.sheet(item:' Pommora/Pommora/Sidebar/SidebarView.swift Pommora/Pommora/ContentView.swift
```

Update Step 2's edit target based on where `.sheet(item: $presentedSheet)` is actually attached today. As of v0.2.7.5 it lives in `ContentView`, not `SidebarView` (see [ContentView.swift:49](Pommora/Pommora/ContentView.swift#L49)).

- [ ] **Step 1: Add `itemsSection`** to SidebarView.swift (renders Item Type stub rows under an "Items" header). Do NOT add an `agendaSection` — Agenda has no sidebar presence in ParadigmV2; Calendar pin entry surfaces Agenda Tasks + Events.

- [ ] **Step 2: Section order** in `var body` — Items above Pages; no Agenda section:

```swift
var body: some View {
    List {
        savedSection
        spacesSection
        topicsSection
        itemsSection            // ← Items above Pages (quicker-capture)
        pagesSection
        // No agendaSection — Agenda surfaces via Calendar pin entry; data layer ships
        // in Phase 4 but no sidebar visualization until Calendar UI plan.
    }
    .listStyle(.sidebar)
    .scrollContentBackground(.hidden)
    .sheet(item: $presentedSheet) { sheet in
        switch sheet {
        case .newSpace:                       NewSpaceSheet()
        case .newTopic:                       NewTopicSheet()
        case .newProject(let p):              NewProjectSheet(parent: p)
        case .newPageType:                    NewPageTypeSheet()
        case .newPageCollection(let t):       NewPageCollectionSheet(type: t)
        case .newPage(let c, let t):          NewPageSheet(collection: c, type: t)
        case .newItemType:                    NewItemTypeSheet()
        case .newItemCollection(let t):       NewItemCollectionSheet(type: t)
        case .newItem(let c, let t):          NewItemSheet(collection: c, type: t)
        // No `.newAgendaTask` / `.newAgendaEvent` arms — SidebarSheet enum doesn't
        // include those cases per Phase 8.1 Step 1.
        case .editTopicParents(let t):        EditTopicParentsSheet(topic: t)
        case .editIcon(let target):           IconPickerSheet(target: target)
        case .editColor(let s):               SpaceColorPicker(space: s)
        }
    }
}
```

- [ ] **Step 3: Update environment injection** in ContentView to pass new managers.

- [ ] **Step 4: Update right-click context menus** — all "New X" entries read labels from SettingsManager.

- [ ] **Step 5: Build + commit.**

#### Task 8.4 — Detail-pane views for Item Type + Item Collection (stubs)

**Stub directive:** Both detail views render a `ContentUnavailableView` placeholder. The Items table UI ships in a follow-up plan. Selection routing IS wired so clicks land somewhere build-clean — the destination is just a stub.

**Stub shape:**

```swift
import SwiftUI

struct ItemTypeDetailView: View {
    let type: ItemType

    var body: some View {
        ContentUnavailableView(
            type.title,
            systemImage: "tray",
            description: Text("Items table ships in a follow-up plan. The Item Type exists on disk and via the data manager; UI lands later.")
        )
    }
}
```

- [ ] **Step 1: Create ItemTypeDetailView.swift** per the shape above. Does NOT read SettingsManager labels yet — title comes directly from `type.title`.

- [ ] **Step 2: Create ItemCollectionDetailView.swift** with parallel shape (takes `let collection: ItemCollection`; symbol: `"tray.fill"`). Does NOT read SettingsManager labels.

- [ ] **Step 3: Update SidebarDetailView** — wire routing for the new selection cases (`itemType`, `itemCollection`) so the stub views actually display when their selection lands. Routing IS required — stubs without routing leave the detail pane blank.

- [ ] **Step 4: Build + commit.**

#### Task 8.5 — Row views (Items-side rows are minimal stubs; no context menus yet)

**Stub directive:** Items-side rows render as minimal `SelectableRow` instances — title + icon + click-to-select. No context menus (quick-actions land with the real Items UI plan). `SelectableRow` already exists in the Pages-side row files — reuse exactly; no chrome divergence.

**Stub shape:**

```swift
import SwiftUI

struct ItemTypeRow: View {
    let type: ItemType
    @Binding var selection: SidebarSelection

    var body: some View {
        SelectableRow(
            isSelected: SelectionTag.itemType(type.id).matches(selection),
            onSelect: { selection = .itemType(type.id) }
        ) {
            Label(type.title, systemImage: type.icon ?? "tray.full")
        }
        // No context menu yet — quick-actions land with the real Items UI plan.
    }
}
```

- [ ] **Step 1: Create ItemTypeRow.swift + ItemCollectionRow.swift** per the shape above. `ItemCollectionRow` uses `SelectionTag.itemCollection(c.id)` and symbol `"tray"`. NO context menu modifiers on either row. NO SettingsManager label reads — title comes directly from the entity.

- [ ] **Step 2: Build + verify sidebar renders Items section with stub rows that click-select + commit.**

---

### Phase 9 — Tests consolidation + v0.3.0 Properties spec reconciliation

#### Task 9.1 — Tests audit

- [ ] **Step 1: Run full suite + capture failure list.**

- [ ] **Step 2: Classify each failure** (obsolete type name / behavior change / fixture).

- [ ] **Step 3: Add coverage**: ItemTypeManager CRUD, ItemCollection round-trip, ItemContentManager CRUD, AgendaTaskManager + AgendaEventManager CRUD, SettingsManager round-trip, adoption with new wrapper layout.

- [ ] **Step 4: Commit.**

#### Task 9.2 — Update v0.3.0 Properties implementation spec

**Files:**
- Modify: `.claude/Planning/v0.3.0-Properties-implementation.md`

- [ ] **Step 1: Rewrite "Vault" references** to "Page Type" / "Item Type" / "Type" as appropriate.

- [ ] **Step 2: Update RelationScope cases**:

```swift
enum RelationScope: Codable, Equatable, Hashable, Sendable {
    case pageType(String)
    case itemType(String)
    case pageCollection(String)
    case itemCollection(String)
    case contextTier(Int)
}
```

- [ ] **Step 3: Rename `VaultSettingsSheet` → `PageTypeSettingsSheet`** in `v0.3.0-Properties-implementation.md`. **Flag for the Properties plan's own decision:** `ItemTypeSettingsSheet` is required for Items-side property-editing parity, but Items-side UI overall is deferred to a follow-up plan after ParadigmV2. The Properties plan owner decides whether to ship `ItemTypeSettingsSheet` in v0.3.0 alongside `PageTypeSettingsSheet` (parity now), or defer it with the rest of Items-side UI. ParadigmV2 does NOT prescribe this — it just renames the Pages-side sheet to use the new type name and surfaces the question.

- [ ] **Step 4: Update schema CRUD tasks** — methods live on both PageTypeManager and ItemTypeManager.

- [ ] **Step 5: Update Status "Where built-in" section** — AgendaTask only; NOT on AgendaEvent.

- [ ] **Step 6: Add the AgendaTaskSchema Status seed** (deferred from Phase 4) — when v0.3.0 Phase 0 introduces PropertyDefinition.StatusGroup, extend AgendaTaskSchema.Property with `statusGroups: [PropertyDefinition.StatusGroup]?` + update `defaultSeed()`.

- [ ] **Step 7: Commit.**

#### Task 9.3 — Update Handoff + History

- [ ] **Step 1: Handoff.md** — mark ParadigmV2 complete.

- [ ] **Step 2: History.md** — finalize ParadigmV2 entry with commit list.

- [ ] **Step 3: Commit.**

---

### Phase 10 — Nathan's user-data migration (one-shot script)

**Goal:** Migrate Nathan's own Pommora data (`/Users/nathantaichman/The Nexus/Pommora/`). NOT shipped with Pommora.

**Depends on:** ALL prior code phases green.

#### Task 10.1 — Inventory Nathan's current data

- [ ] **Step 1: Snapshot current layout**:

```bash
ls -la "/Users/nathantaichman/The Nexus/Pommora/"
find "/Users/nathantaichman/The Nexus/Pommora" -name '_vault.json' -o -name '_collection.json' -o -name '*.subtopic.json' -o -name '*.agenda.json' -o -name '_agenda.json' | sort
```

- [ ] **Step 2: Verify "only Pages exist in Vaults" assumption**:

```bash
find "/Users/nathantaichman/The Nexus/Pommora" -name '*.md' | wc -l
find "/Users/nathantaichman/The Nexus/Pommora" -name '*.json' \
    ! -name '_vault.json' ! -name '_collection.json' ! -name '_agenda.json' \
    ! -name 'package.json' | head -20
```

- [ ] **Step 3: Surface findings to Nathan before any data is moved.**

#### Task 10.2 — Migration script

**Files:**
- Create: `migration/paradigmV2.sh` (NOT committed; archived after migration)

- [ ] **Step 1: Write a one-shot bash script** that:
  1. **Backs up the entire `<nexus>/` to `<nexus>.pre-paradigmV2-backup/`** (FIRST step, non-skippable, loud)
  2. Creates `<nexus>/Pages/`, `<nexus>/Items/`, `<nexus>/Agenda/Tasks/`, `<nexus>/Agenda/Events/`
  3. Moves every top-level folder containing `_vault.json` into `<nexus>/Pages/`
  4. Renames every `_vault.json` to `_schema.json`
  5. Renames every `_collection.json` to `_schema.json`
  6. Renames every `*.subtopic.json` to `*.project.json`
  7. If any `.agenda.json` files exist: prompt per-file to classify as Task or Event
  8. Renames classified files to `*.task.json` / `*.event.json`
  9. Seeds default `_schema.json` for Tasks/Events wrappers if missing
  10. Updates internal `vault_id` → `type_id` field references in sub-folder sidecars
  11. Seeds default `.nexus/settings.json` with default labels + nil accent

- [ ] **Step 2: Add `--dry-run` mode first** — prints exactly what would happen.

- [ ] **Step 3: Test on a copy of Nathan's nexus.**

- [ ] **Step 4: Run on the real nexus** (with Nathan's verbal approval + confirmed backup).

- [ ] **Step 5: Launch Pommora** and verify adoption works.

- [ ] **Step 6: Archive the script** in `migration/archive/`.

---

### Phase 11 — Cleanup + Framework reconciliation + ship

#### Task 11.1 — Final grep sweep

- [ ] **Step 1: Production code sweep** — each grep should return empty (or only intentional comments):

```bash
grep -rn '\bVault\b' Pommora/Pommora --include='*.swift' | grep -v 'PageVault\|XCTAssert\|//.*Vault'
grep -rn '\bVaultManager\b\|\bVaultValidator\b\|\bVaultDetailView\b\|\bVaultRow\b\|\bNewVaultSheet\b\|\bVaultView\b' Pommora/Pommora --include='*.swift'
grep -rn '\bSubtopic\b\|\bsubtopic\b' Pommora/Pommora --include='*.swift'
grep -rn '\bAgendaItem\b\|\bAgendaSchema\b\|\bAgendaManager\b\|\bAgendaValidator\b' Pommora/Pommora --include='*.swift'
grep -rn '\bContentManager\b' Pommora/Pommora --include='*.swift'
grep -rn '\bPommora\.Collection\b\|\bPommora\.Set\b\|\bPommora\.Task\b' Pommora/Pommora --include='*.swift'
grep -rn '"_vault\.json"\|"_collection\.json"\|"_agenda\.json"' Pommora/Pommora --include='*.swift'
grep -rn '"\.subtopic\.json"\|"\.agenda\.json"' Pommora/Pommora --include='*.swift'
grep -rn 'kind-agnostic\|kind.agnostic' Pommora/Pommora --include='*.swift'
grep -rn 'Pages and Items can coexist\|vault.root\|inVaultRoot' Pommora/Pommora --include='*.swift'

# Pommora ban check — new `pommora_*` fields not allowed:
grep -rn '"pommora_' Pommora/Pommora --include='*.swift' | grep -v 'pommora_table_widths'

# Pommora.X qualification check — the "no namespace discriminator" rule.
# The `\b` + capital-letter pattern matches discriminator usage like
# `Pommora.Collection`, NOT module-import lines.
grep -rn '\bPommora\.[A-Z]' Pommora/Pommora --include='*.swift' \
    | grep -v '^.*//.*Pommora\.\(Collection\|Set\|Task\).*\(retired\|deprecated\|previously\)'
```

**Acceptable matches** for the `Pommora.X` grep: doc-comment lines explicitly framed as historical context (e.g., `// Pommora.Collection previously required — retired in ParadigmV2`). **Unacceptable**: any non-comment line.

- [ ] **Step 2: Tests sweep**:

```bash
grep -rn '\bVault\b\|\bSubtopic\b\|\bAgendaItem\b\|\bAgendaManager\b' Pommora/PommoraTests --include='*.swift'
grep -rn '"_vault\.json"\|"_collection\.json"\|"\.subtopic\.json"' Pommora/PommoraTests --include='*.swift'
```

- [ ] **Step 3: Docs sweep**:

```bash
grep -rn 'Page Vault\|Pommora\.Collection\|Pommora\.Set\|_vault\.json\|_collection\.json\|\.subtopic\.json\|\.agenda\.json\|AgendaItem\|AgendaSchema\|AgendaManager\|kind-agnostic' .claude --include='*.md'
```

Acceptable: occurrences inside `History.md`, `Planning/ParadigmV2.md` (this plan), the `Collections.md` stub redirect, migration script docs. (`Vaults.md` no longer exists — references swept to `PageTypes.md` / `Items.md`.)

NOT acceptable: occurrences in active feature docs, CLAUDE.md, Framework.md, Handoff.md, Guidelines/.

- [ ] **Step 4: Confirm physical files deleted**:

```bash
for legacy in \
    Pommora/Pommora/Vaults/Vault.swift \
    Pommora/Pommora/Vaults/VaultManager.swift \
    Pommora/Pommora/Vaults/Collection.swift \
    Pommora/Pommora/Vaults/VaultView.swift \
    Pommora/Pommora/Contexts/Subtopic.swift \
    Pommora/Pommora/Agenda/AgendaItem.swift \
    Pommora/Pommora/Agenda/AgendaSchema.swift \
    Pommora/Pommora/Agenda/AgendaManager.swift \
    Pommora/Pommora/Validation/AgendaValidator.swift \
    Pommora/Pommora/Validation/VaultValidator.swift \
    Pommora/Pommora/Validation/SubtopicValidator.swift \
    Pommora/Pommora/Validation/CollectionValidator.swift \
    Pommora/Pommora/Content/ContentManager.swift \
    Pommora/Pommora/Sidebar/VaultRow.swift \
    Pommora/Pommora/Sidebar/SubtopicRow.swift \
    Pommora/Pommora/Sidebar/CollectionRow.swift \
    Pommora/Pommora/Detail/VaultDetailView.swift \
    Pommora/Pommora/Detail/CollectionDetailView.swift \
    Pommora/Pommora/Sidebar/Sheets/NewVaultSheet.swift \
    Pommora/Pommora/Sidebar/Sheets/NewSubtopicSheet.swift \
    Pommora/Pommora/Sidebar/Sheets/NewCollectionSheet.swift; do
    if [ -e "$legacy" ]; then echo "STILL EXISTS: $legacy"; else echo "OK gone: $legacy"; fi
done
```

- [ ] **Step 5: Final build + test + lint**:

```bash
xcodebuild build
xcodebuild test
swift format lint --strict --recursive Pommora
```

- [ ] **Step 6: Commit cleanup pass.**

#### Task 11.2 — Framework.md update

- [ ] **Step 1: Mark ParadigmV2 shipped** between v0.2.7.5 and v0.3.0.

- [ ] **Step 2: Update v0.3.0 description** with new terminology.

- [ ] **Step 3: Commit.**

#### Task 11.3 — Tag the ship

- [ ] **Step 1: Confirm full test pass + clean build + lint.**

- [ ] **Step 2: Tag**:

```bash
git tag paradigmV2 -m "ParadigmV2 — operational-layer domain model refactor"
git push origin main
git push origin paradigmV2
```

- [ ] **Step 3: Update Handoff.md** marking the milestone complete with next-session priorities (back to v0.3.0 Properties).

---

### Self-review checklist

After all phases complete:

- [ ] No `_vault.json` or `_collection.json` in production code (only inside migration script + History.md historical record)
- [ ] No `Subtopic` / `subtopic` in production code (only in Project docstrings explaining the rename)
- [ ] No `AgendaItem` / `AgendaSchema` / `AgendaManager` / `AgendaValidator` references — fully replaced
- [ ] No `Pommora.Collection`, `Pommora.Set`, or `Pommora.Task` qualifications — quirk #6 retired
- [ ] No bare `Task` or `Event` Swift type definitions (only `AgendaTask` and `AgendaEvent`)
- [ ] No `pommora_*` JSON field names other than the grandfathered `pommora_table_widths`
- [ ] Every test file's class name matches its filename
- [ ] xcodebuild build clean exit
- [ ] xcodebuild test ** TEST SUCCEEDED **
- [ ] swift format lint --strict exit 0
- [ ] Sidebar renders: Pinned / Spaces / Topics (nested Projects) / Pages (with Page Types) / Items (with Item Types — sub-folders labeled "Set") / Agenda (Tasks + Events)
- [ ] `.nexus/settings.json` seeded on first nexus open with default labels + nil accent
- [ ] Every Pages-side + Project "New X" sheet title reads from SettingsManager (Items-side and Agenda-side sheets are intentional stubs — they don't read SettingsManager labels until the follow-up UI plan replaces them)
- [ ] Cmd+, opens the Settings scene (stub placeholder for now)
- [ ] Accent color reads from settings (nil = system default; explicit values override)
- [ ] Nathan's nexus migrated successfully + all data accessible
- [ ] v0.3.0 Properties spec updated to reference new types
- [ ] CLAUDE.md "Active branch quirks" updated: quirk #6 retired
- [ ] CLAUDE.md "Core Principles" includes the "Pommora prohibited" bullet

---

### Open questions to resolve before execution

These remain TBD; flag in plan-review:

1. **PageContentManager + ItemContentManager split** (Phase 5.5) — confirmed as the recommended approach.

2. **VaultView → SavedView rename** (Phase 2.3 Step 4) — recommended; struct serves both Page Types and Item Types.

3. **Page Type-root and Item Type-root content allowed** — both sides allow Pages/Items directly in their parent Type without a Collection. Confirmed.

4. **NewItemSheet Collection-less creation** — `newItem(collection: ItemCollection?, type: ItemType)` allows it. Confirmed.

5. **AgendaManager removal vs facade** — delete the legacy manager; each side gets its own. Confirmed.

6. **Migration script location** — `migration/` subfolder (not committed), archived after migration. Confirmed.

7. **Settings consolidation** — `.nexus/tier-config.json` and `.nexus/saved-config.json` stay SEPARATE from `.nexus/settings.json` in v0.3.0. Consolidation into a single file deferred to v0.6.0 Settings UI work.

8. **Settings UI scope in v0.3.0** — scaffold only (storage + manager + label wiring + Cmd+, stub). Full editing UI ships v0.6.0. To edit settings before then: edit `.nexus/settings.json` directly.

9. **Accent color palette** — 8 named colors (red/orange/yellow/green/blue/purple/pink/gray) plus nil (system default). Matches macOS standard accent options. Extensible later if custom hex picker becomes a Prospect.

---

### Execution mode

Two ways to run this plan after review:

**Option 1 — Subagent-driven (recommended).** Fresh subagent dispatched per task; main session reviews between tasks. Best for large multi-phase plans like this one — protects context window and lets each task ship green.

**Option 2 — Inline execution.** Tasks executed in the current session with checkpoints. Faster for small phases; risky for this scope.

If choosing Subagent-driven: each task's subagent gets the relevant section of this plan + the Pommora project quirks list from `CLAUDE.md`. Builder agent handles all `xcodebuild` calls (quirk #3).

All dispatched agents use Opus 4.7 per Nathan's lock.
