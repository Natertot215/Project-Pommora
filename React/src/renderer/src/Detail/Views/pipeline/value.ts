// Field-value extraction for the view pipeline. Two functions, two AXES that must NOT be
// confused (this is the trap the plan calls out):
//   - declaredType: the column's SCHEMA type — a snake_case PropertyType (e.g. 'multi_select',
//     'last_edited_time') plus the synthetic 'title'/'tier' sentinels for reserved columns. This
//     is what sort/group/filter switch on to choose type-aware behavior.
//   - resolveFieldValue: the row's VALUE as a PropertyValue, whose `.kind` is camelCase (e.g.
//     'multiSelect', 'lastEditedTime'). The shape-parse is trusted for the unambiguous kinds, but
//     the three plain-string kinds (url/select/datetime — identical on disk) are re-tagged to the
//     column's DECLARED type: a url column always reads url, a select column select. The shape
//     guess only decides when there's no schema (the raw codec). This is the fix for the type-erased
//     format's shape ambiguity — without it a Renamed link (`[alias](url)`) read back as a select pill.
// Pure: no fs, no React.

import type { ViewRow } from '@shared/types'
import type { PageFrontmatter } from '@shared/schemas'
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

/** The plain-string PropertyValue kinds — indistinguishable on disk (a URL, a select option, and a
 *  bare date are all just strings), so the codec's shape guess for these is overridden by the column's
 *  declared type. Every other kind (arrays / tagged objects / bool / number) is unambiguous. */
const STRING_KIND_FOR_TYPE: Partial<Record<PropertyType, 'url' | 'select' | 'datetime'>> = {
  url: 'url',
  select: 'select',
  datetime: 'datetime'
}

/** Re-tag a shape-guessed plain-string value to what its column actually declares (a url column reads
 *  url, a select column select). A no-op for every unambiguous kind and for reserved/typeless columns.
 *  The value string is unchanged — only the `.kind` tag. */
function coerceToDeclaredType(v: PropertyValue, dt: PropertyType | 'title' | 'tier' | undefined): PropertyValue {
  const want = dt && dt !== 'title' && dt !== 'tier' ? STRING_KIND_FOR_TYPE[dt] : undefined
  if (want && (v.kind === 'url' || v.kind === 'select' || v.kind === 'datetime') && v.kind !== want) {
    return { kind: want, value: v.value }
  }
  return v
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
 *  fields; user `prop_*` columns route through the on-disk codec (`parsePropertyValue`). The shape
 *  parse is cached (the measured grouped-view hot spot); the declared-type coercion rides on top,
 *  fresh + O(1), so the cache stays schema-free and a schema type-change reflects at once. Absent OR
 *  malformed ⇒ `{ kind: 'null' }` — a single bad cell never poisons a view. */
export function resolveFieldValue(row: ViewRow, propertyId: string, schema: PropertyDefinition[]): PropertyValue {
  // `_title` bypasses the cache — it reads `row.title`, which a rename changes without touching
  // the frontmatter object the cache is keyed on.
  if (propertyId === RESERVED_PROPERTY_ID.title) return { kind: 'select', value: row.title }
  let m = resolvedByFm.get(row.frontmatter)
  if (!m) {
    m = new Map()
    resolvedByFm.set(row.frontmatter, m)
  }
  let v = m.get(propertyId)
  if (!v) {
    v = computeFieldValue(row.frontmatter, propertyId)
    m.set(propertyId, v)
  }
  return coerceToDeclaredType(v, declaredType(propertyId, schema))
}

// MEMOIZED per frontmatter object: the grouped pipeline resolves every row per run and every
// Cell resolves the same value again per render — the shape-inference parse was the measured
// grouped-view hot spot. A value write swaps the page's frontmatter identity (loadValues / the
// optimistic patch), so entries self-expire; resolved values are shared and treated immutable.
const resolvedByFm = new WeakMap<PageFrontmatter, Map<string, PropertyValue>>()

function computeFieldValue(fm: PageFrontmatter, propertyId: string): PropertyValue {
  switch (propertyId) {
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
