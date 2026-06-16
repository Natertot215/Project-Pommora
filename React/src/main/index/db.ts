// The SQLite seam. better-sqlite3 lives ONLY behind this module — swapping the driver
// (e.g. to node:sqlite later) is a one-file change, callers unchanged ("no dependency
// lock-in"). Synchronous (better-sqlite3 has no async). The index is regeneratable, so an
// open failure returns null and the app degrades to file-only reads — the DB never blocks
// anything (it's a pure accelerator, off the read path).

import Database from 'better-sqlite3'

export type Db = Database.Database

/** Open (creating if needed) a SQLite database at `path` — or null if it can't be opened
 *  (corrupt / locked / native-load failure). The caller degrades to file-only reads. */
export function openDb(path: string): Db | null {
  try {
    const db = new Database(path)
    db.pragma('journal_mode = WAL')
    db.pragma('foreign_keys = ON')
    return db
  } catch {
    return null
  }
}

/** Run `fn` inside a transaction (auto-rollback if it throws). Returns fn's result. */
export function transact<T>(db: Db, fn: () => T): T {
  return db.transaction(fn)()
}
