## Cards Interaction Sweep — Plan

Consolidated from an 8-agent read-only audit (one per property type: multi-select, select, status, checkbox, date/time, number, link, context). Every `file:line` below was reported grounded by its agent; each is re-verified against real code at implementation time before the edit. Goal: fix every real bug, cut the on-every-X violations, and land the DRY hoists the audit surfaced — then build-breaker + simplify + screenshots.

### Locked Decisions (Nathan)

- **D-1 Chip × gate:** gate the inline hover-× on **multi-select only** — keep it where `(view.card_size ?? 1) >= 0.8`, drop it below so a click always opens the picker. Select/context keep their × always (it clears the whole value, an expected affordance; only multi-select's × drops one of several values on a stray click). Table × always stays. *(Residual: the overlap is label-width-driven, so a very short single-value multi chip can still overlap at ≥0.80 — flag, don't over-engineer.)*
- **D-2 Switch look:** keep Switch on cards but give it a card zoom hook so it scales with `--chip-zoom`/`--card-scale`.
- **D-3 Re-add a removed prop/tier/context:** no new surface — the existing add-property menu / property picker already IS the "not-currently-shown" surface, so a hidden prop/tier/context must simply appear there. Picking it reveals (unhide).
- **D-4 Checkbox double-surface:** exclude already-visible checkboxes from the add list (a consequence of D-3's "list only what's not shown").

### Bugs

- **BUG-1 [P0] Compact chip click-steal → value loss (multi/select/context).** The chip's `chipRemove` zone is always pointer-active (opacity-0 but hittable, ~80% of a short chip); a click fires `onRemove`, filters the value (multi→[], select→null), and `applyPropertyValue` deletes the frontmatter key → the property vanishes. `Cell.tsx` remove wiring at `CardValue.tsx:170`; `chip.css.ts:149-170`. **Fix (D-1):** wire the `remove` prop into `Cell` only when `(view.card_size ?? 1) >= 0.8`.
- **BUG-2 [P1] Link Edit silently drops the alias (data loss).** `cardValueInput.ts:34-38` serializes `{url}` with no alias; the current alias (`v`) is never read. Table does it right (`TableView.tsx:742-748` rides the alias along). **Fix:** thread the current alias into the url commit; share the Table's logic (see DRY-6).
- **BUG-3 [P1] Link "Rename" is identical to "Edit" — no alias-edit path on cards.** `CardValue.tsx:120` collapses `cell:rename` and `cell:edit` to the same URL editor; the Table has a distinct alias mode (`TableView.tsx:897-915`). **Fix:** give cards a real alias-edit mode for `cell:rename`; share the seam (DRY-6).

### Reveal / Add-property menu (D-3, D-4)

- **REV-1 The add-property menu lists exactly what's NOT currently shown.** Today `addable` = schema props in `ADDABLE_TYPES` ∩ `isBlankValue` (`CardsView.tsx:576-585`), so it misses: hidden-but-filled schema props (select agent), and hidden tiers/contexts (they're not in the schema and `ADDABLE_TYPES` omits tier/context — context agent). **Fix:** the menu lists every column that is hidden OR blank-and-not-shown — hidden schema props (any type), hidden tiers/contexts, and blank addable props — and excludes anything already visible (drops the visible-checkbox double-surface, D-4). Picking reveals via `unhide`; a blank addable type still opens its value pane to set a value; a hidden-with-value prop/tier just reappears. Reuse `hiddenListIds`-style logic; don't hand-roll a parallel visibility test.

### Performance (on-every-X — hard rule)

- **PERF-1 `contextOptionsFor` allocates a fresh option array per tier/context column, per card, per render** (eager, whether or not a picker is open) — `CardsView.tsx:118-125` called at `:508-519`. The table only computes it inside the open cell's picker. **Fix:** memoize the three tier lists once per `tree`; compute options lazily (only for the open picker). Folds into DRY-4.
- **PERF-2 Intl formatters rebuilt on every format call** — `new Intl.NumberFormat` (`formatValue.ts:183-190`) and `toLocaleDateString/Time` (`formatValue.ts:26-28,83,102-104`), both on the shared non-virtualized card render path. **Fix:** module-level cached `Intl.NumberFormat`/`Intl.DateTimeFormat` keyed by their option tuple.
- **PERF-3 `ctx.schema.find(d => d.id === id)` scattered ~20 sites** (Cell, CardValue, TableView, pipeline, GroupBand, cellResolve, columnLabel), several run 2–3× per value per render. **Fix:** add `schemaById: Map<string, PropertyDefinition>` to `ResolveContext`, built in `buildResolveContext` beside the existing `contextsById` (`resolveContext.ts:24-35`); replace the hot-path finds (Cell, CardValue) with O(1) lookups.
- **PERF-4 The datetime `PickerMenu` subtree is allocated for every value kind** (`CardValue.tsx:176-190`) even when `t !== 'datetime'`. **Fix:** gate that `PickerMenu` behind `t === 'datetime'`.
- **PERF-5 `statusOptions(def)` / `findOption` / `statusGroupOf` re-run per status cell render** (`Cell.tsx:93-97`, `properties.ts:178-184`). **Fix:** a memoized `statusMeta(def)` (WeakMap on `def`) → `{ optionByValue, groupByValue }`; single-sources the DRY-7 box too.

### DRY / hoists

- **DRY-1 `PropertyPicker.pick` duplicates `pickSemantics.pick`** byte-for-byte except the context branch (`PropertyPicker.tsx:69-81` vs `:169-179`). **Fix:** `PropertyPicker` consumes `pickSemantics`, extended to take the context branch (honors the file's own "extracted so a host pane reuses the exact semantics" note).
- **DRY-2 Multi-toggle `includes ? filter : [...spread]` triplicated** (`PropertyPicker.tsx:71-73`, `:170-172`, `Cell.tsx:134`). **Fix:** one `toggleValue(selected, value)` helper.
- **DRY-3 Four near-identical `CalendarPicker` mounts** (`CardValue.tsx:176-190`, `CardAddPicker.tsx:52-61`, `TableView.tsx:820-832`, `PreviewInspector.tsx:338-349`). **Fix:** a shared `DatetimeValuePicker` wrapper owning the value mapping, the `relative→short` remap, the `timeFormat` source, and `date_format` — which also erases the add/inspector's hardcoded-`full` divergence (was P2) and the non-reactive `getState()` timeFormat read.
- **DRY-4 `contextOptionsFor` duplicated** (`CardsView.tsx:118-125` vs `TableView.tsx:611-620`). **Fix:** hoist `contextOptionsForColumn(col, schema, tree)` to `pipeline/contextOptions.ts`; carries PERF-1's memo.
- **DRY-5 Tier commit routing duplicated** (`CardsView.tsx:107-115` vs `TableView.tsx:623-628`) + the synthetic context-def fallback `{id, name:'', type:'context'}` (`CardValue.tsx:192`, `TableView.tsx:841`). **Fix:** shared tier-write helper + a shared synthetic-def factory.
- **DRY-6 Link url logic forked** — `urlClickTarget` (open-or-edit), `editorInitial` url branch, and the alias preserve/edit logic all live only in the Table. **Fix:** a shared `linkValue.ts` seam (`urlClickTarget(v)`, alias-preserving commit, alias editor) consumed by both views; kills BUG-2 + BUG-3 at the fork.
- **DRY-7 Checkbox-look status box duplicates the real-checkbox box** (`Cell.tsx:102-107` vs `:81-87`). **Fix:** extract a small box-glyph component (sibling to `StatusCapsule`) both compose.

### Small fixes

- **SM-1 (D-2)** Switch card zoom hook in `switch.css.ts` (track/knob read `--chip-zoom`/`--card-scale`); extend `.card-value:has(.cell-checkbox)` → `:has(.cell-checkbox, .cell-switch)` so the switch shares the value band.
- **SM-2** Bar is a dead style-pick on a plain number — gate the Bar item in `columnMenu.ts:74-75` to bar-capable configs (percent, or fraction + truthy denominator).
- **SM-3** Empty checkbox-look status renders `--` instead of an empty box — exclude the `status && look==='checkbox'` case from `canFillBlank` so `Cell` paints its box (matches the real-checkbox metaphor).
- **SM-4** Empty-context dead picker — when a context column resolves zero options, suppress the `--` fill affordance (`CardValue.tsx:65-72`).
- **SM-5** Thread the column `look` into the card add-picker's value pane (`CardAddPicker`) so a status/checkbox added there shows its real look, not always pill.

### Deferred (logged, not this sweep)

- Status cycle/glyph hardcode the 3 seed group ids (latent — no group-editing UI ships) · off-step stored minutes have no dropdown option (edge) · negative fraction denominator (nonsensical input, already guarded) · select with zero options offers no inline "create option" (that's a feature, not a fix).

### Implementation order

1. **Bugs + D-1/D-2 small UIX** (BUG-1, BUG-2, BUG-3, SM-1) — the value-loss fixes first.
2. **Reveal/add menu** (REV-1, D-4) — one coherent change to the add list.
3. **Perf** (PERF-1..5) — the hard-rule violations.
4. **DRY hoists** (DRY-1..7) — shared seams; several touch `TableView`, so gate after each.
5. **Remaining small fixes** (SM-2..5).
6. Gate (typecheck + vitest + build) between logical groups; **commit** the sweep.
7. **Build-breaker** pass on the diff → fold findings → **simplify** pass + comment cleanup → final gate.
8. **Screenshots** — compact + regular card, every property type filled; flag+fix anything off; second agent's opinion.
