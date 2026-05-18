### Contexts + Vaults — Domain Model Revision Spec

#### Context

Pommora's original 3-entity model (Pages / Collections / Spaces + Items) was reconsidered during an RC session on 2026-05-16. The conversation iterated through Vault-as-containment, Anytype-style typed-objects, and Capacities-style renamable labels before landing on a final shape: a **2-layer model** with PARA-aligned naming and a tiered Context system.

This spec is the locked synthesis of that conversation. It supersedes the relevant sections of `Domain-Model.md`, `Spaces.md`, `Collections.md`, `Items.md`, `Pages.md`, `Sidebar.md`, `PommoraPRD.md`, and `Framework.md` once implemented; the spec-doc rewrites happen post-implementation, not as part of this work.

The implementation discipline locked in by Nathan during the same session: **CRUD and paradigm must land hand-in-hand**. Spaces are not "added" until "+ New Space" works end-to-end on disk; sub-topics don't exist until the "create sub-topic" interaction lands. Each entity's first appearance in the codebase is paired with its CRUD interface, not a separate later pass.

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
- **Topics** have multi-parent Spaces — a single Topic can be tagged to multiple Spaces. The Topic's parent Space(s) are a **typed multi-valued relation property** on the Topic, not a folder-structural fact.
- **Sub-topics** have a single **file-structural parent Topic** (encoded by which Topic folder the file lives in). This is fixed by the filesystem.
- **Sub-topics can have additional Topic relations** beyond their file-structural parent. These are stored as a **typed multi-valued relation property** on the Sub-topic (`linked_relations` field — same shape as the property-panel multi-select chip relations used for Item↔Context relations). **They are not body wikilinks** — they are real relational properties, editable in the property panel, queryable via the index, and surfaced in graph view. The file-structural parent Topic remains fixed; the linked Topic relations are additive.
- **Same-tier links between Tier entities are not file-structural** (Topic ↛ Topic, Space ↛ Space). If users want to express a relationship between two Topics (or two Spaces), it lives as a body-content wikilink inside that Tier entity's composed page — never as a parent or sibling relation.
- **Tier-skip allowed** — a Sub-topic can parent directly to a Space (becoming what's effectively a leaf Topic), and its `linked_relations` field can target any tier.

##### Operational layer — Vaults / Collections / Content + Agenda

| Entity | Role | On disk |
|---|---|---|
| Vault | Folder with property schema applied to all contained Content | A folder containing `_vault.json` |
| Collection | Sub-folder within a Vault; shares the Vault's schema (v1) | A folder inside a Vault, no separate schema file |
| Content | The data itself — Pages (`.md`) and Items (`.json`) | Files inside a Collection |
| **Agenda** | **Calendar-anchored entities (Events, Tasks); EventKit-bridgeable; sibling of Vault, not nested** | **Files in `<nexus-root>/Agenda/` — `.agenda.json`** |

**Collection-local schemas** are a Prospect for post-v1. Simplicity-first: in v1, every Page or Item inside a Vault conforms to that Vault's single shared schema regardless of which Collection it lives in.

##### Inline editing in composed-page blocks (Notion-style)

**Embedded blocks are live, fully-editable views of their source — never read-only snapshots.** Whenever a Context page (Space / Topic / Sub-topic) or the Homepage embeds another entity (Items, Pages, Agenda items, Collection views, linked-content lists), the user can interact with that content **in place**: check off a task, edit a property cell, add a new row, change a date, all without leaving the composed page.

This is structurally identical to how Notion treats embedded databases — the embed stores a reference (entity ID + view config + filters), and the UI renders an interactive view backed by the live source. Pommora's existing foundation already supports this:

- **Embed = reference, not snapshot** — block JSON stores the source entity ID + view config; the actual data is read live from the SQLite index
- **Edits route to the source manager** — checking off a Task in a Topic's embedded view calls `AgendaManager.toggleCompleted(...)`; the manager atomically writes the source file; the file watcher catches the change; SQLite re-indexes; *every* embedded view of that entity refreshes live
- **Same write discipline everywhere** — there's no "embed-edit path" separate from "primary-surface edit path"; both call the same manager methods. One source of truth per entity.

**Editability by block type (v1 scope):**

| Block type | Inline editing |
|---|---|
| Embedded Collection View (table / board / list / cards / gallery) | Full — edit cells, add rows, drag-reorder, change view config locally |
| Linked Items widget | Full — Item properties editable inline; toggle Item completion; add new Item |
| Linked Agenda widget (calendar / list) | Full — toggle task completion, edit due dates, drag to reschedule, add new Agenda item |
| Linked Pages widget | Mixed — title and frontmatter properties editable inline; full body editing requires opening the Page in a tab |
| Link list | Full — rename labels, reorder, add / remove links |
| Text blocks (paragraphs, headings, callouts, columns) | Full — composed-page authoring as expected |

**Why this matters for implementation:** the block renderer is a thin shell around the entity's normal property/row UI components, NOT a separate read-only renderer. The Item-Window's property editor and a Collection-view-block's row editor are the *same component*, just embedded in different layouts. Reuse is structural — building inline editing isn't a separate feature, it's how the components were going to be built anyway.

**Out-of-scope concerns for v1:** drag-to-rewrite-frontmatter on kanban boards (planned post-v1.0 per current spec); cross-block transclusion of body text (post-v1); collaborative simultaneous editing (out of scope indefinitely — single-user).

**Why Agenda is separate from Vaults:**
- EventKit (the macOS Calendar/Reminders system framework) requires structurally distinct entities matching `EKEvent` and `EKReminder` shapes — fixed schemas with `startDate`/`endDate` (events) or `dueDate`/`completed` (tasks). Generic Vault Items can't carry these cleanly without lossy bidirectional mapping.
- Quick-capture surfaces (system Calendar, Siri, Reminders, lock-screen widgets, Notification Center) need a single known-location entity to write to. "Create a task" shouldn't have to decide "in which Vault?"
- Pommora's Mac-first posture makes deep EventKit integration a real value, not polish. The structural decision is upstream of all of it.
- UX-wise Agenda items behave identically to Items — they open in the Item Window popover, carry tier1/2/3 multi-relations to Contexts, have user properties, and can be sorted/filtered. The distinction is on-disk + EventKit-facing only.

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
- Three default items: `Homepage`, `Calendar`, `Recents`
- Each item key is fixed in code (`homepage`, `calendar`, `recents`); label is user-renamable via Settings
- `Homepage` opens the **Homepage entity** (see below — its own type, NOT a Space)
- `Calendar` opens the **Agenda layer's calendar view** (see "Agenda" entity below)
- `Recents` shows recently-opened tabs (lightweight v1 implementation if state tracking is already available; otherwise placeholder)
- User-pinning of arbitrary entities remains a post-v1 Prospect

**Homepage entity** (singleton, NOT a Space):
- One per Nexus, fixed identity (code key: `homepage`)
- A **composed-blocks dashboard surface** — like a Notion page that can embed anything
- Can embed: linked-content views of Spaces / Topics / Sub-topics, embedded Vault collection views, link lists, prose blocks, callouts, columns, calendar/agenda mini-views — anything
- Stored at `.nexus/homepage.json` (fixed location, singleton — not under `spaces/` or any tier folder)
- Structurally **shares the same composed-blocks surface pattern as Contexts** (Spaces, Topics, Sub-topics) — all four entity types are composed-page surfaces that can embed anything. The distinction is **identity / parenting**:
  - Contexts have an `id`, a `tier`, and `parents` — they are tiered, parented entities that things relate *to*
  - Homepage is a singleton — no `id`, no tier, no parents — exists at a fixed location; can pull things *in* but isn't itself a referent

**Topic tagging visual** (sidebar tagging of Topics by their parent Space):
- Tagging can be rendered as **color dots**, **SF Symbol icons**, or **both** — leave the door open for all three modes
- Spaces store both `color` and `icon`/`symbol` fields; the sidebar's tagging style is a setting (v1 default: color dot)
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

  Agenda/                                ← NEW operational-layer entity (sibling of Vaults)
    Buy-groceries.agenda.json            ← kind: "task"
    Team-standup.agenda.json             ← kind: "event"
    Submit-report.agenda.json            ← kind: "task"

  Planner/                               ← Vault (folder with content)
    _vault.json                          ← shared schema for all Content inside
    Tasks-archive/                       ← Collection (a generic Tasks-style Collection still possible —
      Old-task.json                      ←   for retrospective/non-EventKit work)
    Goals/
      Q1-goals.json
    Events-notes/                        ← Collection (notes about events, not the events themselves)
      Conference-summary.md

  Materials/                             ← Vault
    _vault.json
    Pages/                               ← Collection
      Attention-is-all-you-need.md       ← Page
    Documents/
      Annual-report.json
    Reports/
      Research-summary.md

  .trash/                                ← existing spec; nexus-local trash
  .git/, .obsidian/, etc.                ← user's own dotfolders, filtered from sidebar

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

- `color`: one of the 9 Notion-palette colors (`gray`, `brown`, `orange`, `yellow`, `green`, `blue`, `purple`, `pink`, `red`) — reuses the existing palette spec
- `icon`: SF Symbol name (e.g. `person.circle`, `book.closed`)
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

- `parents`: multi-Space, validated each must be a tier-1 Space
- `icon`: SF Symbol name (optional)
- Topic has NO own `color` — its visual tag comes from inheriting parent Space(s) colors

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

- `parents`: single-valued, the file-structural parent Topic (encoded by which Topic folder the file lives in). Cannot be changed without moving the file.
- `linked_relations`: **a typed multi-valued relation property** (edited in the property panel like any other relation). Holds IDs of additional Topics or Spaces the Sub-topic relates to, beyond its file-structural parent. **These are NOT body wikilinks — they are real relational properties** queryable via the index and surfaced in graph view + property panel.
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

- Singleton — no `id` field (the file location is the identity)
- `blocks`: same composed-page block tree as the existing `.space.json` schema. Can embed any other Pommora entity by ID.
- Seeded on first launch with a minimal default (welcome heading + empty callout) so the file always exists on disk
- Distinct from Spaces — Spaces are *categorical anchors* (things relate *to* them); Homepage is a *user-composed dashboard* (it pulls things *in*)

##### Agenda Item (`<nexus-root>/Agenda/<Title>.agenda.json`)

Agenda items are a **single unified entity** — no structural `kind` discriminator. The user-facing distinction (Task vs To-Do vs Phase vs Event) is a **property** (`properties.type`), making it user-extensible like any other Select property. EventKit mapping is driven by which time fields are populated, not by a schema discriminator.

Schema is **deliberately shaped to mirror EventKit primitives** (`EKEvent` and `EKReminder`) verified against Apple's current EventKit documentation. The fields below have exact EventKit counterparts to make two-way sync 1:1 mapping rather than lossy transformation.

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

A small serializer/deserializer (~80 lines) converts between this JSON and `EKRecurrenceRule` on sync.

**Important EventKit constraint:** `EKRecurrenceRule` and its properties are **read-only after creation** — modifying recurrence on a saved EKEvent / EKReminder requires creating a new `EKRecurrenceRule` and reassigning. Pommora's sync layer always constructs a fresh `EKRecurrenceRule` when writing recurrence changes back; no in-place mutation.

##### EventKit change observation (Swift Concurrency)

Pommora observes external EKEventStore changes via `NotificationCenter` async sequences:

```swift
let center = NotificationCenter.default
Task {
    for await _ in center.notifications(named: .EKEventStoreChanged) {
        await agendaManager.reconcileWithEventKit()
    }
}
```

Reconciliation re-fetches all EKEvents and EKReminders in the user-selected calendars, compares against Pommora's `.agenda.json` files by `eventkit_uuid` + `lastModifiedDate`, and applies last-write-wins per item.

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

- The Agenda layer uses the same schema mechanism as Vaults (a `_agenda.json` schema sidecar) — reuses the Vault property/view editor UI
- The built-in `type` Select has default values `[Task, To-Do, Phase, Event]` — user can add custom types (e.g., "Habit," "Block," "Reminder") and rename existing options, but the `type` property itself cannot be deleted (marked `builtin: true`)
- All other Agenda properties are user-defined the same way Vault properties are

##### EventKit mapping (data-driven, no explicit kind)

| Pommora Agenda fields populated | EventKit target | Mapping notes |
|---|---|---|
| `start_at` + `end_at` set | `EKEvent` | `startDate` ← `start_at`; `endDate` ← `end_at`; `isAllDay` ← `all_day`. Uses `eventIdentifier`. |
| `due_at` set, no `start_at` | `EKReminder` | `dueDateComponents` ← `due_at` (with `timeZone = nil` if `due_floating == true`; with hour/minute/second stripped if `due_all_day == true`). Uses `calendarItemIdentifier`. |
| Neither set | `EKReminder` | Unscheduled to-do — `dueDateComponents` left nil. macOS allows this; iOS doesn't (port consideration). |
| `sync_target` explicitly set | Forced target | Edge cases (e.g. user marks a long "Phase" with start+end as a Reminder rather than Calendar event). |

##### EventKit permissions + entitlements (required for sandbox)

Pommora is sandboxed (per v0.1a — `ENABLE_APP_SANDBOX = YES`). EventKit access requires additional setup beyond the file-r/w entitlement:

**1. Sandbox entitlement (required for any Calendar / EventKit access):**
- `com.apple.security.personal-information.calendars` — enables EventKit at the sandbox level
- Set via Xcode build setting `ENABLE_PERSONAL_INFORMATION_CALENDARS = YES` (auto-generates the entitlement in modern Xcode projects, same mechanism used for `ENABLE_USER_SELECTED_FILES = readwrite` in v0.1a)
- Without this entitlement, all EventKit API calls fail silently in a sandboxed build

**2. Info.plist usage description keys (required for the system permission prompt):**
- `NSCalendarsFullAccessUsageDescription` — string shown when requesting full Calendar access
- `NSRemindersFullAccessUsageDescription` — string shown when requesting Reminders access
- These are separate keys for separate permission grants; both required if Agenda syncs both

**3. Permission request flow (macOS 14+ / iOS 17+):**
- Use the modern `requestFullAccessToEvents(completion:)` and `requestFullAccessToReminders(completion:)` APIs (or their async variants)
- The legacy `requestAccess(to:completion:)` is deprecated on iOS 17+ / macOS 14+ — Pommora targets macOS 26.4 so this is well past the cutoff
- Calendar offers a `requestWriteOnlyAccessToEvents` variant (less invasive — only write, can't read existing events) but Reminders does NOT have a write-only equivalent

**4. Identifiers for two-way sync stability:**
- `EKEvent.eventIdentifier` for events
- `EKCalendarItem.calendarItemIdentifier` for reminders (also works for events as a generic identifier)
- Both are documented as stable for external persistence — safe to store in Pommora's `eventkit_uuid` field
- `EKEventStoreChangedNotification` posts when EventKit data changes externally — observe for two-way sync

**5. Sync conflict policy (initial v1):**
- Last-write-wins by `modified_at` / EKCalendarItem's `lastModifiedDate`
- Surface conflict count in UI but don't block sync
- More sophisticated conflict resolution is post-v1

##### UI affordance — collapsed single-date input

When an Agenda item's start_at and due_at would carry the same value, the property editor should collapse them into a **single "When?" date input** rather than showing two separate fields. Expands back to two inputs when the user wants asymmetric values (e.g. "scheduled today but due tomorrow"). On disk, both `start_at` and `due_at` continue to exist as separate JSON fields — the collapse is purely UI. Schema unchanged.

Resolved when the Agenda property panel UI lands (Phase 6.5 / Phase 7 area).

##### Notes and constraints

- Filename = title (same convention as Items and Pages)
- `calendar_id` + `eventkit_uuid` are nullable — populated only when the user enables EventKit sync for this item or globally for the Agenda layer
- The user can disable EventKit sync per-item or globally; disabling per-item clears `eventkit_uuid` (the Pommora item persists, the EventKit-side mirror is removed)
- **EventKit sync is NOT enabled in v1 by default** — users opt in via Settings → Agenda. Schema fields exist from day one so opt-in is additive, not migration

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

Property values on disk (in Page frontmatter, Item `properties` block, Agenda item `properties` block) decode via shape-sniffing the JSON/YAML token. Most types decode directly:

- `number` → JSON number
- `checkbox` → JSON boolean
- `date` / `datetime` → ISO-8601 string (date-only vs with time)
- `select` → JSON string (the option's value)
- `multiSelect` → JSON `[string]` array
- `url` → JSON string

**Relation values use a tagged-object encoding** `{"$rel": "<ULID>"}` (paradigm decision 2026-05-16, `// Guidelines//Paradigm-Decisions.md`) — NOT a bare string. Rationale: bare-string `.relation` and `.select` are indistinguishable on the wire; the tagged-object form makes relation edges legible to external agents + the graph-view indexer without consulting Vault schema (satisfies load-bearing constraint #3). Single-relation: `{"$rel": "01H..."}`. Multi-relation: `[{"$rel": "01H..."}, {"$rel": "01H..."}]`.

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

Collections persist a minimal `_collection.json` sidecar. The `vault_id` makes the parent-Vault relation an explicit on-disk property so external query/parsing tools can navigate the relationship without inferring from filesystem nesting. Title still comes from the folder name (filename-as-title rule applies). Collections share the parent Vault's property schema in v1.

**Post-v1 Prospect**: Collection-local schema overrides + per-Collection icons / descriptions / view configs land additively in the same `_collection.json` (additive fields, no migration cost). Not in v1 scope.

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

| Entity | Create | Read | Update | Delete |
|---|---|---|---|---|
| Space | Name + color + icon picker | Click to open composed-blocks page (can embed anything, like Homepage) | Inline rename / right-click change color/icon / edit blocks | Confirm + warn if Topics reference it (strips parent reference from Topics) |
| Topic | Name + parent Space picker (multi) + icon | Click to open composed-blocks page (can embed anything, like Homepage) | Inline rename / change parents / icon / edit blocks | Confirm + warn if Sub-topics inside (move sub-topics out OR delete cascade?) |
| Sub-topic | Inside expanded Topic; name + icon | Click to open composed-blocks page (can embed anything, like Homepage) | Inline rename / move to another Topic / edit linked_relations via property panel / edit blocks | Confirm + delete |
| Vault | Name + icon + schema editing | Click to open default Collection view | Inline rename / icon / edit Vault schema | Confirm + warn (contains N Collections, M Items/Pages) |
| Collection | Inside Vault; name only | Click to open view | Inline rename | Confirm + warn (contains N Items/Pages) |
| Item | Inside Collection; name | Item Window popover | Item Window (properties, description, relations) | Confirm + delete |
| Page | Inside Collection; name | Tab | Editor in tab | Confirm + delete |
| **Homepage** | **Seeded on first launch (no manual create)** | **Saved → Homepage opens it in a tab** | **Composed-blocks editor (Phase 10)** | **Not user-deletable (singleton)** |
| **Agenda Item** | **From Calendar saved view / quick-capture (no Vault decision); name + type + optional times** | **Item Window popover OR inline in calendar view** | **Item Window (properties, time fields, relations); EventKit two-way sync** | **Confirm + delete (with EventKit unsync if mirrored)** |

Open spec question parked for later: **on Topic delete, do we delete sub-topics (cascade) or move them out (promote to standalone)?** Recommend warning + cascade-delete as v1 default since standalone sub-topics aren't an exposed concept. Confirm during implementation.

---

#### Implementation Phasing

CRUD + paradigm pair at every step. Each phase delivers a *functional* slice — entity creation works end-to-end on disk before the next phase begins.

##### Phase 0 — Schema + Codable foundation
- Codable structs: `Space`, `Topic`, `Subtopic`, `Vault`, `TierConfig`, `SavedConfig`, `Item`, `PageFrontmatter`
- ULID generation already shipped in v0.1a (`ULID.swift`)
- Atomic-write JSON helpers (`.tmp` + `rename`)
- YAML frontmatter parser for `.md` files (frontmatter only; body stays as raw `String` until editor work)
- Round-trip tests for every entity Codable

##### Phase 1 — File system primitives + validation
- Folder create / rename / delete under sandbox (security-scoped bookmark coordination)
- File create / atomic write / read / delete
- Validation rules engine (tier-parent rule, sub-topic file location, etc.)
- Extend existing `FolderTree.swift` to recognize Spaces/Topics/Vaults/Collections vs. cosmetic folders

##### Phase 2 — Spaces CRUD + sidebar (first user-visible slice)
- New `Spaces/` source folder
- `SpaceFile.swift` (Codable), `SpaceManager.swift` (@Observable @MainActor)
- Sidebar `Spaces` section renders flat rows from `SpaceManager.spaces`
- "+ New Space" command — sheet with name field + color picker + SF Symbol picker
- Inline rename: tap-to-edit on row
- Right-click context menu: rename, change color, change icon, delete
- Delete confirmation
- Locked selection language from v0.0 reused (`SelectableRow`)

##### Phase 3 — Topics CRUD + sidebar
- New `Topics/` source folder
- `TopicFile.swift`, `SubtopicFile.swift`, `TopicManager.swift`
- Sidebar `Topics` section: chevron-disclosure row per Topic
- "+ New Topic" command — sheet with name + parent Space multi-picker + icon picker
- Topic creation = folder + `_topic.json` written atomically
- Sidebar Topic row tagging indicator (color dot v1; symbol/both modes settable later)
- Inline rename, right-click menu, delete with cascade warning

##### Phase 4 — Sub-topics CRUD
- "+ New Sub-topic" appears inside an expanded Topic
- Sub-topic file written into the parent Topic's folder
- Inline rename
- Right-click: rename, move to another Topic (filesystem move + relink), delete
- `linked_relations` editing deferred to property panel work (Phase 7)

##### Phase 5 — Vaults + Collections CRUD + sidebar
- New `Vaults/` source folder
- `VaultFile.swift`, `VaultManager.swift`
- Sidebar `Vaults` section: chevron disclosure per Vault, sub-disclosure per Collection (Collection has no chevron in v1 — leaf node showing Items list when opened in main pane)
- "+ New Vault" sheet — name + icon picker; schema starts empty (full property editor v1.x)
- "+ New Collection" — name only; creates a folder inside the Vault
- Rename + delete with cascade warnings

##### Phase 6 — Content CRUD (Pages + Items)
- "+ New Page" in a Collection → creates `.md` with frontmatter scaffold (id, tier1/2/3 empty, properties empty)
- "+ New Item" in a Collection → creates `.json` with empty properties/relations
- Inline rename in sidebar/Item window
- Delete

##### Phase 7 — Cross-tier relations on Items/Pages
- Property panel (or Item Window) UI for `tier1`/`tier2`/`tier3` multi-select chips
- Type-to-search relation picker that resolves to Tier entity IDs
- Save updates frontmatter/json via atomic write
- SQLite `links` table re-indexes via watcher

##### Phase 8 — Tier-config + Saved-config settings UI
- Settings scene scaffold (Cmd-, opens `SettingsScene`)
- Tier labels editor — three sections (one per tier), singular + plural text fields each
- Saved-section labels editor — three rows (homepage/calendar/recents), label only
- Tagging style picker (color / symbol / both)

##### Phase 9 — Saved section content
- `Homepage` resolves to the seeded Homepage Space (existing spec); clicking opens it
- `Calendar` placeholder — empty view with "Calendar view coming v1.x" marker
- `Recents` — implement if recently-opened-tabs tracking is already available; otherwise placeholder

##### Phase 10 — File watcher integration (this is the v0.2 spec)
- FSEventStream on the nexus folder
- External file changes → SQLite re-index → sidebar refresh
- Atomic-write detection (debounce 50–100 ms; track outbound mtimes to ignore self-writes)

##### Phase 11 — Graph view foundation (Prospect, but code-ready)
- Ensure SQLite `links` table is queryable for graph data
- Reserve tab-content shape that can accommodate a graph-view tab later
- No actual graph rendering in v1

---

#### What Changes from Current Spec Docs (post-implementation)

Tracking list — these edits happen after implementation, not as part of this work:

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
- Unit tests for that phase's Codable round-trip pass
- Manual verification: create / rename / delete on that phase's entity works end-to-end, on-disk files reflect the operation, sidebar updates live
- `codesign -d --entitlements - Pommora.app` confirms sandbox still intact
- LLM-legibility check: read a freshly created entity file directly via `cat` (or Read tool) — confirm content is human/agent-parseable

##### End-to-end gold path test (Phase 2 onward)

After Phase 2: create a Space "Personal," rename it to "Life," delete it. Verify all three operations land cleanly on disk; the sidebar reflects each change instantly.

After Phase 3: create the Personal Space, then a "Productivity" Topic tagged to Personal. Verify Topic folder + `_topic.json` exist, sidebar shows Topic under chevron disclosure.

After Phase 4: add Sub-topic "GTD Method" inside Productivity. Verify file in correct folder, sidebar shows the nesting.

After Phase 5: create Planner Vault with Tasks Collection inside.

After Phase 6: create a Task Item "Buy groceries" inside Planner/Tasks. Open it in the Item Window.

After Phase 7: edit the Task's `tier2` relation to include Productivity. Verify the relationship persists to disk and surfaces on the Productivity Topic's page.

That's the v1 organization + operational layer fully functional.

---

#### Research Findings — SwiftUI Implementation Patterns

Derived from `swiftui-expert-skill` consultation + existing Pommora code review (`NexusManager`, `NexusStore`, `NexusIdentity`, `SidebarView`, `FolderTree`).

##### 1. Manager pattern — per entity, mirroring `NexusManager`

Pommora's `NexusManager` is `@MainActor @Observable final class` with a single source-of-truth pattern. **Same shape for each new entity manager** — no unified store, because each entity has independent file-system locations, validation rules, and CRUD flows. Per-entity managers keep state-driven updates narrowly scoped (changing a Topic doesn't re-evaluate the Spaces section).

```swift
@MainActor
@Observable
final class SpaceManager {
    var spaces: [Space] = []
    var pendingError: SpaceError?

    private let nexusURL: URL  // injected from NexusManager

    func loadAll() async { ... }
    func create(name: String, color: SpaceColor, icon: String?) async { ... }
    func rename(_ space: Space, to newName: String) async { ... }
    func updateColor(_ space: Space, to color: SpaceColor) async { ... }
    func delete(_ space: Space) async { ... }
}
```

Inject the active Nexus's root URL into each manager at construction; managers re-load when `NexusManager.currentNexus` changes (driven via an `.onChange(of:)` on the parent view).

##### 2. Sidebar pattern — extend the existing `SidebarView`

The existing `SidebarView` already uses `List` with `Section(isExpanded:)` and `DisclosureGroup` + the locked `SelectableRow` selection language. **No new sidebar architecture needed** — just swap the hardcoded placeholders for real data from each manager.

Layout target:
- Top-level `List` with four `Section`s: Saved, Spaces, Topics, Vaults
- Saved section: 3 fixed rows (`Homepage`, `Calendar`, `Recents`) reading labels from `SavedConfig`
- Spaces section: `ForEach(spaceManager.spaces)` — flat rows, no chevron
- Topics section: `ForEach(topicManager.topics)` — each Topic is a `DisclosureGroup` whose content is its sub-topics
- Vaults section: `ForEach(vaultManager.vaults)` — each Vault is a `DisclosureGroup` whose content is its Collections (Collections themselves are leaf rows)

`SelectableRow` already encapsulates the selection chrome — reuse as-is for every leaf and disclosure-label row.

##### 3. Inline rename — `@FocusState` + `TextField`

The cleanest inline-rename pattern on macOS Tahoe:

```swift
@State private var editingID: String?
@State private var draftName: String = ""
@FocusState private var renameFocused: Bool

// In the row:
if editingID == space.id {
    TextField("", text: $draftName)
        .focused($renameFocused)
        .onSubmit { commitRename(); editingID = nil }
        .onExitCommand { editingID = nil }  // Esc cancels
} else {
    Text(space.title)
}
```

Trigger rename via:
- Right-click context menu → "Rename"
- Keyboard Enter on selected row (via `.onKeyPress(.return)`)
- Double-click on row (avoid — conflicts with open-on-click for entities that are openable)

##### 4. Right-click context menu — `.contextMenu`

Native SwiftUI `.contextMenu` on each row:

```swift
SelectableRow(...)
    .contextMenu {
        Button("Rename") { startRename(space) }
        Button("Change Color") { showColorPicker = space }
        Button("Change Icon") { showIconPicker = space }
        Divider()
        Button("Delete", role: .destructive) { confirmDelete = space }
    }
```

Color/icon pickers + delete confirmation: drive via `.sheet(item:)` and `.confirmationDialog(item:)` patterns (deferred to Phase 2+).

##### 5. "+ New" sheets — `.sheet(item:)` with enum-keyed presentation

Per the SwiftUI ref, item-driven sheets are preferred. Each section's `+ New X` button sets a presentation enum:

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

Each sheet owns its actions via `@Environment(\.dismiss)` — no callback prop-drilling per the SwiftUI ref.

##### 6. Atomic JSON write — already done in `NexusIdentity`

Pommora's existing pattern in `NexusIdentity.save(to:)`:

```swift
let encoder = JSONEncoder()
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
encoder.dateEncodingStrategy = .iso8601
let data = try encoder.encode(self)
try data.write(to: url, options: [.atomic])
```

`Data.write(to:options:[.atomic])` writes to a temp file + atomic rename under the hood — no separate `.tmp` helper needed. **Reuse this pattern verbatim for every Codable entity file.**

##### 7. YAML frontmatter parsing — recommend `Yams` (MIT, jpsim)

There is no first-party Apple YAML parser. `apple/swift-markdown` handles Markdown body but not frontmatter.

**Recommendation: [Yams](https://github.com/jpsim/Yams)** (MIT, written by John Sundell, maintained by jpsim, used by the Swift compiler's own SwiftPM tooling).

```swift
import Yams

let frontmatterString = "id: 01H...\ntier1: [01H...]\n..."
let decoder = YAMLDecoder()
let frontmatter = try decoder.decode(PageFrontmatter.self, from: frontmatterString)
```

Parsing a `.md` file becomes:
1. Read file as `String`
2. Detect frontmatter block by leading `---\n` + trailing `\n---\n`
3. Pass the inner YAML to `YAMLDecoder().decode(PageFrontmatter.self, ...)`
4. Body is everything after the trailing `---`

Wraps the parsing + composition into a `PageFile` struct mirroring `NexusIdentity`'s `load(from:)` / `save(to:)` shape. Encoder uses `YAMLEncoder()` for the round-trip.

Add to project via Swift Package Manager: `https://github.com/jpsim/Yams.git`, version `5.1.0+`.

##### 8. SF Symbol icon picker — `xnth97/SymbolPicker` SPM dep, wrapped behind Pommora's `IconPickerSheet`

**Locked 2026-05-16**: Use the third-party `xnth97/SymbolPicker` Swift package. Most popular, simplest API, cross-platform (macOS 13+), sheet-presented (matches Pommora's other sheet patterns), maintained.

Pommora wraps it in `Pommora/Pommora/Sidebar/Sheets/IconPickerSheet.swift` so call sites only ever see Pommora's API, never `SymbolPicker` directly. Swap-safety: replacing the library (e.g. switching to a hand-rolled grid or a different package) is a single-file rewrite in the wrapper — no call-site churn.

```swift
import SwiftUI
import SymbolPicker

struct IconPickerSheet: View {
    @Binding var icon: String
    @State private var presented = false

    var body: some View {
        Button { presented = true } label: {
            Label("Pick Icon", systemImage: icon.isEmpty ? "questionmark.square" : icon)
        }
        .sheet(isPresented: $presented) {
            SymbolPicker(symbol: $icon)
        }
    }
}
```

SPM dep: `.package(url: "https://github.com/xnth97/SymbolPicker", from: "1.5.1")`.

##### 9. Validation enforcement — pure functions on Codable entities

Validation happens at the manager layer (before write):

```swift
enum SpaceValidator {
    static func validate(_ space: Space, in nexus: Nexus) throws { ... }
}

func create(name: String, color: SpaceColor) async throws {
    let space = Space(id: ULID.generate(), title: name, color: color)
    try SpaceValidator.validate(space, in: currentNexus)
    try await saveAtomically(space)
    spaces.append(space)
}
```

For tier-parent validation, the validator needs access to the other tiers' managers (to resolve parent IDs). Either:
- Pass dependent managers into the validator's call
- Validators live as methods on a higher-level `NexusCoordinator` that has all managers

Simpler v1 approach: validators are static functions; the manager fetches needed parent data (a tier-3's parent must be tier-2) and passes it in. Coordinator layer comes later if needed.

##### 10. Sandbox + security-scoped access — already solved

`NexusManager` already handles `startAccessingSecurityScopedResource()` / `stopAccessingSecurityScopedResource()` lifecycle. New file writes inside the nexus inherit access from the active resource scope — no per-write bookmark needed.

**Discipline:** new entity managers should NOT call `startAccessing` independently — they assume the active Nexus's resource scope is held by `NexusManager`. They read `nexusURL` from the active `Nexus` and write within that tree.

---

#### Ready-to-Code-Today Working Plan

Day-1 scope: land Phase 0 (Codable foundation), Phase 1 (file system + validation), and Phase 2 (Spaces CRUD + sidebar). End of day: user can create / rename / delete a Space, the file lands on disk, the sidebar updates live.

Files to create:

```
Pommora/Pommora/
  Contexts/                       ← NEW folder
    Space.swift                   ← Codable value type (id, title, color, icon, blocks, modified_at)
    SpaceColor.swift              ← enum (gray, brown, orange, yellow, green, blue, purple, pink, red)
    SpaceFile.swift               ← Codable storage + load/save (mirrors NexusIdentity)
    SpaceManager.swift            ← @MainActor @Observable; loadAll/create/rename/delete
    SpaceValidator.swift          ← pure validation functions

  AtomicIO/                       ← NEW folder (shared helpers for future entities)
    AtomicJSON.swift              ← thin wrapper over Data.write(.atomic) for any Codable
    NexusPaths.swift              ← NEW — path resolution helpers within the active nexus
                                  ←   (e.g. spacesDirURL(in:), topicsDirURL(in:), vaultsDir(in:))

Pommora/Pommora/Sidebar/
  SidebarView.swift               ← MODIFY — add Spaces section reading from SpaceManager
  SpaceRow.swift                  ← NEW — extracted row view; reuses SelectableRow styling
  NewSpaceSheet.swift             ← NEW — "+ New Space" sheet (name + color picker + icon)

Pommora/Pommora/
  ContentView.swift               ← MODIFY — inject SpaceManager into environment

Pommora/PommoraTests/
  SpaceFileTests.swift            ← NEW — round-trip tests
  SpaceValidatorTests.swift       ← NEW — validation rule coverage
  SpaceManagerTests.swift         ← NEW — CRUD lifecycle (temp dir, no real nexus)
```

Concrete sequence to execute today:

1. **Add Yams via Swift Package Manager** — even though Spaces don't use YAML, registering it now means Phase 6 (Pages CRUD) doesn't block on dependency-management. URL: `https://github.com/jpsim/Yams.git`, version `from: "5.1.0"`.

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

4. **Create `SpaceColor.swift`** — fixed 9-color enum matching Notion palette:

   ```swift
   enum SpaceColor: String, Codable, CaseIterable, Identifiable, Hashable {
       case gray, brown, orange, yellow, green, blue, purple, pink, red
       var id: String { rawValue }
       var swiftUIColor: Color { ... }  // map each to a Color value
   }
   ```

5. **Create `Space.swift`** — value type:

   ```swift
   struct Space: Codable, Equatable, Identifiable, Hashable {
       var id: String           // ULID
       var tier: Int = 1
       var title: String        // derived from filename on load, set on create
       var color: SpaceColor
       var icon: String?        // SF Symbol name
       var blocks: [SpaceBlock] // empty in v1; populated when Spaces composition lands
       var modifiedAt: Date
   }

   // Placeholder until Phase 10 (Spaces composition)
   struct SpaceBlock: Codable, Equatable, Hashable {}
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
               // Icon picker: text field + filtered grid (phase 2 keeps it minimal — just a TextField for SF Symbol name)
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
           do {
               try await spaceManager.create(name: name, color: color, icon: icon)
               dismiss()
           } catch { /* show inline error */ }
       }
   }
   ```

9. **Modify `SidebarView.swift`** — replace placeholder rows with real data:

   - Inject `@Environment(SpaceManager.self)` 
   - Replace the existing "Spaces" section's hardcoded placeholders with `ForEach(spaceManager.spaces)`
   - Each row is `SpaceRow(space:)` wrapping `SelectableRow` with the space's color/icon
   - Add `+ New Space` button at section footer that sets `presentedSheet = .newSpace`
   - Add `.sheet(item: $presentedSheet)` modifier (initially handles `.newSpace`, extensible)
   - Add `.contextMenu` per row (rename, change color, change icon, delete)
   - Add inline rename state (`@State private var editingSpaceID: String?`)

10. **Modify `ContentView.swift`** — inject `SpaceManager` when the Nexus loads:

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

11. **Write tests** — at minimum:
    - `SpaceFileTests`: encode/decode round-trip for a sample `Space`
    - `SpaceValidatorTests`: empty title rejected, duplicate rejected, valid passes
    - `SpaceManagerTests`: create → file exists on disk; rename → file renamed; delete → file gone

12. **Run `xcodebuild` + run tests + manually verify** in the app:
    - Create a Space "Personal" → `<nexus>/.nexus/spaces/Personal.space.json` exists on disk
    - Rename "Personal" → "Life" → file renamed; sidebar shows "Life"
    - Delete "Life" → file gone; sidebar updates
    - All operations leave SQLite untouched (no DB layer yet)
    - `codesign -d --entitlements -` still shows sandbox + user-files-rw

End of day deliverable: **Spaces tier fully CRUD-able end-to-end**, with the file-on-disk reflecting every UI action. Phase 3 (Topics) starts the next session — same pattern, plus folder creation and parent Space picker.

---

#### Open Items Carrying Into Day 2+

- Phase 3: Topics (folder + `_topic.json`, multi-Space parent picker, chevron-disclosure sidebar)
- Phase 4: Sub-topics
- Phase 5: Vaults + Collections (note: Collection has no metadata file in v1)
- Phase 6: Content CRUD — first place Yams comes in
- Phase 7: cross-tier relations property panel
- Phase 8: Settings scene scaffold + Tier-config / Saved-config editors
- Phase 9: Saved-section content (Homepage seeded Space, Calendar/Recents placeholders)
- Phase 10: file watcher (v0.2 in current Framework)
- Phase 11: graph-view readiness audit
- Post-implementation: doc-set rewrites per the tracking list above

---

#### Pre-Plan Validation Findings (2026-05-16)

Sanity-check pass via context7 + find-docs + swiftui-expert-skill before entering structured plan mode. Documenting what's verified-fine vs what needed adjustment so the plan doesn't re-litigate.

##### Verified fine (no adjustment needed)

- **Yams** (`/jpsim/yams`) — clean Codable patterns (`YAMLDecoder().decode(T.self, from: String/Data/Node)`); supports multi-document YAML via `compose_all`; has source-position `Mark` for diagnostics. v5.1+ works under Swift 6. Add via SwiftPM: `https://github.com/jpsim/Yams.git`, `from: "5.1.0"`.
- **GRDB.swift v7+** (`/groue/grdb.swift`, v7.5.0 on context7) — **explicitly requires Xcode 16+ and Swift 6 compiler**. `ValueObservation.values(in:)` returns an `AsyncSequence` consumable via `for try await values in observation.values(in: dbQueue)`. FTS5 supports `unicode61` (default), `ascii`, `porter` tokenizers. macOS Application Support directory pattern is the documented file-location convention. Standard `DatabaseQueue(path:)` initializer.
- **EKCalendarItem.lastModifiedDate** — confirmed `var lastModifiedDate: Date? { get }`, available since macOS 10.8. Safe for sync conflict resolution.
- **`@Observable` + `@MainActor`** combo for managers — verified against `swiftui-expert-skill/references/state-management.md`: "Always mark @Observable classes with @MainActor for thread safety." Pommora pattern matches.
- **`@Environment(Type.self)` injection** — verified pattern. Inject via `.environment(SpaceManager(...))`; read via `@Environment(SpaceManager.self) private var spaceManager`. No `.environmentObject` needed with `@Observable`.

##### Adjusted in spec (applied to this doc + Features/Agenda.md)

- **EKRecurrenceRule `daysOfTheWeek` shape correction** — actual type is `[EKRecurrenceDayOfWeek]?` (a typed object with `dayOfTheWeek` enum + optional `weekNumber`), NOT a string array like `["mon", "wed"]`. Updated JSON schema above to reflect.
- **EKRecurrenceRule `firstDayOfTheWeek` property** — was missing from earlier JSON sketch. Added.
- **EKRecurrenceRule immutability** — modifying recurrence on a saved EKEvent/EKReminder requires constructing a new `EKRecurrenceRule` (no in-place mutation). Pommora's sync layer always builds fresh objects. Noted in spec + Agenda.md.
- **EKEventStoreChanged observation pattern** — added the Swift Concurrency `for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged)` pattern to spec + Agenda.md.

##### Implementation discipline to add (folder + file atomicity)

Creating a Topic / Vault is a two-step filesystem operation: (1) create folder, (2) write metadata file inside. If step 2 fails, the folder is orphaned. Two complementary disciplines:

1. **Best-effort rollback on creation failure** — if metadata write throws, delete the created folder before propagating the error. The manager's `create(...)` method wraps both ops:
   ```swift
   func create(name: String, ...) async throws {
       let folderURL = NexusPaths.topicsDir(in: nexus).appendingPathComponent(name)
       try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
       do {
           let topic = Topic(...)
           try AtomicJSON.write(topic, to: folderURL.appendingPathComponent("_topic.json"))
       } catch {
           try? FileManager.default.removeItem(at: folderURL)  // rollback
           throw error
       }
   }
   ```
2. **Idempotent recovery on load** — if a folder exists without its metadata file, `loadAll()` skips it silently (treats as cosmetic folder) rather than crashing or creating a phantom Topic. User can inspect via Finder if curious.

Folder rename is atomic via `FileManager.moveItem(at:to:)` on same volume (always true for nexus contents). Cross-volume isn't a concern.

##### Esc-to-cancel for inline rename

Both `.onExitCommand { cancel() }` (macOS-specific, fires on system Cancel command including Esc) and `.onKeyPress(.escape) { cancel(); return .handled }` (iOS 17+ / macOS 14+, more flexible) work. **Recommendation: `.onKeyPress(.escape)`** for forward-compatibility and explicit key-binding. Both pass validation.

##### SwiftUI WebView on macOS 26 — Pages editor (Phase 8+) consideration

macOS 26 ships first-class `WebView` + `WebPage` observable model (WWDC25 Session 231 "Meet WebKit for SwiftUI"). For Pommora's Option 2 editor (WKWebView hosting a JS Markdown editor — Tiptap / Milkdown / BlockNote / CodeMirror), the native `WebView` *should* simplify the SwiftUI shell, but:

- The simple `WebView(url:)` and `WebView(_:page)` initializers don't surface a public `WKScriptMessageHandler` equivalent in early docs
- Pommora's editor needs a JS↔Swift bridge (editor change events, save commands, paste handlers)
- Pommora's editor needs to load bundled JS via custom URL scheme (`WKURLSchemeHandler`) because `file://` blocks ES module loading in WebKit

**Recommendation for Pages editor work (Phase 8+):**
- **Try `WebView` + `WebPage` first** when implementing the editor canvas; if it exposes message handlers + custom scheme support, use it (simpler, more SwiftUI-native)
- **Fall back to `WKWebView` via `NSViewRepresentable`** if the bridge or scheme APIs aren't exposed — this is the existing spec direction and remains valid
- This is **not blocking** for Phases 0–7 (no Pages editor work in those phases). Decision happens when Phase 8 starts and the `WebView`/`WebPage` API can be poked at directly.

##### FSEventStream

No community-blessed Apple-direct replacement for FSEventStream in Swift 6. `EonilFSEvents` (Swift wrapper) or hand-rolled `FSEventStreamCreate` remain the two options; both work under Swift 6 with `@MainActor` discipline on the callback dispatch. No spec change.

