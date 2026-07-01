import { mutateRegistry } from '../io/propertiesRegistry'
import { validateDefinition, validateName } from '../properties/schema'
import { mintPropertyId } from '../ids'
import { defaultStatusSeed, defaultSelectSeed, type PropertyDefinition } from '@shared/properties'
import { ok, fail, type Result } from '@shared/result'

function seeded(def: PropertyDefinition): PropertyDefinition {
  let d = def
  if (d.type === 'status' && d.status_groups === undefined) d = { ...d, status_groups: defaultStatusSeed() }
  if ((d.type === 'select' || d.type === 'multi_select') && (d.select_options?.length ?? 0) === 0) {
    d = { ...d, select_options: defaultSelectSeed() }
  }
  return d
}

/** Mint + persist a nexus-wide definition. Name uniqueness is validated against the WHOLE registry. */
export function createProperty(root: string, def: PropertyDefinition): Promise<Result<{ id: string }>> {
  return mutateRegistry<Result<{ id: string }>>(root, (registry) => {
    const candidate = seeded({ ...def, id: def.id || mintPropertyId() })
    const v = validateDefinition(candidate, Object.values(registry))
    if (!v.ok) return { result: v }
    return { next: { ...registry, [candidate.id]: candidate }, result: ok({ id: candidate.id }) }
  })
}

/** Edit the global definition in place — every assigning Collection sees the change on next read. */
export function editProperty(
  root: string,
  propertyId: string,
  changes: Partial<PropertyDefinition>
): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    const current = registry[propertyId]
    if (!current) return { result: fail('not-found', 'Property not found.') }
    const next = seeded({ ...current, ...changes, id: propertyId })
    if (next.name !== current.name) {
      const v = validateName(next.name, Object.values(registry), propertyId)
      if (!v.ok) return { result: v }
    }
    return { next: { ...registry, [propertyId]: next }, result: ok(null) }
  })
}

/** Bare registry delete — no value scrub or assignment cleanup; `deleteProperty` wraps this. */
export function removeFromRegistry(root: string, propertyId: string): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    if (!registry[propertyId]) return { result: fail('not-found', 'Property not found.') }
    const next = { ...registry }
    delete next[propertyId]
    return { next, result: ok(null) }
  })
}
