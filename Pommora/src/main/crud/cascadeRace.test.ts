// F1 regression: the schema-op page cascades (option rename/remove/clear, [[link]] + tier
// cascades, property delete/remove) and the cell-write path (mutate's setProperty/setTier) must
// serialize on the SAME per-file lock. Before the fix the cascade rode SchemaTransaction (no
// per-file guard) while cell-writes rode serializeOnFile — two independent locks, so a cascade
// racing a cell edit on one page could silently clobber a value.
//
// This drives the REAL keys: the cell-write locks on resolveUnderRoot's output (realpath'd) and
// the cascade keys off sessionRoot(). They match ONLY because openSession canonicalizes the root
// — on a symlinked-root ancestry (a tmpdir on macOS IS /var→/private/var) a raw sessionRoot would
// split the two into different lock buckets and this test would go red. (fileLock.test proves the
// other half — that a page rewrite reads FRESH inside the lock, so nothing is lost.)

import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, relative } from 'node:path'
import { renameOption } from './optionOps'
import { createProperty } from './registryProperty'
import { assignProperty } from './assignment'
import { createFolderEntity } from './folderEntity'
import { createPage, updatePageProperty } from './page'
import { serializeOnFile } from '../io/fileLock'
import { openSession, closeSession, sessionRoot } from '../session'
import { resolveUnderRoot } from '../pathSafety'
import type { PropertyDefinition } from '@shared/properties'

let rawRoot: string
beforeEach(async () => {
  rawRoot = await mkdtemp(join(tmpdir(), 'pom-race-'))
})
afterEach(async () => {
  closeSession()
  await rm(rawRoot, { recursive: true, force: true })
})

/** A Select property assigned to one collection whose page holds the option `value`. Built under
 *  `root` (the canonical session root); returns the property id and the page's nexus-relative path. */
async function setup(root: string, value: string): Promise<{ propertyId: string; rel: string }> {
  const c = await createProperty(root, {
    id: '',
    name: 'P',
    type: 'select',
    select_options: [{ value, label: value }]
  } as PropertyDefinition)
  if (!c.ok) throw new Error('createProperty failed')
  const col = await createFolderEntity(root, 'collection', 'Col')
  if (!col.ok) throw new Error('collection failed')
  await assignProperty(root, col.value.path, c.value.id)
  const p = await createPage(col.value.path, 'Target', { body: 'b' })
  if (!p.ok) throw new Error('page failed')
  await updatePageProperty(p.value.path, c.value.id, { kind: 'select', value })
  return { propertyId: c.value.id, rel: relative(root, p.value.path) }
}

describe('F1 — the cascade takes the cell-write lock', () => {
  it('a rename cascade queues behind an in-flight cell-write on the same page', async () => {
    await openSession(rawRoot) // canonicalizes the root
    const root = sessionRoot()!
    const { propertyId, rel } = await setup(root, 'old')
    // The exact key the real setProperty locks on (mutate.ts → resolveUnderRoot → realpath'd).
    const key = await resolveUnderRoot(root, rel)
    if (!key.ok) throw new Error('resolve failed')

    const order: string[] = []
    let release!: () => void
    const gate = new Promise<void>((r) => {
      release = r
    })
    // Occupy the page's file lock with a gated cell-write. If the cascade keyed off a different
    // path string (pre-fix: raw root vs realpath'd) it would land in another bucket and slip past.
    const held = serializeOnFile(key.value, async () => {
      await gate
      order.push('cell-write')
    })
    const cascade = renameOption(root, propertyId, 'old', 'new').then(() => order.push('cascade'))
    await new Promise((r) => setTimeout(r, 50))
    release()
    await Promise.all([held, cascade])
    expect(order).toEqual(['cell-write', 'cascade'])
  })
})
