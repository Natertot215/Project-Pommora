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

function repairNode(node: RawTile | RawSplit): LayoutNode {
  if (node.kind === 'tile') return { kind: 'tile', id: node.id }
  const children = node.children.map(repairNode)
  if (children.length === 1) return children[0] as LayoutNode
  const positive = node.ratios.filter((r) => r > 0)
  const ratios =
    positive.length === children.length
      ? (() => {
          const sum = positive.reduce((a, r) => a + r, 0)
          return positive.map((r) => r / sum)
        })()
      : children.map(() => 1 / children.length)
  return { kind: 'split', dir: node.dir, ratios, children }
}

export function decodeLayout(raw: unknown): SurfaceLayout | null {
  const parsed = layoutSchema.safeParse(raw)
  if (!parsed.success) return null
  return {
    bands: parsed.data.bands.map((b) => ({
      height: Math.max(MIN_BAND, b.height),
      node: repairNode(b.node)
    }))
  }
}

export function encodeLayout(layout: SurfaceLayout): unknown {
  return JSON.parse(JSON.stringify(layout))
}
