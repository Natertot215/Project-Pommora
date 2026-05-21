### Contexts + Vaults — Domain Model Revision Spec

#### Context

Locked synthesis of the 2026-05-16 RC session: **2-layer model** with PARA-aligned naming + tiered Contexts. Supersedes sections of `Domain-Model.md`, `Spaces.md`, `Collections.md`, `Items.md`, `Pages.md`, `Sidebar.md`, `PommoraPRD.md`, `Framework.md` once implemented (doc rewrites happen post-implementation).

**Locked discipline**: CRUD and paradigm land hand-in-hand. Each entity's first appearance in the codebase is paired with its CRUD interface — no separate later pass.

---

#### Final Domain Model

##### Two layers, PARA-aligned

| PARA term | Pommora term | Role |
|---|---|---|
| (workspace) | Nexus | The user's whole installation |
| Areas | Spaces (tier 1) | Broad life domains |
| Projects | Topics (tier 2) | Subject areas |
| (sub-projects) | Sub-topics (tier 3) | Specifics within a Topic |
| Resources | Vaults + Collections | Operational data containers |
| Archive | `.trash/` | Nexus-local trash (existing spec) |

##### Organization layer — Contexts

Three tiers, all exposed in UI from v1.

| Tier | Default label (renamable) | UI surface in sidebar |
|---|---|---|
| 1 | Space / Spaces | Flat row — no chevron, no children disclosure |
| 2 | Topic / Topics | Chevron-disclosure row, expanding to show file-nested Sub-topics |
| 3 | Sub-topic / Sub-topics | Leaf row inside parent Topic disclosure |

**Tier labels are user-configurable per-Nexus** via a Settings panel — singular and plural inputs per tier, Capacities-style. Code references entities by tier *number*; UI references by configured *label*.

##### Connection rules within the Contexts layer

- **Spaces** have no parents (tier 1 is root).
- **Topics** have multi-parent Spaces — a Topic can be tagged to multiple Spaces. Parent Space(s) are a **typed multi-valued relation property**, not a folder-structural fact.
- **Sub-topics** have a single **file-structural parent Topic** (encoded by Topic folder location). Fixed by the filesystem.
- **Sub-topics' `linked_relations`** — typed multi-valued relation property holding additional Topic / Space IDs beyond the file-structural parent. Editable in the property panel, queryable via index, surfaced in graph view. **NOT body wikilinks** — real relational properties.
- **Same-tier links are not file-structural** (Topic ↛ Topic, Space ↛ Space). Same-tier relationships live as body-content wikilinks inside that entity's composed page — never as parent / sibling relations.
- **Tier-skip allowed** — a Sub-topic can parent directly to a Space; `linked_relations` can target any tier.

##### Operational layer — Vaults / Collections / Content + Agenda

| Entity | Role | On disk |
|---|---|---|
| Vault | Folder with property schema applied to all contained Content | A folder containing `_vault.json` |
| Collection | Sub-folder within a Vault; shares the Vault's schema (v1) | A folder inside a Vault, no separate schema file |
| Content | The data itself — Pages (`.md`) and Items (`.json`) | Files inside a Collection |
| **Agenda** | **Calendar-anchored entities (Events, Tasks); EventKit-bridgeable; sibling of Vault, not nested** | **Files in `<nexus-root>/Agenda/` — `.agenda.json`** |

**Collection-local schemas** are a Prospect for post-v1. Simplicity-first: in v1, every Page or Item inside a Vault conforms to that Vault's single shared schema regardless of which Collection it lives in.

##### Inline editing in composed-page blocks (Notion-style)

**Embedded blocks are live, fully-editable views of their source — never read-only snapshots.** When a Context page or the Homepage embeds another entity (Items, Pages, Agenda items, Collection views, linked-content lists), the user can interact with that content in place — check off tasks, edit cells, add rows, change dates.

Structurally identical to Notion's embedded databases — the embed stores a reference (entity ID + view config + filters); UI renders an interactive view backed by the live source:

- **Embed = reference, not snapshot** — block JSON stores entity ID + view config; data read live from SQLite index
- **Edits route to the source manager** — e.g. checking off a Task calls `AgendaManager.toggleCompleted(...)`; manager atomic-writes; watcher catches; SQLite re-indexes; every embedded view refreshes live
- **Same write discipline everywhere** — no separate "embed-edit path"; both call the same manager methods

**Editability by block type (v1 scope):**

| Block type | Inline editing |
|---|---|
| Embedded Collection View (table / board / list / cards / gallery) | Full — edit cells, add rows, drag-reorder, change view config locally |
| Linked Items widget | Full — Item properties editable inline; toggle Item completion; add new Item |
| Linked Agenda widget (calendar / list) | Full — toggle task completion, edit due dates, drag to reschedule, add new Agenda item |
| Linked Pages widget | Mixed — title and frontmatter properties editable inline; full body editing requires opening the Page in a tab |
| Link list | Full — rename labels, reorder, add / remove links |
| Text blocks (paragraphs, headings, callouts, columns) | Full — composed-page authoring as expected |

**Why this matters for implementation:** the block renderer is a thin shell around the entity's normal property/row UI components — NOT a separate read-only renderer. Item-Window's property editor and Collection-view-block's row editor are the *same component* in different layouts. Reuse is structural.

**Out-of-scope for v1:** drag-to-rewrite-frontmatter on kanban boards (post-v1.0); cross-block transclusion of body text (post-v1); collaborative simultaneous editing (out of scope indefinitely — single-user).

**Why Agenda is separate from Vaults:**
- EventKit requires structurally distinct entities matching `EKEvent` and `EKReminder` shapes — fixed schemas with `startDate`/`endDate` or `dueDate`/`completed`. Generic Vault Items can't carry these without lossy mapping.
- Quick-capture surfaces (system Calendar, Siri, Reminders, widgets, Notification Center) need a single known-location entity — "create a task" shouldn't have to decide "in which Vault?"
- Mac-first posture makes deep EventKit integration real value, not polish.
- UX-wise Agenda items behave identically to Items — Item Window popover, tier1/2/3 multi-relations, user properties, sortable/filterable. Distinction is on-disk + EventKit-facing only.

##### Cross-layer connections (Content → Contexts)

Pages and Items carry **per-tier multi-relation fields**:

```yaml
tier1: [<space-id>, ...]   # multi-valued, independent
tier2: [<topic-id>, ...]   # multi-valued, independent  
tier3: [<subtopic-id>, ...] # multi-valued, independent
```

Each tier's relation is filled independently — no requirement to fill all three. A Task can link only to a Sub-topic, only to a Space, all three, or any combination.

##### Sidebar shape

```
[Sidebar]
─ Saved ────────────────────────
  Homepage
  Calendar
  Recents
─ Spaces ───────────────────────
  ◉ Personal       [color/symbol]
  ◉ Academics
  ◉ Work
  + New Space
─ Topics ───────────────────────
  ▾ Academics      [tagged: red]
      CS 161
      Linear Algebra
  ▾ Productivity   [tagged: blue + green]   ← multi-Space
      GTD method
      Time-blocking
  ▸ Side Projects  [tagged: blue]
  + New Topic
─ Vaults ───────────────────────
  ▾ Planner
      Tasks
      Goals
      Events
  ▾ Materials
      Pages
      Documents
      Reports
  + New Vault
```

**Saved section** (renamed from earlier "Pinned"):
- Three default items: `Homepage`, `Calendar`, `Recents`. Keys fixed in code (`homepage`, `calendar`, `recents`); labels user-renamable via Settings.
- `Homepage` opens the **Homepage entity** (singleton; see below)
- `Calendar` opens the **Agenda layer's calendar view**
- `Recents` shows recently-opened tabs (lightweight v1 if state tracking available; otherwise placeholder)
- User-pinning of arbitrary entities is a post-v1 Prospect

**Homepage entity** (singleton, NOT a Space):
- One per Nexus; fixed code key `homepage`; stored at `.nexus/homepage.json`
- Composed-blocks dashboard surface — can embed linked-content views, Vault collection views, link lists, prose, callouts, columns, calendar mini-views, anything
- Shares the composed-blocks surface pattern with Contexts. Distinction = **identity / parenting**:
  - Contexts have `id`, `tier`, `parents` — tiered parented entities that things relate *to*
  - Homepage is a singleton — no `id`, no tier, no parents — pulls things *in* but isn't a referent

**Topic tagging visual** (sidebar tagging of Topics by parent Space):
- Renderable as color dots, SF Symbol icons, or both — all three modes supported
- Spaces store `color` and `icon`/`symbol` fields; tagging style is a setting (v1 default: color dot)
- Multi-Space Topics show multiple indicators side by side

---

#### File Layout

```
<nexus-root>/
  .nexus/
    nexus.json                           ← v0.1a: ULID + createdAt
    state.json                           ← v0.2+: open tabs, sidebar collapsed state
    tier-config.json                     ← NEW: tier label config
    saved-config.json                    ← NEW: Saved section label config
    homepage.json                        ← NEW: singleton Homepage entity

    spaces/                              ← tier 1, flat files
      Personal.space.json
      Academics.space.json
      Work.space.json

    topics/                              ← tier 2 (each Topic is a folder)
      Academics/
        _topic.json                      ← parents: [Academics-id]
        CS-161.subtopic.json             ← file-structural parent = this folder
        Linear-Algebra.subtopic.json
      Productivity/
        _topic.json                      ← parents: [Personal-id, Work-id]
        GTD-method.subtopic.json
      Side-Projects/
        _topic.json

  Agenda/                                ← operational-layer sibling of Vaults
    Buy-groceries.agenda.json
    Team-standup.agenda.json
    Submit-report.agenda.json

  Planner/                               ← Vault
    _vault.json                          ← shared schema for all contained Content
    Tasks-archive/                       ← Collection (generic Tasks for non-EventKit work)
      Old-task.json
    Goals/
      Q1-goals.json
    Events-notes/                        ← Collection (notes about events, not events themselves)
      Conference-summary.md

  Materials/                             ← Vault
    _vault.json
    Pages/                               ← Collection
      Attention-is-all-you-need.md
    Documents/
      Annual-report.json
    Reports/
      Research-summary.md

  .trash/                                ← nexus-local trash
  .git/, .obsidian/, etc.                ← user dotfolders, filtered from sidebar

~/Library/Application Support/com.nathantaichman.Pommora/
  state.json                             ← machine-specific (security-scoped bookmark)
  nexuses/<nexus-id>/
    nexus.db                             ← regeneratable SQLite index (v0.2+)
```

---

#### File Schemas

##### Space (`.nexus/spaces/<Title>.space.json`)

```json
{
  "id": "01H...",
  "tier": 1,
  "icon": "person.circle",
  "color": "blue",
  "blocks": [],
  "modified_at": 1716480000
}
```

- `color`: one of 9 Notion-palette colors (`gray`, `brown`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `red`)
- `icon`: SF Symbol name (e.g. `person.circle`)
- `blocks`: composed-page block tree (same shape as existing `.space.json`)

##### Topic (`.nexus/topics/<Title>/_topic.json`)

```json
{
  "id": "01H...",
  "tier": 2,
  "parents": ["01H...space-id", "01H...space-id"],
  "icon": "graduationcap",
  "blocks": [],
  "modified_at": 1716480000
}
```

- `parents`: multi-Space; each must be a tier-1 Space
- `icon`: SF Symbol name (optional)
- No own `color` — visual tag inherited from parent Space(s)

##### Sub-topic (`.nexus/topics/<TopicFolder>/<Title>.subtopic.json`)

```json
{
  "id": "01H...",
  "tier": 3,
  "parents": ["01H...topic-id"],
  "linked_relations": ["01H...other-topic-id", "01H...space-id"],
  "icon": "doc.text",
  "blocks": [],
  "modified_at": 1716480000
}
```

- `parents`: single-valued, the file-structural parent Topic (encoded by folder location). Cannot be changed without moving the file.
- `linked_relations`: typed multi-valued relation property (edited in property panel). Holds IDs of additional Topics / Spaces. NOT body wikilinks — real relational properties queryable via index, surfaced in graph view + property panel.
- `icon`: SF Symbol name (optional)

##### Tier config (`.nexus/tier-config.json`)

```json
{
  "schemaVersion": 1,
  "tiers": [
    { "level": 1, "singular": "Space", "plural": "Spaces", "exposed": true },
    { "level": 2, "singular": "Topic", "plural": "Topics", "exposed": true },
    { "level": 3, "singular": "Sub-topic", "plural": "Sub-topics", "exposed": true }
  ],
  "tagging_style": "color"
}
```

- `tagging_style`: `"color"` | `"symbol"` | `"both"` — controls how Topic rows render their parent-Space indicators in the sidebar

##### Saved-section config (`.nexus/saved-config.json`)

```json
{
  "schemaVersion": 1,
  "items": [
    { "key": "homepage", "label": "Homepage" },
    { "key": "calendar", "label": "Calendar" },
    { "key": "recents",  "label": "Recents" }
  ]
}
```

- `key`: immutable, code-referenced
- `label`: user-renamable

##### Homepage (`.nexus/homepage.json`) — singleton

```json
{
  "schemaVersion": 1,
  "icon": "house",
  "blocks": [
    /* composed-blocks tree — text, headings, callouts, columns,
       embedded-collection-view, embedded-context-view,
       linked-pages, link-list, mini-calendar (Agenda), etc. */
  ],
  "modified_at": 1716480000
}
```

- Singleton — no `id` field (file location is identity)
- `blocks`: same composed-page block tree as `.space.json`. Can embed any entity by ID.
- Seeded on first launch with a minimal default (welcome heading + empty callout)
- Distinct from Spaces — Spaces are categorical anchors (things relate *to*); Homepage is a user-composed dashboard (pulls things *in*)

##### Agenda Item (`<nexus-root>/Agenda/<Title>.agenda.json`)

Single unified entity — no structural `kind` discriminator. User-facing distinction (Task / To-Do / Phase / Event) is a `properties.type` Select, user-extensible. EventKit mapping is driven by which time fields are populated, not a schema discriminator.

Schema mirrors EventKit primitives (`EKEvent`, `EKReminder`) — each field has an exact EventKit counterpart for 1:1 sync.

```json
{
  "id": "01H...",
  "icon": "checkmark.circle",

  /* Time fields — all optional; combination determines EventKit mapping */

  /* Event-shaped (mirrors EKEvent.startDate / .endDate / .isAllDay) */
  "start_at": null,                       /* ISO-8601 with timezone; if set, end_at is required */
  "end_at":   null,                       /* ISO-8601 with timezone */
  "all_day":  false,

  /* Reminder-shaped (mirrors EKReminder.dueDateComponents) */
  "due_at":        null,                  /* ISO-8601; converted to DateComponents on EventKit save */
  "due_floating":  false,                 /* true = nil timezone in DateComponents ("3 PM local wherever I am") */
  "due_all_day":   false,                 /* true = DateComponents without hour/minute/second */

  /* Completion (mirrors EKReminder.isCompleted / .completionDate) */
  "completed":    false,
  "completed_at": null,                   /* ISO-8601; only meaningful when completed == true */

  /* Shared optional fields */
  "location":       null,                 /* mirrors EKEvent.location (string); EKReminder doesn't carry location */
  "recurrence":     null,                 /* EKRecurrenceRule-shaped JSON — see "Recurrence shape" below */
  "alarm_offsets":  [],                   /* array of TimeInterval (seconds) before start_at / due_at */
                                          /*   matches EKAlarm.relativeOffset semantics exactly */
                                          /*   negative = before; positive = after */
  "alarm_absolute": [],                   /* array of ISO-8601 absolute dates for EKAlarm(absoluteDate:) */

  /* EventKit sync (nullable; populated only when item is mirrored) */
  "sync_target":   null,                  /* "calendar" | "reminder" | null (inferred from time fields) */
  "calendar_id":   null,                  /* EKCalendar.calendarIdentifier */
  "eventkit_uuid": null,                  /* EKEvent.eventIdentifier OR EKCalendarItem.calendarItemIdentifier */
                                          /*   (which one is determined by sync_target / inferred kind) */

  /* Same shape as Items — Context relations + lifecycle */
  "description":  "Short plain text, 250-char cap",
                                          /* maps to EKCalendarItem.notes on sync */
  "tier1": [], "tier2": [], "tier3": [],
  "created_at":  1716480000,
  "modified_at": 1716480000,

  /* User-defined properties — including `type` */
  "properties": {
    "type":     "Task",                   /* Built-in Select; defaults [Task, To-Do, Phase, Event]; user-extensible */
    "priority": null,                     /* Optional. If present + numeric (0/1/5/9), maps to EKReminder.priority on sync */
                                          /*   0 = none, 1 = high, 5 = medium, 9 = low (EventKit convention) */
    /* other user properties */
  }
}
```

##### Recurrence shape (verified against EventKit docs 2026-05-16)

EventKit uses `EKRecurrenceRule`, conceptually equivalent to RFC 5545 RRULE but represented as a structured Objective-C object — not a raw RRULE string. Pommora stores the recurrence as JSON matching `EKRecurrenceRule`'s actual shape:

```json
"recurrence": {
  "frequency":          "weekly",                  /* "daily" | "weekly" | "monthly" | "yearly" */
  "interval":           1,                         /* every N units */
  "first_day_of_week":  2,                         /* 1=Sunday … 7=Saturday; affects weekly recurrence semantics */
  "end": {                                         /* nullable; one shape OR the other */
    "kind":  "occurrence_count",
    "value": 10
  },
  "days_of_week": [                                /* array of structured EKRecurrenceDayOfWeek shapes */
    { "day": "mon" },
    { "day": "wed" },
    { "day": "fri", "week_number": -1 }            /* "last Friday of the month" — week_number -1..-5 or 1..5 */
  ],
  "days_of_month":   [],                           /* array of integers (NSNumber on the EventKit side) */
  "days_of_year":    [],
  "weeks_of_year":   [],
  "months_of_year":  [],
  "set_positions":   []                            /* e.g. [-1] for "last instance" */
}
```

A small serializer/deserializer (~80 lines) converts between JSON and `EKRecurrenceRule` on sync.

**Constraint:** `EKRecurrenceRule` is read-only after creation — modifying recurrence on a saved EKEvent/EKReminder requires constructing a new `EKRecurrenceRule` and reassigning. Pommora's sync layer always builds fresh; no in-place mutation.

##### EventKit change observation (Swift Concurrency)

Observe external EKEventStore changes via `NotificationCenter` async sequences:

```swift
let center = NotificationCenter.default
Task {
    for await _ in center.notifications(named: .EKEventStoreChanged) {
        await agendaManager.reconcileWithEventKit()
    }
}
```

Reconciliation re-fetches EKEvents/EKReminders in selected calendars, compares against `.agenda.json` files by `eventkit_uuid` + `lastModifiedDate`, applies last-write-wins per item.

**Built-in schema for Agenda items** (`<nexus-root>/Agenda/_agenda.json`):

```json
{
  "schemaVersion": 1,
  "icon": "calendar",
  "properties": [
    {
      "name": "type",
      "type": "select",
      "options": [
        { "value": "Task",   "color": "blue" },
        { "value": "To-Do",  "color": "yellow" },
        { "value": "Phase",  "color": "purple" },
        { "value": "Event",  "color": "green" }
      ],
      "builtin": true,                    /* cannot be deleted, but options can be edited and added */
      "default": "Task"
    }
    /* additional user-defined properties (priority, status, etc.) editable like a Vault */
  ],
  "views": [
    /* saved calendar / list / board views over Agenda items */
  ],
  "modified_at": 1716480000
}
```

- Agenda uses Vault's schema mechanism (`_agenda.json` sidecar); reuses Vault property/view editor UI
- Built-in `type` Select defaults to `[Task, To-Do, Phase, Event]` — users can add types (e.g. "Habit", "Block") and rename existing options; the `type` property itself cannot be deleted (`builtin: true`)
- All other Agenda properties are user-defined like Vault properties

##### EventKit mapping (data-driven, no explicit kind)

| Pommora Agenda fields populated | EventKit target | Mapping notes |
|---|---|---|
| `start_at` + `end_at` set | `EKEvent` | `startDate` ← `start_at`; `endDate` ← `end_at`; `isAllDay` ← `all_day`. Uses `eventIdentifier`. |
| `due_at` set, no `start_at` | `EKReminder` | `dueDateComponents` ← `due_at` (with `timeZone = nil` if `due_floating == true`; with hour/minute/second stripped if `due_all_day == true`). Uses `calendarItemIdentifier`. |
| Neither set | `EKReminder` | Unscheduled to-do — `dueDateComponents` left nil. macOS allows this; iOS doesn't (port consideration). |
| `sync_target` explicitly set | Forced target | Edge cases (e.g. user marks a long "Phase" with start+end as a Reminder rather than Calendar event). |

##### EventKit permissions + entitlements (required for sandbox)

Pommora is sandboxed (`ENABLE_APP_SANDBOX = YES`); EventKit requires additional setup:

**1. Sandbox entitlement:** `com.apple.security.personal-information.calendars` — set via Xcode build setting `ENABLE_PERSONAL_INFORMATION_CALENDARS = YES` (auto-generates entitlement, same mechanism as `ENABLE_USER_SELECTED_FILES = readwrite`). Without it, EventKit calls fail silently in sandboxed builds.

**2. Info.plist usage description keys** (required for system permission prompts):
- `NSCalendarsFullAccessUsageDescription`
- `NSRemindersFullAccessUsageDescription`
- Separate keys for separate grants; both required if Agenda syncs both.

**3. Permission request flow (macOS 14+ / iOS 17+):**
- Use `requestFullAccessToEvents(completion:)` and `requestFullAccessToReminders(completion:)` (or async variants)
- Legacy `requestAccess(to:completion:)` is deprecated on macOS 14+ — Pommora targets macOS 26.4 so well past cutoff
- Calendar offers `requestWriteOnlyAccessToEvents`; Reminders has no write-only equivalent

**4. Identifiers for two-way sync stability:**
- `EKEvent.eventIdentifier` for events; `EKCalendarItem.calendarItemIdentifier` for reminders (also works as a generic identifier)
- Both documented stable for external persistence — safe to store in `eventkit_uuid`
- `EKEventStoreChangedNotification` posts on external EventKit data changes — observe for two-way sync

**5. Sync conflict policy (initial v1):** last-write-wins by `modified_at` / EKCalendarItem's `lastModifiedDate`. Surface conflict count in UI; don't block sync. Sophisticated resolution is post-v1.

##### UI affordance — collapsed single-date input

When `start_at` and `due_at` would carry the same value, the property editor collapses them into a single "When?" date input. Expands back to two inputs when the user wants asymmetric values. On disk both fields persist separately — collapse is purely UI. Schema unchanged. Resolved when Agenda property panel lands (Phase 6.5 / 7 area).

##### Notes and constraints

- Filename = title (same convention as Items and Pages)
- `calendar_id` + `eventkit_uuid` nullable — populated only when EventKit sync is enabled per-item or globally
- Disabling sync per-item clears `eventkit_uuid` (Pommora item persists; EventKit mirror removed)
- **EventKit sync NOT enabled in v1 by default** — users opt in via Settings → Agenda. Schema fields exist day one so opt-in is additive, not migration.

##### Vault (`<nexus>/<VaultName>/_vault.json`)

```json
{
  "id": "01H...",
  "icon": "folder",
  "properties": [
    { "name": "status", "type": "select", "options": [...] },
    { "name": "due", "type": "date" }
  ],
  "views": [],
  "modified_at": 1716480000
}
```

- `properties`: schema entries; v1 shared across all Collections inside the Vault
- `views`: saved view configurations (table / board / list / cards / gallery)

##### Property value encoding (PropertyValue Codable)

Property values on disk (Page frontmatter, Item `properties`, Agenda `properties`) decode via shape-sniffing. Most types decode directly:

- `number` → JSON number
- `checkbox` → JSON boolean
- `date` / `datetime` → ISO-8601 string (date-only vs with time)
- `select` → JSON string (the option's value)
- `multiSelect` → JSON `[string]` array
- `url` → JSON string

**Relation values use a tagged-object encoding** `{"$rel": "<ULID>"}` (paradigm decision 2026-05-16, `// Guidelines//Paradigm-Decisions.md`) — NOT a bare string. Bare-string `.relation` and `.select` are indistinguishable on the wire; tagged-object form makes relation edges legible to external agents + the graph indexer without consulting Vault schema (satisfies load-bearing constraint #3). Single: `{"$rel": "01H..."}`. Multi: `[{"$rel": "..."}, {"$rel": "..."}]`.

Example mixed-properties block:

```json
{
  "status": "Active",
  "due": "2026-06-15",
  "owner": {"$rel": "01H...page-id"},
  "tags": ["urgent", "frontend"],
  "url": "https://..."
}
```

##### Collection (`<nexus>/<VaultName>/<CollectionName>/_collection.json`)

```json
{
  "id": "01H...",
  "vault_id": "01H...parent-vault-id",
  "modified_at": 1716480000
}
```

Minimal `_collection.json` sidecar. `vault_id` makes the parent-Vault relation explicit on-disk so external tools navigate without inferring from nesting. Title from folder name (filename-as-title). Collections share parent Vault's schema in v1.

**Post-v1 Prospect**: Collection-local schema overrides + per-Collection icons / descriptions / view configs land additively in `_collection.json` (no migration cost). Not v1.

##### Item (`<nexus>/<VaultName>/<CollectionName>/<Title>.json`)

```json
{
  "id": "01H...",
  "icon": "tag",
  "description": "Short plain text, 250-char cap",
  "tier1": ["01H...space-id"],
  "tier2": ["01H...topic-id"],
  "tier3": ["01H...subtopic-id"],
  "properties": {
    "status": "Active",
    "due": "2026-06-15"
  },
  "created_at": 1716480000,
  "modified_at": 1716480000
}
```

##### Page (`<nexus>/<VaultName>/<CollectionName>/<Title>.md`)

```markdown
---
id: 01H...
icon: doc
tier1: [01H...space-id]
tier2: [01H...topic-id]
tier3: [01H...subtopic-id]
status: Active
created_at: 2026-05-16
---

# Page body in Markdown
```

---

#### Validation Rules

Enforced at every file write. Reject + warn the user if violated.

1. **Tier-parent rule**: a Tier entity's `parents[i]` must resolve to a Tier with `level < this.tier`. Cycles impossible by construction.
2. **Sub-topic single-parent at file**: a Sub-topic's `parents` array contains exactly one ID for file-structural parent. Additional links go in `linked_relations` (typed multi-valued relation property, NOT body wikilinks).
3. **Sub-topic file location**: a Sub-topic file MUST physically live inside a Topic folder. The file's folder location IS the file-structural parent.
4. **Item / Page / Agenda tier-N rule**: every value in a `tierN` array must resolve to a Tier entity with `level == N`.
5. **Vault schema conformance**: every Item and Page inside a Vault must carry property values that conform to the Vault's schema (extra fields stripped on write per existing move-strip rule).
6. **Agenda schema conformance**: every Agenda item must carry property values conforming to `Agenda/_agenda.json`. The built-in `type` property cannot be removed; its options can be edited.
7. **Agenda time-field consistency**: if `start_at` is set, `end_at` MUST also be set (and `end_at >= start_at`). `due_at` is independently optional. `all_day` is only meaningful when `start_at` is set.
8. **Homepage is singleton**: exactly one `.nexus/homepage.json` per Nexus. Created on first launch if missing; never deleted by user action.
9. **Filename = title**: no separate `title` field on any entity (except Homepage, which is a singleton with no title). The filename is canonical.

---

#### CRUD Scope per Entity

Each entity must support all four operations in v1.

Context entities (Space / Topic / Sub-topic) open a composed-blocks page on Read (can embed anything, like Homepage).

| Entity | Create | Read | Update | Delete |
|---|---|---|---|---|
| Space | Name + color + icon picker | Composed-blocks page | Inline rename / right-click change color/icon / edit blocks | Confirm + warn if Topics reference it (strips parent reference from Topics) |
| Topic | Name + parent Space picker (multi) + icon | Composed-blocks page | Inline rename / change parents / icon / edit blocks | Confirm + warn if Sub-topics inside (move out OR cascade?) |
| Sub-topic | Inside expanded Topic; name + icon | Composed-blocks page | Inline rename / move to another Topic / edit linked_relations via property panel / edit blocks | Confirm + delete |
| Vault | Name + icon + schema editing | Click to open default Collection view | Inline rename / icon / edit Vault schema | Confirm + warn (contains N Collections, M Items/Pages) |
| Collection | Inside Vault; name only | Click to open view | Inline rename | Confirm + warn (contains N Items/Pages) |
| Item | Inside Collection; name | Item Window popover | Item Window (properties, description, relations) | Confirm + delete |
| Page | Inside Collection; name | Tab | Editor in tab | Confirm + delete |
| **Homepage** | **Seeded on first launch (no manual create)** | **Saved → Homepage opens it in a tab** | **Composed-blocks editor (Phase 10)** | **Not user-deletable (singleton)** |
| **Agenda Item** | **From Calendar saved view / quick-capture (no Vault decision); name + type + optional times** | **Item Window popover OR inline in calendar view** | **Item Window (properties, time fields, relations); EventKit two-way sync** | **Confirm + delete (with EventKit unsync if mirrored)** |

**Open question (parked):** on Topic delete — cascade sub-topics or promote to standalone? Recommend warning + cascade-delete as v1 default (standalone sub-topics aren't an exposed concept). Confirm during implementation.

---

#### Implementation Phasing

CRUD + paradigm pair every step. Each phase ships a functional slice — entity creation works end-to-end on disk before next phase begins.

##### Phase 0 — Schema + Codable foundation
- Codable structs: `Space`, `Topic`, `Subtopic`, `Vault`, `TierConfig`, `SavedConfig`, `Item`, `PageFrontmatter`
- ULID already shipped (v0.1a `ULID.swift`)
- Atomic-write JSON helpers (`.tmp` + rename)
- YAML frontmatter parser for `.md` (frontmatter only; body stays raw `String` until editor work)
- Round-trip tests for every Codable

##### Phase 1 — File system primitives + validation
- Folder create / rename / delete under sandbox (security-scoped bookmark coordination)
- File create / atomic write / read / delete
- Validation rules engine (tier-parent, sub-topic file location, etc.)
- Extend `FolderTree.swift` to recognize Spaces/Topics/Vaults/Collections vs. cosmetic folders

##### Phase 2 — Spaces CRUD + sidebar (first user-visible slice)
- New `Spaces/` source folder; `SpaceFile.swift`, `SpaceManager.swift` (`@Observable @MainActor`)
- Sidebar `Spaces` section renders flat rows from `SpaceManager.spaces`
- "+ New Space" — sheet with name + color picker + SF Symbol picker
- Inline rename (tap-to-edit); right-click menu (rename, change color, change icon, delete); delete confirmation
- Reuses locked v0.0 `SelectableRow` selection language

##### Phase 3 — Topics CRUD + sidebar
- New `Topics/` source folder; `TopicFile.swift`, `SubtopicFile.swift`, `TopicManager.swift`
- Sidebar `Topics` section: chevron-disclosure per Topic
- "+ New Topic" — sheet with name + parent Space multi-picker + icon picker
- Topic creation = folder + `_topic.json` written atomically
- Tagging indicator (color dot v1; symbol/both later)
- Inline rename, right-click menu, delete with cascade warning

##### Phase 4 — Sub-topics CRUD
- "+ New Sub-topic" inside expanded Topic; file written into parent Topic's folder
- Inline rename; right-click rename / move to another Topic (FS move + relink) / delete
- `linked_relations` editing deferred to property panel (Phase 7)

##### Phase 5 — Vaults + Collections CRUD + sidebar
- New `Vaults/` source folder; `VaultFile.swift`, `VaultManager.swift`
- Sidebar `Vaults`: chevron-disclosure per Vault; sub-disclosure per Collection (no chevron in v1 — leaf node showing Items list when opened)
- "+ New Vault" — name + icon picker; schema starts empty (full property editor v1.x)
- "+ New Collection" — name only; creates folder inside Vault
- Rename + delete with cascade warnings

##### Phase 6 — Content CRUD (Pages + Items)
- "+ New Page" → `.md` with frontmatter scaffold (id, tier1/2/3 empty, properties empty)
- "+ New Item" → `.json` with empty properties/relations
- Inline rename in sidebar / Item Window; delete

##### Phase 7 — Cross-tier relations on Items/Pages
- Property panel UI for `tier1`/`tier2`/`tier3` multi-select chips
- Type-to-search relation picker resolves to Tier entity IDs
- Save → atomic write to frontmatter/json; SQLite `links` table re-indexes via watcher

##### Phase 8 — Tier-config + Saved-config settings UI
- Settings scene scaffold (Cmd-, opens `SettingsScene`)
- Tier labels editor — 3 sections, singular + plural text fields each
- Saved-section labels editor — 3 rows (homepage/calendar/recents), label only
- Tagging style picker (color / symbol / both)

##### Phase 9 — Saved section content
- `Homepage` resolves to seeded Homepage Space; clicking opens it
- `Calendar` placeholder — "Calendar view coming v1.x"
- `Recents` — implement if recently-opened-tabs tracking exists; otherwise placeholder

##### Phase 10 — File watcher integration (v0.2 spec)
- FSEventStream on the nexus folder
- External file changes → SQLite re-index → sidebar refresh
- Atomic-write detection (debounce 50–100 ms; track outbound mtimes to ignore self-writes)

##### Phase 11 — Graph view foundation (Prospect, code-ready)
- SQLite `links` table queryable for graph data
- Reserve tab-content shape that can accommodate a graph-view tab later
- No graph rendering in v1

---

#### What Changes from Current Spec Docs (post-implementation)

Tracking list (edits happen post-implementation, not as part of this work):

- `PommoraPRD.md` → Storage Model section, on-disk tree, SQLite schema
- `Features/Domain-Model.md` → Major rewrite (2-layer model with PARA mapping)
- `Features/Pages.md` → Add `tier1/2/3` relations
- `Features/Items.md` → Add `tier1/2/3` relations
- `Features/Collections.md` → Major rewrite (Collection inside Vault, shares schema)
- `Features/Spaces.md` → Reframe as tier-1 Context (still composed surface)
- `Features/Sidebar.md` → Major rewrite (Saved/Spaces/Topics/Vaults sections)
- `Features/Architecture.md` → Update entity list, validation rules
- `Features/Properties.md` → Update scope (Vault-wide in v1)
- `Framework.md` → Reorder phases (CRUD lands paired with paradigm; v0.2 watcher = Phase 10 of this spec)
- NEW: `Features/Contexts.md` → entire spec for the Contexts tier system
- NEW: `Features/Vaults.md` → entire spec for Vaults/Collections (replacing parts of `Collections.md`)
- NEW: `Guidelines/CRUD-Patterns.md` → SwiftUI patterns + atomic-write discipline

---

#### Verification

After each Phase ships:
- `xcodebuild -project Pommora/Pommora.xcodeproj -scheme Pommora build` succeeds
- Phase's Codable round-trip tests pass
- Manual: create / rename / delete works end-to-end; on-disk files reflect; sidebar updates live
- `codesign -d --entitlements - Pommora.app` confirms sandbox intact
- LLM-legibility check: `cat` a freshly created file — confirm human/agent-parseable

##### End-to-end gold path test (Phase 2 onward)

- **Phase 2:** create Space "Personal", rename to "Life", delete. Verify all operations land on disk; sidebar reflects instantly.
- **Phase 3:** create Personal Space + "Productivity" Topic tagged to Personal. Verify Topic folder + `_topic.json`; sidebar shows under chevron disclosure.
- **Phase 4:** add Sub-topic "GTD Method" inside Productivity. Verify file in correct folder; sidebar shows nesting.
- **Phase 5:** create Planner Vault with Tasks Collection inside.
- **Phase 6:** create Item "Buy groceries" inside Planner/Tasks. Open in Item Window.
- **Phase 7:** edit Task's `tier2` to include Productivity. Verify persistence + surfacing on Productivity Topic's page.

That's the v1 organization + operational layer fully functional.

---

#### Research Findings — SwiftUI Implementation Patterns

Derived from `swiftui-expert-skill` + Pommora code review (`NexusManager`, `NexusStore`, `NexusIdentity`, `SidebarView`, `FolderTree`).

##### 1. Manager pattern — per entity, mirroring `NexusManager`

`NexusManager` is `@MainActor @Observable final class` with single source-of-truth. **Same shape per new entity** — no unified store; each entity has independent file locations, validation, and CRUD flows. Per-entity managers keep state-driven updates narrowly scoped. Concrete shape in Day-1 plan step 7 (`SpaceManager`).

Inject active Nexus root URL at construction; re-load when `NexusManager.currentNexus` changes via `.onChange(of:)` on the parent view.

##### 2. Sidebar pattern — extend the existing `SidebarView`

`SidebarView` already uses `List` with `Section(isExpanded:)` + `DisclosureGroup` + locked `SelectableRow`. **No new sidebar architecture** — swap hardcoded placeholders for manager data.

Layout target:
- Top-level `List` with four `Section`s: Saved, Spaces, Topics, Vaults
- Saved: 3 fixed rows (`Homepage`, `Calendar`, `Recents`) reading labels from `SavedConfig`
- Spaces: `ForEach(spaceManager.spaces)` — flat rows, no chevron
- Topics: `ForEach(topicManager.topics)` — each is a `DisclosureGroup` of sub-topics
- Vaults: `ForEach(vaultManager.vaults)` — each is a `DisclosureGroup` of Collections (leaf rows)

`SelectableRow` encapsulates selection chrome — reuse as-is.

##### 3. Inline rename — `@FocusState` + `TextField`

Pattern on macOS Tahoe: `@State editingID: String?` + `@State draftName: String` + `@FocusState renameFocused: Bool`. When `editingID == space.id`, render `TextField` with `.focused($renameFocused)`, `.onSubmit { commitRename(); editingID = nil }`, `.onExitCommand { editingID = nil }`; otherwise render `Text(space.title)`.

Trigger via right-click → "Rename" or Enter on selected row (`.onKeyPress(.return)`). Avoid double-click — conflicts with open-on-click for openable entities.

##### 4. Right-click context menu — `.contextMenu`

Native SwiftUI `.contextMenu` per row, with Buttons for Rename / Change Color / Change Icon / Divider / Delete (destructive role). Color/icon pickers + delete confirmation drive via `.sheet(item:)` + `.confirmationDialog(item:)` (deferred to Phase 2+).

##### 5. "+ New" sheets — `.sheet(item:)` with enum-keyed presentation

Item-driven sheets preferred. Each section's `+ New X` button sets a presentation enum:

```swift
enum SidebarSheet: Identifiable {
    case newSpace
    case newTopic
    case newVault
    case newCollection(vault: Vault)
    case newSubtopic(topic: Topic)
    var id: String { ... }
}

@State private var presentedSheet: SidebarSheet?

.sheet(item: $presentedSheet) { sheet in
    switch sheet {
    case .newSpace: NewSpaceSheet()
    case .newTopic: NewTopicSheet()
    case ...
    }
}
```

Each sheet owns its actions via `@Environment(\.dismiss)` — no callback prop-drilling.

##### 6. Atomic JSON write — already done in `NexusIdentity`

Pattern from `NexusIdentity.save(to:)`: `JSONEncoder` (`.prettyPrinted`, `.sortedKeys`, `.iso8601`) + `Data.write(to:options:[.atomic])` (writes to temp + atomic-rename — no separate `.tmp` helper). **Reuse verbatim for every Codable entity.** Concrete impl in Day-1 plan step 3 (`AtomicJSON`).

##### 7. YAML frontmatter parsing — recommend `Yams` (MIT, jpsim)

No first-party Apple YAML parser. `apple/swift-markdown` handles body but not frontmatter.

**Use [Yams](https://github.com/jpsim/Yams)** (MIT, John Sundell, jpsim-maintained, used by SwiftPM tooling). API: `try YAMLDecoder().decode(PageFrontmatter.self, from: yamlString)`.

Parsing a `.md`:
1. Read file as `String`
2. Detect frontmatter block via leading `---\n` + trailing `\n---\n`
3. `YAMLDecoder().decode(PageFrontmatter.self, ...)` on inner YAML
4. Body = everything after trailing `---`

Wrap into a `PageFile` struct mirroring `NexusIdentity`'s `load(from:)` / `save(to:)`. Encoder uses `YAMLEncoder()`. SPM: `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`.

##### 8. SF Symbol icon picker — `xnth97/SymbolPicker` SPM dep, wrapped behind `IconPickerSheet`

**Locked 2026-05-16**: `xnth97/SymbolPicker` — most popular, simplest API, cross-platform (macOS 13+), sheet-presented, maintained.

Wrapped in `Pommora/Pommora/Sidebar/Sheets/IconPickerSheet.swift` — `@Binding var icon: String` + a Button that presents `SymbolPicker(symbol: $icon)` via `.sheet(isPresented:)`. Call sites see Pommora's API only; replacing the library is a single-file wrapper rewrite.

SPM dep: `.package(url: "https://github.com/xnth97/SymbolPicker", from: "1.5.1")`.

##### 9. Validation enforcement — pure functions on Codable entities

Validation runs at the manager layer (before write). Concrete `SpaceValidator` impl in Day-1 plan step 6. Manager pattern: `try Validator.validate(...) → try await save(...)`.

Tier-parent validation needs access to other tiers' managers (to resolve parent IDs). Two options:
- Pass dependent managers into the validator call
- Validators as methods on a higher-level `NexusCoordinator` holding all managers

Simpler v1: static functions; manager fetches parent data and passes it in. Coordinator later if needed.

##### 10. Sandbox + security-scoped access — already solved

`NexusManager` handles `startAccessingSecurityScopedResource()` / `stop...` lifecycle. New file writes inside the nexus inherit access from the active resource scope — no per-write bookmark.

**Discipline:** new entity managers MUST NOT call `startAccessing` independently — they assume `NexusManager` holds the active scope. Read `nexusURL` from the active `Nexus`; write within that tree.

---

#### Ready-to-Code-Today Working Plan

Day-1 scope: Phases 0–2 (Codable foundation, FS + validation, Spaces CRUD + sidebar). End-of-day: user can create / rename / delete a Space; file lands on disk; sidebar updates live.

Files to create:

```
Pommora/Pommora/
  Contexts/                       ← NEW
    Space.swift                   ← Codable value type
    SpaceColor.swift              ← enum (Notion 9-palette)
    SpaceFile.swift               ← load/save (mirrors NexusIdentity)
    SpaceManager.swift            ← @MainActor @Observable; CRUD
    SpaceValidator.swift          ← pure validation

  AtomicIO/                       ← NEW (shared helpers)
    AtomicJSON.swift              ← Data.write(.atomic) wrapper
    NexusPaths.swift              ← path helpers (spacesDir(in:), topicsDir(in:), …)

Pommora/Pommora/Sidebar/
  SidebarView.swift               ← MODIFY: Spaces section reads SpaceManager
  SpaceRow.swift                  ← NEW: reuses SelectableRow styling
  NewSpaceSheet.swift             ← NEW: name + color + icon

Pommora/Pommora/
  ContentView.swift               ← MODIFY: inject SpaceManager into environment

Pommora/PommoraTests/
  SpaceFileTests.swift            ← round-trip
  SpaceValidatorTests.swift       ← validation coverage
  SpaceManagerTests.swift         ← CRUD lifecycle (temp dir)
```

Concrete sequence to execute today:

1. **Add Yams via SPM** — registering now so Phase 6 (Pages CRUD) doesn't block on dependency management. `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`.

2. **Create `NexusPaths.swift`** — pure path helpers:

   ```swift
   enum NexusPaths {
       static func nexusConfigDir(in nexus: Nexus) -> URL {
           nexus.rootURL.appendingPathComponent(".nexus", isDirectory: true)
       }
       static func spacesDir(in nexus: Nexus) -> URL {
           nexusConfigDir(in: nexus).appendingPathComponent("spaces", isDirectory: true)
       }
       static func topicsDir(in nexus: Nexus) -> URL {
           nexusConfigDir(in: nexus).appendingPathComponent("topics", isDirectory: true)
       }
       static func spaceFileURL(for space: Space, in nexus: Nexus) -> URL {
           spacesDir(in: nexus)
               .appendingPathComponent("\(space.title).space.json", isDirectory: false)
       }
       static func ensureDirectoryExists(_ url: URL) throws {
           try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
       }
   }
   ```

3. **Create `AtomicJSON.swift`** — generic helper:

   ```swift
   enum AtomicJSON {
       static func encode<T: Codable>(_ value: T) throws -> Data {
           let encoder = JSONEncoder()
           encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
           encoder.dateEncodingStrategy = .iso8601
           return try encoder.encode(value)
       }
       static func decode<T: Codable>(_ type: T.Type, from url: URL) throws -> T {
           let data = try Data(contentsOf: url)
           let decoder = JSONDecoder()
           decoder.dateDecodingStrategy = .iso8601
           return try decoder.decode(type, from: data)
       }
       static func write<T: Codable>(_ value: T, to url: URL) throws {
           let data = try encode(value)
           try data.write(to: url, options: [.atomic])
       }
   }
   ```

4. **Create `SpaceColor.swift`** — 9-color enum (Notion palette):

   ```swift
   enum SpaceColor: String, Codable, CaseIterable, Identifiable, Hashable {
       case gray, brown, orange, yellow, green, blue, purple, pink, red
       var id: String { rawValue }
       var swiftUIColor: Color { ... }
   }
   ```

5. **Create `Space.swift`** — value type:

   ```swift
   struct Space: Codable, Equatable, Identifiable, Hashable {
       var id: String           // ULID
       var tier: Int = 1
       var title: String        // derived from filename on load
       var color: SpaceColor
       var icon: String?        // SF Symbol
       var blocks: [SpaceBlock] // empty v1; populated when Spaces composition lands
       var modifiedAt: Date
   }

   struct SpaceBlock: Codable, Equatable, Hashable {} // placeholder until Phase 10
   ```

6. **Create `SpaceValidator.swift`** — pure functions:

   ```swift
   enum SpaceValidator {
       enum ValidationError: Error {
           case emptyTitle
           case invalidTitleCharacters
           case duplicateTitle
       }
       static func validate(title: String, existing: [Space], excluding: Space? = nil) throws {
           guard !title.trimmingCharacters(in: .whitespaces).isEmpty else { throw .emptyTitle }
           let invalidChars: Set<Character> = ["/", ":", "\\"]
           guard title.allSatisfy({ !invalidChars.contains($0) }) else { throw .invalidTitleCharacters }
           let conflicts = existing.contains {
               $0.title.lowercased() == title.lowercased() && $0.id != (excluding?.id ?? "")
           }
           guard !conflicts else { throw .duplicateTitle }
       }
   }
   ```

7. **Create `SpaceManager.swift`** — full CRUD:

   ```swift
   @MainActor
   @Observable
   final class SpaceManager {
       var spaces: [Space] = []
       var pendingError: Error?

       private let nexus: Nexus

       init(nexus: Nexus) {
           self.nexus = nexus
           Task { await loadAll() }
       }

       func loadAll() async { ... walks spacesDir, decodes each .space.json ... }
       func create(name: String, color: SpaceColor, icon: String?) async throws { ... }
       func rename(_ space: Space, to newName: String) async throws { ... }
       func updateColor(_ space: Space, to color: SpaceColor) async throws { ... }
       func updateIcon(_ space: Space, to icon: String?) async throws { ... }
       func delete(_ space: Space) async throws { ... }
   }
   ```

8. **Create `NewSpaceSheet.swift`** — sheet UI:

   ```swift
   struct NewSpaceSheet: View {
       @Environment(\.dismiss) private var dismiss
       @Environment(SpaceManager.self) private var spaceManager
       @State private var name = ""
       @State private var color: SpaceColor = .blue
       @State private var icon: String? = "person.circle"
       @FocusState private var nameFocused: Bool

       var body: some View {
           Form {
               TextField("Name", text: $name).focused($nameFocused)
               Picker("Color", selection: $color) {
                   ForEach(SpaceColor.allCases) { color in
                       Label(color.rawValue.capitalized, systemImage: "circle.fill")
                           .foregroundStyle(color.swiftUIColor)
                           .tag(color)
                   }
               }
               // Phase-2 icon picker: TextField for SF Symbol name; grid later.
           }
           .toolbar {
               ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
               ToolbarItem(placement: .confirmationAction) {
                   Button("Create") { Task { await create() } }
                       .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
               }
           }
           .onAppear { nameFocused = true }
       }

       private func create() async {
           do { try await spaceManager.create(name: name, color: color, icon: icon); dismiss() }
           catch { /* show inline error */ }
       }
   }
   ```

9. **Modify `SidebarView.swift`** — replace placeholders with real data:
   - Inject `@Environment(SpaceManager.self)`
   - Replace "Spaces" section placeholders with `ForEach(spaceManager.spaces)`
   - Each row = `SpaceRow(space:)` wrapping `SelectableRow` with color/icon
   - `+ New Space` button at section footer sets `presentedSheet = .newSpace`
   - Add `.sheet(item: $presentedSheet)` (handles `.newSpace`, extensible)
   - `.contextMenu` per row (rename, change color, change icon, delete)
   - Inline rename state (`@State private var editingSpaceID: String?`)

10. **Modify `ContentView.swift`** — inject `SpaceManager` on Nexus load:

    ```swift
    @State private var spaceManager: SpaceManager?

    var body: some View {
        // existing NavigationSplitView
        .onChange(of: nexusManager.currentNexus) { _, newNexus in
            if let nexus = newNexus { spaceManager = SpaceManager(nexus: nexus) }
        }
        .environment(spaceManager)  // requires unwrap or default
    }
    ```

11. **Write tests** — minimum:
    - `SpaceFileTests`: encode/decode round-trip
    - `SpaceValidatorTests`: empty title rejected, duplicate rejected, valid passes
    - `SpaceManagerTests`: create → file exists; rename → renamed; delete → gone

12. **Run `xcodebuild` + tests + manually verify**:
    - Create "Personal" → `<nexus>/.nexus/spaces/Personal.space.json` exists
    - Rename → "Life" → file renamed; sidebar shows "Life"
    - Delete → file gone; sidebar updates
    - SQLite untouched (no DB layer yet)
    - `codesign -d --entitlements -` still shows sandbox + user-files-rw

End-of-day deliverable: **Spaces tier fully CRUD-able end-to-end**; file-on-disk reflects every UI action. Phase 3 (Topics) next session — same pattern + folder creation + parent Space picker.

---

#### Open Items Carrying Into Day 2+

Phases 3–11 as specified in *Implementation Phasing*. Post-implementation: doc-set rewrites per *What Changes from Current Spec Docs* above. Notes: Phase 6 is first Yams use; Phase 10 = v0.2 file watcher in Framework.

---

#### Pre-Plan Validation Findings (2026-05-16)

Sanity-check via context7 + find-docs + swiftui-expert-skill before plan mode. Verified-fine vs adjusted, recorded so the plan doesn't re-litigate.

##### Verified fine (no adjustment needed)

- **Yams** (`/jpsim/yams`) — Codable patterns (`YAMLDecoder().decode(T.self, from: String/Data/Node)`); multi-document via `compose_all`; source-position `Mark` for diagnostics. v5.1+ on Swift 6. `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`.
- **GRDB.swift v7+** (`/groue/grdb.swift`, v7.5.0) — requires Xcode 16+ and Swift 6. `ValueObservation.values(in:)` returns `AsyncSequence` via `for try await values in observation.values(in: dbQueue)`. FTS5: `unicode61` (default), `ascii`, `porter`. macOS Application Support directory is the documented location. Standard `DatabaseQueue(path:)`.
- **EKCalendarItem.lastModifiedDate** — confirmed `var lastModifiedDate: Date? { get }`, since macOS 10.8. Safe for conflict resolution.
- **`@Observable` + `@MainActor`** combo — verified per `swiftui-expert-skill/references/state-management.md`: "Always mark @Observable classes with @MainActor for thread safety." Pommora pattern matches.
- **`@Environment(Type.self)` injection** — `.environment(SpaceManager(...))` to inject; `@Environment(SpaceManager.self) private var spaceManager` to read. No `.environmentObject` needed with `@Observable`.

##### Adjusted in spec (applied here + Features/Agenda.md)

- **EKRecurrenceRule `daysOfTheWeek`** — actual type is `[EKRecurrenceDayOfWeek]?` (typed object with `dayOfTheWeek` enum + optional `weekNumber`), NOT a string array. JSON schema above reflects this.
- **EKRecurrenceRule `firstDayOfTheWeek`** — added to schema (was missing).
- **EKRecurrenceRule immutability** — modifying recurrence on a saved item requires constructing a new `EKRecurrenceRule`. Sync layer always builds fresh.
- **EKEventStoreChanged observation** — added Swift Concurrency `for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged)` pattern.

##### Implementation discipline to add (folder + file atomicity)

Creating a Topic / Vault is two-step: (1) create folder, (2) write metadata. If step 2 fails, the folder is orphaned. Two disciplines:

1. **Best-effort rollback on creation failure** — if metadata write throws, `try? FileManager.removeItem(at: folderURL)` before propagating. Manager's `create(...)` wraps both ops in a do/catch, calling `AtomicJSON.write(topic, to: folderURL/_topic.json)` and rolling back on throw.
2. **Idempotent recovery on load** — if a folder exists without metadata, `loadAll()` silently skips it (treats as cosmetic).

Folder rename atomic via `FileManager.moveItem(at:to:)` on same volume (always true for nexus contents).

##### Esc-to-cancel for inline rename

Both `.onExitCommand` (macOS-specific) and `.onKeyPress(.escape) { cancel(); return .handled }` (macOS 14+) work. **Use `.onKeyPress(.escape)`** for forward-compatibility and explicit key-binding.

##### SwiftUI WebView on macOS 26 — Pages editor (Phase 8+) consideration

macOS 26 ships `WebView` + `WebPage` observable model (WWDC25 Session 231). For Option 2 editor (WKWebView hosting JS Markdown), native `WebView` may simplify the shell — but `WebView(url:)` / `WebView(_:page)` don't surface a public `WKScriptMessageHandler` equivalent in early docs, and Pommora needs both a JS↔Swift bridge (editor events, save, paste) and `WKURLSchemeHandler` (since `file://` blocks ES modules).

**Recommendation (Phase 8+):** Try `WebView` + `WebPage` first; fall back to `WKWebView` via `NSViewRepresentable` if message handlers / custom scheme APIs aren't exposed. Not blocking for Phases 0–7.

##### FSEventStream

No community-blessed Apple-direct replacement in Swift 6. `EonilFSEvents` (Swift wrapper) or hand-rolled `FSEventStreamCreate` — both work under Swift 6 with `@MainActor` discipline on callback dispatch.

