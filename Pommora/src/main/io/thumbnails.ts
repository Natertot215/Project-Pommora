// Detail-pane thumbnail capture for the Navigation gallery. Captured on entity-open (renderer signals
// after the view settles), downscaled, and written under the SYNCED `.nexus/assets/<nexusId>/thumbnails/`
// tree so the existing `nexus-asset://` protocol serves it and a second machine gets real previews.
// Full-page capturePage then crop (rect × scaleFactor) sidesteps the HiDPI rect-crop bug; JPEG has no
// alpha (dodges the transparent→black resize bug). Membership eviction keeps the folder to the live set.

import { mkdir, readdir, rm } from 'node:fs/promises'
import { dirname, join } from 'node:path'
import { nativeImage } from 'electron'
import type { BrowserWindow, NativeImage } from 'electron'
import { WINDOW_BG } from '@shared/theme'
import type { ThumbRect } from '@shared/types'
import { ensureIdentity } from '../identity'
import { atomicWriteBinary } from './atomicWrite'

const THUMB_WIDTH = 480

/** `#RRGGBB` → `[r, g, b]`. */
function hexToRgb(hex: string): [number, number, number] {
  const n = Number.parseInt(hex.slice(1), 16)
  return [(n >> 16) & 255, (n >> 8) & 255, n & 255]
}

/** Hide the toolbar chrome overlapping the top of the shot WITHOUT touching the live DOM (no flicker):
 *  overpaint the top `maskTop` band in the captured bitmap. Over a full-bleed banner the band is back-filled
 *  by copying the banner block just below it up over the chrome (chrome gone, banner reads continuous); with
 *  no banner that strip is empty, so it's filled with the window bg. Rebuilt at the same scaleFactor so the
 *  downscale that follows is unchanged. */
function maskTopBand(img: NativeImage, maskTopDip: number, fill: 'banner' | 'window', sf: number, width: number, height: number): NativeImage {
  const rows = Math.min(Math.round(maskTopDip * sf), height)
  if (rows < 1) return img
  const bmp = img.toBitmap() // B, G, R, A
  const rowBytes = width * 4
  if (fill === 'banner' && rows * 2 <= height) {
    bmp.copyWithin(0, rows * rowBytes, rows * 2 * rowBytes)
  } else {
    const [r, g, b] = hexToRgb(WINDOW_BG)
    for (let i = 0, end = rows * rowBytes; i < end; i += 4) {
      bmp[i] = b
      bmp[i + 1] = g
      bmp[i + 2] = r
      bmp[i + 3] = 255
    }
  }
  return nativeImage.createFromBitmap(bmp, { width, height, scaleFactor: sf })
}

/** navKey → filesystem-safe thumbnail key (the colon is illegal on Windows). */
export function thumbKey(navKey: string): string {
  return navKey.replace(':', '-')
}

/** Nexus-relative POSIX path of a thumbnail (served by `nexus-asset://nexus/<rel>`). */
export function thumbRel(nexusId: string, key: string): string {
  return `.nexus/assets/${nexusId}/thumbnails/${key}.jpg`
}

const thumbsDir = (root: string, nexusId: string): string => join(root, '.nexus', 'assets', nexusId, 'thumbnails')

/** Capture the content-only rect as a downscaled JPEG, overwrite its keyed file, return its asset URL —
 *  or null on a bad/blank capture (the card falls back to a placeholder). `capturePage(rect)` returns an
 *  empty image on HiDPI (the rect-crop bug), so we grab the whole page and crop in device pixels. `rect`
 *  is DIP; `scaleFactor` (the renderer's devicePixelRatio, which folds in both the display scale and any
 *  page zoom) maps it onto the captured image's pixels. */
export async function captureThumbnail(win: BrowserWindow, root: string, navKey: string, rect: ThumbRect, scaleFactor: number): Promise<string | null> {
  if (rect.width < 1 || rect.height < 1) return null
  const img = await win.webContents.capturePage()
  if (img.isEmpty()) return null
  const sf = scaleFactor > 0 ? scaleFactor : 1
  const { width: iw, height: ih } = img.getSize()
  const x = Math.max(0, Math.round(rect.x * sf))
  const y = Math.max(0, Math.round(rect.y * sf))
  const width = Math.min(Math.round(rect.width * sf), iw - x)
  const height = Math.min(Math.round(rect.height * sf), ih - y)
  if (width < 1 || height < 1) return null
  const cropped = img.crop({ x, y, width, height })
  if (cropped.isEmpty()) return null
  const masked = maskTopBand(cropped, rect.maskTop ?? 0, rect.maskFill ?? 'window', sf, width, height)
  const buf = masked.resize({ width: THUMB_WIDTH, quality: 'good' }).toJPEG(78)
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
