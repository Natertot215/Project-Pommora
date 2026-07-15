// The single owner of safe writes for the data layer. Every write goes to a temp
// sibling then atomically renames over the target (write-file-atomic does the
// temp + fsync + rename), so a crash can never leave a half-written file. Atomic on
// the SAME volume only — temps are siblings of the target, so a nexus stays intact.

import writeFileAtomic from 'write-file-atomic'
import { readFile, rename, mkdir, stat } from 'node:fs/promises'
import { join, basename } from 'node:path'
import { isPlainObject } from '@shared/propertyValue'
import { recordWrite } from './writeEcho'

/** Atomically write a UTF-8 string to `filePath`. Recorded for watcher echo
 *  suppression — the app's own writes never trigger its own re-walk. */
export async function atomicWriteFile(filePath: string, data: string): Promise<void> {
  recordWrite(filePath)
  await writeFileAtomic(filePath, data, { encoding: 'utf8' })
}

/** Atomically write raw bytes to `filePath` (binary siblings of the UTF-8 writer). */
export async function atomicWriteBinary(filePath: string, data: Buffer): Promise<void> {
  recordWrite(filePath)
  await writeFileAtomic(filePath, data)
}

/** The canonical on-disk JSON bytes: stable, sorted keys + a trailing newline. The one
 *  source of the sidecar serialization shape — used by writeJson and by SchemaTransaction
 *  when it stages a sidecar alongside member-file rewrites. */
export function serializeJson(value: unknown): string {
  return stableStringify(value) + '\n'
}

/** Atomically write a JSON value with stable, sorted keys + a trailing newline. */
export async function writeJson(filePath: string, value: unknown): Promise<void> {
  await atomicWriteFile(filePath, serializeJson(value))
}

/**
 * Read a JSON file, apply `mutate` to the parsed value, write the result back
 * atomically. Read-modify-write so concurrent sibling writers don't clobber each
 * other's keys. A missing/unreadable file starts from `fallback()`. Returns the
 * value that was written.
 */
export async function mutateJson<T>(
  filePath: string,
  fallback: () => T,
  mutate: (current: T) => T
): Promise<T> {
  let current: T
  try {
    current = JSON.parse(await readFile(filePath, 'utf8')) as T
  } catch {
    current = fallback()
  }
  const next = mutate(current)
  await writeJson(filePath, next)
  return next
}

/** Read + JSON-parse a file to a plain object, or null if missing / unreadable / not an
 *  object. The one owner of "parse a JSON file to a record" — used by sidecar, agenda, and
 *  index reads (the JSON-side analog of pageFile's mergeFrontmatter). */
export async function readJsonObject(absPath: string): Promise<Record<string, unknown> | null> {
  try {
    const v: unknown = JSON.parse(await readFile(absPath, 'utf8'))
    return isPlainObject(v) ? v : null
  } catch {
    return null
  }
}

/** Read + JSON-parse a file to a plain array, or `[]` if missing / unreadable / not an array.
 *  The array-side analog of `readJsonObject` — the lenient reader for sidecars stored as lists
 *  (the Navigation recents/favorites streams). Element validation is the caller's job. */
export async function readJsonArray(absPath: string): Promise<unknown[]> {
  try {
    const v: unknown = JSON.parse(await readFile(absPath, 'utf8'))
    return Array.isArray(v) ? v : []
  } catch {
    return []
  }
}

/** Deterministic JSON: object keys sorted recursively, 2-space indent. Byte-stable
 *  across writes so re-saving unchanged data produces identical bytes. */
export function stableStringify(value: unknown): string {
  return JSON.stringify(sortKeys(value), null, 2)
}

function sortKeys(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(sortKeys)
  if (value !== null && typeof value === 'object') {
    const source = value as Record<string, unknown>
    const out: Record<string, unknown> = {}
    for (const key of Object.keys(source).sort()) out[key] = sortKeys(source[key])
    return out
  }
  return value
}

/** True when a path exists. The one owner of the stat-as-existence check. */
export async function pathExists(p: string): Promise<boolean> {
  try {
    await stat(p)
    return true
  } catch {
    return false
  }
}

/**
 * Move a file/folder into the nexus-local `.trash/`, timestamped and de-collided.
 * Files stay canonical and recoverable (in-nexus, not OS trash). Returns the
 * destination path. The original's relative layout is not preserved.
 */
export async function trashWithTimestamp(nexusRoot: string, absPath: string): Promise<string> {
  const trash = join(nexusRoot, '.trash')
  await mkdir(trash, { recursive: true })
  const stamp = new Date().toISOString().replace(/[:.]/g, '-')
  const base = basename(absPath)
  let dest = join(trash, `${stamp}__${base}`)
  for (let n = 1; await pathExists(dest); n++) dest = join(trash, `${stamp}__${n}__${base}`)
  await rename(absPath, dest)
  return dest
}
