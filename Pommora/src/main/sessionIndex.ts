// The per-session SQLite index handle. The index is a regeneratable accelerator that
// sits OFF the read path (the sidebar reads the filesystem via readNexus), so opening it
// is best-effort: rebuildIndex returns null on any failure and the app runs file-only.
// One handle per open nexus, kept warm so a mutation can apply its incremental upsert.
//
// Kept separate from session.ts (which owns only the root path) so that module stays pure
// Node with no native dependency; the better-sqlite3 import enters the graph only here.

import { rmSync } from 'node:fs'
import { join } from 'node:path'
import { rebuildIndex } from './index/build'
import { nexusDir } from './paths'
import type { Db } from './index/db'

let db: Db | null = null

/** The open nexus's index handle, or null when none is open / the index is unavailable. */
export function sessionDb(): Db | null {
  return db
}

/**
 * Open the index for `root`, cold-building it if the version handshake requires, and keep
 * the handle for this session (replacing any prior one). Best-effort + never throws: a null
 * outcome (corrupt DB, native-load failure, unreadable nexus) just means file-only reads.
 */
export async function openSessionIndex(root: string): Promise<void> {
  closeSessionIndex()
  try {
    db = await rebuildIndex(root)
  } catch {
    db = null
  }
}

/**
 * Rebuild the index from the (now-mutated) files after a mutation. The index has no
 * incremental updater yet, so we drop index.db + cold-rebuild — correct by construction
 * (reuses the cold build; no per-entity row logic duplicated from buildIndex). Never throws
 * (all errors internally caught), so the mutate layer fire-and-forgets it off the UI path.
 * v1.1: targeted incremental upserts/deletes when nexuses grow + a query consumer lands.
 */
export async function refreshSessionIndex(root: string): Promise<void> {
  closeSessionIndex() // release the handle + flush WAL so the file delete is clean
  for (const suffix of ['', '-wal', '-shm']) {
    try {
      rmSync(join(nexusDir(root), 'index.db' + suffix), { force: true })
    } catch {
      /* best-effort */
    }
  }
  await openSessionIndex(root)
}

/** Close + drop the current index handle (session switch / app quit). */
export function closeSessionIndex(): void {
  if (db) {
    try {
      db.close()
    } catch {
      /* best-effort — a regeneratable index never needs a clean close */
    }
    db = null
  }
}
