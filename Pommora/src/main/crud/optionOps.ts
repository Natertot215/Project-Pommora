// Option-level CRUD for Select / Multi-Select properties. setOptions is registry-only (add / recolor
// / reorder) and rides the mutateRegistry chain; the page-touching ops (rename / remove / clear) ride
// the serializeSchemaOp chain, cascading each edit across every assigning collection's pages. Errors
// flow as Result, never thrown.

import { mutateRegistry, readRegistry } from '../io/propertiesRegistry'
import { validateOptionValues } from '../properties/schema'
import { allCollectionFolders } from './assignment'
import { serializeSchemaOp } from './schemaChain'
import { rewritePageSerialized } from '../io/fileLock'
import { listMarkdownFiles } from '../io/walk'
import { replacePageValue, stripPageValue } from './pageValue'
import { ok, fail, type Result } from '@shared/result'
import {
  renameOption as renameInArray,
  renameStatusOption as renameStatusInArray,
  type Option,
} from '@shared/optionModel'
import type { PropertyType, StatusGroup } from '@shared/properties'

/** These ops edit `select_options`, so they apply to Select / Multi-Select only. A Status property's
 *  options live in `status_groups` (Phase 3's per-group ops); other types have none. Reject anything
 *  else up front — writing select_options onto a status def corrupts it and orphans its page values. */
function requireOptionType(type: PropertyType): Result<null> {
  return type === 'select' || type === 'multi_select'
    ? ok(null)
    : fail('invalid-property', 'Options can only be edited on Select or Multi-Select properties.')
}

/** Replace a Select / Multi-Select property's options wholesale. Validates unique titles and writes
 *  the array verbatim — an emptied array stays empty (no re-seed; the >=1 floor is gone), unlike the
 *  create path's editProperty which seeds a default on an empty list. Rides serializeSchemaOp (like
 *  the page-touching ops) so it can't land inside a concurrent renameOption's cascade and desync the
 *  registry from pages; the actual registry write still goes through mutateRegistry inside. */
export function setOptions(
  root: string,
  propertyId: string,
  options: Option[],
): Promise<Result<null>> {
  return serializeSchemaOp(() =>
    mutateRegistry<Result<null>>(root, (registry) => {
      const current = registry.defs[propertyId]
      if (!current) return { result: fail('not-found', 'Property not found.') }
      const typeCheck = requireOptionType(current.type)
      if (!typeCheck.ok) return { result: typeCheck }
      const check = validateOptionValues(options)
      if (!check.ok) return { result: check }
      const next = { ...current, select_options: options }
      return {
        next: { ...registry, defs: { ...registry.defs, [propertyId]: next } },
        result: ok(null),
      }
    }),
  )
}

/** Replace a Status property's `status_groups` wholesale — the registry-only path behind add / recolor
 *  / reorder (the Status analog of setOptions). Validates unique option values PROPERTY-WIDE (a page's
 *  `$status` references the value across all groups), then writes verbatim. Rides serializeSchemaOp so
 *  it can't interleave with a concurrent page cascade. */
export function setStatusGroups(
  root: string,
  propertyId: string,
  groups: StatusGroup[],
): Promise<Result<null>> {
  return serializeSchemaOp(() =>
    mutateRegistry<Result<null>>(root, (registry) => {
      const current = registry.defs[propertyId]
      if (!current) return { result: fail('not-found', 'Property not found.') }
      if (current.type !== 'status') {
        return {
          result: fail('invalid-property', 'Status groups can only be set on a Status property.'),
        }
      }
      const check = validateOptionValues(groups.flatMap((g) => g.options))
      if (!check.ok) return { result: check }
      const next = { ...current, status_groups: groups }
      return {
        next: { ...registry, defs: { ...registry.defs, [propertyId]: next } },
        result: ok(null),
      }
    }),
  )
}

/** These ops edit a Status property's `status_groups`; reject anything else up front. */
function requireStatusType(type: PropertyType): Result<null> {
  return type === 'status'
    ? ok(null)
    : fail('invalid-property', 'Status options can only be edited on a Status property.')
}

/** Rename a status option (value=title, like Select's renameOption) and cascade the new value onto every
 *  assigning page's `$status`. Validates unique values property-wide before any page is touched. */
export function renameStatusOption(
  root: string,
  propertyId: string,
  oldValue: string,
  newTitle: string,
): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const edit = await mutateRegistry<Result<null>>(root, (registry) => {
      const def = registry.defs[propertyId]
      if (!def) return { result: fail('not-found', 'Property not found.') }
      const typeCheck = requireStatusType(def.type)
      if (!typeCheck.ok) return { result: typeCheck }
      const nextGroups = renameStatusInArray(def.status_groups ?? [], oldValue, newTitle)
      const check = validateOptionValues(nextGroups.flatMap((g) => g.options))
      if (!check.ok) return { result: check }
      const next = { ...def, status_groups: nextGroups }
      return {
        next: { ...registry, defs: { ...registry.defs, [propertyId]: next } },
        result: ok(null),
      }
    })
    if (!edit.ok) return edit
    await cascadePages(root, (content) =>
      replacePageValue(content, propertyId, oldValue, newTitle, 'status'),
    )
    return ok(null)
  })
}

/** Clear a status option's value from every page, keeping the option in its group. Registry untouched. */
export function clearStatusOption(
  root: string,
  propertyId: string,
  value: string,
): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const def = (await readRegistry(root)).defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const typeCheck = requireStatusType(def.type)
    if (!typeCheck.ok) return typeCheck
    await cascadePages(root, (content) => stripPageValue(content, propertyId, value, 'status'))
    return ok(null)
  })
}

/** Remove a status option: strip its value from every page, then drop it from its group. Pages first,
 *  so a def-edit failure never leaves the option gone with its page values orphaned. */
export function removeStatusOption(
  root: string,
  propertyId: string,
  value: string,
): Promise<Result<null>> {
  return serializeSchemaOp(async () => {
    const def = (await readRegistry(root)).defs[propertyId]
    if (!def) return fail('not-found', 'Property not found.')
    const typeCheck = requireStatusType(def.type)
    if (!typeCheck.ok) return typeCheck
    await cascadePages(root, (content) => stripPageValue(content, propertyId, value, 'status'))
    return mutateRegistry<Result<null>>(root, (registry) => {
      const current = registry.defs[propertyId]
      if (!current) return { result: fail('not-found', 'Property not found.') }
      const nextGroups = (current.status_groups ?? []).map((g) => ({
        ...g,
        options: g.options.filter((o) => o.value !== value),
      }))
      return {
        next: {
          ...registry,
          defs: { ...registry.defs, [propertyId]: { ...current, status_groups: nextGroups } },
        },
        result: ok(null),
      }
    })
  })
}

/** Rewrite every assigning collection's pages through `rewrite` (null = the page doesn't hold it,
 *  skip). Each page's read-modify-write runs under its file lock — the SAME lock the cell-write path
 *  takes — so a cascade and a concurrent cell edit on one page can't clobber each other (F1). Per
 *  file, not all-or-nothing across pages: a partly-applied rename/strip is recoverable by re-running
 *  and each page stays individually valid. Shared by rename (replace) and remove/clear (strip). */
async function cascadePages(
  root: string,
  rewrite: (content: string) => string | null,
): Promise<void> {
  for (const folder of await allCollectionFolders(root)) {
    for (const file of await listMarkdownFiles(folder)) {
      await rewritePageSerialized(file, rewrite)
    }
  }
}

/** Rename an option (value=label → newTitle) and cascade the new value onto every page that held the
 *  old one. The registry edit rides mutateRegistry and validates unique titles — a collision fails
 *  before any page is touched; the page cascade rides this serializeSchemaOp. */
export function renameOption(
  root: string,
  propertyId: string,
  oldValue: string,
  newTitle: string,
): Promise<Result<null>> {
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
      return {
        next: { ...registry, defs: { ...registry.defs, [propertyId]: next } },
        result: ok(def.type),
      }
    })
    if (!edit.ok) return edit
    await cascadePages(root, (content) =>
      replacePageValue(content, propertyId, oldValue, newTitle, edit.value),
    )
    return ok(null)
  })
}

/** Clear an option's value from every page, keeping the option in the def. Page-only fan-out on the
 *  serializeSchemaOp chain; the registry is untouched. */
export function clearOption(
  root: string,
  propertyId: string,
  value: string,
): Promise<Result<null>> {
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
export function removeOption(
  root: string,
  propertyId: string,
  value: string,
): Promise<Result<null>> {
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
      return {
        next: {
          ...registry,
          defs: { ...registry.defs, [propertyId]: { ...current, select_options: nextOptions } },
        },
        result: ok(null),
      }
    })
  })
}
