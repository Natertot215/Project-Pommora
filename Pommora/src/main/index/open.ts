// Per-nexus index open with the version handshake. Mirrors Swift's PommoraIndex.open: an
// existing index at the current SCHEMA_VERSION is reused; any other version (or a
// corrupt/unreadable file, or an absent version left by a half-built index) is deleted
// and recreated fresh, signalling needsRebuild so the caller runs a cold build then
// stamps. The index lives at <nexus>/.nexus/index.db. Returns null only when even a fresh
// DB can't be opened — the caller degrades to file-only reads.

import { rmSync, existsSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'
import { openDb, type Db } from './db'
import { applySchema, readSchemaVersion, SCHEMA_VERSION } from './schema'
import { nexusDir } from '../paths'

export interface OpenedIndex {
  db: Db
  /** True for a freshly created/reset DB — the caller must cold-build then stamp. */
  needsRebuild: boolean
}

/** Open (creating/resetting as needed) the per-nexus index. null ⇒ degrade to files. */
export function openIndex(nexusRoot: string): OpenedIndex | null {
  const dir = nexusDir(nexusRoot)
  mkdirSync(dir, { recursive: true })
  const dbPath = join(dir, 'index.db')

  if (existsSync(dbPath)) {
    const existing = openDb(dbPath)
    if (existing) {
      if (readSchemaVersion(existing) === SCHEMA_VERSION)
        return { db: existing, needsRebuild: false }
      existing.close() // version mismatch / absent → reset below
    }
    // Mismatch or unreadable → delete the DB + its WAL/SHM siblings so no stale data survives.
    for (const suffix of ['', '-wal', '-shm']) {
      try {
        rmSync(dbPath + suffix, { force: true })
      } catch {
        /* best-effort */
      }
    }
  }

  const db = openDb(dbPath)
  if (!db) return null
  applySchema(db)
  return { db, needsRebuild: true }
}
