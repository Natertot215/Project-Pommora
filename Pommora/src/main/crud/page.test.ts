import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, stat, readFile, writeFile } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { createPage, renamePage, deletePage, updatePageBody, movePage, updatePageProperty, setPageTier } from './page'
import { splitEnvelope, assembleEnvelope } from '../io/pageFile'
import { splitFrontmatter } from '../readNexus'
import { isUlid } from '../ids'

let root: string
let typeDir: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-page-crud-'))
  typeDir = join(root, 'Notes')
  await mkdir(typeDir, { recursive: true })
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
})

describe('createPage', () => {
  it('writes a .md with a fresh ULID, empty tiers, timestamps, and the body', async () => {
    const r = await createPage(typeDir, 'My Page', { body: 'Hello' })
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('My Page.md')).toBe(true)
    const content = await readFile(r.value.path, 'utf8')
    const fm = splitFrontmatter(content)
    expect(isUlid(fm.id as string)).toBe(true)
    expect(fm.tier1).toEqual([])
    expect(fm.created_at).toBeTruthy()
    expect(fm.modified_at).toBeTruthy()
    expect(splitEnvelope(content).body).toBe('Hello')
  })

  it('rejects duplicate + unsafe names', async () => {
    await createPage(typeDir, 'Dup')
    expect((await createPage(typeDir, 'Dup')).ok).toBe(false)
    expect((await createPage(typeDir, 'a/b')).ok).toBe(false)
    expect((await createPage(typeDir, 'Note.md')).ok).toBe(false) // would yield Note.md.md
  })
})

describe('renamePage', () => {
  it('renames the file', async () => {
    const c = await createPage(typeDir, 'Old', { body: 'b' })
    if (!c.ok) throw new Error('setup failed')
    const r = await renamePage(c.value.path, 'New')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path.endsWith('New.md')).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
    expect(splitFrontmatter(await readFile(r.value.path, 'utf8')).id).toBe(c.value.id)
  })

  it('bumps modified_at — a rename counts as an edit', async () => {
    const c = await createPage(typeDir, 'Old', { body: 'b' })
    if (!c.ok) throw new Error('setup failed')
    // Pin an old stamp so a real bump is unmistakable (vs the create-time stamp).
    const parts = splitEnvelope(await readFile(c.value.path, 'utf8'))
    await writeFile(
      c.value.path,
      assembleEnvelope(
        parts.frontmatter.replace(/^modified_at:.*$/m, 'modified_at: "2000-01-01T00:00:00.000Z"'),
        parts.body
      ),
      'utf8'
    )

    const r = await renamePage(c.value.path, 'New')
    if (!r.ok) throw new Error('rename failed')
    const after = splitFrontmatter(await readFile(r.value.path, 'utf8')).modified_at as string
    expect(after).not.toBe('2000-01-01T00:00:00.000Z') // rename advanced it
    expect(after >= '2026-01-01').toBe(true) // to a real recent stamp
  })

  it('rejects renaming onto an existing page', async () => {
    const a = await createPage(typeDir, 'A')
    await createPage(typeDir, 'B')
    if (!a.ok) throw new Error('setup failed')
    expect((await renamePage(a.value.path, 'B')).ok).toBe(false)
  })
})

describe('updatePageBody', () => {
  it('replaces the body and preserves frontmatter incl. foreign keys', async () => {
    const c = await createPage(typeDir, 'P', { body: 'one' })
    if (!c.ok) throw new Error('setup failed')
    // Inject a foreign frontmatter key to prove it survives a body update.
    const withForeign = assembleEnvelope(
      splitEnvelope(await readFile(c.value.path, 'utf8')).frontmatter + '\nplugin_key: keep',
      'one'
    )
    await writeFile(c.value.path, withForeign, 'utf8')

    const r = await updatePageBody(c.value.path, 'two')
    expect(r.ok).toBe(true)
    const content = await readFile(c.value.path, 'utf8')
    expect(splitEnvelope(content).body).toBe('two')
    const fm = splitFrontmatter(content)
    expect(fm.id).toBe(c.value.id)
    expect(fm.plugin_key).toBe('keep')
    expect(fm.modified_at).toBeTruthy()
  })
})

describe('deletePage / movePage', () => {
  it('deletes into .trash', async () => {
    const c = await createPage(typeDir, 'Gone')
    if (!c.ok) throw new Error('setup failed')
    expect((await deletePage(root, c.value.path)).ok).toBe(true)
    await expect(stat(c.value.path)).rejects.toThrow()
  })

  it('moves a page to another container', async () => {
    const other = join(root, 'Journal')
    await mkdir(other, { recursive: true })
    const c = await createPage(typeDir, 'Movable', { body: 'x' })
    if (!c.ok) throw new Error('setup failed')
    const r = await movePage(c.value.path, other)
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value.path).toBe(join(other, 'Movable.md'))
    await expect(stat(c.value.path)).rejects.toThrow()
    expect(splitEnvelope(await readFile(r.value.path, 'utf8')).body).toBe('x')
  })

  it('refuses to move onto an existing page of the same name', async () => {
    const other = join(root, 'Journal')
    await mkdir(other, { recursive: true })
    const a = await createPage(typeDir, 'Clash', { body: 'a' })
    await createPage(other, 'Clash', { body: 'b' })
    if (!a.ok) throw new Error('setup failed')
    expect((await movePage(a.value.path, other)).ok).toBe(false)
  })
})

describe('updatePageProperty', () => {
  it('sets, replaces, and clears values; preserves siblings + other frontmatter', async () => {
    const c = await createPage(typeDir, 'Props', { body: 'x' })
    if (!c.ok) throw new Error('setup failed')
    const f = c.value.path
    const props = async (): Promise<Record<string, unknown>> =>
      (splitFrontmatter(await readFile(f, 'utf8')).properties ?? {}) as Record<string, unknown>

    await updatePageProperty(f, 'prop_status', { kind: 'status', value: 'todo' })
    await updatePageProperty(f, 'prop_tags', { kind: 'multiSelect', value: ['a', 'b'] })
    expect(await props()).toEqual({ prop_status: { $status: 'todo' }, prop_tags: ['a', 'b'] })
    expect(splitFrontmatter(await readFile(f, 'utf8')).id).toBe(c.value.id)

    await updatePageProperty(f, 'prop_status', { kind: 'status', value: 'done' })
    expect((await props()).prop_status).toEqual({ $status: 'done' })

    await updatePageProperty(f, 'prop_status', null)
    expect(await props()).toEqual({ prop_tags: ['a', 'b'] })
  })

  it('encodes a context as a tagged array', async () => {
    const c = await createPage(typeDir, 'Rel', { body: 'x' })
    if (!c.ok) throw new Error('setup failed')
    await updatePageProperty(c.value.path, 'prop_link', { kind: 'context', value: ['01H', '01J'] })
    const fm = splitFrontmatter(await readFile(c.value.path, 'utf8'))
    expect((fm.properties as Record<string, unknown>).prop_link).toEqual([{ $ctx: '01H' }, { $ctx: '01J' }])
  })

  it('errors when the page is missing', async () => {
    const r = await updatePageProperty(join(typeDir, 'nope.md'), 'p', { kind: 'status', value: 'x' })
    expect(r.ok).toBe(false)
  })
})

describe('setPageTier', () => {
  it('writes a bare ULID array to the tier root field, preserving the other tiers + id', async () => {
    const c = await createPage(typeDir, 'Tiered', { body: 'x' })
    if (!c.ok) throw new Error('setup failed')
    expect((await setPageTier(c.value.path, 1, ['ctxA', 'ctxB'])).ok).toBe(true)
    const fm = splitFrontmatter(await readFile(c.value.path, 'utf8'))
    expect(fm.tier1).toEqual(['ctxA', 'ctxB'])
    expect(fm.tier2).toEqual([])
    expect(fm.id).toBe(c.value.id)
  })

  it('rejects an out-of-range tier and a missing page', async () => {
    const c = await createPage(typeDir, 'T2')
    if (!c.ok) throw new Error('setup failed')
    expect((await setPageTier(c.value.path, 4, [])).ok).toBe(false)
    expect((await setPageTier(join(typeDir, 'nope.md'), 1, [])).ok).toBe(false)
  })
})
