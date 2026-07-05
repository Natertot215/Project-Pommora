import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readTableHeadingColumns, writeTableHeadingColumns } from './tableHeadingColumns'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-tblhc-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('table heading-column store (.nexus/tableHeadingColumns.json)', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readTableHeadingColumns(root)).toEqual({})
  })

  it('round-trips heading-column table indices keyed by page id', async () => {
    await writeTableHeadingColumns(root, 'page-1', [0, 2])
    expect((await readTableHeadingColumns(root))['page-1']).toEqual([0, 2])
  })

  it('writes to .nexus/tableHeadingColumns.json (out of frontmatter, out of the index)', async () => {
    await writeTableHeadingColumns(root, 'page-1', [1])
    const raw = await readFile(join(root, '.nexus', 'tableHeadingColumns.json'), 'utf8')
    expect(JSON.parse(raw)['page-1']).toEqual([1])
  })

  it('clears a page entry when written with no indices', async () => {
    await writeTableHeadingColumns(root, 'page-1', [0])
    await writeTableHeadingColumns(root, 'page-1', [])
    expect(await readTableHeadingColumns(root)).toEqual({})
  })

  it('drops corrupt (non-integer) entries on read', async () => {
    await writeTableHeadingColumns(root, 'good', [0])
    const raw = JSON.parse(await readFile(join(root, '.nexus', 'tableHeadingColumns.json'), 'utf8'))
    raw['bad'] = ['x', -1]
    await writeTableHeadingColumns(root, 'good', [0]) // rewrite keeps only good
    expect(await readTableHeadingColumns(root)).toEqual({ good: [0] })
  })
})
