### Agenda

The operational layer's calendar-anchored side. Agenda is the parent schema holding two peer entity types, mirroring EventKit:

- **Tasks** — EKReminder-aligned: optional due date, completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` in the Tasks singleton folder.
- **Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` in the Events singleton folder.

Both carry the shared property catalog and `tier1` / `tier2` / `tier3` Context relations, with the same property mechanics as Pages — multi-relations, user properties, sort/filter (catalog → [[Resources/II. Pommora/II. Swift/II. Features/Properties]]). The only distinction is on-disk shape and the EventKit target. `EKEvent` and `EKReminder` are peer types (separate APIs, separate apps), so the disk layout uses two sibling singleton folders rather than an `Agenda/` wrapper. UI labels default to "Task" / "Event" (renameable via Settings).

---

#### On disk

```
<nexus-root>/
  Tasks/                                    ← Tasks singleton (folder name renameable; discovered by sidecar)
    _taskconfig.json                        ← Task schema
    Submit grant proposal.task.json
  Events/                                   ← Events singleton (folder name renameable; discovered by sidecar)
    _eventconfig.json                       ← Event schema
    Team standup.event.json
```

Discovery is sidecar-driven: the Tasks/Events singleton is whichever root folder carries `_taskconfig.json` / `_eventconfig.json`, so renaming the folder in Finder Just Works (first-found wins if duplicated). The `config` suffix avoids clashing with the `.task.json` / `.event.json` entity extensions, which let indexes and external agents identify the kind without opening the file.

Both folders are eagerly created on launch — `loadAll` ensures the folder exists and seeds the sidecar if absent, so a fresh Nexus shows both even when empty. Multiple Task / Event types per Nexus is a Prospect.

---

#### Schema (config sidecar)

Each sidecar carries `properties` — the same shape as Page Collections. The default seed is exactly one built-in, non-deletable property: `_status` (Status type); everything else is user-defined. Tier relations merge in via `BuiltInContextLinkProperties` for surfaces that show them.

The `_status` structure (3 fixed EventKit-aligned groups — Upcoming / In Progress / Done — renameable labels, the 3-slot rule, `EKReminder.isCompleted` mapping) is canonical in [[Resources/II. Pommora/II. Swift/II. Features/Properties]] § "Status property type". Agenda-specific:

- Group IDs (`upcoming` / `in_progress` / `done`) map onto EventKit semantics directly — no sync translation needed.
- `_status` is user-set, decoupled from date math — it tracks engagement. EKEvent's own status is a separate concept; how sync bridges to it is an open question.
- Neither kind ships a built-in `type` field; `_status` is the sole built-in workflow indicator. A `type` taxonomy can be added as any other Select.

#### Entity fields (per-entity file)

EventKit-shaped fields live at the root of each `.task.json` / `.event.json` file, NOT in the sidecar. `tier1` / `tier2` / `tier3` store there too, as bare ID arrays.

**Task:** `due_at` (`EKReminder.dueDateComponents`), `due_floating` (no timezone), `due_all_day`, `start_at` ("not before"), `completed` (`isCompleted`), `completed_at`, `priority` (0–9), `recurrence`, `alarm_offsets` (negative = before due), `calendar_id` + `eventkit_uuid` (sync state). All optional.

**Event:** `start_at` + `end_at` (required, `startDate` / `endDate`), `all_day`, `location`, `recurrence`, `alarm_offsets`, `alarm_absolute` (fixed-time alarms), `calendar_id` + `eventkit_uuid` (sync state).

---

#### EventKit sync (deferred)

Opt-in (Settings → Agenda); the on-disk fields exist now so opt-in is purely additive. Each side maps to one EventKit entity by extension:

| Extension | Target | Key mapping |
|---|---|---|
| `.task.json` | `EKReminder` | `due_at` → `dueDateComponents`; `completed` → `isCompleted`; `priority` → `priority` |
| `.event.json` | `EKEvent` | `start_at` → `startDate`; `end_at` → `endDate`; `all_day` → `isAllDay` |

Sync state lives in `calendar_id` + `eventkit_uuid`. Entitlements: `.calendars` + `.reminders`; access via `requestFullAccessToEvents` / `requestFullAccessToReminders`. Change observation via `.EKEventStoreChanged`, last-write-wins.

---

#### Sidebar treatment

Agenda has no sidebar section — Tasks and Events surface via the Calendar pin entry, detailed in [[Resources/II. Pommora/II. Swift/II. Features/Sidebar]]. Also reachable from a Context's composed-blocks surface (planned) or in Finder.

---

#### Opening Tasks + Events

Tasks and Events open in a compact panel — title + properties + description (a JSON field on the entity), not a full-frame surface. Not yet wired: the list rows aren't clickable and the hosting surface is undecided. Planned per-side detail: a Task whose `start_at` and `due_at` match collapses to a single **"When?"** input, expanding to two for asymmetric values (both persist separately); an Event always shows separate start/end inputs.

---

#### Validation

`_status` is non-removable (options stay editable); per-entity shape rules apply on each write.

- **Task:** conforms to `_taskconfig.json`; `due_at` / `start_at` optional; `due_all_day` meaningful only with `due_at` set.
- **Event:** conforms to `_eventconfig.json`; `start_at` + `end_at` required, `end_at >= start_at`.

Filename = title for both.

---
