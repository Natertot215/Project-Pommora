// Make the app icon full-bleed so macOS (Tahoe masks every icon into its own
// rounded tile) doesn't double-border it. The source is a beveled dark squircle
// inset on a near-black background; we find the squircle by brightness, then scale
// the whole image so the squircle (and its bevel) overflow the canvas edges, so the
// system's rounding is the only visible border. Output: build/icon.png.
//
// Needs pngjs + macOS sips. Run from repo root: node scripts/make-icon.mjs
import pngjs from 'pngjs'
import { readFileSync, writeFileSync } from 'node:fs'
import { execSync } from 'node:child_process'

const { PNG } = pngjs
const CANVAS = 1024
const OVER = 20 // overflow px per side — trimmed from 50 to size the mark nearer Swift's inset (still clears the bevel)
const THRESH = 28 // brightness above this = the squircle (below = near-black margin/shadow)

const src = PNG.sync.read(readFileSync('build/pommora-icon-src.png'))
const { width: W, height: H, data } = src
const bright = (i) => (data[i] + data[i + 1] + data[i + 2]) / 3

// 1) Bounding box + centre of the squircle (brightness-keyed, skips the dark margin).
let minX = W
let minY = H
let maxX = 0
let maxY = 0
for (let y = 0; y < H; y++) {
  for (let x = 0; x < W; x++) {
    const i = (y * W + x) * 4
    if (data[i + 3] > 200 && bright(i) > THRESH) {
      if (x < minX) minX = x
      if (x > maxX) maxX = x
      if (y < minY) minY = y
      if (y > maxY) maxY = y
    }
  }
}
const bw = maxX - minX + 1
const bh = maxY - minY + 1
const cx = (minX + maxX) / 2
const cy = (minY + maxY) / 2

// 2) Fill colour for any corner gaps — a dark squircle-interior sample (not the margin).
const fi = (Math.round(cy) * W + Math.round(minX + bw * 0.06)) * 4
const FILL = [data[fi], data[fi + 1], data[fi + 2]]

// 3) Scale the whole image so the squircle fills the canvas + overflow.
const scaleFactor = (CANVAS + OVER * 2) / Math.max(bw, bh)
const sW = Math.round(W * scaleFactor)
const sH = Math.round(H * scaleFactor)
execSync(`sips -z ${sH} ${sW} build/pommora-icon-src.png --out /tmp/_scaled.png`, {
  stdio: 'ignore',
})
const scaled = PNG.sync.read(readFileSync('/tmp/_scaled.png'))

// 4) Centre-crop to the canvas on the (scaled) squircle centre; dark fill behind.
const ox = Math.round(cx * scaleFactor) - CANVAS / 2
const oy = Math.round(cy * scaleFactor) - CANVAS / 2
const out = new PNG({ width: CANVAS, height: CANVAS })
for (let y = 0; y < CANVAS; y++) {
  for (let x = 0; x < CANVAS; x++) {
    const oi = (y * CANVAS + x) * 4
    const sx = x + ox
    const sy = y + oy
    out.data[oi + 3] = 255
    if (sx < 0 || sy < 0 || sx >= scaled.width || sy >= scaled.height) {
      out.data[oi] = FILL[0]
      out.data[oi + 1] = FILL[1]
      out.data[oi + 2] = FILL[2]
      continue
    }
    const si = (sy * scaled.width + sx) * 4
    const a = scaled.data[si + 3] / 255
    out.data[oi] = Math.round(scaled.data[si] * a + FILL[0] * (1 - a))
    out.data[oi + 1] = Math.round(scaled.data[si + 1] * a + FILL[1] * (1 - a))
    out.data[oi + 2] = Math.round(scaled.data[si + 2] * a + FILL[2] * (1 - a))
  }
}
writeFileSync('build/icon.png', PNG.sync.write(out))
console.log(
  `squircle bbox=${bw}x${bh} fill=${FILL} scale=${scaleFactor.toFixed(3)} -> build/icon.png`,
)
