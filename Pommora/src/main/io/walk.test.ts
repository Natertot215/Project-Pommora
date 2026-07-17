import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join, relative } from 'node:path'
import { listMarkdownFiles } from './walk'

let root: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-walk-'))
  await mkdir(join(root, 'sub'), { recursive: true })
  await mkdir(join(root, '.nexus'), { recursive: true })
  await mkdir(join(root, '.trash'), { recursive: true })
  await writeFile(join(root, 'a.md'), 'x', 'utf8')
  await writeFile(join(root, 'sub', 'b.md'), 'x', 'utf8')
  await writeFile(join(root, 'e.txt'), 'x', 'utf8')
  await writeFile(join(root, '.nexus', 'c.md'), 'x', 'utf8')
  await writeFile(join(root, '.trash', 'd.md'), 'x', 'utf8')
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

const rels = (paths: string[]) =>
  paths.map((p) => relative(root, p).split(/[/\\]/).join('/')).sort()

describe('listMarkdownFiles', () => {
  it('lists .md recursively (only .md), absolute paths', async () => {
    expect(rels(await listMarkdownFiles(root))).toEqual([
      '.nexus/c.md',
      '.trash/d.md',
      'a.md',
      'sub/b.md',
    ])
  })

  it('skips named top-level dirs', async () => {
    expect(rels(await listMarkdownFiles(root, { skipTopLevel: ['.nexus', '.trash'] }))).toEqual([
      'a.md',
      'sub/b.md',
    ])
  })

  it('returns [] for a missing dir', async () => {
    expect(await listMarkdownFiles(join(root, 'nope'))).toEqual([])
  })
})
