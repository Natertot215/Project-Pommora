// Detail-pane thumbnail capture for the Navigation gallery. Captured on entity-open (renderer signals
// after the view settles), downscaled, and written under the SYNCED `.nexus/assets/<nexusId>/thumbnails/`
// tree so the existing `nexus-asset://` protocol serves it and a second machine gets real previews.
// Full-page capturePage then crop (rect × scaleFactor) sidesteps the HiDPI rect-crop bug; JPEG has no
// alpha (dodges the transparent→black resize bug). Membership eviction keeps the folder to the live set.

import { mkdir, readdir, rm } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import type { BrowserWindow } from 'electron'
import type { ThumbRect } from '@shared/types'
import { ensureIdentity } from '../identity'
import { atomicWriteBinary } from './atomicWrite'

const THUMB_WIDTH = 480

/** navKey → filesystem-safe thumbnail key (the colon is illegal on Windows). */
export function thumbKey(navKey: string): string {
  return navKey.replace(':', '-')
}

/** Nexus-relative POSIX path of a thumbnail (served by `nexus-asset://nexus/<rel>`). */
export function thumbRel(nexusId: string, key: string): string {
  return `.nexus/assets/${nexusId}/thumbnails/${key}.jpg`
}

const thumbsDir = (root: string, nexusId: string): string => join(root, '.nexus', 'assets', nexusId, 'thumbnails')

/** Capture the detail-pane rect as a downscaled JPEG, overwrite its keyed file, return its asset URL —
 *  or null on a bad/blank capture (the card falls back to a placeholder). `capturePage(rect)` takes the
 *  DIP rect and returns just that region (Electron applies the display scale), so no manual crop math. */
export async function captureThumbnail(win: BrowserWindow, root: string, navKey: string, rect: ThumbRect): Promise<string | null> {
  if (rect.width < 1 || rect.height < 1) return null
  const img = await win.webContents.capturePage({ x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) })
  if (img.isEmpty()) return null
  const buf = img.resize({ width: THUMB_WIDTH, quality: 'best' }).toJPEG(78)
  const { id: nexusId } = await ensureIdentity(root)
  const key = thumbKey(navKey)
  const rel = thumbRel(nexusId, key)
  await mkdir(dirname(join(root, rel)), { recursive: true })
  await atomicWriteBinary(join(root, rel), buf)
  return `nexus-asset://nexus/${rel}`
}

/** Delete thumbnails whose key isn't in the live set (recents ∪ pins) — bounds the synced folder to
 *  the working set with no orphan accumulation. No-op when the folder doesn't exist yet. */
export async function evictThumbnails(root: string, liveKeys: string[]): Promise<void> {
  const { id: nexusId } = await ensureIdentity(root)
  const dir = thumbsDir(root, nexusId)
  let names: string[]
  try {
    names = await readdir(dir)
  } catch {
    return
  }
  const live = new Set(liveKeys.map(thumbKey))
  await Promise.all(names.filter((n) => n.endsWith('.jpg') && !live.has(n.slice(0, -4))).map((n) => rm(join(dir, n), { force: true })))
}
