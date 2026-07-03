// The PropertyDefinition model — one schema entry inside a Type / agenda-config
// sidecar's `property_definitions[]`. The zod schema IS the codec AND the type
// (z.infer), mirroring Swift's PropertyDefinition + PropertyType + nested config +
// ReservedPropertyID, minus the ~117 lines of Codable / CodingKeys ceremony.
//
// Snake_case keys = the on-disk shape. Loose ⇒ foreign keys within a def survive a
// rewrite. Only structurally load-bearing fields are modeled. Display formats live
// per-VIEW in SavedView `column_styles` (a deliberate divergence from Swift's def-level
// keys); Swift's def-level riders (number_format, date_format, time_format, display_as,
// date_includes_time) stay inert foreign keys that round-trip but are never read.
// The renderable structure (type, options, context target, tier reverse labels,
// icons) IS modeled because the write path + tier synthesis read it.

import { z } from 'zod'

/** Property type catalog. Raw lowercase / snake_case strings = the on-disk values. */
export const propertyType = z.enum([
  'number',
  'checkbox',
  'datetime',
  'select',
  'multi_select',
  'status',
  'url',
  'context', // the three context-tier links (_tier1/2/3); not user-creatable
  'last_edited_time',
  'file'
])
export type PropertyType = z.infer<typeof propertyType>

const selectOption = z.looseObject({
  value: z.string(),
  label: z.string(),
  // Open solid-palette key (chipColorFor normalizes on render). Lenient: a non-string degrades to
  // undefined rather than failing the whole def parse.
  color: z.string().optional().catch(undefined)
})

/** Three fixed status-group slots — a fourth breaks EventKit sync mapping. */
export const statusGroupId = z.enum(['upcoming', 'in_progress', 'done'])
export type StatusGroupId = z.infer<typeof statusGroupId>

const statusOption = z.looseObject({
  value: z.string(),
  label: z.string(),
  color: z.string().optional().catch(undefined),
  group_id: statusGroupId
})

const statusGroup = z.looseObject({
  id: statusGroupId,
  label: z.string(),
  // Open solid-palette key, required — an absent / non-string color falls back to the neutral solid
  // rather than dropping the group.
  color: z.string().catch('grey'),
  options: z.array(statusOption)
})
export type StatusGroup = z.infer<typeof statusGroup>

/** Context picker constraint. On-disk: `{ kind: "context_tier", tier: N }`. Lenient
 *  `kind` so an unknown target survives parse. */
const contextTarget = z.looseObject({
  kind: z.string(),
  tier: z.number().optional()
})

/** One property schema entry. Loose ⇒ display config + any foreign keys ride through. */
export const propertyDefinition = z.looseObject({
  id: z.string(),
  name: z.string(),
  type: propertyType,
  icon: z.string().optional(),
  select_options: z.array(selectOption).optional(),
  status_groups: z.array(statusGroup).optional(),
  context_target: contextTarget.optional(),
  reverse_name: z.string().optional(),
  reverse_icon: z.string().optional(),
  accept: z.array(z.string()).optional()
})
export type PropertyDefinition = z.infer<typeof propertyDefinition>

// MARK: - Reserved property IDs

/** Built-in property IDs use a `_` prefix; user properties use `prop_<ulid>` (minted by
 *  `mintPropertyId` in ids.ts). Only the ID is reserved — display names are
 *  unrestricted. Mirrors Swift `ReservedPropertyID`. */
export const RESERVED_PROPERTY_ID = {
  id: '_id',
  title: '_title',
  createdAt: '_created_at',
  modifiedAt: '_modified_at',
  status: '_status',
  type: '_type',
  tier1: '_tier1',
  tier2: '_tier2',
  tier3: '_tier3'
} as const

const RESERVED_SET = new Set<string>(Object.values(RESERVED_PROPERTY_ID))

/** True iff `id` is in the reserved catalog (the schema editor blocks claiming one). */
export function isReservedPropertyId(id: string): boolean {
  return RESERVED_SET.has(id)
}

/** The context tier levels. The one source for iterating tiers (1 = Area, 2 = Topic,
 *  3 = Project). Callers validate the 1–3 bound at the CRUD boundary. */
export const TIER_LEVELS = [1, 2, 3] as const

/** Tier level → the BARE frontmatter-root array field (`tier1`/`tier2`/`tier3`). */
export function tierFieldName(level: number): string {
  return `tier${level}`
}

/** Tier level → the RESERVED property id (`_tier1`/`_tier2`/`_tier3`) used in the schema +
 *  context_links.property_id. Distinct from the bare root field (tierFieldName). */
export function tierPropertyId(level: number): string {
  return `_tier${level}`
}

/** Default 3-group seed written when a Status property is first added. Group IDs stay fixed (calendar
 *  sync); labels are Open / Active / Done, and each group seeds one option whose value=label=its group
 *  label, carrying the group color. Per Properties.md § "Status property type → Default seed". */
export function defaultStatusSeed(): StatusGroup[] {
  return [
    { id: 'upcoming', label: 'Open', color: 'grey', options: [{ value: 'Open', label: 'Open', color: 'grey', group_id: 'upcoming' }] },
    { id: 'in_progress', label: 'Active', color: 'blue', options: [{ value: 'Active', label: 'Active', color: 'blue', group_id: 'in_progress' }] },
    { id: 'done', label: 'Done', color: 'green', options: [{ value: 'Done', label: 'Done', color: 'green', group_id: 'done' }] }
  ]
}

/** The pre-7-3 seed (Upcoming / In Progress / Done with `not_started`-style values). A Status property
 *  untouched since before the relabel still matches this, so `isUntouchedSeed` keeps treating it as an
 *  empty seed-only def rather than surfacing its old starter options as real ones. */
function legacyStatusSeed(): StatusGroup[] {
  return [
    { id: 'upcoming', label: 'Upcoming', color: 'gray', options: [{ value: 'not_started', label: 'Not started', group_id: 'upcoming' }] },
    { id: 'in_progress', label: 'In Progress', color: 'blue', options: [{ value: 'in_progress', label: 'In progress', color: 'blue', group_id: 'in_progress' }] },
    { id: 'done', label: 'Done', color: 'green', options: [{ value: 'done', label: 'Done', color: 'green', group_id: 'done' }] }
  ]
}

/** Default single-option seed written when a Select / Multi-Select property is first added. Creation
 *  seeds one starter option (value=label=title) the user then renames or extends. */
export function defaultSelectSeed(): { value: string; label: string }[] {
  return [{ value: 'Option 1', label: 'Option 1' }]
}

/** True while a def still carries EXACTLY its untouched creation seed — scaffolding, not options
 *  the user defined. Value surfaces (the cell picker) treat a seed-only def as "no options yet"
 *  and render empty (Nathan: "don't render groupings as options"); the checkbox-status cycle still
 *  writes the seed values — they're its fixed 3-state backbone. Any rename/add/removal makes the
 *  options real. */
export function isUntouchedSeed(def: PropertyDefinition): boolean {
  if (def.type === 'status') {
    const groups = def.status_groups
    if (!groups) return false
    const matches = (seed: StatusGroup[]): boolean =>
      groups.length === seed.length &&
      seed.every((sg) => {
        const g = groups.find((x) => x.id === sg.id)
        return (
          g?.options.length === 1 &&
          g.options[0].value === sg.options[0].value &&
          g.options[0].label === sg.options[0].label
        )
      })
    return matches(defaultStatusSeed()) || matches(legacyStatusSeed())
  }
  if (def.type === 'select' || def.type === 'multi_select') {
    const seed = defaultSelectSeed()[0]
    return def.select_options?.length === 1 && def.select_options[0].value === seed.value && def.select_options[0].label === seed.label
  }
  return false
}
