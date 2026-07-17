// Pure transforms over a PropertyDefinition[] — the per-def parsing + validation Swift spread
// across PropertyDefinition.init(from:), the user-context-dropping Array extension, and
// PropertyDefinitionValidator. No I/O. The single typed gate between a raw sidecar array and a
// usable schema.

import {
  propertyDefinition,
  isReservedPropertyId,
  type PropertyDefinition,
} from '@shared/properties'
import { fail, ok, type Result } from '@shared/result'

/** Parse a raw `property_definitions` array, dropping any entry that fails to parse (resilient —
 *  one malformed def never sinks the whole schema, matching Swift's per-def tolerance). A retired
 *  type (the removed `date`, or a user `relation`/`context`) simply fails the enum and is dropped.
 *  Non-array input → []. */
export function parseDefinitions(raw: unknown): PropertyDefinition[] {
  if (!Array.isArray(raw)) return []
  const out: PropertyDefinition[] = []
  for (const entry of raw) {
    const parsed = propertyDefinition.safeParse(entry)
    if (parsed.success) out.push(parsed.data)
  }
  return out
}

/** Drop stored user `.context` defs (the context tiers are synthesized at runtime) EXCEPT reserved
 *  `_tier1/2/3` entries, which persist a user's reverse-name/icon override. Mirrors the Swift
 *  array extension that drops stored user contexts. */
export function droppingUserContexts(defs: PropertyDefinition[]): PropertyDefinition[] {
  return defs.filter((d) => d.type !== 'context' || isReservedPropertyId(d.id))
}

// MARK: - Validation (mirrors Swift PropertyDefinitionValidator)

/** A property name in the context of a schema: non-empty after trim + unique
 *  case-insensitively, excluding the def identified by `excludeId` (for rename).
 *  `unique: false` skips the clash check — the registry paths allow twin names (D-3);
 *  Agenda's callers pass nothing, so uniqueness holds there. */
export function validateName(
  name: string,
  existing: PropertyDefinition[],
  excludeId?: string,
  opts: { unique?: boolean } = {},
): Result<null> {
  const trimmed = name.trim()
  if (!trimmed) return fail('invalid-property', 'A property name cannot be empty.')
  if (opts.unique !== false) {
    const lower = trimmed.toLowerCase()
    const clash = existing.some((d) => d.id !== excludeId && d.name.trim().toLowerCase() === lower)
    if (clash) return fail('invalid-property', `A property named "${trimmed}" already exists.`)
  }
  return ok(null)
}

/** Full add-time validation: name rules + reserved-id block + unique id + select /
 *  multiSelect option constraints. Mirrors `PropertyDefinitionValidator.validate`. */
export function validateDefinition(
  def: PropertyDefinition,
  existing: PropertyDefinition[],
  opts?: { unique?: boolean },
): Result<null> {
  const nameCheck = validateName(def.name, existing, def.id, opts)
  if (!nameCheck.ok) return nameCheck
  if (isReservedPropertyId(def.id)) return fail('invalid-property', 'That property id is reserved.')
  if (existing.some((d) => d.id === def.id)) {
    return fail('invalid-property', 'That property id already exists.')
  }
  if (def.type === 'select' || def.type === 'multi_select') {
    const check = validateOptionValues(def.select_options ?? [])
    if (!check.ok) return check
  }
  return ok(null)
}

/** Option titles (their `value`s) must be unique within a property. No minimum count — a Select may
 *  hold zero options. Enforced at create AND on every option edit (add / rename / reorder). */
export function validateOptionValues(options: { value: string }[]): Result<null> {
  const values = options.map((o) => o.value)
  if (new Set(values).size < values.length) {
    return fail('invalid-property', 'Option titles must be unique.')
  }
  return ok(null)
}
