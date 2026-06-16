// Atomic multi-file commit for schema mutations that touch more than one file. A
// delete-property or a lossy type-change rewrites the type sidecar AND strips the
// property from every member page — those writes must land together-or-not-at-all. A
// filesystem has no real multi-file transaction, so this fakes it with a two-phase
// commit: stage every payload to a sibling temp, then rename each over its target
// (backing up any existing target); any failure rolls the filesystem back. A crash
// mid-commit is self-healed by the stale-temp sweep on the next commit. Single-file
// writes should use atomicWriteFile directly — this is overhead-only for one file.
// Mirrors Swift's SchemaTransaction.

import { writeFile, rename, readdir, unlink } from 'node:fs/promises'
import { join, dirname } from 'node:path'
import { newId } from '../ids'
import { pathExists } from './atomicWrite'

interface Staged {
  target: string
  content: string
  temp: string
}

export class SchemaTransaction {
  private pending: Staged[] = []

  /** Stage a UTF-8 payload to write to `target` on the next `commit()`. Restaging the
   *  same target replaces the prior stage (last-stage-wins). */
  stage(target: string, content: string): void {
    const staged: Staged = { target, content, temp: `${target}.txn-${newId()}` }
    const at = this.pending.findIndex((p) => p.target === target)
    if (at >= 0) this.pending[at] = staged
    else this.pending.push(staged)
  }

  /** How many distinct files are staged. */
  get size(): number {
    return this.pending.length
  }

  /** Two-phase commit. On any failure the filesystem is restored to its pre-commit
   *  state (best-effort) and the error is rethrown. */
  async commit(): Promise<void> {
    await this.cleanStaleTemps()

    // Phase 1: write every payload to its temp sibling.
    const written: string[] = []
    for (const w of this.pending) {
      try {
        await writeFile(w.temp, w.content, 'utf8')
        written.push(w.temp)
      } catch (e) {
        for (const t of written) await unlink(t).catch(() => {})
        throw new Error(`SchemaTransaction stage failed for ${w.target}: ${String(e)}`)
      }
    }

    // Phase 2: rename each temp over its target, backing up any existing target.
    const renamed: { target: string; backup: string | null }[] = []
    for (const w of this.pending) {
      // `backup` is hoisted so the catch can restore THIS entry too: if the target was
      // already moved aside but the temp→target rename then failed, the original lives
      // only in `backup` and isn't in `renamed` yet — without this it would be lost.
      let backup: string | null = null
      try {
        if (await pathExists(w.target)) {
          backup = `${w.target}.bak-${newId()}`
          await rename(w.target, backup)
        }
        await rename(w.temp, w.target)
        renamed.push({ target: w.target, backup })
      } catch (e) {
        // Roll back: restore THIS entry's backup first, then the already-renamed ones
        // (reverse order), then delete any remaining temps.
        if (backup) await rename(backup, w.target).catch(() => {})
        for (const r of [...renamed].reverse()) {
          await unlink(r.target).catch(() => {})
          if (r.backup) await rename(r.backup, r.target).catch(() => {})
        }
        for (const t of this.pending) await unlink(t.temp).catch(() => {})
        throw new Error(`SchemaTransaction commit failed for ${w.target}: ${String(e)}`)
      }
    }

    // Phase 3: success — delete backups; clear pending (the object is reusable).
    for (const r of renamed) if (r.backup) await unlink(r.backup).catch(() => {})
    this.pending = []
  }

  /** Sweep every staged target's parent dir for stale `*.txn-*` temps left by a previous
   *  crashed commit (a temp is uncommitted, so it's always safe to delete). `*.bak-*` files
   *  are deliberately NOT swept: a leftover backup is the ORIGINAL content of a target whose
   *  commit crashed after the move-aside but before the temp landed — it may be the only
   *  copy, and a concurrent transaction's live backups would also be hit. Successful commits
   *  delete their own backups in phase 3; a crashed one's backup is left for recovery. */
  private async cleanStaleTemps(): Promise<void> {
    const dirs = new Set(this.pending.map((p) => dirname(p.target)))
    for (const dir of dirs) {
      let entries: string[]
      try {
        entries = await readdir(dir)
      } catch {
        continue
      }
      for (const name of entries) {
        if (name.includes('.txn-')) await unlink(join(dir, name)).catch(() => {})
      }
    }
  }
}
