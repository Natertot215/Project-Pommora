// The single owner of safe writes for the data layer. Every write goes to a temp
// sibling then atomically renames over the target (write-file-atomic does the
// temp + fsync + rename), so a crash can never leave a half-written file. Atomic on
// the SAME volume only — temps are siblings of the target, so a nexus stays intact.

import writeFileAtomic from 'write-file-atomic'
import { readFile } from 'node:fs/promises'

/** Atomically write a UTF-8 string to `filePath`. */
export async function atomicWriteFile(filePath: string, data: string): Promise<void> {
  await writeFileAtomic(filePath, data, { encoding: 'utf8' })
}

/** Atomically write a JSON value with stable, sorted keys + a trailing newline. */
export async function writeJson(filePath: string, value: unknown): Promise<void> {
  await atomicWriteFile(filePath, stableStringify(value) + '\n')
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
