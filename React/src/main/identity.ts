// Per-Nexus identity (`.nexus/nexus.json`), Swift-compatible. Swift creates this eagerly
// on open (NexusManager.openPicked); React must too, or a React-touched folder stays in
// "raw mode" (its stamped sidecars ignored) and drifts from Swift's expected shape —
// breaking the goal of opening the same folder in either app with no conflict.

import { mkdir } from 'node:fs/promises'
import { newId } from './ids'
import { readJsonObject, writeJson } from './io/atomicWrite'
import { asString } from './coerce'
import { nexusDir, nexusConfig, NEXUS_CONFIG_FILES } from './paths'

// Swift `AtomicJSON` uses `.iso8601` (ISO8601DateFormatter, internet-date-time, NO
// fractional seconds). JS `toISOString()` appends milliseconds, which Swift's default
// .iso8601 decoder rejects — strip them so Swift can read our timestamp.
function swiftISODate(): string {
  return new Date().toISOString().replace(/\.\d{3}Z$/, 'Z')
}

/** A fresh identity in Swift's shape. Single source for both the open-time ensure and the
 *  lazy create-defaults on the first description/photo write. */
export function defaultIdentity(): { schemaVersion: number; id: string; createdAt: string } {
  return { schemaVersion: 1, id: newId(), createdAt: swiftISODate() }
}

/** Ensure `.nexus/nexus.json` exists in Swift's `{ schemaVersion, id, createdAt }` shape.
 *  Absent → create with a fresh ULID. Present → backfill only missing schemaVersion/
 *  createdAt (foreign keys + existing id untouched); a complete file is left byte-identical,
 *  so re-opening never churns it. */
export async function ensureIdentity(root: string): Promise<{ id: string; created: boolean }> {
  const path = nexusConfig(root, NEXUS_CONFIG_FILES.identity)
  const existing = await readJsonObject(path)
  const existingId = existing && asString(existing.id)

  if (existing && existingId) {
    const patch: Record<string, unknown> = {}
    if (typeof existing.schemaVersion !== 'number') patch.schemaVersion = 1
    if (!asString(existing.createdAt)) patch.createdAt = swiftISODate()
    if (Object.keys(patch).length > 0) await writeJson(path, { ...existing, ...patch })
    return { id: existingId, created: false }
  }

  await mkdir(nexusDir(root), { recursive: true })
  const identity = defaultIdentity()
  await writeJson(path, identity)
  return { id: identity.id, created: true }
}
