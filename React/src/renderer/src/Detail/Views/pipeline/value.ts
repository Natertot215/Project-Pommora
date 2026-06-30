// Field-value extraction for the view pipeline. Two functions, two AXES that must NOT be
// confused (this is the trap the plan calls out):
//   - declaredType: the column's SCHEMA type — a snake_case PropertyType (e.g. 'multi_select',
//     'last_edited_time') plus the synthetic 'title'/'tier' sentinels for reserved columns. This
//     is what sort/group/filter switch on to choose type-aware behavior.
//   - resolveFieldValue: the row's VALUE as a PropertyValue, whose `.kind` is camelCase (e.g.
//     'multiSelect', 'lastEditedTime'). The codec's shape-inferred kind is TRUSTED, never
//     re-coerced against the declared type — a shape mismatch just sorts/groups as "unknown",
//     matching Swift.
// Pure: no fs, no React.

import type { ViewRow } from '@shared/types'
import { type PropertyDefinition, type PropertyType, RESERVED_PROPERTY_ID } from '@shared/properties'
import { type PropertyValue, parsePropertyValue } from '@shared/propertyValue'

/** The declared type a column sorts/groups/filters by. Reserved columns map to a PropertyType or
 *  a synthetic sentinel: `_title`→'title', `_tier1/2/3`→'tier', `_modified_at`→'last_edited_time'
 *  (Swift treats it as a date for both filter and sort). `_status`/`_id`/`_created_at`/`_type`
 *  carry no special branch — they resolve through the schema (undefined when absent). */
export function declaredType(
  propertyId: string,
  schema: PropertyDefinition[]
): PropertyType | 'title' | 'tier' | undefined {
  switch (propertyId) {
    case RESERVED_PROPERTY_ID.title:
      return 'title'
    case RESERVED_PROPERTY_ID.modifiedAt:
      return 'last_edited_time'
    case RESERVED_PROPERTY_ID.tier1:
    case RESERVED_PROPERTY_ID.tier2:
    case RESERVED_PROPERTY_ID.tier3:
      return 'tier'
    default:
      return schema.find((d) => d.id === propertyId)?.type
  }
}

/** Reserved tier id → its bare frontmatter array field, stated once so the three tier cases
 *  share one value-access expression (the field names are literal-typed, so `fm[field]` stays
 *  type-checked as `string[] | undefined`). */
type TierField = 'tier1' | 'tier2' | 'tier3'
const TIER_FIELD: Record<string, TierField> = {
  [RESERVED_PROPERTY_ID.tier1]: 'tier1',
  [RESERVED_PROPERTY_ID.tier2]: 'tier2',
  [RESERVED_PROPERTY_ID.tier3]: 'tier3'
}

/** The row's value for a column, as a PropertyValue. Reserved columns read intrinsic/frontmatter
 *  fields; user `prop_*` columns route through the on-disk codec (`parsePropertyValue`), whose
 *  classification is trusted as-is. Absent OR malformed ⇒ `{ kind: 'null' }` — a single bad cell
 *  never poisons a view. (No `schema` param: the value comes from the data, not the schema —
 *  the declared type is `declaredType`'s job.) */
export function resolveFieldValue(row: ViewRow, propertyId: string): PropertyValue {
  const fm = row.frontmatter
  switch (propertyId) {
    case RESERVED_PROPERTY_ID.title:
      return { kind: 'select', value: row.title }
    case RESERVED_PROPERTY_ID.modifiedAt:
      return typeof fm.modified_at === 'string' && fm.modified_at
        ? { kind: 'datetime', value: fm.modified_at }
        : { kind: 'null' }
    case RESERVED_PROPERTY_ID.tier1:
    case RESERVED_PROPERTY_ID.tier2:
    case RESERVED_PROPERTY_ID.tier3:
      return { kind: 'context', value: fm[TIER_FIELD[propertyId]] ?? [] }
    default:
      try {
        return parsePropertyValue(fm.properties?.[propertyId])
      } catch {
        return { kind: 'null' }
      }
  }
}

/** The `_modified_at` SORT/FILTER stamp: modified_at, falling back to created_at (Swift
 *  modifiedStamp) so a never-modified page orders by its creation time. Deliberately distinct from
 *  `resolveFieldValue('_modified_at')` (the display value, modified_at only, no fallback). Null
 *  when neither is present. */
export function modifiedStampString(row: ViewRow): string | null {
  const fm = row.frontmatter
  return (
    (typeof fm.modified_at === 'string' && fm.modified_at) ||
    (typeof fm.created_at === 'string' && fm.created_at) ||
    null
  )
}
