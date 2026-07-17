import { mutateRegistry } from '../io/propertiesRegistry'
import { validateDefinition, validateName } from '../properties/schema'
import { mintPropertyId } from '../ids'
import { defaultStatusSeed, defaultSelectSeed, type PropertyDefinition } from '@shared/properties'
import { ok, fail, type Result } from '@shared/result'

// Seed defaults for a def that has NONE (the field is undefined — a fresh create, or a type-change
// into select/status). An EMPTY array is a deliberate state (the user deleted every option), never
// re-seeded — else emptying a select's options and then any unrelated edit resurrects the seed.
function seeded(def: PropertyDefinition): PropertyDefinition {
  let d = def
  if (d.type === 'status' && d.status_groups === undefined)
    d = { ...d, status_groups: defaultStatusSeed() }
  if ((d.type === 'select' || d.type === 'multi_select') && d.select_options === undefined) {
    d = { ...d, select_options: defaultSelectSeed() }
  }
  return d
}

/** Mint + persist a nexus-wide definition, appending its id to the nexus order (A-9).
 *  Duplicate names are allowed — the flat D-3 policy; ids keep twins mechanically safe. */
export function createProperty(
  root: string,
  def: PropertyDefinition,
): Promise<Result<{ id: string }>> {
  return mutateRegistry<Result<{ id: string }>>(root, (registry) => {
    const candidate = seeded({ ...def, id: def.id || mintPropertyId() })
    const v = validateDefinition(candidate, Object.values(registry.defs), { unique: false })
    if (!v.ok) return { result: v }
    return {
      next: {
        order: [...registry.order.filter((id) => id !== candidate.id), candidate.id],
        defs: { ...registry.defs, [candidate.id]: candidate },
      },
      result: ok({ id: candidate.id }),
    }
  })
}

/** Edit the global definition in place — every assigning Collection sees the change on next read. */
export function editProperty(
  root: string,
  propertyId: string,
  changes: Partial<PropertyDefinition>,
): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    const current = registry.defs[propertyId]
    if (!current) return { result: fail('not-found', 'Property not found.') }
    const next = seeded({ ...current, ...changes, id: propertyId })
    if (next.name !== current.name) {
      const v = validateName(next.name, Object.values(registry.defs), propertyId, { unique: false })
      if (!v.ok) return { result: v }
    }
    return {
      next: { ...registry, defs: { ...registry.defs, [propertyId]: next } },
      result: ok(null),
    }
  })
}

/** Bare registry delete — no value scrub or assignment cleanup; `deleteProperty` wraps this. */
export function removeFromRegistry(root: string, propertyId: string): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    if (!registry.defs[propertyId]) return { result: fail('not-found', 'Property not found.') }
    const defs = { ...registry.defs }
    delete defs[propertyId]
    return {
      next: { order: registry.order.filter((id) => id !== propertyId), defs },
      result: ok(null),
    }
  })
}

/** Move propertyId to toIndex in the nexus-wide cosmetic order (C-1). Clamped; unknown id fails. */
export function reorderRegistry(
  root: string,
  propertyId: string,
  toIndex: number,
): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    if (!(propertyId in registry.defs)) return { result: fail('not-found', 'Property not found.') }
    const order = registry.order.filter((id) => id !== propertyId)
    order.splice(Math.max(0, Math.min(toIndex, order.length)), 0, propertyId)
    return { next: { ...registry, order }, result: ok(null) }
  })
}
