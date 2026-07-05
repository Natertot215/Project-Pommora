import { describe, it, expect, beforeEach, afterEach } from 'vitest'
import { mkdtemp, rm, mkdir, writeFile, symlink, realpath } from 'node:fs/promises'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { resolveUnderRoot } from './pathSafety'

let root: string
let outside: string
beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'pom-pathsafety-'))
  outside = await mkdtemp(join(tmpdir(), 'pom-outside-'))
})
afterEach(async () => {
  await rm(root, { recursive: true, force: true })
  await rm(outside, { recursive: true, force: true })
})

describe('resolveUnderRoot', () => {
  it('resolves an existing relative file to its canonical absolute path', async () => {
    await mkdir(join(root, 'Notes'), { recursive: true })
    await writeFile(join(root, 'Notes', 'a.md'), 'x')
    const r = await resolveUnderRoot(root, 'Notes/a.md')
    expect(r.ok).toBe(true)
    if (!r.ok) return
    expect(r.value).toBe(join(await realpath(root), 'Notes', 'a.md'))
  })

  it('accepts the root itself', async () => {
    const r = await resolveUnderRoot(root, '.')
    expect(r.ok).toBe(true)
  })

  it('rejects an absolute path', async () => {
    const r = await resolveUnderRoot(root, '/etc/passwd')
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('invalid-path')
  })

  it('rejects a `..` traversal', async () => {
    const r = await resolveUnderRoot(root, '../escape')
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('invalid-path')
  })

  it('rejects an empty or non-string path', async () => {
    expect((await resolveUnderRoot(root, '')).ok).toBe(false)
    expect((await resolveUnderRoot(root, undefined)).ok).toBe(false)
    expect((await resolveUnderRoot(root, 42)).ok).toBe(false)
  })

  it('reports a missing-but-contained path as not-found, not a security reject', async () => {
    const r = await resolveUnderRoot(root, 'Notes/ghost.md')
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('not-found')
  })

  it('rejects an in-nexus symlink that resolves OUTSIDE the root', async () => {
    await writeFile(join(outside, 'secret.txt'), 'top secret')
    // A symlink inside the nexus pointing at the outside dir — lexically `link/...`
    // looks contained; only realpath sees it escapes.
    await symlink(outside, join(root, 'link'))
    const r = await resolveUnderRoot(root, 'link/secret.txt')
    expect(r.ok).toBe(false)
    if (r.ok) return
    expect(r.error.code).toBe('invalid-path')
  })
})
