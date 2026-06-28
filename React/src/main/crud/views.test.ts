import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, writeFile, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import type { SavedView } from '@shared/views'
import { saveView, reorderViews, deleteView } from './views'

let folder: string
beforeEach(async () => {
  folder = await mkdtemp(join(tmpdir(), 'pom-views-crud-'))
})
afterEach(async () => {
  await rm(folder, { recursive: true, force: true })
})

const view = (over: Partial<SavedView> & { id: string }): SavedView => ({
  name: 'V',
  type: 'table',
  property_order: [],
  hidden_properties: [],
  ...over
})

// Write a collection sidecar directly (not via writeSidecar) so foreign keys are controllable.
async function writeCollectionSidecar(obj: Record<string, unknown>): Promise<void> {
  await writeFile(join(folder, '_pagecollection.json'), JSON.stringify({ id: 'col', ...obj }))
}
async function readRaw(file: string): Promise<Record<string, unknown>> {
  return JSON.parse(await readFile(join(folder, file), 'utf8'))
}

describe('view persistence CRUD', () => {
  it('upserts a view and round-trips it', async () => {
    await writeCollectionSidecar({ views: [] })
    const r = await saveView(folder, 'collection', view({ id: 'view_1', name: 'Table' }))
    expect(r.ok).toBe(true)
    const sidecar = await readRaw('_pagecollection.json')
    expect((sidecar.views as SavedView[]).map((v) => v.id)).toEqual(['view_1'])
  })

  it('swaps the view_default sentinel for a real view_<ulid> on save', async () => {
    await writeCollectionSidecar({ views: [] })
    const r = await saveView(folder, 'collection', view({ id: 'view_default', name: 'Table' }))
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.id).not.toBe('view_default')
    expect(r.value.id).toMatch(/^view_[0-9A-HJKMNP-TV-Z]{26}$/)
    const sidecar = await readRaw('_pagecollection.json')
    expect((sidecar.views as SavedView[])[0].id).toBe(r.value.id)
  })

  it('preserves a foreign top-level key + a foreign key on an untouched view', async () => {
    await writeCollectionSidecar({
      plugin_top: 'keep-top',
      views: [{ id: 'view_keep', name: 'Keep', type: 'table', property_order: [], hidden_properties: [], _plugin: 'keep-view' }]
    })
    const r = await saveView(folder, 'collection', view({ id: 'view_default', name: 'New' }))
    expect(r.ok).toBe(true)
    const sidecar = await readRaw('_pagecollection.json')
    expect(sidecar.plugin_top).toBe('keep-top')
    const keep = (sidecar.views as Record<string, unknown>[]).find((v) => v.id === 'view_keep')
    expect(keep?._plugin).toBe('keep-view')
  })

  it('reorders views by id, keeping unnamed views at the end', async () => {
    await writeCollectionSidecar({
      views: [view({ id: 'a' }), view({ id: 'b' }), view({ id: 'c' })]
    })
    await reorderViews(folder, 'collection', ['c', 'a'])
    const sidecar = await readRaw('_pagecollection.json')
    expect((sidecar.views as SavedView[]).map((v) => v.id)).toEqual(['c', 'a', 'b'])
  })

  it('deletes a view but refuses to remove the last one', async () => {
    await writeCollectionSidecar({ views: [view({ id: 'a' }), view({ id: 'b' })] })
    expect((await deleteView(folder, 'collection', 'a')).ok).toBe(true)
    expect((await readRaw('_pagecollection.json')).views).toHaveLength(1)
    // now only one view remains → refuse
    const last = await deleteView(folder, 'collection', 'b')
    expect(last.ok).toBe(false)
    if (!last.ok) expect(last.error.code).toBe('operation-failed')
  })

  it('writes Set views into the _pageset.json sidecar', async () => {
    await writeFile(join(folder, '_pageset.json'), JSON.stringify({ id: 'set', views: [] }))
    const r = await saveView(folder, 'set', view({ id: 'view_s', name: 'SetTable' }))
    expect(r.ok).toBe(true)
    const sidecar = JSON.parse(await readFile(join(folder, '_pageset.json'), 'utf8'))
    expect(sidecar.views.map((v: SavedView) => v.id)).toEqual(['view_s'])
  })
})
