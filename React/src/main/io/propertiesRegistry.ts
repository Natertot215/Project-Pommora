import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { isPlainObject } from '@shared/propertyValue'
import { propertyDefinition, type PropertyDefinition } from '@shared/properties'

/** propId → its nexus-wide definition. The shared registry, `.nexus/properties.json`. */
export type PropertyRegistry = Record<string, PropertyDefinition>

/** The on-disk registry file: defs + the nexus-wide cosmetic order (B-1/B-2). */
export type RegistryFile = { order: string[]; defs: PropertyRegistry }

const registryPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.properties)

/** Lenient read: absent / corrupt → empty; a legacy bare-Record file reads as
 *  `{ order: [], defs }`; drops any entry that fails the def schema, and element-filters
 *  the order — non-strings and ids without defs dropped (B-3). */
export async function readRegistry(root: string): Promise<RegistryFile> {
  const obj = await readJsonObject(registryPath(root))
  if (obj === null) return { order: [], defs: {} }
  const isFileShape = isPlainObject(obj.defs) || Array.isArray(obj.order)
  const rawDefs = isFileShape ? (isPlainObject(obj.defs) ? obj.defs : {}) : obj
  const defs: PropertyRegistry = {}
  for (const [id, value] of Object.entries(rawDefs)) {
    const parsed = propertyDefinition.safeParse(value)
    if (parsed.success) defs[id] = parsed.data
  }
  const rawOrder = isFileShape && Array.isArray(obj.order) ? obj.order : []
  const order = rawOrder.filter((x): x is string => typeof x === 'string' && x in defs)
  return { order, defs }
}

/** Every def in the nexus-wide cosmetic order — order-listed first, unlisted appended.
 *  ONE ordering rule for every consumer (readNexus + the SQLite mirror). */
export function orderedDefs(reg: RegistryFile): PropertyDefinition[] {
  return [
    ...reg.order.map((id) => reg.defs[id]),
    ...Object.values(reg.defs).filter((d) => !reg.order.includes(d.id))
  ].filter((d): d is PropertyDefinition => d !== undefined)
}

/** Overwrite the whole registry file. Prefer `mutateRegistry` — a bare write outside the
 *  chain can lose a concurrent mutation's update. */
export async function writeRegistry(root: string, registry: RegistryFile): Promise<void> {
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(registryPath(root), registry)
}

// Every mutation shares one file, so read-modify-writes must not interleave: two overlapping
// IPC ops that both read the same snapshot would have the later write silently drop the
// earlier one's change. One module-level chain serializes them (single main process; the
// session has one root, so a per-root map would be ceremony).
let chain: Promise<unknown> = Promise.resolve()

/** Serialized read-modify-write. `fn` returns the next registry to persist (or nothing to
 *  leave disk untouched, e.g. a validation failure) plus the caller's result. */
export function mutateRegistry<T>(
  root: string,
  fn: (registry: RegistryFile) => { next?: RegistryFile; result: T }
): Promise<T> {
  const run = chain.then(async () => {
    const { next, result } = fn(await readRegistry(root))
    if (next) await writeRegistry(root, next)
    return result
  })
  chain = run.catch(() => undefined)
  return run
}
