// The layout tree's persistence codec. Decoding REPAIRS rather than rejects —
// drifted ratios renormalize, ratio/child count mismatches rebuild uniform,
// single-child splits collapse, band heights floor — so a hand-edited or
// foreign-written tree renders sanely instead of blanking the host. Unknown
// keys and the surrounding block document are the block-doc layer's concern,
// not this codec's.

import { z } from 'zod'
import type { LayoutNode, SurfaceLayout } from './model'

const MIN_BAND = 80

interface RawTile {
  kind: 'tile'
  id: string
}

interface RawSplit {
  kind: 'split'
  dir: 'row' | 'column'
  ratios: number[]
  children: Array<RawTile | RawSplit>
}

const tileSchema: z.ZodType<RawTile> = z.object({ kind: z.literal('tile'), id: z.string().min(1) })

const splitSchema: z.ZodType<RawSplit> = z.lazy(() =>
  z.object({
    kind: z.literal('split'),
    dir: z.enum(['row', 'column']),
    ratios: z.array(z.number()),
    children: z.array(z.union([tileSchema, splitSchema])).min(1)
  })
)

const layoutSchema = z.object({
  bands: z.array(z.object({ height: z.number(), node: z.union([tileSchema, splitSchema]) }))
})

/** Repair one node, dropping any tile whose id was already seen — a duplicate
 *  leaf would make ops (first occurrence) and geometry (last, Map-keyed by id)
 *  disagree about which region a tile owns. The payload still renders exactly
 *  once; siblings absorb the dropped space through the usual collapse. */
function repairNode(node: RawTile | RawSplit, seen: Set<string>): LayoutNode | null {
  if (node.kind === 'tile') {
    if (seen.has(node.id)) return null
    seen.add(node.id)
    return { kind: 'tile', id: node.id }
  }
  const pairs: Array<{ repaired: LayoutNode; ratio: number | undefined }> = []
  node.children.forEach((child, i) => {
    const repaired = repairNode(child, seen)
    if (repaired) pairs.push({ repaired, ratio: node.ratios[i] })
  })
  if (pairs.length === 0) return null
  if (pairs.length === 1) return (pairs[0] as { repaired: LayoutNode }).repaired

  const kept = pairs.map((p) => p.ratio)
  const positive = kept.filter((r): r is number => typeof r === 'number' && r > 0)
  const ratios =
    positive.length === pairs.length
      ? (() => {
          const sum = positive.reduce((a, r) => a + r, 0)
          return positive.map((r) => r / sum)
        })()
      : pairs.map(() => 1 / pairs.length)
  return { kind: 'split', dir: node.dir, ratios, children: pairs.map((p) => p.repaired) }
}

export function decodeLayout(raw: unknown): SurfaceLayout | null {
  const parsed = layoutSchema.safeParse(raw)
  if (!parsed.success) return null
  const seen = new Set<string>()
  const bands = parsed.data.bands.flatMap((b) => {
    const node = repairNode(b.node, seen)
    return node ? [{ height: Math.max(MIN_BAND, b.height), node }] : []
  })
  return { bands }
}

export function encodeLayout(layout: SurfaceLayout): unknown {
  return JSON.parse(JSON.stringify(layout))
}
