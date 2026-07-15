// Durable pins persist one file per pin under `.nexus/pins/`, so concurrent cross-device add/unpin
// touch disjoint files and file-sync merges them — no whole-array last-writer-wins loss. Unpin is a
// tombstone (`deleted: true`) rather than an unlink, so a delete racing a concurrent reorder of the
// same pin resolves as an ordinary same-file LWW on a flag instead of resurrecting the pin.

import { mkdir, readdir } from 'node:fs/promises'
import { join } from 'node:path'
import { isPlainObject } from '@shared/propertyValue'
import type { NavTarget, PinEntry } from '@shared/types'
import { nexusDir } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { serializeOnFile } from './fileLock'

const NAV_KINDS = new Set(['homepage', 'context', 'collection', 'set', 'page', 'task', 'event'])
const pinsDir = (root: string): string => join(nexusDir(root), 'pins')

/** navKey with the path-illegal colon swapped for a hyphen (kinds are hyphen-free and we never split
 *  the name back apart, so it's collision-free over ULID / `adopted-<hex>` ids). Homepage has no id
 *  → the bare kind. */
export function pinFileName(t: NavTarget): string {
  return 'id' in t ? `${t.kind}-${t.id}` : t.kind
}

function isPinEntry(v: unknown): v is PinEntry {
  if (!isPlainObject(v)) return false
  const kind = v.kind
  if (typeof kind !== 'string' || !NAV_KINDS.has(kind)) return false
  if (kind !== 'homepage' && typeof v.id !== 'string') return false
  if ((kind === 'set' || kind === 'page') && typeof v.path !== 'string') return false
  if (typeof v.order !== 'number') return false
  return v.deleted === undefined || typeof v.deleted === 'boolean'
}

/** Read the live pin set: every `.json` under `.nexus/pins/`, validated, tombstones + malformed
 *  dropped (a parse-null is skipped, never allowed to silently shrink the set on corruption), sorted
 *  by `(order, filename)` so a concurrent equal-order insert still sorts deterministically everywhere. */
export async function readPins(root: string): Promise<PinEntry[]> {
  let names: string[]
  try {
    names = (await readdir(pinsDir(root))).filter((n) => n.endsWith('.json'))
  } catch {
    return []
  }
  const out: PinEntry[] = []
  for (const name of names) {
    const obj = await readJsonObject(join(pinsDir(root), name))
    if (obj === null || !isPinEntry(obj) || obj.deleted) continue
    out.push(obj)
  }
  return out.sort((x, y) => x.order - y.order || pinFileName(x).localeCompare(pinFileName(y)))
}

function writeAt(root: string, name: string, value: PinEntry): Promise<void> {
  const path = join(pinsDir(root), `${name}.json`)
  return serializeOnFile(path, async () => {
    await mkdir(pinsDir(root), { recursive: true })
    await writeJson(path, value)
  })
}

export async function writePin(root: string, pin: PinEntry): Promise<void> {
  await writeAt(root, pinFileName(pin), pin)
}

/** Unpin = tombstone-write (not unlink), reaped on the next read. */
export async function removePin(root: string, target: NavTarget, order: number): Promise<void> {
  await writeAt(root, pinFileName(target), { ...target, order, deleted: true } as PinEntry)
}
