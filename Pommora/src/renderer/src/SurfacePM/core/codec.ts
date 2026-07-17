// The layout tree's persistence codec. Decoding REPAIRS rather than rejects —
// drifted row ratios renormalize, ratio/child count mismatches rebuild uniform,
// single-child splits collapse, tile heights floor, duplicate tile ids drop
// (later occurrences; the space closes up) — so a hand-edited or foreign-written
// tree renders sanely instead of blanking the host. Unknown keys and the
// surrounding block document are the block-doc layer's concern, not this codec's.

import { rawLayoutSchema, type RawColumn, type RawRow, type RawTile } from '@shared/blocks'
import type { LayoutNode, SurfaceLayout, TileLeaf } from './model'

const MIN_TILE = 32

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
  const ratios = (() => {
    if (positive.length === kept.length) {
      const sum = positive.reduce((a, r) => a + r, 0)
      const norm = positive.map((r) => r / sum)
      // Extreme inputs overflow the sum (→ Infinity → 0-ratios) or underflow a
      // share — a "repaired" tree validateLayout would reject. Uniform instead.
      if (norm.every((r) => Number.isFinite(r) && r > 0)) return norm
    }
    return kept.map(() => 1 / kept.length)
  })()
  return { kind: 'row', ratios, children }
}

// One malformed node must never wipe the document: when the strict parse fails,
// salvage — coerce a broken tile height (a hand-edit or foreign writer's null /
// NaN, which zod 4 rejects outright) to the floor, drop unrecognizable nodes,
// keep every survivor. Repair-not-reject applies to the WHOLE decode, not just
// ratios — files are hand-editable by design.
type SalvagedNode = RawTile | RawRow | RawColumn

function salvageNode(raw: unknown): SalvagedNode | null {
  if (typeof raw !== 'object' || raw === null) return null
  const node = raw as Record<string, unknown>
  if (node.kind === 'tile') {
    if (typeof node.id !== 'string' || node.id.length === 0) return null
    const h = typeof node.h === 'number' && Number.isFinite(node.h) ? node.h : MIN_TILE
    return { kind: 'tile', id: node.id, h }
  }
  if ((node.kind !== 'row' && node.kind !== 'column') || !Array.isArray(node.children)) return null
  const children = node.children.map(salvageNode).filter((c): c is SalvagedNode => c !== null)
  if (children.length === 0) return null
  if (node.kind === 'column') return { kind: 'column', children }
  const ratios = Array.isArray(node.ratios)
    ? node.ratios.filter((r): r is number => typeof r === 'number' && Number.isFinite(r))
    : []
  return { kind: 'row', ratios, children }
}

function salvageLayout(raw: unknown): { bands: Array<{ node: SalvagedNode }> } | null {
  const bands = (raw as { bands?: unknown } | null)?.bands
  if (!Array.isArray(bands)) return null
  return {
    bands: bands
      .map((b) => salvageNode((b as { node?: unknown } | null)?.node))
      .filter((n): n is SalvagedNode => n !== null)
      .map((node) => ({ node })),
  }
}

export function decodeLayout(raw: unknown): SurfaceLayout | null {
  const parsed = rawLayoutSchema.safeParse(raw)
  const data = parsed.success ? parsed.data : salvageLayout(raw)
  if (!data) return null
  const seen = new Set<string>()
  const bands = data.bands.flatMap((b) => {
    const node = repairNode(b.node, seen)
    return node ? [{ node }] : []
  })
  return { bands }
}

export function encodeLayout(layout: SurfaceLayout): unknown {
  return JSON.parse(JSON.stringify(layout))
}
