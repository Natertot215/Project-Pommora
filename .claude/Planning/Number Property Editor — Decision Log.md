## Number Property Editor — Decision Log

### Frame

- **Purpose:** Fill the `number` branch of the PropertiesPane property editor (no branch today) with a **Format** surface — a format family (Number / Percent / Currency), thousands separators, decimal places, and a fraction/"out of" Value — all **property-wide** (def-level) — plus a **per-view Style** row (Number / Bar) that renders a progress bar in-cell.
- **Core Value:** One discoverable, in-editor surface that fully controls how a number property renders everywhere, matching Notion's property-wide number formatting rather than the current half-built per-view stub.
- **Success Criteria:** Opening Properties → a Number property shows the Format section; setting currency/percent/separators/decimals/fraction rewrites the def-level config and every view's cells re-render on the same beat; the on-disk value stays a bare, human-legible number.

### The Reframe (what already exists vs what changes)

A **per-view** number format is half-built and shipping today — and we're **replacing** it, not extending it:

- **Per-view `number_format`** (`columnStyles.ts:18` enum `integer/decimal/percent/currency`) is a `column_styles` field, resolved by `styleFor`, rendered by `formatNumber` (`formatValue.ts:118`), and set by the column-header Style radios (`columnMenu.ts:64`).
- Nathan's call: number config is **property-wide** (like `checkbox_color`/`link_color`), not per-view. So the format family + all its knobs move to **def-level** on `propertyDefinition`, the renderer reads the def, and the per-view `number_format` stub is superseded.
- **Percent today does ×100** (`Intl` `style:'percent'` → `0.42` renders `"42%"`). Nathan ruled for files-canonical/agent-legibility: store the literal (`30` → `"30%"`) — C-1.

So this task = **(1)** new def-level number fields + zod, **(2)** a `formatNumber` rewrite reading the def config (literal percent), **(3)** a `NumberEditor` pane mirroring `CheckboxEditor`/`DateTimeEditor`, **(4)** reconciling the superseded per-view `number_format` (remove its column-menu radios), **(5)** a per-view `look` (number/bar) + an in-cell progress-bar renderer.

### Sources

- `Features/Properties.md` — property system; §"Where Properties Live" says display formats live per-VIEW in `column_styles`, calling out number formats specifically. **This goes stale** — number format moves def-level per Nathan. Pending §"Per-Type Editor Panes" + "Display Formats" name the Number pane + number-format picker as the remaining gap.
- `Features/Views.md` — `column_styles` documented as carrying "number format choices" per-view. Stale once number format is def-level.
- `src/shared/columnStyles.ts:18` — `NUMBER_FORMATS=['integer','decimal','percent','currency']`; `columnStyle` zod carries `number_format`; `defaultStyleFor('number') → {number_format:'decimal'}`. **All superseded by def-level.**
- `src/shared/columnMenu.ts:64` — `styleMenuItems('number')` = the 4 Integer/Decimal/Percent/Currency radios (the existing surface); `STYLE_VALUES.number_format`; `parseStyleAction`. **Radios removed** (format no longer per-view).
- `src/shared/properties.ts:69` — `propertyDefinition` zod (looseObject); def-level precedent fields `checkbox_color`/`link_color`/`link_underline`/`link_display`, each `z.string()/.boolean().optional().catch(undefined)`. **No live number def field** — Swift's old `number_format` rides inert as a foreign key (comment lines 8–12). New number def fields land here.
- `src/renderer/src/Detail/Views/PropertyEditing/formatValue.ts:118` — `formatNumber(value, number_format)`: `integer`=0-frac, `decimal`=default (thousands sep on), `percent`=`Intl` percent (×100, ≤2 frac), `currency`=`Intl` currency hardcoded `USD`. **Rewritten** to read the def config (family + currency + separators + decimals + fraction/target).
- `src/renderer/src/Detail/Views/Table/Cell.tsx:153` — number branch calls `formatNumber(v.value, style.number_format ?? 'decimal')`. **Changes** to pass the def config (from `ctx.schema.find(...)`, the checkbox-cell pattern at the color lookup) instead of the per-view style.
- `src/renderer/src/Components/Detail/PropertiesPane.tsx:344` — `editor(id)` type switch; **no `number` branch** (falls through). `saveColumnStyle(propId, patch)` (per-view, `:259`) vs def-level IPC writers `saveCheckboxColor`/link config (`:254`). New number def-level fields need a **new IPC writer** (mirror `setCheckboxColor` → `editProperty`).
- `src/renderer/src/Components/Detail/CheckboxEditor.tsx` — the def-level-field editor pattern to mirror (property-wide value in, IPC writer out). `DateTimeEditor.tsx` — the multi-`PickerRow` layout + conditional/`Reveal` row pattern (the fraction Target row reveals like the Day row).
- `src/renderer/src/Components/Detail/PickerControl.tsx` — `PickerControl<T>({ariaLabel,value,options,onPick})`, the reusable trigger+PickerMenu row control.
- `src/main/index.ts` — `property:setCheckboxColor` handler = `editProperty(root, id, {checkbox_color})`; the def-field write template. `src/preload/index.ts` — the bridge method template.
- `src/renderer/src/Detail/Views/Table/TableView.tsx:550/574/603` — number cell edit path: numeric keystroke filter `/^-?\d*(\.\d*)?$/`, `parseFloat`, commits a **bare number**. Confirms format is pure display; input untouched.
- `src/renderer/src/Detail/Views/Table/columnWidths.ts:30` — `number:{min:50,default:100,max:350}`; `STYLE_MIN` per-style scaffold (keyed on per-view look — won't directly serve a def-level fraction, which widens cells).

### Decisions

#### A — Scope
- **A-1:** [confirmed] Number config is **property-wide (def-level)** on `propertyDefinition`, not per-view — Nathan's call, matching `checkbox_color`/`link_color` and Notion, dodging "a new view forgets the column is dollars." Per-view is reserved for the *look* (Number/Bar), mirroring checkbox's color(def)/look(view) split.
- **A-2:** [confirmed] The property editor is the **sole** surface for number *format* (family/currency/separators/decimals/fraction). The existing per-view column-menu *format* radios (Integer/Decimal/Percent/Currency) are **removed** — format went def-level. **They're replaced, not deleted**, by the per-view **look** radios (Number/Bar): `styleMenuItems('number')` returns `[look('Number','number'), look('Bar','bar')]`, so a number cell's right-click menu stays populated and the look gets a native menu surface too, mirroring checkbox's Checkbox/Switch look radios (review finding F2).

#### B — Format Model (the def-level fields)
- **B-1:** [assumed] Format **family** is a single picker: **Number**, **Percent**, **Currency** (currency then names which — B-4). "Integer" and "Decimal" from the old enum collapse away — integer-vs-decimal is now the **Decimals** knob, not a format. ← confirm the family list
- **B-2:** [confirmed] **Separators** (on/off) — thousands grouping (commas in en-US). Offered for **Number + Currency only**; the Separators row is **hidden when family = Percent** (Nathan).
- **B-3:** [confirmed] **Decimals** — `Hidden` or a fixed count 1–10, all families incl. Percent. `Hidden` = **no decimals displayed** (a stored `3.14` shows `3`); the value is untouched — decimals are hidden, not stripped, so switching off Hidden brings `.14` back. 1–10 = force exactly N places. (Read as display-as-integer; Nathan to flag if he meant "show the number's own decimals, don't pad.")
- **B-4:** [confirmed] **Currency** — seed a curated common list: **USD, EUR, GBP, AUD, CAD, JPY** ("GBP" = pounds; Nathan's "GDP" was a slip). `Intl.NumberFormat` renders any ISO code natively. Full-ISO search = Prospect.
- **B-5:** [confirmed] **Fraction** (on/off) — Number + Currency only (**not** Percent, which is inherently /100 — Nathan's "brain fart"). When on, a value renders "N out of [Value]" and the editor reveals a **Value** input (Nathan keeps the name "Value" — it's the denominator/"out of" number). Value is def-level. This is the ratio the Show-as ring/bar fills against (N ÷ Value). ← wording "N out of M" vs "N/M" still to pick (Nathan: "does exactly what you describe")

#### C — Percent Semantics (the value fork)
- **C-1:** [confirmed] **Percent stores the literal.** Type `30`, frontmatter reads `30`, cell shows `"30%"` — no hidden ×100, so an agent/human reads `progress: 30` as 30%. Ring/bar fills `value ÷ 100`. The renderer stops using `Intl` percent style (which ×100s); it formats the bare number and appends `%`.

#### C2 — Show-as Look (per-view stub)
- **C2-1:** [confirmed] **In tables, "Style" is a plain picker ROW** (a `PickerControl` like Format/Decimals — **not** a tile grid), options **Number · Bar**. **Ring is dropped for tables** — a table cell has no vertical room for a ring. The Style row reveals **only when Fraction is on (Number/Currency) or family is Percent** (the cases with a fillable ratio); a bare unbounded number gets no Style row.
- **C2-2:** [confirmed] **This look is PER-VIEW** (`column_styles.look`), *unlike* Notion's all-views — the clean mirror of checkbox (color def-level, look per-view). The table look ∈ `number`/`bar`. Add `'number','bar'` to `COLUMN_LOOKS` (`columnStyles.ts:6`); `STYLE_VALUES.look = COLUMN_LOOKS` (`columnMenu.ts:93`) then covers `style:look:bar` automatically — **no new allowlist entry** (review-verified). No consumer switches exhaustively on look, so a `look:'bar'` breaks nothing (review-verified).
- **C2-3:** [confirmed] **Bar RENDERS this cycle** (not a stub — Nathan has the design), via a **new design-system component** `design-system/components/ProgressBar/{ProgressBar.tsx, progressBar.css.ts}` (NOT inline in Cell) — a reusable primitive taking a `fill` (0–1) + accent, consumed by the Cell number branch. It draws a **rounded bar**: **accent fill** (`var(--accent)`) over a **label-control track** (the unfilled background), **no stroke/border yet** (held until Nathan visually confirms). Fill fraction = `value ÷ divisor` — `divisor` = the def-level **Value** (fraction) or `100` (percent). `look:'number'` renders the formatted text as usual.
- **C2-4:** [confirmed] The Style row rides the **same `Reveal` disclosure animation** as the other toggle-gated rows (the Day row precedent) — content revealed by a toggle above it.
- **C2-5:** [open] **Bar fill edge cases** — clamp fill to `[0, 1]` (value > divisor caps at full, negative → empty); `divisor` of `0`/unset → empty bar (no divide-by-zero). ← confirm clamp vs overflow at build/visual
- **C2-6:** [confirmed] **The tile grid (Layout-pane style) is for OTHER view types, not tables** — the Notion 3-tile "Show as" (Number/Bar/Ring) belongs to view types with vertical room (Gallery/Board). Available Show-as options are gated by **view type**, not just the property. Ring is a Prospect; tables ship the Number/Bar row only.

#### D — Reconciliation & Adjacencies
- **D-1:** [confirmed] `formatNumber` signature changes (per-view enum → def config); its **only** caller is `Cell.tsx:153` (no showcase caller, unlike `formatDate` — review-verified) — updates in lockstep. Tests move: `formatValue`, `columnStyles`, `columnMenu`, **`cellMenu.test.ts:17`**, **`Cell.test.tsx:164`** (the last two surfaced by review finding F3; typecheck/vitest gate catches them regardless).
- **D-2:** [confirmed] Removing per-view `number_format` *format enum* ripples: `columnStyle` zod field, `defaultStyleFor('number')`, `STYLE_VALUES.number_format`, `parseStyleAction`. `styleMenuItems('number')` is **repurposed, not dropped** → Number/Bar look radios (A-2). `columnStyle` is loose + `.catch` so an old view carrying `number_format` reads clean (ignored) — no migration. **Not affected:** `build.ts:187 configOf` preserves a *def-level* `number_format` (Swift's foreign key in the SQLite config blob), which is a different field from the per-view enum — untouched by this removal (review finding F1).
- **D-3:** [confirmed] Docs to reconcile (go stale): Properties.md §"Where Properties Live" + Pending, Views.md `column_styles` description — number format is **def-level**, not per-view. Log the Number editor + Bar as shipped.
- **D-4:** [confirmed] New def-level number fields need one batched IPC writer mirroring `setLinkConfig` (`index.ts:748`, the field-by-field-whitelisted multi-field template) → `editProperty` → `mutateRegistry`; one round-trip per editor change (review-verified this generalizes cleanly; `editProperty` re-validates only on name change). **Field naming:** the new fields must NOT reuse `number_format` — that name is already Swift's def-level foreign key preserved in `build.ts:187 configOf` (finding F1). Use distinct names (e.g. `number_style`/`number_family`, `number_currency`, `number_separators`, `number_decimals`, `number_fraction`, `number_denominator`). The new fields **don't** join `configOf` — cosmetic def config stays off the index, matching `checkbox_color`/`link_color` (which aren't in `configOf`).

#### E — Sweep-Surfaced (interaction, state, ripple)
- **E-1:** [confirmed] **Conditional reveal chain.** Currency-name row shows only when family=Currency; Separators hidden when family=Percent; Fraction row shows only for Number/Currency (hidden for Percent); Value row shows only when Fraction=on; Style row shows when Fraction=on OR family=Percent. All ride the `Reveal` disclosure (`DateTimeEditor` Day-row pattern).
- **E-2:** [confirmed] **Value preservation on collapse** — hiding the Value row (Fraction off, or family→Percent) preserves the stored Value (restore on re-enable), matching the Day-row precedent. Same for the currency code when family leaves Currency, and the `look` when the Style row hides. Reveal is display-only, never a data clear.
- **E-3:** [open] **Column width** — "N out of [Value]", currency strings, and the bar are wider than a bare number; the `number` width floor (`columnWidths.ts:30`, min 50) likely wants a bump. Per-style `STYLE_MIN` is keyed on per-view look, so `bar` COULD take a `STYLE_MIN.number.bar` (the mechanism fits the per-view look); the def-level fraction/currency width can't use it — raise the base `number` min or leave to manual resize. Defer exact values to plan.
- **E-4:** [confirmed] **Percent-semantics reconciliation dodges a migration.** Removing per-view `number_format` means no property is "percent" until re-configured def-level (default = Number/plain). Existing per-view percent columns revert to plain-number display (showing the raw stored `0.42` as `0.42`, not misreading it) rather than silently reinterpreting old ×100 data. Once a user sets Percent def-level, storage is literal from then on. No data migration needed.
- **E-5:** [confirmed] **Empty value + Bar** — a number cell with no stored value renders blank (no bar), not an empty track; the bar only draws for a present value (the "No value, no key" model already means absent = no cell content).
- **E-6:** [confirmed] **Def fields on non-number / after changeType** — the new number def fields ride as inert loose-object foreign keys on any non-number def (like `checkbox_color` on a URL), round-tripping unread; a number→other type change leaves them dormant, not cleared (matches `checkbox_color`/`link_color` behavior). No special handling.
- **E-7:** [confirmed] **Backward read is free** — `propertyDefinition` is loose with per-field `.catch(undefined)`; old defs without the number fields read clean, and an older build round-trips fields it doesn't know. No migration.

### Core (must-have)
- Def-level number fields on `propertyDefinition` (format family, currency code, separators, decimals, fraction toggle, Value/denominator) — zod `.optional().catch(undefined)`, loose round-trip, one IPC writer.
- `formatNumber` rewritten to compose family + separators + decimals (+ fraction "N out of Value"); `Cell.tsx` feeds it the def config; percent stores the literal + appends `%` (C-1).
- `NumberEditor` pane in the `number` branch, mirroring `CheckboxEditor`/`DateTimeEditor`: Format picker → conditional Currency row (family=Currency) → Separators toggle → Decimals picker → conditional Fraction toggle + revealed **Value** input → conditional **Style** row (Number/Bar, revealed when Fraction-on or Percent). All conditional rows ride the `Reveal` disclosure.
- Per-view **Style/look** field for number (`column_styles.look` ∈ `number`/`bar`), written via `saveColumnStyle`; `styleMenuItems('number')` repurposed to Number/Bar look radios (A-2). **Bar renders** via a new `ProgressBar` design-system component (C2-3) — rounded accent-fill over a label-control track, no stroke, fill = `value ÷ divisor`.
- Per-view `number_format` *format* enum removed end-to-end (D-2); docs reconciled (D-3).
- Bare-number storage preserved; input path untouched.

#### Prospects (allowed later, not now)
- **Bar stroke/border refinement** — a stroke around the bar, held until Nathan eyeballs the strokeless look (C2-3).
- **Ring + the tile-grid Show-as for dynamic view types** — completion ring (and the Notion-style Number/Bar/Ring tile grid) for Gallery/Board/etc. that have vertical room; the available Show-as set is view-type-gated (C2-6). Not for tables.
- **Full-ISO currency search** — beyond the curated seed; `Intl` already supports every code, so it's a picker-UI addition, no schema change.
- **Negative/color formatting** (red negatives, etc.) — not asked; leave the formatter composable.

#### Out of Scope (won't do — distinct from Prospects)
- Number cell input/entry changes — the numeric keystroke filter + parseFloat stay; format is display-only.
- Per-view number format — explicitly replaced by property-wide (A-1).

#### Considered & Rejected
- **Extend the per-view `number_format` enum** (add currency codes/decimals as per-view) — rejected: Nathan wants property-wide; per-view fragments a currency's identity across views.
- **Keep percent as ×100 ratio storage** — on the table, pending C-1; departs from files-canonical legibility.

#### Lessons
- The "new feature" was 60% already shipped as a per-view stub — grounding caught that "add a Number editor" is really "replace the per-view number format with a property-wide one," which reframes the whole task and its doc reconciliation.
- Removing a per-view surface (format radios) doesn't mean deleting the code path — repurposing `styleMenuItems('number')` to the new per-view look kept the cell menu alive; the adversarial pass caught the would-be empty menu (F2).

#### Review Record
- Independent adversarial pass (build-breaking-agent) run against the log + live code: **3 findings, 0 blockers** — F1 (`build.ts:187 configOf` awareness + field-name collision), F2 (number cell menu would empty → repurpose to look radios), F3 (two more tests migrate). All three verified against real code and folded (D-1/D-2/D-4, A-2, C2-2). Every Sources `file:line` was verified accurate; the def-write path, `look` union safety, `formatNumber` single-caller, bar-math (no crash), and E-2 non-issue all confirmed by the pass. Log is planning-ready.
