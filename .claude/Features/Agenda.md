### Agenda

The operational layer's calendar-anchored side. Splits into two distinct entity types:

- **Agenda Tasks** — EKReminder-aligned: due date (optional), completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` inside `<nexus>/Agenda/Tasks/`.
- **Agenda Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` inside `<nexus>/Agenda/Events/`.

Both share the property catalog used elsewhere (Number / Select / Status / Relation / etc.) and both carry `tier1` / `tier2` / `tier3` Context relations.

The split matches EventKit's own API split — separate access permissions, separate predicates, separate data models. EventKit sync at v0.6.0 maps each side cleanly: Agenda Task → EKReminder, Agenda Event → EKEvent.

In code, the Swift types are `AgendaTask` and `AgendaEvent` (prefixed to avoid `Task` / `Event` Swift stdlib collisions — per the ParadigmV2 "no Pommora.X qualification" rule). UI labels remain "Task" and "Event" by default (renameable via Settings).

UX-wise both entities behave identically to [[Items]] — Item Window popover, tier1/2/3 multi-relations, user properties, sort/filter. Distinction is on-disk shape + EventKit-facing only.

---

#### On disk

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

`.task.json` and `.event.json` extensions — easy to filter in indexes; agents reading files can immediately identify the kind without opening them.

---

#### Schema

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

Full field-by-field details, recurrence shape, and validation rules live in `// Planning//Contexts-Vaults-spec.md`.

---

#### Built-in `type` property

Each schema includes a built-in `type` Select with side-appropriate defaults:

- **AgendaTask** — defaults `[Task, To-do, Phase]`
- **AgendaEvent** — defaults `[Event, Meeting, Conference]`

`builtin: true` (cannot be deleted); options user-editable (rename, add custom values, recolor). Other properties on each schema are user-defined — same property/view editor used elsewhere; no special panel.

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

AgendaEvent has no `status` field — events don't have a completion concept. EKEvent status (`.tentative` / `.confirmed`) is not surfaced as a Pommora property in v0.3.0.

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
1. Conforms to `<nexus>/Agenda/Tasks/_schema.json` (`type` property cannot be removed; options editable)
2. `due_at` is optional; `start_at` is optional ("not before" hint)
3. `due_all_day` only meaningful when `due_at` is set
4. `completed_at` only meaningful when `completed = true`
5. Filename = title

**AgendaEvent (`.event.json`):**
1. Conforms to `<nexus>/Agenda/Events/_schema.json` (`type` property cannot be removed; options editable)
2. `start_at` AND `end_at` both required; `end_at >= start_at`
3. `all_day` only meaningful when `start_at` is set
4. Filename = title

---

#### Full specification

Complete schema details, recurrence shape, EventKit sync conflict resolution, and CRUD scope live in `// Planning//Contexts-Vaults-spec.md` (the v0.3.0 ParadigmV2 plan documents the Task / Event split implementation under Phase 4).
