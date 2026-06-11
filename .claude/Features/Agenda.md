### Agenda

The operational layer's calendar-anchored side. Splits into two distinct entity types:

- **Agenda Tasks** — EKReminder-aligned: due date (optional), completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` inside the Tasks singleton folder at the nexus root.
- **Agenda Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` inside the Events singleton folder at the nexus root.

Both share the property catalog used elsewhere (Number / Select / Status / etc.) and both carry `tier1` / `tier2` / `tier3` Context relations.

The split mirrors EventKit: `EKEvent` and `EKReminder` are peer types (separate `EKEntityType` buckets, separate access APIs, separate apps — Calendar.app vs Reminders.app), so the disk layout uses two sibling singleton folders at the nexus root rather than an `Agenda/` wrapper. EventKit sync (v0.5.0) maps each side cleanly: Agenda Task → EKReminder, Agenda Event → EKEvent.

In code, the Swift types are `AgendaTask` and `AgendaEvent` (prefixed to avoid `Task` / `Event` Swift stdlib collisions). UI labels remain "Task" and "Event" by default (renameable via Settings).

UX-wise both entities carry the same property mechanics as Pages — tier1/2/3 multi-relations, user properties, sort/filter. Distinction is on-disk shape + EventKit-facing only.

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

Both folders sit at the nexus root as siblings of Page Types — no `Agenda/` wrapper. Discovery is sidecar-driven: the Tasks singleton is whichever root folder carries `_taskconfig.json`; the Events singleton is whichever root folder carries `_eventconfig.json`. Renaming the folder in Finder Just Works. If multiple folders carry the same sidecar (pathological), first-found wins with a warning logged.

The sidecars carry the `config` suffix (vs the un-suffixed `_pagetype.json`) so they don't clash with the `.task.json` / `.event.json` entity extensions. Those per-entity extensions let indexes and external agents identify the kind without opening the file.

Both singleton folders are **eagerly created on launch**: `AgendaTaskManager.loadAll` / `AgendaEventManager.loadAll` ensure the folder exists and seed the sidecar if absent, so a fresh Nexus shows both folders even when empty. Multiple Task / Event types per Nexus remain a post-v1 Prospect.

---

#### Schema (config sidecar)

`_taskconfig.json` and `_eventconfig.json` each carry `properties: [PropertyDefinition]` — the same property shape as Page Types. The default seed is exactly one built-in, non-deletable property: `_status` (Status type); every other property is user-defined. The three tier relations (`tier1` / `tier2` / `tier3`) merge in via `BuiltInContextLinkProperties` for surfaces that show them.

The `_status` Status structure (3 fixed EventKit-aligned groups — Upcoming / In Progress / Done — renameable labels, user-editable options, default seed, the 3-slot rule, the `EKReminder.isCompleted` mapping) is canonical in [[Properties]] § "Status property type". Agenda-specific notes:

- Group IDs (`upcoming` / `in_progress` / `done`) map onto EventKit semantics directly, so the sync layer needs no translation logic.
- `_status` is user-set, decoupled from any date math — it tracks engagement ("Upcoming" before, "In Progress" during, "Done" after). EKEvent's own `.tentative` / `.confirmed` status is a separate EventKit concept; how sync bridges to it is an open sync-layer question.
- Neither kind ships a built-in `type` field — `_status` is the sole built-in workflow indicator. A `type` taxonomy can be added via the schema editor like any other Select.

#### Entity fields (per-entity file)

The EventKit-shaped fields live at the root of each `.task.json` / `.event.json` file (on the `AgendaTask` / `AgendaEvent` struct), NOT in the config sidecar. `tier1` / `tier2` / `tier3` store there too, as bare ID arrays.

**Agenda Task (`.task.json`):** `due_at` (optional, `EKReminder.dueDateComponents`), `due_floating` (Bool — true = no timezone), `due_all_day` (Bool), `start_at` (optional, "not before"), `completed` (`EKReminder.isCompleted`), `completed_at`, `priority` (Int 0–9), `recurrence`, `alarm_offsets` (`[TimeInterval]`, negative = before due), `calendar_id` + `eventkit_uuid` (sync state).

**Agenda Event (`.event.json`):** `start_at` (required, `EKEvent.startDate`), `end_at` (required, `EKEvent.endDate`), `all_day` (Bool), `location`, `recurrence`, `alarm_offsets` (`[TimeInterval]`), `alarm_absolute` (`[Date]` — fixed-time alarms), `calendar_id` + `eventkit_uuid` (sync state).

---

#### EventKit sync (deferred)

Opt-in (Settings → Agenda); on-disk fields exist now so opt-in is purely additive. Each side maps to one EventKit entity by file extension:

| File extension | EventKit target | Key field mapping |
|---|---|---|
| `.task.json` | `EKReminder` | `due_at` → `dueDateComponents`; `completed` → `isCompleted`; `priority` → `priority` |
| `.event.json` | `EKEvent` | `start_at` → `startDate`; `end_at` → `endDate`; `all_day` → `isAllDay` |

Sync state stored as `calendar_id` + `eventkit_uuid` on each entity. Required entitlements: `com.apple.security.personal-information.calendars` + `.reminders`; APIs: `requestFullAccessToEvents` / `requestFullAccessToReminders` (macOS 14+). Change observation via `.EKEventStoreChanged` with last-write-wins reconciliation.

---

#### Sidebar treatment

**Agenda has no sidebar section.** Tasks and Events surface via the **Calendar pin entry** at the top of the sidebar. The Calendar row opens `CalendarDetailView` — currently a placeholder two-section list (Tasks above, Events below); the calendar grid and EventKit-mirrored content ship v0.5.0. Right-click the Calendar pin → "New Task" / "New Event" stubs an entity (`createTask` / `createEvent`). Also reachable from a Context's composed-blocks surface (embedded linked-agenda view; v0.7.0+) or directly in Finder.

---

#### UI: opening Tasks + Events

Tasks and Events open in a compact panel surface — title + properties + description, not a full-frame surface (the description stays a JSON field on `.task.json` / `.event.json`). **Not yet wired** — rows in the placeholder Calendar list aren't yet clickable, and the hosting surface is undecided. Planned per-side detail: when an AgendaTask's `start_at` and `due_at` carry the same value, the panel collapses to a single **"When?"** input, expanding to two for asymmetric values (both persist separately on disk); AgendaEvent always shows separate start/end inputs since both are required.

---

#### Validation

Enforced at every file write:

**AgendaTask (`.task.json`):** conforms to `_taskconfig.json` (`_status` non-removable; options editable); `due_at` and `start_at` optional; `due_all_day` meaningful only when `due_at` set; `completed_at` meaningful only when `completed`; filename = title.

**AgendaEvent (`.event.json`):** conforms to `_eventconfig.json` (`_status` non-removable); `start_at` + `end_at` both required, `end_at >= start_at`; filename = title.

---

