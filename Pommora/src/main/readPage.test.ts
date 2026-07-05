import { describe, it, expect, beforeAll, afterAll } from 'vitest'
import { mkdtempSync, mkdirSync, writeFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { readPage } from './readPage'

const d = (p: string): void => {
  mkdirSync(p, { recursive: true })
}
const w = (p: string, c: string): void => {
  writeFileSync(p, c)
}

let root: string

beforeAll(() => {
  root = mkdtempSync(join(tmpdir(), 'pom-page-'))
  d(join(root, 'Vault A', 'Collection A'))
  w(
    join(root, 'Vault A', 'Collection A', 'Page A.md'),
    '---\nid: page-a\nicon: star\ntags:\n  - x\n  - y\n---\n# Heading\n\nbody text\n'
  )
  w(join(root, 'Vault A', 'Collection A', 'Plain.md'), '# just markdown\n\nno frontmatter')
  w(join(root, 'Vault A', 'Collection A', 'Empty.md'), '')
  w(join(root, 'Vault A', 'Collection A', 'Unterminated.md'), '---\nid: x\nno close fence')
})

afterAll(() => {
  rmSync(root, { recursive: true, force: true })
})

describe('readPage', () => {
  it('reads frontmatter + body, derives title + path from the rel path', async () => {
    const p = await readPage(root, 'Vault A/Collection A/Page A.md')
    expect(p.id).toBe('page-a')
    expect(p.title).toBe('Page A')
    expect(p.path).toBe('Vault A/Collection A/Page A.md')
    expect(p.frontmatter).toEqual({ id: 'page-a', icon: 'star', tags: ['x', 'y'] })
    expect(p.body).toBe('# Heading\n\nbody text\n')
  })

  it('adopts an id and returns whole file as body when no frontmatter', async () => {
    const p = await readPage(root, 'Vault A/Collection A/Plain.md')
    expect(p.id.startsWith('adopted-')).toBe(true)
    expect(p.frontmatter).toEqual({})
    expect(p.body).toBe('# just markdown\n\nno frontmatter')
    expect(p.title).toBe('Plain')
  })

  it('handles an empty file', async () => {
    const p = await readPage(root, 'Vault A/Collection A/Empty.md')
    expect(p.frontmatter).toEqual({})
    expect(p.body).toBe('')
  })

  it('treats an unterminated fence as all-body', async () => {
    const p = await readPage(root, 'Vault A/Collection A/Unterminated.md')
    expect(p.frontmatter).toEqual({})
    expect(p.body).toBe('---\nid: x\nno close fence')
  })

  it('throws when the file does not exist', async () => {
    await expect(readPage(root, 'Vault A/Collection A/Nope.md')).rejects.toThrow()
  })
})
