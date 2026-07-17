import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { splitEnvelope, assembleEnvelope, mergeFrontmatter, writePageFile } from './pageFile'

describe('splitEnvelope / assembleEnvelope', () => {
  it('round-trips a canonical envelope', () => {
    const content = '---\nid: X\n---\nBody text'
    expect(splitEnvelope(content)).toEqual({ frontmatter: 'id: X', body: 'Body text' })
    expect(assembleEnvelope('id: X\n', 'Body text')).toBe(content)
  })

  it('reads a legacy envelope (separator blank line) to the same body', () => {
    expect(splitEnvelope('---\nid: X\n---\n\nBody text')).toEqual({
      frontmatter: 'id: X',
      body: 'Body text',
    })
  })

  it('strips exactly one separator blank line before the body', () => {
    expect(splitEnvelope('---\nid: X\n---\n\n\nBody').body).toBe('\nBody')
  })

  it('treats a file with no opening fence as all body', () => {
    expect(splitEnvelope('Just body')).toEqual({ frontmatter: '', body: 'Just body' })
  })

  it('treats an unterminated fence as all body (lenient)', () => {
    const content = '---\nid: X'
    expect(splitEnvelope(content)).toEqual({ frontmatter: '', body: content })
  })
})

describe('mergeFrontmatter — foreign preservation (the contract)', () => {
  it('updates a modeled key while preserving foreign keys + nesting', () => {
    const existing = assembleEnvelope('id: OLD\nplugin_key: keepme\nnested:\n  a: 1\n', 'Body')
    const { frontmatter, body } = splitEnvelope(
      mergeFrontmatter(existing, { id: 'NEW' }, ['id'], 'Body'),
    )
    expect(frontmatter).toContain('id: NEW')
    expect(frontmatter).toContain('plugin_key: keepme')
    expect(frontmatter).toContain('nested:')
    expect(frontmatter).toContain('a: 1')
    expect(body).toBe('Body')
  })

  it('preserves foreign comments', () => {
    const existing = assembleEnvelope('id: OLD\n# a foreign comment\nplugin_key: keepme\n', 'B')
    const out = mergeFrontmatter(existing, { id: 'NEW' }, ['id'], 'B')
    expect(out).toContain('# a foreign comment')
    expect(out).toContain('plugin_key: keepme')
  })

  it('deletes a modeled key when omitted, leaving foreign keys intact', () => {
    const existing = assembleEnvelope('id: X\nicon: star\nplugin: keep\n', 'B')
    const { frontmatter } = splitEnvelope(
      mergeFrontmatter(existing, { id: 'X' }, ['id', 'icon'], 'B'),
    )
    expect(frontmatter).toContain('id: X')
    expect(frontmatter).not.toContain('icon')
    expect(frontmatter).toContain('plugin: keep')
  })

  it('writes modeled keys + body for a new (empty) file', () => {
    const out = mergeFrontmatter('', { id: 'X', tier1: ['A', 'B'] }, ['id', 'tier1'], 'Hello')
    expect(out.startsWith('---\n')).toBe(true)
    const { frontmatter, body } = splitEnvelope(out)
    expect(frontmatter).toContain('id: X')
    expect(frontmatter).toContain('A')
    expect(body).toBe('Hello')
  })

  it('is idempotent — re-saving identical input yields identical bytes', () => {
    const first = mergeFrontmatter('', { id: 'X', tier1: ['T'] }, ['id', 'tier1'], 'Body')
    const second = mergeFrontmatter(first, { id: 'X', tier1: ['T'] }, ['id', 'tier1'], 'Body')
    expect(second).toBe(first)
  })
})

describe('writePageFile (fs)', () => {
  let dir: string
  beforeEach(async () => {
    dir = await mkdtemp(join(tmpdir(), 'pom-page-'))
  })
  afterEach(async () => {
    await rm(dir, { recursive: true, force: true })
  })

  it('writes a new page atomically', async () => {
    const p = join(dir, 'page.md')
    await writePageFile(p, { id: 'X', tier1: ['T'] }, ['id', 'tier1'], 'Hello')
    const content = await readFile(p, 'utf8')
    expect(content).toContain('id: X')
    expect(splitEnvelope(content).body).toBe('Hello')
  })

  it('preserves foreign frontmatter on update', async () => {
    const p = join(dir, 'page.md')
    await writeFile(p, assembleEnvelope('id: OLD\nplugin: keep\n', 'Body'), 'utf8')
    await writePageFile(p, { id: 'NEW' }, ['id'], 'Body')
    const content = await readFile(p, 'utf8')
    expect(content).toContain('id: NEW')
    expect(content).toContain('plugin: keep')
    expect(splitEnvelope(content).body).toBe('Body')
  })
})
