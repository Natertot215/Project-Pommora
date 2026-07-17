// The preview windows' per-nexus persistence: one SYNCED sidecar under `.nexus/` —
// `page-previews.json` (H-3/H-10): the NavWindow flavor's tab set, the per-origin page-preview
// sets (keyed by origin page id, re-keyed on re-parent), and which preview was open. The renderer
// owns restore-time reconciliation against the live tree; main is the persister.

import { isPlainObject } from '@shared/propertyValue'
import type { PreviewSetRecord, PreviewsFile, PreviewTabTarget } from '@shared/types'
import { nexusConfig, NEXUS_CONFIG_FILES } from '../paths'
import { readJsonObject } from './atomicWrite'
import { debouncedSidecar } from './debouncedSidecar'

const previewsPath = (root: string): string => nexusConfig(root, NEXUS_CONFIG_FILES.previews)

const PREVIEWS_DEBOUNCE_MS = 500

export const EMPTY_PREVIEWS: PreviewsFile = { navSet: null, origins: {}, open: null }

// --- validation (lenient read) --------------------------------------------

/** The operational subset: previews hold pages and the nav sentinel, never other entity kinds. */
function isPreviewTarget(v: unknown): v is PreviewTabTarget {
  if (!isPlainObject(v)) return false
  if (v.kind === 'navwindow') return true
  return v.kind === 'page' && typeof v.id === 'string' && typeof v.path === 'string'
}

/** A well-formed persisted set: 1+ valid tabs, activeIndex clamped into range. Hand-edited or
 *  cross-version junk degrades (bad tabs drop; an emptied record reads as absent, never crashes). */
function readRecord(v: unknown): PreviewSetRecord | null {
  if (!isPlainObject(v) || !Array.isArray(v.tabs)) return null
  const tabs = v.tabs
    .filter((t): t is { target: PreviewTabTarget } => isPlainObject(t) && isPreviewTarget(t.target))
    .map((t) => ({ target: t.target }))
  if (tabs.length === 0) return null
  const raw =
    typeof v.activeIndex === 'number' && Number.isInteger(v.activeIndex) ? v.activeIndex : 0
  return { tabs, activeIndex: Math.min(Math.max(0, raw), tabs.length - 1) }
}

// --- read -------------------------------------------------------------------

/** The persisted previews file, read leniently: absent / corrupt → the empty shape. */
export async function readPreviewsState(root: string): Promise<PreviewsFile> {
  const raw = await readJsonObject(previewsPath(root))
  if (!raw) return EMPTY_PREVIEWS
  const origins: Record<string, PreviewSetRecord> = {}
  if (isPlainObject(raw.origins)) {
    for (const [k, v] of Object.entries(raw.origins)) {
      const rec = readRecord(v)
      if (rec) origins[k] = rec
    }
  }
  let open: PreviewsFile['open'] = null
  if (isPlainObject(raw.open) && typeof raw.open.originId === 'string') {
    const flavor = raw.open.flavor
    if (flavor === 'page' || flavor === 'nav') open = { flavor, originId: raw.open.originId }
  }
  return { navSet: readRecord(raw.navSet), origins, open }
}

// --- debounced write --------------------------------------------------------

const sidecar = debouncedSidecar<PreviewsFile>({
  path: previewsPath,
  debounceMs: PREVIEWS_DEBOUNCE_MS,
  label: 'previews',
})

/** Debounced previews write — every tab mutation mirrors the whole file. Newest payload wins. */
export function schedulePreviewsWrite(root: string, file: PreviewsFile): void {
  sidecar.schedule(root, file)
}

/** Any previews write still owed to disk. The quit gate + nexus-switch drain check this. */
export const hasPendingPreviewsWrites = (): boolean => sidecar.hasPending()

/** Drain every owed previews write (before-quit + nexus switch). */
export const flushPreviewsWrites = (): Promise<void> => sidecar.flush()
