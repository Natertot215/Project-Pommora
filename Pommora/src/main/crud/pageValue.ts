// Per-value page primitives — strip or rewrite ONE option's value on a page, distinct from
// stripPageMember (which deletes a whole property key). The option editor's Remove/Clear fan-out
// and the rename cascade drive these. Type-switched over the on-disk value shapes: select = bare
// string, multi_select = string array, status = { $status }. Mirrors stripPageMember's read/merge.
//
// Multi arrays are edited IN PLACE (filter/map on the raw array), never decode-to-strings→re-encode:
// a page may carry foreign / non-string elements (hand- or agent-authored, Pommora's whole pitch),
// and an op must touch only its target, preserving everything else it never named.

import type { PropertyType } from '@shared/properties'
import { isPlainObject } from '@shared/propertyValue'
import { splitFrontmatter } from '../readNexus'
import { splitEnvelope, mergeFrontmatter } from '../io/pageFile'
import { nowIso } from './util'

type ValueEdit = { op: 'strip' } | { op: 'replace'; to: string }

/** Sentinel: the page's value doesn't hold the target, so the whole call is a no-op (returns null). */
const SKIP = Symbol('skip')

/** Rewrite the raw stored value so `target` is stripped or replaced, preserving foreign content.
 *  Returns SKIP when the value doesn't hold `target`; otherwise the next value (null = delete key). */
function rewriteRaw(
  raw: unknown,
  type: PropertyType,
  target: string,
  edit: ValueEdit,
): unknown | typeof SKIP {
  if (type === 'multi_select') {
    if (!Array.isArray(raw) || !raw.includes(target)) return SKIP
    if (edit.op === 'replace') {
      // Renaming target into a DIFFERENT value the array already holds would duplicate it — merge
      // instead by dropping the target (its new value is already present). The `to !== target` guard
      // keeps a no-op rename from deleting the value. Foreign elements are otherwise untouched.
      if (edit.to !== target && raw.includes(edit.to)) return raw.filter((el) => el !== target)
      return raw.map((el) => (el === target ? edit.to : el))
    }
    const filtered = raw.filter((el) => el !== target)
    return filtered.length ? filtered : null
  }
  if (type === 'status') {
    if (!isPlainObject(raw) || raw.$status !== target) return SKIP
    return edit.op === 'replace' ? { $status: edit.to } : null
  }
  // select
  if (raw !== target) return SKIP
  return edit.op === 'replace' ? edit.to : null
}

function applyEdit(
  content: string,
  propertyId: string,
  type: PropertyType,
  target: string,
  edit: ValueEdit,
): string | null {
  const rawProps = splitFrontmatter(content).properties
  const props = isPlainObject(rawProps) ? rawProps : {}
  const nextValue = rewriteRaw(props[propertyId], type, target, edit)
  if (nextValue === SKIP) return null
  const next = { ...props }
  if (nextValue === null) delete next[propertyId]
  else next[propertyId] = nextValue
  const body = splitEnvelope(content).body
  return mergeFrontmatter(
    content,
    { properties: next, modified_at: nowIso() },
    ['properties', 'modified_at'],
    body,
  )
}

/** Remove one option's value from a page. Returns null if the page didn't hold it. */
export function stripPageValue(
  content: string,
  propertyId: string,
  value: string,
  type: PropertyType,
): string | null {
  return applyEdit(content, propertyId, type, value, { op: 'strip' })
}

/** Rename cascade: swap oldValue → newValue in place. Returns null if the page didn't hold it. */
export function replacePageValue(
  content: string,
  propertyId: string,
  oldValue: string,
  newValue: string,
  type: PropertyType,
): string | null {
  return applyEdit(content, propertyId, type, oldValue, { op: 'replace', to: newValue })
}
