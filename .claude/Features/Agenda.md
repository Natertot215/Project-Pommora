### Agenda

Pommora's third operational-layer entity, sibling to Vaults — **calendar-anchored items (events, tasks, to-dos, phases)** with EventKit integration as a load-bearing concern.

**Why separate from Vaults:**
- EventKit requires entities matching `EKEvent` / `EKReminder` shapes — fixed schemas (`startDate`/`endDate` or `dueDateComponents`/`completed`). Generic Vault Items can't carry these without lossy bidirectional mapping.
- Quick-capture surfaces (system Calendar, Siri, Reminders, lock-screen widgets) need a single known-location entity. "Create a task" shouldn't have to decide "in which Vault?"
- Pommora's Mac-first posture makes deep EventKit integration a real value.

UX-wise Agenda items behave identically to Items — Item Window popover, tier1/2/3 multi-relations, user properties, sort/filter. Distinction is on-disk + EventKit-facing only.

---

#### On disk

```
<nexus-root>/
  Agenda/                              ← sibling of Vaults
    _agenda.json                        ← shared schema for all Agenda items
    Buy-groceries.agenda.json           ← Agenda item
    Team-standup.agenda.json
    Submit-report.agenda.json
```

`.agenda.json` extension — easy to filter in indexes; agent reading files can immediately identify them.

---

#### Single unified entity with type-as-property

No structural `kind` discriminator. The user-facing distinction (Task / To-Do / Phase / Event / custom) is a **property** (`properties.type`) — user-extensible like any other Select. EventKit mapping is driven by which time fields are populated, not by a schema field. Users enter what they know (a time, a due date, or just a title) and Pommora figures out the mapping from the data shape.

---

#### Schema

```json
{
  "id": "01H...",
  "icon": "checkmark.circle",

  "start_at": null,                        /* ISO-8601; if set, end_at required → EKEvent */
  "end_at":   null,
  "all_day":  false,

  "due_at":        null,                   /* ISO-8601; if set without start_at → EKReminder */
  "due_floating":  false,                  /* true = nil timezone (Apple's "floating date") */
  "due_all_day":   false,

  "completed":    false,
  "completed_at": null,

  "location":       null,
  "recurrence":     null,                  /* EKRecurrenceRule-shaped JSON */
  "alarm_offsets":  [],                    /* TimeInterval seconds before; negative = before */
  "alarm_absolute": [],                    /* ISO-8601 absolute alarm dates */

  "sync_target":   null,                   /* "calendar" | "reminder" | null (inferred) */
  "calendar_id":   null,
  "eventkit_uuid": null,

  "description":  "Short plain text, 250-char cap",
  "tier1": [], "tier2": [], "tier3": [],
  "created_at":  1716480000,
  "modified_at": 1716480000,

  "properties": {
    "type":     "Task",                    /* Built-in Select; defaults [Task, To-Do, Phase, Event] */
    "status":   "not_started",             /* Built-in Status; EventKit-aligned 3 groups (Upcoming/In Progress/Done) */
    "priority": null,                      /* If 0/1/5/9 numeric, maps to EKReminder.priority */
    /* other user properties */
  }
}
```

Full field-by-field details, recurrence shape, and validation rules live in `// Planning//Contexts-Vaults-spec.md`.

---

#### Built-in `type` property

`_agenda.json` includes a built-in `type` Select with defaults `[Task, To-Do, Phase, Event]`. `builtin: true` (cannot be deleted); options user-editable (rename, add Habit/Block/Reminder, recolor). Other Agenda properties are user-defined like Vault properties; reuses the Vault property/view editor — no special panel.

---

#### Built-in `status` property (v0.3.0)

Pommora's Status type with **3 EventKit-aligned fixed groups: Upcoming / In Progress / Done**. Group IDs (`upcoming` / `in_progress` / `done`) map cleanly onto EventKit semantics — the v0.7.0 sync layer doesn't need translation logic.

Marked `builtin: true` — Status cannot be deleted. Group **labels** are user-renamable; **options** are user-editable (add "Blocked", "Waiting on someone", etc.). Default seed:

```
Upcoming        → [Not started]
In Progress     → [In progress]
Done            → [Done]
```

EventKit mapping when v0.6.0 sync ships:

| Pommora StatusGroupID | `EKEvent.status` | `EKReminder.isCompleted` |
|---|---|---|
| `upcoming` | `.tentative` (future-dated) | `false` |
| `in_progress` | `.confirmed` (currently happening) | `false` |
| `done` | `.confirmed` (past) | `true` |

**The 3-slot structure is structural — not user-configurable.** Adding a 4th group would break EventKit compatibility (no clean mapping target). Customization happens by adding options within groups.

Existing nexuses predating v0.3.0 get Status auto-injected on first load via `AgendaSchema.migrate(_:)`. Full spec → `// Features//Properties.md`.

---

#### EventKit mapping (data-driven)

| Pommora fields populated | EventKit target | Mapping |
|---|---|---|
| `start_at` + `end_at` | `EKEvent` | `startDate` ← `start_at`; `endDate` ← `end_at`; `isAllDay` ← `all_day` |
| `due_at` set, no `start_at` | `EKReminder` | `dueDateComponents` ← `due_at` (with `timeZone = nil` if floating) |
| Neither set | `EKReminder` | Unscheduled to-do (macOS allows; iOS doesn't) |
| `sync_target` explicit | Forced | Edge cases (long Phase the user wants as a Reminder) |

Stable identifiers: `EKEvent.eventIdentifier` for events, `EKCalendarItem.calendarItemIdentifier` for reminders. Both stored in `eventkit_uuid`.

---

#### Sandbox + permissions (macOS 26.4 target)

Required for EventKit access in a sandboxed build:

1. **Sandbox entitlement** — `com.apple.security.personal-information.calendars` (`ENABLE_PERSONAL_INFORMATION_CALENDARS = YES`)
2. **Info.plist** — `NSCalendarsFullAccessUsageDescription` + `NSRemindersFullAccessUsageDescription`
3. **Modern access APIs** — `requestFullAccessToEvents(completion:)` + `requestFullAccessToReminders(completion:)` (legacy `requestAccess` deprecated on macOS 14+)

EventKit sync **NOT enabled by default in v1** — opt-in via Settings → Agenda. Schema fields exist day one so opt-in is additive.

##### Change observation

External EKEventStore changes observed via Swift Concurrency async sequences over `NotificationCenter`:

```swift
for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
    await agendaManager.reconcileWithEventKit()
}
```

Reconciliation re-fetches calendars + reminders, compares against `.agenda.json` files by `eventkit_uuid` + `EKCalendarItem.lastModifiedDate`, applies last-write-wins.

##### Constraint: `EKRecurrenceRule` is immutable after creation

Modifying recurrence requires constructing a new `EKRecurrenceRule` and reassigning. Pommora's sync layer always builds fresh from the JSON `recurrence` block — never in-place mutation.

---

#### Sidebar treatment

**Agenda items don't appear in the sidebar at all** (consistent with Items — see `Items.md` "Sidebar visibility"). Access via:

- The `Calendar` row at the top of the sidebar (heading-less pinned section; opens the calendar view over Agenda items + EventKit-mirrored system events)
- From within a Context's composed page (embedded "agenda items linked to this Topic" view; v0.7.0)
- Direct file access in Finder

---

#### UI: single "When?" date input

When `start_at` and `due_at` would carry the same value, the property panel collapses to **a single "When?" date input**. Expands to two when the user wants asymmetric values. On disk, both fields persist separately — the collapse is purely UI.

---

#### Validation

Enforced at every file write:

1. Every Agenda item conforms to `Agenda/_agenda.json` schema (`type` property cannot be removed; options editable)
2. If `start_at` is set, `end_at` MUST also be set (and `end_at >= start_at`)
3. `due_at` is independently optional
4. `all_day` only meaningful when `start_at` is set
5. `due_all_day` only meaningful when `due_at` is set
6. Filename = title

---

#### Full specification

Complete schema details, recurrence shape, EventKit sync conflict resolution, and CRUD scope live in `// Planning//Contexts-Vaults-spec.md`.
