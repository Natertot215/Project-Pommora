// Option-level CRUD for Select / Multi-Select properties. setOptions is registry-only (add / recolor
// / reorder) and rides the mutateRegistry chain; the page-touching ops (rename / remove / clear) land
// in later tasks on the serializeSchemaOp chain. Errors flow as Result, never thrown.

import { readFile } from 'node:fs/promises'
import { mutateRegistry, readRegistry } from '../io/propertiesRegistry'
import { validateOptionValues } from '../properties/schema'
import { allCollectionFolders } from './assignment'
import { serializeSchemaOp } from './schemaChain'
import { SchemaTransaction } from '../io/schemaTransaction'
import { listMarkdownFiles } from '../io/walk'
import { replacePageValue, stripPageValue } from './pageValue'
import { ok, fail, type Result } from '@shared/result'
import { renameOption as renameInArray, type Option } from '@shared/optionModel'
import type { PropertyType } from '@shared/properties'

/** These ops edit `select_options`, so they apply to Select / Multi-Select only. A Status property's
 *  options live in `status_groups` (Phase 3's per-group ops); other types have none. Reject anything
 *  else up front — writing select_options onto a status def corrupts it and orphans its page values. */
function requireOptionType(type: PropertyType): Result<null> {
  return type === 'select' || type === 'multi_select'
    ? ok(null)
    : fail('invalid-property', 'Options can only be edited on Select or Multi-Select properties.')
}

/** Replace a Select / Multi-Select property's options wholesale (registry-only). Validates unique
 *  titles and writes the array verbatim — an emptied array stays empty (no re-seed; the >=1 floor is
 *  gone), unlike the create path's editProperty which seeds a default on an empty list. */
export function setOptions(root: string, propertyId: string, options: Option[]): Promise<Result<null>> {
  return mutateRegistry<Result<null>>(root, (registry) => {
    const current = registry.defs[propertyId]
    if (!current) return { result: fail('not-found', 'Property not found.') }
    const typeCheck = requireOptionType(current.type)
    if (!typeCheck.ok) return { result: typeCheck }
    const check = validateOptionValues(options)
    if (!check.ok) return { result: check }
    const next = { ...current, select_options: options }
    return { next: { ...registry, defs: { ...registry.defs, [propertyId]: next } }, result: ok(null) }
  })
}

/** Rewrite every assigning collection's pages through `rewrite` (null = the page doesn't hold it,
 *  skip), atomically via one SchemaTransaction. Shared by rename (replace) and remove/clear (strip). */
async function cascadePages(root: string, rewrite: (content: string) => string | null): Promise<void> {
  const tx = new SchemaTransaction()
  for (const folder of await allCollectionFolders(root)) {
    for (const file of await listMarkdownFiles(folder)) {
      let content: string
      try {
        content = await readFile(file, 'utf8')
      } catch {
        continue
      }
      const next = rewrite(content)
      if (next !== null) tx.stage(file, next)
    }
  }
  await tx.commit()
}

/** Rename an option (value=label → newTitle) and cascade the new value onto every page that held the
 *  old one. The registry edit rides mutateRegistry and validates unique titles — a collision fails
 *  before any page is touched; the page cascade rides this serializeSchemaOp. */
export function renameOption(root: string, propertyId: string, oldValue: string, newTitle: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const edit = await mutateRegistry<Result<PropertyType>>(root, (registry) => {
      const def = registry.defs[propertyId]
      if (!def) return { result: fail('not-found', 'Property not found.') }
      const typeCheck = requireOptionType(def.type)
      if (!typeCheck.ok) return { result: typeCheck }
      const nextOptions = renameInArray(def.select_options ?? [], oldValue, newTitle)
      const check = validateOptionValues(nextOptions)
      if (!check.ok) return { result: check }
      const next = { ...def, select_options: nextOptions }
      return { next: { ...registry, defs: { ...registry.defs, [propertyId]: next } }, result: ok(def.type) }
    })
    if (!edit.ok) return edit
    await cascadePages(root, (content) => replacePageValue(content, propertyId, oldValue, newTitle, edit.value))
    return ok(null)
  })
}

/** Clear an option's value from every page, keeping the option in the def. Page-only fan-out on the
 *  serializeSchemaOp chain; the registry is untouched. */
export function clearOption(root: string, propertyId: string, value: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const def = (await readRegistry(root)).defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const typeCheck = requireOptionType(def.type)
    if (!typeCheck.ok) return typeCheck
    await cascadePages(root, (content) => stripPageValue(content, propertyId, value, def.type))
    return ok(null)
  })
}

/** Remove an option: strip its value from every page, then drop it from the def. Pages first (as
 *  deleteProperty does) so a def edit failure never leaves the option gone with its values orphaned. */
export function removeOption(root: string, propertyId: string, value: string): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const def = (await readRegistry(root)).defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const typeCheck = requireOptionType(def.type)
    if (!typeCheck.ok) return typeCheck
    await cascadePages(root, (content) => stripPageValue(content, propertyId, value, def.type))
    return mutateRegistry<Result<null>>(root, (registry) => {
      const current = registry.defs[propertyId]
      if (!current) return { result: fail('not-found', 'Property not found.') }
      const nextOptions = (current.select_options ?? []).filter((o) => o.value !== value)
      return { next: { ...registry, defs: { ...registry.defs, [propertyId]: { ...current, select_options: nextOptions } } }, result: ok(null) }
    })
  })
}
