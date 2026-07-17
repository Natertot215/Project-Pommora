// View persistence CRUD — save / reorder / delete a SavedView in a Collection or Set sidecar's
// `views[]`. Read-modify-write through readSidecar/writeSidecar so the sidecar's foreign keys (top
// level AND on the views NOT being touched) ride through untouched. A freshly-minted default view
// arrives with the `view_default` sentinel id; saveView swaps it for a real `view_<ulid>` here
// (shared/ can't mint ids — see mintDefaultView). Errors flow as Result, never thrown.

import { pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import { DEFAULT_VIEW_ID, VIEW_ID_PREFIX, type SavedView } from '@shared/views'
import { ok, fail, type Result } from '@shared/result'
import { newId } from '../ids'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { nowIso } from './util'

/** Collection vs Set picks the sidecar kind + schema; both carry `views[]`. */
type ViewContainerKind = 'collection' | 'set'

function readViewSidecar(folder: string, kind: ViewContainerKind) {
  return kind === 'collection'
    ? readSidecar(folder, 'collection', pageCollectionSidecar)
    : readSidecar(folder, 'set', pageSetSidecar)
}

const viewsOf = (sidecar: { views?: SavedView[] }): SavedView[] =>
  Array.isArray(sidecar.views) ? sidecar.views : []

/** Upsert a view by id. A `view_default` sentinel id is swapped for a real `view_<ulid>` and the
 *  assigned id is returned. Other views + foreign keys ride through untouched. */
export async function saveView(
  folder: string,
  kind: ViewContainerKind,
  view: SavedView,
): Promise<Result<{ id: string }>> {
  const sidecar = await readViewSidecar(folder, kind)
  if (sidecar === null) return fail('not-found', 'Container sidecar not found.', kind)
  const id = view.id === DEFAULT_VIEW_ID ? `${VIEW_ID_PREFIX}${newId()}` : view.id
  const finalView: SavedView = { ...view, id }
  const views = [...viewsOf(sidecar)]
  const idx = views.findIndex((v) => v.id === id)
  if (idx >= 0) views[idx] = finalView
  else views.push(finalView)
  await writeSidecar(folder, kind, { ...sidecar, views, modified_at: nowIso() })
  return ok({ id })
}

/** Reorder views to match `orderedIds`; any views not named ride along at the end (defensive). */
export async function reorderViews(
  folder: string,
  kind: ViewContainerKind,
  orderedIds: string[],
): Promise<Result<null>> {
  const sidecar = await readViewSidecar(folder, kind)
  if (sidecar === null) return fail('not-found', 'Container sidecar not found.', kind)
  const views = viewsOf(sidecar)
  const byId = new Map(views.map((v) => [v.id, v]))
  const named = new Set(orderedIds)
  const reordered: SavedView[] = [
    ...orderedIds.map((id) => byId.get(id)).filter((v): v is SavedView => v !== undefined),
    ...views.filter((v) => !named.has(v.id)),
  ]
  await writeSidecar(folder, kind, { ...sidecar, views: reordered, modified_at: nowIso() })
  return ok(null)
}

/** Delete a view by id; refuses to remove the last one (a container always keeps ≥1 view). */
export async function deleteView(
  folder: string,
  kind: ViewContainerKind,
  viewId: string,
): Promise<Result<null>> {
  const sidecar = await readViewSidecar(folder, kind)
  if (sidecar === null) return fail('not-found', 'Container sidecar not found.', kind)
  const views = viewsOf(sidecar)
  if (views.length <= 1) return fail('operation-failed', 'Cannot delete the last view.', kind)
  const next = views.filter((v) => v.id !== viewId)
  if (next.length === views.length) return fail('not-found', 'View not found.', kind)
  await writeSidecar(folder, kind, { ...sidecar, views: next, modified_at: nowIso() })
  return ok(null)
}
