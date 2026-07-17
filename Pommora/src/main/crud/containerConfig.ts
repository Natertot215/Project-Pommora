// Per-container non-view settings CRUD — the sidecar's open_in / view_button / view_style. A
// read-modify-write through readSidecar/writeSidecar so foreign keys (and every field not in the
// patch) ride through untouched. open_in is collection-owned; a Set write is refused. Errors flow as
// Result, never thrown.

import { pageCollectionSidecar, pageSetSidecar } from '@shared/schemas'
import type { OpenIn, ViewButton, ViewStyle } from '@shared/types'
import { ok, fail, type Result } from '@shared/result'
import { readSidecar, writeSidecar } from '../sidecarIO'
import { nowIso } from './util'

type ContainerKind = 'collection' | 'set'

/** Only the keys a surface wants to change; omitted keys ride through untouched. */
export type ContainerConfigPatch = {
  open_in?: OpenIn
  view_button?: ViewButton
  view_style?: ViewStyle
}

function readCfgSidecar(folder: string, kind: ContainerKind) {
  return kind === 'collection'
    ? readSidecar(folder, 'collection', pageCollectionSidecar)
    : readSidecar(folder, 'set', pageSetSidecar)
}

/** Spread only the patch's defined keys, so an explicit `undefined` can't wipe an existing value. */
function definedOnly(patch: ContainerConfigPatch): Record<string, unknown> {
  const out: Record<string, unknown> = {}
  for (const [k, v] of Object.entries(patch)) if (v !== undefined) out[k] = v
  return out
}

export async function setContainerConfig(
  folder: string,
  kind: ContainerKind,
  patch: ContainerConfigPatch,
): Promise<Result<null>> {
  if (kind === 'set' && patch.open_in !== undefined) {
    return fail('operation-failed', 'Open In is collection-owned.', kind)
  }
  const sidecar = await readCfgSidecar(folder, kind)
  if (sidecar === null) return fail('not-found', 'Container sidecar not found.', kind)
  await writeSidecar(folder, kind, { ...sidecar, ...definedOnly(patch), modified_at: nowIso() })
  return ok(null)
}
