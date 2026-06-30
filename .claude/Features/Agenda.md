### Agenda

The operational layer's calendar-anchored side. Agenda is the parent schema holding two peer entity types, each mirroring an EventKit kind:

- **Tasks** (`.task.json`) — reminder-shaped: an optional due date, an optional "not before" start, completion, and priority.
- **Events** (`.event.json`) — calendar-event-shaped: a required start and end, a location, and an all-day flag.

Both carry the shared property catalog and `tier1` / `tier2` / `tier3` relations, with the same property mechanics as Pages. The only differences are the on-disk shape and the EventKit target.

Each kind lives in its own singleton folder, discovered by a config sidecar (`_taskconfig.json` / `_eventconfig.json`); the folder name is a renameable default. EventKit's reminder and event APIs are separate, so the two kinds stay separate singletons rather than sharing one `Agenda/` wrapper. UI labels default to "Task" and "Event."

### Features

#### II. Tasks

A `.task.json` file carries at its root `due_at` (with `due_floating` and `due_all_day` modifiers), an optional `start_at` ("not before"), `completed` and `completed_at`, and `priority`. All are optional.

#### II. Events

An `.event.json` file carries `start_at` and `end_at` (required on write, lenient on read), `all_day`, `location`, and `alarm_absolute` (fixed-time alarms).

#### II. Shared Fields

Both kinds carry `id`, an optional `icon`, a plain-text `description`, the `tier1` / `tier2` / `tier3` relations (bare ULID arrays), a `properties` object (values keyed by property ID), `created_at` / `modified_at`, a `recurrence` object (round-tripped, not yet edited), `alarm_offsets` (seconds; negative is before), and `calendar_id` + `eventkit_uuid` for sync state. Foreign keys are preserved by value on every write.

#### II. Schema + Status

Each kind's config sidecar carries `property_definitions` — the same shape as a Collection's schema. The seed is one built-in, non-deletable **Status** property (three EventKit-aligned groups — see `Properties.md`); everything else is user-defined. Status is user-set on both kinds — for an Event it's decoupled from the date math, tracking the user's engagement rather than the clock. The catalog → `Properties.md`.

### Architecture

#### II. On-Disk Layout

```
<nexus-root>/
  Tasks/                          ← discovered by its sidecar (folder name renameable)
    _taskconfig.json
    Submit grant proposal.task.json
  Events/
    _eventconfig.json
    Team standup.event.json
```

The `config` suffix on the sidecar avoids clashing with the `.task.json` / `.event.json` entity extensions, which let the index and external agents identify a file's kind without opening it. Any folder carrying an agenda config sidecar is skipped by Collection discovery, so no folder name is reserved — a Collection could be named "Tasks" and stay a Collection.

#### II. CRUD

Tasks and Events run through one generic agenda CRUD: create mints a ULID and writes the JSON with kind defaults; rename is a file rename preserving the `.task.json` / `.event.json` suffix; update merges over the JSON, retaining foreign keys; and set-property and set-tier each have their own path. The filename is the title, and an Event's `end_at` can't precede its `start_at`.

#### II. EventKit Sync

Each kind maps to one EventKit entity by extension (`.task.json` → a reminder, `.event.json` → a calendar event); `calendar_id` + `eventkit_uuid` hold the sync state, and the Status groups map onto reminder completion.

### Pending

**Agenda Surfacing:** The UI for Tasks and Events. The data layer round-trips and indexes, but nothing renders — a Task or Event can't be selected or opened. The planned surface is a Calendar entry in the sidebar opening a combined Tasks-and-Events view, with a compact per-entity panel.

**EventKit Sync:** The live, opt-in bidirectional mirror between Agenda entities and the system Reminders and Calendar apps. The on-disk fields are ready; the bridge isn't built.
