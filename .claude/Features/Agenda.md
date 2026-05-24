### Agenda

The operational layer's calendar-anchored side. Splits into two distinct entity types:

- **Agenda Tasks** — EKReminder-aligned: due date (optional), completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` inside the Tasks singleton folder at the nexus root.
- **Agenda Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` inside the Events singleton folder at the nexus root.

Both share the property catalog used elsewhere (Number / Select / Status / Relation / etc.) and both carry `tier1` / `tier2` / `tier3` Context relations.

The split is **EventKit-aligned, not just structural** — `EKEvent` and `EKReminder` are peer types in EventKit (separate `EKEntityType` buckets, separate `requestFullAccessTo*` access APIs, separate Apple apps — Calendar.app vs Reminders.app). Pommora's UI already collapses Agenda (no Agenda sidebar heading; Calendar pin consolidates), and the disk layout now matches the same peer-relationship: two sibling singleton folders at the nexus root, not nested inside an `Agenda/` wrapper. EventKit sync at v0.6.0 maps each side cleanly: Agenda Task → EKReminder, Agenda Event → EKEvent.

In code, the Swift types are `AgendaTask` and `AgendaEvent` (prefixed to avoid `Task` / `Event` Swift stdlib collisions). UI labels remain "Task" and "Event" by default (renameable via Settings).

UX-wise both entities behave identically to [[Items]] — Item Window popover, tier1/2/3 multi-relations, user properties, sort/filter. Distinction is on-disk shape + EventKit-facing only.

---

#### On disk

```
<nexus-root>/
  Tasks/                                    ← AgendaTask singleton (folder name renameable; discovered by sidecar)
    _taskconfig.json                        ← AgendaTask schema
    Submit grant proposal.task.json
  Events/                                   ← AgendaEvent singleton (folder name renameable; discovered by sidecar)
    _eventconfig.json                       ← AgendaEvent schema
    Team standup.event.json
```

Both folders sit at the nexus root as siblings of Page Types and Item Types — no `Agenda/` wrapper. Discovery is sidecar-driven: the Tasks singleton is whichever root folder carries `_taskconfig.json`; the Events singleton is whichever root folder carries `_eventconfig.json`. Renaming the folder in Finder Just Works. If multiple folders carry the same sidecar (pathological), first-found wins with a warning logged.

`_taskconfig.json` / `_eventconfig.json` carry the `config` suffix (asymmetric with the Pages-side / Items-side sidecars) on purpose — the per-entity files use `.task.json` / `.event.json` extensions, so bare `_task.json` / `_event.json` sidecar names would visually clash. Pages-side (`.md` Pages) and Items-side (`.json` Items) don't have this collision, so they get the un-suffixed `_pagetype.json` / `_itemtype.json` / `_pagecollection.json` / `_itemcollection.json` filenames.

`.task.json` and `.event.json` per-entity extensions — easy to filter in indexes; agents reading files can immediately identify the kind without opening them.

Both singleton folders are **eagerly created on launch**. `AgendaTaskManager.loadAll` and `AgendaEventManager.loadAll` ensure the folder exists + seed the appropriate sidecar if absent, so a fresh Nexus shows both folders at root even when empty — predictable for the user, uniform for discovery. Multiple Task / Event types per Nexus remain a post-v1 Prospect.

---

#### Schema

##### Agenda Task schema (`_taskconfig.json` inside the Tasks singleton)

Built-in (non-deletable) property:
- `status` (Status) — 3-group EventKit-aligned (Upcoming / In Progress / Done)

Built-in fields (not user-creatable):
- `due_at` (Date & Time, optional) — `EKReminder.dueDateComponents`
- `due_floating` (Bool) — true = no timezone
- `due_all_day` (Bool) — true = strip hour/minute/second
- `start_at` (Date & Time, optional) — EKReminder "not before"
- `completed` (Bool) — `EKReminder.isCompleted`
- `completed_at` (Date & Time, optional) — `EKReminder.completionDate`
- `priority` (Number 0–9) — `EKReminder.priority`
- `recurrence` — `EKRecurrenceRule` mirror
- `alarm_offsets` (Number[]) — negative seconds before due
- `tier1` / `tier2` / `tier3` — Context relations

##### Agenda Event schema (`_eventconfig.json` inside the Events singleton)

Built-in (non-deletable) property:
- `status` (Status) — 3-group EventKit-aligned (Upcoming / In Progress / Done). Same shape as AgendaTask; user-set, decoupled from `start_at` / `end_at` date math.

Built-in fields (not user-creatable):
- `start_at` (Date & Time, required) — `EKEvent.startDate`
- `end_at` (Date & Time, required) — `EKEvent.endDate`
- `all_day` (Bool) — strip time
- `location` (String) — `EKEvent.location`
- `recurrence` — `EKRecurrenceRule` mirror
- `alarm_offsets` (Number[]) — negative seconds before start
- `alarm_absolute` (Date & Time[]) — fixed-time alarms
- `tier1` / `tier2` / `tier3` — Context relations


---

#### Built-in properties

- **AgendaTask** — required built-in **`status`** Status property (3 EventKit-aligned groups: Upcoming / In Progress / Done; non-deletable; bridges to `EKReminder.isCompleted`). All other AgendaTask properties are user-defined.
- **AgendaEvent** — required built-in **`status`** Status property. Same 3 EventKit-aligned groups as AgendaTask. User-set (decoupled from `start_at` / `end_at` date math) — the user marks status to track their own engagement with the event ("Upcoming" before, "In Progress" during, "Done" after attending). EventKit mapping for AgendaEvent ships at v0.6.0; through v0.3.0 the field round-trips on disk and edits via the Item Window inspector. All other AgendaEvent properties are user-defined.

Users who want a `type` taxonomy can add it via the schema editor like any other Select — neither Agenda kind ships a built-in `type` field (Status is the sole built-in workflow indicator).

---

#### Built-in `status` property (AgendaTask only, v0.3.0)

Pommora's Status type with **3 EventKit-aligned fixed groups: Upcoming / In Progress / Done**. Group IDs (`upcoming` / `in_progress` / `done`) map cleanly onto EventKit semantics — the v0.6.0 sync layer doesn't need translation logic.

Marked `builtin: true` — Status cannot be deleted on AgendaTask. Group **labels** are user-renamable; **options** are user-editable (add "Blocked", "Waiting on someone", etc.). Default seed:

```
Upcoming        → [Not started]
In Progress     → [In progress]
Done            → [Done]
```

EventKit mapping when v0.6.0 sync ships:

| Pommora StatusGroupID | `EKReminder.isCompleted` |
|---|---|
| `upcoming` | `false` |
| `in_progress` | `false` |
| `done` | `true` |

**The 3-slot structure is structural — not user-configurable.** Adding a 4th group would break EventKit compatibility (no clean mapping target). Customization happens by adding options within groups.

AgendaEvent also carries built-in `status`. Same 3 EventKit-aligned groups (Upcoming / In Progress / Done). User-set, decoupled from `start_at` / `end_at` date math — tracks the user's engagement with the event. EKEvent's own status field (`.tentative` / `.confirmed`) is a separate EventKit concept; the v0.6.0 sync layer chooses how to bridge Pommora's Status as the design evolves.

Full spec → [[Properties]].

---

#### EventKit mapping

Each side maps to one EventKit entity. No data-driven inference — the file extension is the discriminator.

| File extension | EventKit target | Mapping |
|---|---|---|
| `.task.json` | `EKReminder` | `dueDateComponents` ← `due_at` (with `timeZone = nil` if `due_floating`); `isCompleted` ← `completed`; `completionDate` ← `completed_at`; `priority` ← `priority` |
| `.event.json` | `EKEvent` | `startDate` ← `start_at`; `endDate` ← `end_at`; `isAllDay` ← `all_day`; `location` ← `location` |

Stable identifiers: `EKEvent.eventIdentifier` for events, `EKCalendarItem.calendarItemIdentifier` for reminders. Both stored on the entity (field name `eventkit_uuid` on each Codable struct).

---

#### Sandbox + permissions (macOS 26.4 target)

Required for EventKit access in a sandboxed build:

1. **Sandbox entitlements** — `com.apple.security.personal-information.calendars` (events) AND `com.apple.security.personal-information.reminders` (tasks). Both required because the two sides hit separate EventKit APIs with separate permission grants.
2. **Info.plist** — `NSCalendarsFullAccessUsageDescription` + `NSRemindersFullAccessUsageDescription`
3. **Modern access APIs** — `requestFullAccessToEvents(completion:)` + `requestFullAccessToReminders(completion:)` (legacy `requestAccess` deprecated on macOS 14+)

EventKit sync **NOT enabled by default** — opt-in via Settings → Agenda. Schema fields exist day one so opt-in is additive. Sync ships v0.6.0.

##### Change observation

External EKEventStore changes observed via Swift Concurrency async sequences over `NotificationCenter`. AgendaTask and AgendaEvent each get a dedicated reconciliation pass:

```swift
for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
    await agendaTaskManager.reconcileWithEventKit()
    await agendaEventManager.reconcileWithEventKit()
}
```

Reconciliation re-fetches calendars (for events) and reminders (for tasks), compares against `.event.json` / `.task.json` files by `eventkit_uuid` + `EKCalendarItem.lastModifiedDate`, applies last-write-wins.

##### Constraint: `EKRecurrenceRule` is immutable after creation

Modifying recurrence requires constructing a new `EKRecurrenceRule` and reassigning. Pommora's sync layer always builds fresh from the JSON `recurrence` block — never in-place mutation. Same constraint applies to both sides.

---

#### Sidebar treatment

**Agenda has no sidebar section.** Agenda Tasks and Agenda Events surface via the **Calendar pin entry** at the top of the sidebar (heading-less Pinned section). The Calendar view shows both kinds plus EventKit-mirrored system content once sync is enabled.

Access via:

- The Calendar row in the Pinned section (data layer ships v0.3.0; Calendar UI lands in a follow-up plan)
- From within a Context's composed-blocks surface (embedded "agenda items linked to this Topic" view; v0.6.0+)
- Direct file access in Finder

---

#### UI: Item Window for AgendaTask + AgendaEvent

Both AgendaTask and AgendaEvent open in the same Item Window popover used for [[Items]] — title + properties + 250-char description, not a full-frame surface. Per-side UI variations (kind-specific quick fields, layout differences) ship with the v0.3.1 redesign.

When an AgendaTask's `start_at` and `due_at` would carry the same value, the property panel collapses to **a single "When?" date input**. Expands to two when the user wants asymmetric values. On disk, both fields persist separately — the collapse is purely UI. (AgendaEvent always shows separate start/end inputs since both are required.)

---

#### Validation

Enforced at every file write:

**AgendaTask (`.task.json`):**
1. Conforms to the Tasks singleton's `_taskconfig.json` (`type` property cannot be removed; options editable)
2. `due_at` is optional; `start_at` is optional ("not before" hint)
3. `due_all_day` only meaningful when `due_at` is set
4. `completed_at` only meaningful when `completed = true`
5. Filename = title

**AgendaEvent (`.event.json`):**
1. Conforms to the Events singleton's `_eventconfig.json` (`type` property cannot be removed; options editable)
2. `start_at` AND `end_at` both required; `end_at >= start_at`
3. `all_day` only meaningful when `start_at` is set
4. Filename = title

---

