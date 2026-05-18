### Agenda

Pommora's third operational-layer entity, sibling to Vaults — **calendar-anchored items (events, tasks, to-dos, phases)** with EventKit integration as a load-bearing concern. Agenda items live structurally separate from Vault Content because the macOS EventKit ecosystem requires distinct, fixed-shape entities that map cleanly to `EKEvent` and `EKReminder`.

**Why Agenda is separate from Vaults:**
- EventKit (Calendar / Reminders system framework) requires entities matching `EKEvent` / `EKReminder` shapes — fixed schemas with `startDate`/`endDate` (events) or `dueDateComponents`/`completed` (reminders). Generic Vault Items can't carry these cleanly without lossy bidirectional mapping.
- Quick-capture surfaces (system Calendar, Siri, Reminders, lock-screen widgets, Notification Center) need a single known-location entity to write to. "Create a task" shouldn't have to decide "in which Vault?"
- Pommora's Mac-first posture makes deep EventKit integration a real value, not polish

UX-wise Agenda items behave identically to Items — Item Window popover, tier1/2/3 multi-relations to Contexts, user properties, sort/filter. Distinction is on-disk + EventKit-facing only.

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

No structural `kind` discriminator. The user-facing distinction (Task / To-Do / Phase / Event / custom) is a **property** (`properties.type`) — user-extensible like any other Select. EventKit mapping is driven by which time fields are populated, not by a schema field.

This means: users don't have to know "is this an event or a reminder?" up front. They enter what they know (a time, or a due date, or just a title) and Pommora — and EventKit — figure out the mapping from the data shape.

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
    "priority": null,                      /* If 0/1/5/9 numeric, maps to EKReminder.priority */
    /* other user properties */
  }
}
```

Full field-by-field details, recurrence shape, and validation rules live in `// Planning//Contexts-Vaults-spec.md`.

---

#### Built-in `type` property

The Agenda layer's `_agenda.json` schema includes one built-in property — `type` — as a Select with defaults `[Task, To-Do, Phase, Event]`. It's marked `builtin: true` (cannot be deleted), but the options are user-editable: rename existing, add custom (Habit, Block, Reminder, etc.), recolor.

All other Agenda properties are user-defined the same way Vault properties are. The Agenda layer reuses Pommora's Vault property/view editor UI — no special property panel.

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

Required for any EventKit access in a sandboxed Pommora build:

1. **Sandbox entitlement** — `com.apple.security.personal-information.calendars` (Xcode build setting `ENABLE_PERSONAL_INFORMATION_CALENDARS = YES`)
2. **Info.plist usage description keys** — `NSCalendarsFullAccessUsageDescription` + `NSRemindersFullAccessUsageDescription`
3. **Modern access APIs** — `requestFullAccessToEvents(completion:)` and `requestFullAccessToReminders(completion:)` (legacy `requestAccess` is deprecated on macOS 14+; Pommora targets 26.4)

EventKit sync is **NOT enabled by default in v1** — opt-in via Settings → Agenda. Schema fields exist from day one so opt-in is additive.

##### Change observation

Pommora observes external EKEventStore changes via Swift Concurrency async sequences over `NotificationCenter`:

```swift
for await _ in NotificationCenter.default.notifications(named: .EKEventStoreChanged) {
    await agendaManager.reconcileWithEventKit()
}
```

Reconciliation re-fetches calendars + reminders, compares against Pommora's `.agenda.json` files by `eventkit_uuid` + `EKCalendarItem.lastModifiedDate`, applies last-write-wins per item. Verified against current Apple EventKit documentation.

##### Constraint: `EKRecurrenceRule` is immutable after creation

Modifying recurrence on a saved EKEvent / EKReminder requires constructing a new `EKRecurrenceRule` and reassigning. Pommora's sync layer always builds a fresh `EKRecurrenceRule` from the JSON `recurrence` block when writing changes back — never attempts in-place mutation. Same shape on the JSON side, fresh object on the EventKit side every write.

---

#### Sidebar treatment

No dedicated "Agenda" section in the sidebar. **Agenda items don't appear in the sidebar at all** (consistent with Items — see `Items.md` "Sidebar visibility"; both live exclusively in their primary views, not in the structural tree). Access via:

- The `Calendar` row at the top of the sidebar (in the heading-less pinned section; opens the calendar view over Agenda items + EventKit-mirrored system events)
- From within a Context's composed page (embedded "agenda items linked to this Topic" view; v0.9+)
- Direct file access in Finder for power users

Keeps the sidebar focused on browse navigation; Agenda's primary surface is calendar / list views.

---

#### UI: single "When?" date input

When an Agenda item's `start_at` and `due_at` would carry the same value, the property panel collapses to **a single "When?" date input** rather than two separate fields. Expands back to two when the user wants asymmetric values. On disk, both fields persist separately — the collapse is purely UI. Schema unchanged.

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
