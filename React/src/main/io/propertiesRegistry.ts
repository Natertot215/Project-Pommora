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

/** Overwrite the whole registry (callers read-modify-write). */
export async function writeRegistry(root: string, registry: PropertyRegistry): Promise<void> {
  await mkdir(nexusDir(root), { recursive: true })
  await writeJson(registryPath(root), registry)
}
