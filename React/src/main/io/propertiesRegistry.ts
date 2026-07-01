import { mkdir } from 'node:fs/promises'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject, writeJson } from './atomicWrite'
import { propertyDefinition, type PropertyDefinition } from '@shared/properties'

/** propId → its nexus-wide definition. The shared registry, `.nexus/properties.json`. */
export type PropertyRegistry = Record<string, PropertyDefinition>

const registryPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.properties)

/** Lenient read: absent / corrupt → `{}`; drops any entry that fails the def schema. */
export async function readRegistry(root: string): Promise<PropertyRegistry> {
  const obj = await readJsonObject(registryPath(root))
  if (obj === null) return {}
  const out: PropertyRegistry = {}
  for (const [id, value] of Object.entries(obj)) {
    const parsed = propertyDefinition.safeParse(value)
    if (parsed.success) out[id] = parsed.data
  }
  return out
}

/** Overwrite the whole registry. Prefer `mutateRegistry` — a bare write outside the chain
 *  can lose a concurrent mutation's update. */
export async function writeRegistry(root: string, registry: PropertyRegistry): Promise<void> {
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
  fn: (registry: PropertyRegistry) => { next?: PropertyRegistry; result: T }
): Promise<T> {
  const run = chain.then(async () => {
    const { next, result } = fn(await readRegistry(root))
    if (next) await writeRegistry(root, next)
    return result
  })
  chain = run.catch(() => undefined)
  return run
}
