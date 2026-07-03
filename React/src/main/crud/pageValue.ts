// Per-value page primitives — strip or rewrite ONE option's value on a page, distinct from
// stripPageMember (which deletes a whole property key). The option editor's Remove/Clear fan-out
// and the rename cascade drive these. Type-switched over the on-disk value shapes: select = bare
// string, multi_select = string array, status = { $status }. Mirrors stripPageMember's read/merge.

import type { PropertyType } from '@shared/properties'
import { isPlainObject } from '@shared/propertyValue'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { nowIso } from './util'

/** The option `value` string(s) a property key holds, decoded by on-disk shape. */
function storedValues(raw: unknown, type: PropertyType): string[] {
  if (type === 'multi_select') return Array.isArray(raw) ? raw.filter((x): x is string => typeof x === 'string') : []
  if (type === 'status') return isPlainObject(raw) && typeof raw.$status === 'string' ? [raw.$status] : []
  return typeof raw === 'string' ? [raw] : [] // select
}

/** Re-encode a value set to its on-disk shape, or null to signal "delete the key" (nothing left). */
function encode(values: string[], type: PropertyType): unknown {
  if (values.length === 0) return null
  if (type === 'multi_select') return values
  if (type === 'status') return { $status: values[0] }
  return values[0] // select
}

/** Read the page's value set for a property, run `transform`, and write the result back. `transform`
 *  returns the next value set, or null to signal "the page doesn't hold the target — skip it" (the
 *  whole call then returns null). An emptied set deletes the key; otherwise it re-encodes in place. */
function editPageValue(
  content: string,
  propertyId: string,
  type: PropertyType,
  transform: (values: string[]) => string[] | null
): string | null {
  const raw = splitFrontmatter(content).properties
  const props = isPlainObject(raw) ? raw : {}
  const nextValues = transform(storedValues(props[propertyId], type))
  if (nextValues === null) return null
  const next = { ...props }
  const encoded = encode(nextValues, type)
  if (encoded === null) delete next[propertyId]
  else next[propertyId] = encoded
  const body = splitEnvelope(content).body
  return mergeFrontmatter(content, { properties: next, modified_at: nowIso() }, ['properties', 'modified_at'], body)
}

/** Remove one option's value from a page. Returns null if the page didn't hold it. */
export function stripPageValue(content: string, propertyId: string, value: string, type: PropertyType): string | null {
  return editPageValue(content, propertyId, type, (values) => (values.includes(value) ? values.filter((v) => v !== value) : null))
}

/** Rename cascade: swap oldValue → newValue in place. Returns null if the page didn't hold it. */
export function replacePageValue(
  content: string,
  propertyId: string,
  oldValue: string,
  newValue: string,
  type: PropertyType
): string | null {
  return editPageValue(content, propertyId, type, (values) =>
    values.includes(oldValue) ? values.map((v) => (v === oldValue ? newValue : v)) : null
  )
}
