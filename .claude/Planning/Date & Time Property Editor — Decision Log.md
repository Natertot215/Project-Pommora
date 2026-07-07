## Date & Time Property Editor — Decision Log

### Frame

- **Purpose:** Fill the `datetime` branch of the PropertiesPane property editor (a blank stub today) with a **Format** section — a Date picker row and a Time picker row — that sets the property's per-view display format.
- **Core Value:** A discoverable, in-editor surface to choose a date property's display format, where today the only surface is the table column-header right-click menu.
- **Success Criteria:** Opening Properties → a Date property shows the Format section with Date + Time PickerMenus reflecting the active view's current format; changing either writes the active view's `column_styles[propId]` and the table re-renders on the same beat.

### The Reframe (why this is smaller than it looks)

The per-view date/time format feature is **already built end-to-end** — data, write path, renderer, and a UI surface:

- **Storage:** `SavedView.column_styles` is `Record<propId, ColumnStyle>`; `ColumnStyle` already carries `date_format` + `time_format`.
- **Renderer:** `Cell.tsx` renders datetime via `formatDate(value, style.date_format ?? 'full', style.time_format ?? 'none')` — it already respects the format. (The Properties.md claim that formats "ride through as foreign keys until a UI reads them" is **stale** — the renderer reads them.)
- **Existing surface:** the table column-header menu's **Style submenu** already offers Short/Full/DD-MM-YYYY/MM-DD-YYYY + None/12 Hour/24 Hour, writing the same `column_styles`.
- **Write path:** `TableView.setColumnStyle → persistView → saveViewAdopting` persists per-view style.

So this task = **(1)** a new property-editor surface for existing config, **(2)** threading the active view into the schema-scoped editor, **(3)** a new `relative` format, **(4)** reshaping the `full` format to match Nathan's spec.

### Sources

- `Features/Properties.md` — property system; §"Where Properties Live" states display formats persist per-VIEW in `column_styles` (ratified). **Stale**: Pending §"Display Formats" says formats are unread foreign keys — the renderer reads them.
- `Features/Views.md` — `column_styles` = "per-type look + date/time/number format choices; display formats live per-VIEW here."
- `Features/Configuration.md` — `.nexus/settings.json` personalization + apply-map; **no settings-editing UI exists** (Pending).
- `src/shared/columnStyles.ts` — `DATE_FORMATS=['short','full','dayMonthYear','monthDayYear']`, `TIME_FORMATS=['none','twelveHour','twentyFourHour']`, `ColumnStyle`, `defaultStyleFor('datetime') → {date_format:'full', time_format:'none'}`.
- `src/shared/columnMenu.ts` — `styleMenuItems('datetime')` — the existing column-menu Style radios (the existing surface). `parseStyleAction` decodes `style:<key>:<value>`.
- `src/shared/properties.ts` — one `datetime` type (not date+time); `PropertyDefinition` carries NO date/time format fields (Swift's def-level `date_format`/`time_format` are inert foreign keys).
- `src/shared/types.ts` — `TimeFormatSetting='twelveHour'|'twentyFourHour'`, `DEFAULT_TIME_FORMAT='twelveHour'`, threaded as `NexusTree.timeFormat`. **No nexus date_format default exists.**
- `src/renderer/src/Components/Detail/PropertiesPane.tsx` — the `editor(id)` type switch; `datetime` falls to the blank-body stub. Receives `collectionPath` + `schema` + `onBack` — **no view in scope.**
- `src/renderer/src/Components/Detail/SettingsPane.tsx` — invokes `PropertiesPane`; the active view IS available here (`activeViews[node.id]`) but is not passed down.
- `src/renderer/src/Components/Detail/{OptionEditor,StatusEditor,URLEditor}.tsx` — the per-type editor row patterns to mirror (label span + trailing control).
- `src/renderer/src/design-system/components/PickerMenu/PickerMenu.tsx` — `PickerMenu` + `PickerOption`; options center-aligned by default; `center`/`direction` props; `triggerRef` anchor.
- `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts` — `formatDate(iso, dateFormat, timeFormat)` + `condensedDate` + `ordinal`; hand-rolled `Date`+`Intl`, en-US. `full` = "Wednesday, March 1 2026"; `short` = "March 1st".
- `src/renderer/src/Detail/Views/Table/{Cell,TableView,columnStyles}.tsx` — cell render, `setColumnStyle`, `styleFor` (merges saved over `defaultStyleFor`).
- `src/renderer/src/design-system/components/CalendarPicker/CalendarPicker.tsx` — entry; "Use Time" toggle gates time CAPTURE, fully decoupled from display format (confirms Time=Hidden never blocks entry).

### Decisions

#### A — Surface & Scope
- **A-1:** [assumed] The property-editor Format section is a **second surface** for the same per-view config the column-menu Style submenu already writes — both write `column_styles[propId]`. Not a replacement; the column menu stays. ← confirm
- **A-2:** [confirmed] **The load-bearing scope call.** The property editor is schema-scoped (no view). The Format section writes the **active view's** `column_styles`. You're "editing a property" but the control is per-view — intended (discoverability), not the column-menu-only or nexus-default alternatives.
- **A-3:** [confirmed — REVISED by review finding 2] **Thread the NODE, not the path.** `PropertiesPane` today gets only `collectionPath: string` (`PropertiesPane.tsx:149`) — insufficient. `SettingsPane` holds TWO nodes that **diverge for a Set**: `node` (the selected Collection *or depth-1 Set* — owns `views[]` + `activeViews[node.id]`) vs `schemaCollection` (`node` or its ancestor Collection — owns `schema` + the current `collectionPath`). The view write MUST target `node`, not `schemaCollection`, or a Set's format lands on the wrong sidecar. So thread into PropertiesPane → the datetime editor: **`source = node`** (`CollectionNode | SetNode`), **`view = pickView(node, activeViewId, schema)`** (a resolved `SavedView` — `pickView` at `TableView.tsx:87`, already used at `SettingsPane.tsx:162` for the Layout leaf), and **`load`** (refetch). The existing schema/rename writes still key off `collectionPath` — keep both.
- **A-4:** [confirmed] The editor writes via `saveViewAdopting(source, {...view, column_styles: merged}, load)` — the one view writer (`viewMint.ts:40`), merging like `TableView.setColumnStyle`. No new IPC.

#### B — Options, Order, Labels, the Day Dimension
- **B-1:** [confirmed] Date options, picker order: Month/Day/Year (`monthDayYear`), Day/Month/Year (`dayMonthYear`), Short Date (`short` = `July 6th`), Full Date (`full` = `July 6th, 2026` — **weekday removed**), Relative (`relative` — NEW).
- **B-2:** [confirmed] Time options: 12 Hours (`twelveHour`), 24 Hours (`twentyFourHour`), Hidden (`none`).
- **B-3:** [confirmed] The **Day dimension** — a THIRD row between Date and Time. The weekday is decoupled from the date format into its own control. Options: **Full** (`Wednesday`), **Short** (`Wed`), **Hidden**. NEW `column_styles` field (`weekday`, enum `long`/`short`/`none`; default `none`).
- **B-4:** [confirmed] The Day row is **conditional**: shown ONLY when `date_format ∈ {short, full}` (numeric MM/DD·DD/MM and Relative get no weekday). It **disclosure-animates** in/out on the Date-format change (the `Reveal`/Interaction.md disclosure primitive — a "dropdown sorta" reveal).
- **B-5:** [confirmed] The **Time row is ALWAYS visible** (including under Relative) — Day is the only conditional row. Under Relative, Time gates the "at [clock]" rendering (see C-3): Time-shown → `Today at 3:30 PM`, Time-hidden → `Today`.
- **B-6:** [confirmed — REVISED by review finding 4] The column-menu Style submenu gains the same additions (Relative + the Day/weekday radios), from `styleMenuItems` — which `cellMenu.ts:46/51` also consumes, so the cell menu auto-gains them (E-4 satisfied). **BUT** `parseStyleAction`'s `STYLE_VALUES` allowlist (`columnMenu.ts:84`) has NO `weekday` key → `style:weekday:*` actions return `null` and are silently swallowed on BOTH native menus. Must add `weekday: WEEKDAY_FORMATS` to `STYLE_VALUES`, else the radios render but do nothing. (The property editor writes via `setColumnStyle(id,'weekday',v)`, generic over `keyof ColumnStyle`, bypassing this gate — only the native surfaces need the fix.) In the native menus the Day radios always show; the conditional disclosure is the property-editor's concern only.
- **B-7:** [confirmed] Date row glyph `calendar-days`; Time row glyph `clock`; Day row glyph — [assumed] `calendar-days`'s sibling or a weekday glyph, Nathan's pick at build. Picker option text center-aligned (PickerMenu default). Labels capitalized.

#### C — Formatter (renderer)
- **C-1:** [confirmed] **`formatDate` is decomposed into three independent dimensions** — weekday (`weekday`) + date (`date_format`, weekday-free) + time (`time_format`) — composed at render. `full` reshaped to `Month Ordinal, Year` (weekday removed; today it's `Sunday, March 1st 2026` — ordinal, per formatValue.ts:39); `short` stays `Month Ordinal`. Weekday prepends when its field is `long`/`short` AND date is short/full: `Wednesday, July 6th, 2026` / `Wed, July 6th`.
- **C-1a:** [confirmed — review finding 1] **Both switches gain a `relative` arm or they don't compile.** `formatDate` (`let out` + default-less switch → TS2454) AND `condensedDate` (per-case return → TS2366) are exhaustive over the current 4-member union; adding `'relative'` to `DateFormat` breaks both. `formatDate`'s `relative` arm holds the full relative logic (C-3); `condensedDate`'s `relative` arm collapses to the worded short form (`Month Ordinal`) — the picker never shows relative anyway (C-4a), but it must compile. Add `weekday` as `formatDate`'s new 4th param.
- **C-2:** [confirmed] Existing datetime columns default to `date_format:'full'` + `weekday:'none'` → they render `July 6th, 2026` (they LOSE the weekday `full` currently shows — the intended new default; weekday is now opt-in).
- **C-3:** [confirmed] **"Relative"** — capitalized, day-granular, gated by the Time row:
  - **Time-hidden:** `Today` · `Yesterday` · `Tomorrow` · `N Days Ago` / `In N Days` · `N Weeks Ago` · `N Months Ago` · `N Years Ago`. No clock ever.
  - **Time-shown:** within a week of now, append the clock → `Today at 3:30 PM` · `Yesterday at 3:30 PM` · `Tomorrow at 3:30 PM` · `N Days Ago at 3:30 PM` (+ `In N Days at …`). **Past a week the clock auto-drops** → `N Weeks Ago` · `N Months Ago` · `N Years Ago` (relative continues, time gone).
  - Supersedes the earlier sub-day "3 Hours Ago" idea — recent same-day reads `Today at [clock]` (time-shown) or `Today` (time-hidden).
  - [assumed] "within a week" = |Δ| ≤ 7 days; relative never falls back to an absolute date (stays `N Years Ago` at the far end). ← Nathan's to eyeball at build
- **C-4:** [confirmed — REVISED by review finding 5] Renderer respects the format, but `Cell.tsx:140` currently passes only `date_format` + `time_format` to `formatDate` — it must ALSO forward `style.weekday` (the resolver `styleFor` already spreads `weekday` onto the object; the call site drops it). "Weekday flows for free" is true at the resolver, false at the consumer. Time=Hidden (`none`) suppresses display only.
- **C-4a:** [confirmed — review finding 3] **The CalendarPicker entry path must coerce `relative` → a real date format.** `TableView.tsx:611` reads `date_format` and passes it into the picker's `formatDateValue` (`:618-619` → `condensedDate`/`formatDate`), so a `relative` column would render the date *being entered* as "Today at 3:30 PM" — nonsensical. At that boundary, map `date_format === 'relative'` to `short` (or `full`) before handing it to the CalendarPicker. Entry is otherwise decoupled (the "Use Time" toggle is independent — verified).

#### D — Nexus Default & Docs (adjacencies)
- **D-1:** [confirmed] **Nexus-level date/time DISPLAY default is out of scope** (Prospect). No nexus date_format default exists; time_format's nexus default drives the CalendarPicker clock, not column display (column display defaults to `full`/`none` via `defaultStyleFor`). No settings-editing UI exists (Pending), though `.nexus/settings.json` personalization scaffolding (schema + apply-map + generic setter) is the seam a nexus default would ride later. The picker's "current" reflects the resolved style (type default when a view hasn't set one), matching the column menu.
- **D-2:** [assumed] **Docs to reconcile** (they go stale): Properties.md §"Where Properties Live" + Pending "Display Formats"/"Per-Type Editor Panes" (formats ARE read + settable; only the property-editor pickers were missing). Log the date/time editor as shipped.
- **D-3:** [confirmed] `datetime` and `last_edited_time` share the datetime style branch (columnMenu + defaultStyleFor). The property editor's Format section is for user-facing `datetime`; `last_edited_time` isn't user-edited in PropertiesPane (verify it never reaches this editor).

#### E — Sweep-Surfaced (interaction, state, ripple)
- **E-1:** [confirmed] **Value preservation on collapse.** Hiding the Day row (date→numeric/relative) PRESERVES the stored `weekday` value — switching Date back to short/full restores the choice (the `hidden_properties`-keeps-the-slot pattern). The reveal is display-only, never a data clear. (Time never collapses, so only Day is affected.)
- **E-2:** [confirmed] **`formatDate` signature change ripples.** Adding the `weekday` dimension changes `formatDate`/`condensedDate` signatures; every caller updates in lockstep — `Cell.tsx`, `TableView.tsx` (`formatDateValue`), the CalendarPicker range labels. Plan-time adjacency.
- **E-3:** [confirmed] **Test fixtures move.** `full`'s reshape + the new `weekday` field + `relative` break existing formatValue/columnMenu/columnStyles tests; they update in lockstep (the reshape is intended, not a regression).
- **E-4:** [open] **`cellMenu.ts` parity.** The table CELL right-click also carries a Style submenu — verify whether it shares `styleMenuItems` (auto-gains the additions) or builds its own set needing the same weekday/relative rows. ← verify at plan time
- **E-5:** [confirmed] **Backward read is free.** `columnStyle` is `z.looseObject` with per-field `.catch(undefined)`; old views without `weekday` read clean (→ default `none`), and `settings.json`/sidecar unknown-key preservation round-trips a `weekday` an older build doesn't know. No migration.

### Core (must-have)
- The `datetime` branch renders a Format section: Date PickerMenu (5 options, exact order) + conditional Day PickerMenu (3 options, disclosure-animated, shown only for short/full) + always-visible Time PickerMenu (3 options), glyphs calendar-days / weekday / clock, center-aligned capitalized options.
- NEW `column_styles.weekday` field (`long`/`short`/`none`, default `none`) — `WEEKDAY_FORMATS` enum + `columnStyle` zod + `defaultStyleFor` + `styleMenuItems` radios + **`STYLE_VALUES.weekday`** (else native-menu clicks are swallowed — finding 4).
- `formatDate` gains a 4th `weekday` param + a `relative` arm; `condensedDate` gains a `relative` arm (both required to compile — finding 1); `full` reshaped weekday-free; `Cell.tsx:140` forwards `style.weekday` (finding 5).
- Relative is Time-gated ("Today at [clock]" within a week, else "N Weeks Ago"). The **CalendarPicker entry boundary (`TableView.tsx:611/:618`) coerces `relative → short/full`** so a date being entered never renders relative (finding 3).
- Thread `source = node` (Collection/Set, NOT `schemaCollection`), `view = pickView(node, activeViewId, schema)`, and `load` into PropertiesPane → the editor; write `column_styles[propId].{date_format,weekday,time_format}` via `saveViewAdopting` (finding 2).
- The Day row's disclosure reveal rides the existing `Reveal` primitive (already used in PropertiesPane's `MenuScrollFrame` at `:105` for "All Properties" — confirmed fit) — not a new keyframe.

#### Prospects (allowed later, not now)
- Nexus-level date/time DISPLAY defaults + a settings-editing UI (the whole personalization UI is Pending) — don't-foreclose: the per-view picker reads a resolved style, so a nexus default just changes the fallback later.
- Relative auto-refresh (a "3 days ago" cell going stale as time passes) — render-time compute is fine for now; live ticking is a Prospect.

#### Out of Scope (won't do — distinct from Prospects)
- Rebuilding the column-header Style menu — it stays; this adds a parallel surface.
- Range/date-time entry changes — CalendarPicker entry is untouched.

#### Considered & Rejected
- **Per-view format lives ONLY in the column menu (don't add the property-editor surface)** — rejected: Nathan wants the discoverable in-editor surface; the column menu is hidden behind a right-click on a specific column.
- **Property-editor Format writes a nexus/schema-level default (not per-view)** — rejected: contradicts the ratified per-view `column_styles` model and Nathan's "this is PER-VIEW."

#### Lessons
- Docs describe *intent*; verify against code — Properties.md said formats were unread foreign keys, but the renderer + column menu already read/write them. Grounding caught a stale spec before it misled the build.
