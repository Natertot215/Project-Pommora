## Status Group Model & EventKit — Decision Log

### Frame

- **Purpose:** decide whether Pommora's Status property stays at 3 fixed groups (Open / Active / Done) or extends (Paused / Cancelled), and how that reconciles with the planned-but-unbuilt EventKit sync — *before* the Phase 3 Status pane is specced.
- **Core Value:** a Status group model that gives Nathan the status phases he wants without foreclosing the future EventKit bridge.
- **Success Criteria:** the Phase 3 pane builds on a group model that's either (a) confirmed fixed-3, or (b) extensible in a way that can't corrupt future sync.

### Sources

- `React/src/shared/properties.ts` — `statusGroupId` enum (3 fixed: `upcoming`/`in_progress`/`done`), `StatusGroup {id, label, color, options}`, `statusOption {value, label, color?, group_id}`, `defaultStatusSeed()` (Open/Active/Done, Active=`blue`), `isUntouchedSeed`. The *"Three fixed status-group slots — a fourth breaks EventKit sync mapping"* comment lives here.
- `React/src/shared/agenda.ts` — Tasks (EKReminder-shaped: `completed` bool + `completed_at`) + Events (EKEvent-shaped), with `eventkit_uuid` + `calendar_id` round-trip fields. No status-group field on the agenda item itself.
- `React/src/main/crud/agendaEntity.ts` — agenda CRUD; carries no status↔EventKit mapping code.
- `.claude/Features/Agenda.md` — "the Status groups map onto reminder completion"; **"EventKit Sync … The on-disk fields are ready; the bridge isn't built."**
- `.claude/Features/Properties.md` — "three fixed, EventKit-aligned groups"; "Group IDs are load-bearing and the three slots are fixed — a fourth would break calendar-sync mapping — while group labels and the options inside each group are user-editable."

### Decisions

#### A — Constraint Reality
- **A-1:** [confirmed] EventKit sync is NOT implemented — only the storage shape + round-trip fields exist (Agenda.md: "the bridge isn't built"). "A fourth breaks sync" is a *preventive* design constraint, not enforced by live code.
- **A-2:** [confirmed] The current 3-group → reminder mapping is already lossy: `EKReminder` is binary (`isCompleted`), so `done`→complete and `{upcoming, in_progress}`→*both* incomplete. Open-vs-Active already collapses on a reminder round-trip.
- **A-3:** [open] Is "3 fixed" a hard requirement Nathan is certain of, or the preventive assumption it reads as? (verify-absolute)

#### B — EventKit Fit of Paused / Cancelled
- **B-1:** [confirmed, Apple docs — researched] `EKReminder` completion is a binary `isCompleted` Bool tied to `completionDate`; there is NO reminder status enum. `EKEventStatus` = `none / confirmed / tentative / canceled` — Events have a native `.canceled`, Reminders don't. EventKit has NO "in-progress / paused / on-hold" concept for either kind. Sources: developer.apple.com EKReminder.isCompleted, EKEventStatus.
- **B-2:** [confirmed] Because reminders are binary, the *existing* 3-group mapping is already lossy (3 → 2). Extending the group set does not "break" a clean mapping — there was never a clean one. A future bridge maps via a per-group **completion semantic** (which group ids count as done → `isCompleted`), not via a fixed count.
- **B-3:** [confirmed-direction] "Cancelled" can round-trip for Events (`EKEventStatus.canceled`); "Paused" is Pommora-only for both kinds. Nathan removed the hard-3, so Pommora-only states are acceptable — the group model leads, sync maps what it can.

#### D — Removal Approach (EventKit side)
- **D-1:** [confirmed] Removing fixed-3 is viable from EventKit: replace the "exactly 3 ids" lock with a per-group completion-semantic (`done`-ness) the future bridge reads. Group `id`s stay stable keys for on-disk values; the set just isn't capped at 3.

#### E — Code Blast Radius (two Explore audits + own verification)
- **E-1:** [confirmed] NOTHING in the data / agenda / EventKit layer depends on the count. Verified extensible already: sort (`pipeline/sort.ts`), grouping (`pipeline/group.ts`), the status value picker (`PropertyPicker.tsx`), cell value resolution (`cellResolve.ts`), the SQLite index (`index/build.ts` — stores `status_groups` as an opaque blob), option validation (`properties/schema.ts`), and the remove/cascade (`removeProperty.ts`). Agenda `completed` and the `done` group are INDEPENDENT (no sync code); `_status` non-deletion is documented, not enforced.
- **E-2:** [confirmed] The fixed-3 lives in a small, concentrated surface — status CELL RENDERING (the same the display styles touch). For THIS cycle (open enum, keep 3):
  - `shared/properties.ts:40` — `statusGroupId = z.enum([...])` → `z.string()`.
  - `PropertyEditing/statusCycle.ts` — `STATUS_GROUP_GLYPH` (Record keyed by the 3 ids), `CYCLE` (a fixed sequence of the 3 ids — already specific-id, not positional), `statusGroupOf` return type → widen the types to string; keep the id-keyed glyph + cycle for the 3; add a defensive glyph fallback for any unknown id.
  - `PropertyEditing/StatusCapsule.tsx:11` — a `StatusGroupId` prop → widens to string (trivial).
  - `Table/Cell.tsx:79` — the checkbox empty-box keys on `group !== 'upcoming'` (a specific id, per §G) — stays as-is, no change.
  - A fully-dynamic cycle/glyph for *added* groups is deferred with Paused/Cancelled (unreachable until groups can be created).
- **E-3:** [confirmed] `isUntouchedSeed` (`properties.ts:154`) is NOT a blocker (one audit mis-flagged it): its `groups.length === seed.length` correctly reads "group added/removed = touched." No change needed; only the fixture tests update.
- **E-4:** [open] THE design decision the removal forces — the **glyph** for arbitrary groups (the checkbox/capsule look draws one per group; today it's keyed to the 3 ids). Store a glyph per group (like color), or derive by position/semantic? Ties to the completion-semantic (the `done`-group draws the check).

#### F — Model Shape (RESOLVED — minimal now)
- **F-1:** [confirmed] Open the data model to N groups — `statusGroupId`: `z.enum([...])` → `z.string()` — but **ship only the existing three (Open / Active / Done)**. No new groups seeded, no group-creation UI. The three keep their exact id-keyed glyph + cycle; add a defensive glyph fallback for any unknown id (forward-safe, unreachable until groups can be added). Nearly-free type widening, low blast radius (per §E).
- **F-2:** [confirmed] **Paused / Cancelled → deferred Prospect.** The open enum makes them a drop-in later with no model change — just seed + glyph/color/`done`-flag per new group when the time comes. `Cancelled`→`EKEventStatus.canceled` for Events; the rest ride the completion semantic.

#### G — ID-Keyed, Never Order (from directive 2)
- **G-1:** [confirmed] All status logic keys off the specific group **id**, never list position: the glyph map is `id → glyph`, the checkbox cycle is a defined id-sequence, and the empty-box state is the `upcoming` group by id (not "the first group"). Order is display-only, never load-bearing.

#### H — Option Value Identity (from directive 3 — resolved: keep value=title + auto-disambiguate)
- **H-1:** [confirmed] Remove the duplicate-title REJECTION (`validateOptionValues`) across Select / Multi / Status. Grounded dead-end: `optionModel.ts` sets `value = title = label` and the guard enforces unique `value`s, so a default "Untitled" collides with an existing one (default titles + no-dupes can't coexist). Replace rejection with auto-disambiguation, not decoupling.
- **H-2:** [confirmed] KEEP `value = canonical title`; append a **reserved-character-wrapped disambiguator** only on collision (e.g. `Label` / `Label⟨1⟩`). The wrapper chars are BLOCKED from every title field nexus-wide, so a suffix is unambiguously system-added, never a user's typed title. `label` (the canonical title) is freely duplicable; `value` stays unique AND readable.
- **H-3:** [confirmed] The disambiguator is a cheap **matcher on the edited option only** — add-on-collision / drop-when-unique, a registry uniqueness lookup, NOT a re-walk. Adding a duplicate (a new option) touches no pages at all.
- **H-4:** [confirmed] The existing Phase 1 rename→page-cascade STAYS — it fires only when an IN-USE option's value changes (rename, or a suffix flip), is atomic (SchemaTransaction), and is an acceptable cost for a rare, deliberate rename (NOT the high-frequency "on every X" the hard rule targets). Full agent-legibility is preserved: `$status` always reads as the real title (strip the reserved suffix).
- **H-5:** [confirmed] `color` + `group_id` key off `value` (unique), differentiable per-value independent of the (duplicable) title. Existing options need no migration — their title-values are already unique keys.
- **H-6:** [open] UX detail for the spec — display/edit split: the edit field shows the canonical base ("Label"); read-only surfaces (chips, dropdowns) show the disambiguated form ("Label (1)") so dupes are distinguishable. Which exact reserved wrapper chars (must render paren-like, be blockable, not occur in real titles) → design/spec detail.

### Core (must-have — this cycle)
- **Open the enum:** `statusGroupId` → `z.string()`; widen the id-keyed consumers + defensive glyph fallback (§E-2). Keep seeding + shipping ONLY Open / Active / Done; update the fixture tests.
- **Status pane:** the grouped option editor (per-group heading + hover-reveal `+` + its option chips, chips defaulting to the group color) + the Standard / Compact / Checkbox display styles — built in slices on Phase 2's patterns.
- Ships on today's option model (value=title, dup-rejection live) → the dup-title limit persists in the pane until the next cycle (§H).

#### Sequencing (Nathan's order)
1. **This cycle:** open the enum + the Status pane on Open / Active / Done.
2. **Next cycle:** the value-identity / dup-title matcher (§H) — across Select / Multi / Status together, once all property panes are done. The immediate focus after this ships.
3. **Later (Prospects):** Paused / Cancelled groups; fully user-defined group creation.

#### Prospects (allowed later, not now)
- **Paused / Cancelled groups** — the open enum makes them a drop-in: seed + glyph / color / `done`-flag per group, no model change. `Cancelled`→`EKEventStatus.canceled` (Events); the rest ride the completion semantic.
- **Fully user-defined status groups** — a "＋ new group" affordance with per-group icon + color; the open model already permits it, gated off for now.
- **EventKit sync bridge** — out of scope here; when built it reads the per-group `done`-flag. The group + value-identity models leave it a clean seam, nothing to unwind.

#### Considered & Rejected
- **value = opaque id / frozen readable-slug (the "freeze it" rec)** — rejected. Kills the rename-cascade, but the value then DRIFTS from the title after a rename, sacrificing inline agent-legibility (a core construct) to dodge a cost — the rare-rename page-walk — that's actually acceptable (rare, deliberate, atomic; not an "on every X" violation). Keeping the title readable on disk wins.
- **Temporary invisible id for untitled-only** (Nathan's first alt) — rejected: hands identity back to the title once named, so titled dupes collide again and the guard/cascade return; fixes the symptom, not the disease.
- **Curated 5-set (Paused/Cancelled) as this-cycle core** — deferred to Prospect: ship the existing 3, open the enum so more slot in later with no model change.

#### Lessons
- A "locked" constraint written in a code comment ("a fourth breaks sync") protected a feature that **doesn't exist yet** — grounding the referenced system (the bridge) before trusting the lock is what surfaced the real latitude.
