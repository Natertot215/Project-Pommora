import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readFolds, writeFolds } from './folds'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-folds-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('folds store (.nexus/folds.json)', () => {
  it('reads empty when the file is absent', async () => {
    expect(await readFolds(root)).toEqual({})
  })

  it('round-trips folded headings keyed by page id', async () => {
    await writeFolds(root, 'page-1', ['## Notes', '## Tasks [2]'])
    expect((await readFolds(root))['page-1']).toEqual(['## Notes', '## Tasks [2]'])
  })

  it('writes to .nexus/folds.json (out of frontmatter, out of the index)', async () => {
    await writeFolds(root, 'page-1', ['## Notes'])
    const raw = await readFile(join(root, '.nexus', 'folds.json'), 'utf8')
    expect(JSON.parse(raw)['page-1']).toEqual(['## Notes'])
  })

  it('clears a page entry when written with no keys', async () => {
    await writeFolds(root, 'page-1', ['## Notes'])
    await writeFolds(root, 'page-1', [])
    expect(await readFolds(root)).toEqual({})
  })

  it('keeps other pages intact when one changes', async () => {
    await writeFolds(root, 'page-1', ['## A'])
    await writeFolds(root, 'page-2', ['## B'])
    await writeFolds(root, 'page-1', ['## A', '## C'])
    const state = await readFolds(root)
    expect(state['page-1']).toEqual(['## A', '## C'])
    expect(state['page-2']).toEqual(['## B'])
  })
})
