// Pure transforms over a PropertyDefinition[] — the read-time normalization, per-def
// parsing, and validation Swift spread across PropertyDefinition.init(from:) (legacy
// decode), the `droppingUserRelations` Array extension, and PropertyDefinitionValidator.
// No I/O. The single typed gate between a raw sidecar array and a usable schema.

import {
  propertyDefinition,
  isReservedPropertyId,
  type PropertyDefinition
} from '@shared/properties'
import { fail, ok, type Result } from '@shared/result'

/** Fold the legacy shapes Swift migrated on decode: the retired `.date` type → `.datetime`
 *  (date-only display is preserved elsewhere by the time-format default), and the legacy
 *  `relation_scope` key → `relation_target` (new key wins; legacy dropped so it's never
 *  re-emitted). Returns a new object. */
export function normalizeDefinition(def: PropertyDefinition): PropertyDefinition {
  const next: PropertyDefinition = { ...def }
  if (next.type === 'date') next.type = 'datetime'
  const legacy = (next as Record<string, unknown>).relation_scope
  if (legacy !== undefined) {
    if (next.relation_target === undefined) {
      next.relation_target = legacy as PropertyDefinition['relation_target']
    }
    delete (next as Record<string, unknown>).relation_scope
  }
  return next
}

/** Parse + normalize a raw `property_definitions` array, dropping any entry that fails
 *  to parse (resilient — one malformed def never sinks the whole schema, matching
 *  Swift's per-def tolerance). Non-array input → []. */
export function parseDefinitions(raw: unknown): PropertyDefinition[] {
  if (!Array.isArray(raw)) return []
  const out: PropertyDefinition[] = []
  for (const entry of raw) {
    const parsed = propertyDefinition.safeParse(entry)
    if (parsed.success) out.push(normalizeDefinition(parsed.data))
  }
  return out
}

/** Drop stored user `.relation` defs (tiers are synthesized at runtime) EXCEPT reserved
 *  `_tier1/2/3` entries, which persist a user's reverse-name/icon override. Mirrors
 *  Swift's `Array<PropertyDefinition>.droppingUserRelations()`. */
export function droppingUserRelations(defs: PropertyDefinition[]): PropertyDefinition[] {
  return defs.filter((d) => d.type !== 'relation' || isReservedPropertyId(d.id))
}

// MARK: - Validation (mirrors Swift PropertyDefinitionValidator)

/** A property name in the context of a schema: non-empty after trim + unique
 *  case-insensitively, excluding the def identified by `excludeId` (for rename). */
export function validateName(
  name: string,
  existing: PropertyDefinition[],
  excludeId?: string
): Result<null> {
  const trimmed = name.trim()
  if (!trimmed) return fail('invalid-property', 'A property name cannot be empty.')
  const lower = trimmed.toLowerCase()
  const clash = existing.some((d) => d.id !== excludeId && d.name.trim().toLowerCase() === lower)
  if (clash) return fail('invalid-property', `A property named "${trimmed}" already exists.`)
  return ok(null)
}

/** Full add-time validation: name rules + reserved-id block + unique id + select /
 *  multiSelect option constraints. Mirrors `PropertyDefinitionValidator.validate`. */
export function validateDefinition(
  def: PropertyDefinition,
  existing: PropertyDefinition[]
): Result<null> {
  const nameCheck = validateName(def.name, existing, def.id)
  if (!nameCheck.ok) return nameCheck
  if (isReservedPropertyId(def.id)) return fail('invalid-property', 'That property id is reserved.')
  if (existing.some((d) => d.id === def.id)) {
    return fail('invalid-property', 'That property id already exists.')
  }
  if (def.type === 'select' || def.type === 'multi_select') {
    const options = def.select_options ?? []
    if (options.length === 0) {
      return fail('invalid-property', 'A select property needs at least one option.')
    }
    const values = options.map((o) => o.value)
    if (new Set(values).size < values.length) {
      return fail('invalid-property', 'Select option values must be unique.')
    }
  }
  return ok(null)
}
