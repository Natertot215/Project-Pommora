### Agenda

The operational layer's calendar-anchored side. Splits into two distinct entity types:

- **Agenda Tasks** — EKReminder-aligned: due date (optional), completion flag, priority (0–9), optional start ("not before") date. Stored as `.task.json` inside the Tasks singleton folder at the nexus root.
- **Agenda Events** — EKEvent-aligned: required start + end, location, all-day flag. Stored as `.event.json` inside the Events singleton folder at the nexus root.

Both share the property catalog used elsewhere (Number / Select / Status / etc.) and both carry `tier1` / `tier2` / `tier3` Context relations.

The split mirrors EventKit: `EKEvent` and `EKReminder` are peer types (separate `EKEntityType` buckets, separate access APIs, separate apps — Calendar.app vs Reminders.app), so the disk layout uses two sibling singleton folders at the nexus root rather than an `Agenda/` wrapper. EventKit sync (v0.5.0) maps each side cleanly: Agenda Task → EKReminder, Agenda Event → EKEvent.

In code, the Swift types are `AgendaTask` and `AgendaEvent` (prefixed to avoid `Task` / `Event` Swift stdlib collisions). UI labels remain "Task" and "Event" by default (renameable via Settings).

UX-wise both entities behave identically to [[Items]] — the floating Item Window, tier1/2/3 multi-relations, user properties, sort/filter. Distinction is on-disk shape + EventKit-facing only.

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

The sidecars carry the `config` suffix (vs the un-suffixed Pages/Items `_pagetype.json` / `_itemtype.json`) so they don't clash with the `.task.json` / `.event.json` entity extensions. Those per-entity extensions let indexes and external agents identify the kind without opening the file.

Both singleton folders are **eagerly created on launch**: `AgendaTaskManager.loadAll` / `AgendaEventManager.loadAll` ensure the folder exists and seed the sidecar if absent, so a fresh Nexus shows both folders even when empty. Multiple Task / Event types per Nexus remain a post-v1 Prospect.

---

#### Schema (config sidecar)

`_taskconfig.json` and `_eventconfig.json` each carry `properties: [PropertyDefinition]` — the same property shape as Page Types and Item Types. The default seed is exactly one built-in, non-deletable property: `_status` (Status type); every other property is user-defined. The three tier relations (`tier1` / `tier2` / `tier3`) merge in via `BuiltInContextLinkProperties` for surfaces that show them.

The `_status` Status structure (3 fixed EventKit-aligned groups — Upcoming / In Progress / Done — renameable labels, user-editable options, default seed, the 3-slot rule, the `EKReminder.isCompleted` mapping) is canonical in [[Properties]] § "Status property type". Agenda-specific notes:

- Group IDs (`upcoming` / `in_progress` / `done`) map onto EventKit semantics directly, so the sync layer needs no translation logic.
- `_status` is user-set, decoupled from any date math — it tracks engagement ("Upcoming" before, "In Progress" during, "Done" after). EKEvent's own `.tentative` / `.confirmed` status is a separate EventKit concept; how sync bridges to it is an open sync-layer question.
- Neither kind ships a built-in `type` field — `_status` is the sole built-in workflow indicator. A `type` taxonomy can be added via the schema editor like any other Select.

#### Entity fields (per-entity file)

The EventKit-shaped fields live at the root of each `.task.json` / `.event.json` file (on the `AgendaTask` / `AgendaEvent` struct), NOT in the config sidecar. `tier1` / `tier2` / `tier3` store there too, as bare ID arrays.

**Agenda Task (`.task.json`):** `due_at` (optional, `EKReminder.dueDateComponents`), `due_floating` (Bool — true = no timezone), `due_all_day` (Bool), `start_at` (optional, "not before"), `completed` (`EKReminder.isCompleted`), `completed_at`, `priority` (Int 0–9), `recurrence`, `alarm_offsets` (`[TimeInterval]`, negative = before due), `calendar_id` + `eventkit_uuid` (sync state).

**Agenda Event (`.event.json`):** `start_at` (required, `EKEvent.startDate`), `end_at` (required, `EKEvent.endDate`), `all_day` (Bool), `location`, `recurrence`, `alarm_offsets` (`[TimeInterval]`), `alarm_absolute` (`[Date]` — fixed-time alarms), `calendar_id` + `eventkit_uuid` (sync state).

---

#### EventKit sync (v0.5.0)

EventKit sync is opt-in (Settings → Agenda), not enabled by default; the on-disk fields exist day one so opt-in is purely additive. The design below is the sync contract — the integration itself lands at v0.5.0.

Each side maps to one EventKit entity, discriminated by file extension (no data-driven inference).

| File extension | EventKit target | Mapping |
|---|---|---|
| `.task.json` | `EKReminder` | `dueDateComponents` ← `due_at` (with `timeZone = nil` if `due_floating`); `isCompleted` ← `completed`; `completionDate` ← `completed_at`; `priority` ← `priority` |
| `.event.json` | `EKEvent` | `startDate` ← `start_at`; `endDate` ← `end_at`; `isAllDay` ← `all_day`; `location` ← `location` |

Stable identifiers: `EKEvent.eventIdentifier` for events, `EKCalendarItem.calendarItemIdentifier` for reminders. Both stored on the entity (field name `eventkit_uuid` on each Codable struct).

##### Sandbox + permissions

Sandboxed EventKit access requires:

1. **Entitlements** — `com.apple.security.personal-information.calendars` (events) AND `...reminders` (tasks); the two sides hit separate APIs with separate grants.
2. **Info.plist** — `NSCalendarsFullAccessUsageDescription` + `NSRemindersFullAccessUsageDescription`.
3. **Access APIs** — `requestFullAccessToEvents` + `requestFullAccessToReminders` (legacy `requestAccess` deprecated on macOS 14+).

##### Change observation

External `EKEventStore` changes are observed via async sequences over the `.EKEventStoreChanged` notification; each manager re-fetches its side, compares against the `.task.json` / `.event.json` files by `eventkit_uuid` + `EKCalendarItem.lastModifiedDate`, and applies last-write-wins.

`EKRecurrenceRule` is immutable after creation, so the sync layer always builds a fresh rule from the JSON `recurrence` block rather than mutating in place — both sides.

---

#### Sidebar treatment

**Agenda has no sidebar section.** Tasks and Events surface via the **Calendar pin entry** at the top of the sidebar. The Calendar row opens `CalendarDetailView` — currently a placeholder two-section list (Tasks above, Events below); the calendar grid and EventKit-mirrored content ship v0.5.0. Right-click the Calendar pin → "New Task" / "New Event" stubs an entity (`createTask` / `createEvent`). Also reachable from a Context's composed-blocks surface (embedded linked-agenda view; v0.7.0+) or directly in Finder.

---

#### UI: Item Window for AgendaTask + AgendaEvent

Tasks and Events open in the same floating Item Window used for [[Items]] — title + properties + 1000-char description, not a full-frame surface. (Agenda's description stays a JSON field on `.task.json` / `.event.json`; only Item *content* files became `.md` with the body as description.) (Not yet wired; rows in the placeholder Calendar list aren't yet clickable.) Planned per-side detail: when an AgendaTask's `start_at` and `due_at` carry the same value, the panel collapses to a single **"When?"** input, expanding to two for asymmetric values (both persist separately on disk); AgendaEvent always shows separate start/end inputs since both are required.

---

#### Validation

Enforced at every file write:

**AgendaTask (`.task.json`):** conforms to `_taskconfig.json` (`_status` non-removable; options editable); `due_at` and `start_at` optional; `due_all_day` meaningful only when `due_at` set; `completed_at` meaningful only when `completed`; filename = title.

**AgendaEvent (`.event.json`):** conforms to `_eventconfig.json` (`_status` non-removable); `start_at` + `end_at` both required, `end_at >= start_at`; filename = title.

---

