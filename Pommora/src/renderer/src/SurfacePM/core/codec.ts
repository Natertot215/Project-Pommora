// The layout tree's persistence codec. Decoding REPAIRS rather than rejects —
// drifted row ratios renormalize, ratio/child count mismatches rebuild uniform,
// single-child splits collapse, tile heights floor, duplicate tile ids drop
// (later occurrences; the space closes up) — so a hand-edited or foreign-written
// tree renders sanely instead of blanking the host. Unknown keys and the
// surrounding block document are the block-doc layer's concern, not this codec's.

import { z } from 'zod'
import type { LayoutNode, SurfaceLayout, TileLeaf } from './model'

const MIN_TILE = 32

interface RawTile {
  kind: 'tile'
  id: string
  h: number
}

interface RawRow {
  kind: 'row'
  ratios: number[]
  children: Array<RawTile | RawRow | RawColumn>
}

interface RawColumn {
  kind: 'column'
  children: Array<RawTile | RawRow | RawColumn>
}

const tileSchema: z.ZodType<RawTile> = z.object({
  kind: z.literal('tile'),
  id: z.string().min(1),
  h: z.number()
})

const rowSchema: z.ZodType<RawRow> = z.lazy(() =>
  z.object({
    kind: z.literal('row'),
    ratios: z.array(z.number()),
    children: z.array(z.union([tileSchema, rowSchema, columnSchema])).min(1)
  })
)

const columnSchema: z.ZodType<RawColumn> = z.lazy(() =>
  z.object({
    kind: z.literal('column'),
    children: z.array(z.union([tileSchema, rowSchema, columnSchema])).min(1)
  })
)

const layoutSchema = z.object({
  bands: z.array(z.object({ node: z.union([tileSchema, rowSchema, columnSchema]) }))
})

function repairNode(node: RawTile | RawRow | RawColumn, seen: Set<string>): LayoutNode | null {
  if (node.kind === 'tile') {
    if (seen.has(node.id)) return null
    seen.add(node.id)
    return { kind: 'tile', id: node.id, h: Math.max(MIN_TILE, node.h) } satisfies TileLeaf
  }

  const kept: Array<{ child: LayoutNode; ratio: number | undefined }> = []
  node.children.forEach((raw, i) => {
    const child = repairNode(raw, seen)
    if (child) kept.push({ child, ratio: node.kind === 'row' ? node.ratios[i] : undefined })
  })
  if (kept.length === 0) return null
  if (kept.length === 1) return (kept[0] as { child: LayoutNode }).child

  const children = kept.map((k) => k.child)
  if (node.kind === 'column') return { kind: 'column', children }

  const raw = kept.map((k) => k.ratio)
  const positive = raw.filter((r): r is number => typeof r === 'number' && r > 0)
  const ratios =
    positive.length === kept.length
      ? (() => {
          const sum = positive.reduce((a, r) => a + r, 0)
          return positive.map((r) => r / sum)
        })()
      : kept.map(() => 1 / kept.length)
  return { kind: 'row', ratios, children }
}

export function decodeLayout(raw: unknown): SurfaceLayout | null {
  const parsed = layoutSchema.safeParse(raw)
  if (!parsed.success) return null
  const seen = new Set<string>()
  const bands = parsed.data.bands.flatMap((b) => {
    const node = repairNode(b.node, seen)
    return node ? [{ node }] : []
  })
  return { bands }
}

export function encodeLayout(layout: SurfaceLayout): unknown {
  return JSON.parse(JSON.stringify(layout))
}
