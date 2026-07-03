// Option-level CRUD for Select / Multi-Select properties. setOptions is registry-only (add / recolor
// / reorder) and rides the mutateRegistry chain; the page-touching ops (rename / remove / clear) land
// in later tasks on the serializeSchemaOp chain. Errors flow as Result, never thrown.

import { mutateRegistry } from '../io/propertiesRegistry'
import { validateOptionValues } from '../properties/schema'
import { ok, fail, type Result } from '@shared/result'
import type { Option } from '@shared/optionModel'

/** Replace a Select / Multi-Select property's options wholesale (registry-only). Validates unique
 *  titles and writes the array verbatim — an emptied array stays empty (no re-seed; the >=1 floor is
 *  gone), unlike the create path's editProperty which seeds a default on an empty list. */
export function setOptions(root: string, propertyId: string, options: Option[]): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    const current = registry.defs[propertyId]
    if (!current) return { result: fail('not-found', 'Property not found.') }
    const check = validateOptionValues(options)
    if (!check.ok) return { result: check }
    const next = { ...current, select_options: options }
    return { next: { ...registry, defs: { ...registry.defs, [propertyId]: next } }, result: ok(null) }
  })
}
