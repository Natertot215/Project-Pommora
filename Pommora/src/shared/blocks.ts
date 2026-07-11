// The block document — the host-agnostic contract a BlockHost carries (D-2/D-3):
// a SurfacePM layout tree under `layout`, tagged-union tile payloads under
// `blocks` (the Swift-reserved key, now modeled), and the host lock under
// `blocks_locked` (G-3). Entries ride RAW through reads and writes so foreign or
// future tile types survive rewrites (E-1); `knownBlock` is the read lens typing
// the entries this build understands. The layout's raw wire schemas live here so
// main and the renderer validate one shape; the renderer's SurfacePM codec owns
// the repair pass on top.

import { z } from 'zod'

export interface RawTile {
  kind: 'tile'
  id: string
  h: number
}

export interface RawRow {
  kind: 'row'
  ratios: number[]
  children: Array<RawTile | RawRow | RawColumn>
}

export interface RawColumn {
  kind: 'column'
  children: Array<RawTile | RawRow | RawColumn>
}

export const rawTileSchema: z.ZodType<RawTile> = z.object({
  kind: z.literal('tile'),
  id: z.string().min(1),
  h: z.number()
})

export const rawRowSchema: z.ZodType<RawRow> = z.lazy(() =>
  z.object({
    kind: z.literal('row'),
    ratios: z.array(z.number()),
    children: z.array(z.union([rawTileSchema, rawRowSchema, rawColumnSchema])).min(1)
  })
)

export const rawColumnSchema: z.ZodType<RawColumn> = z.lazy(() =>
  z.object({
    kind: z.literal('column'),
    children: z.array(z.union([rawTileSchema, rawRowSchema, rawColumnSchema])).min(1)
  })
)

export const rawLayoutSchema = z.object({
  bands: z.array(z.object({ node: z.union([rawTileSchema, rawRowSchema, rawColumnSchema]) }))
})

/** The BlockHost seam (D-2): which entity's sidecar holds the doc. The homepage
 *  singleton is the dev host (G-12); real hosts extend this union. */
export type BlockHostRef = { kind: 'homepage' }

export function coerceBlockHost(raw: unknown): BlockHostRef | null {
  return typeof raw === 'object' && raw !== null && (raw as { kind?: unknown }).kind === 'homepage'
    ? { kind: 'homepage' }
    : null
}

/** Markdown block: body lives in `<id>.md` inside the host's own folder (D-11). */
export interface MarkdownBlockEntry {
  id: string
  type: 'markdown'
}

export interface PageBlockEntry {
  id: string
  type: 'page'
  page_id: string
}

export interface ViewBlockEntry {
  id: string
  type: 'view'
  view_id?: string
  source_id?: string
}

export type BlockEntry = MarkdownBlockEntry | PageBlockEntry | ViewBlockEntry

const markdownEntry = z.looseObject({ id: z.string().min(1), type: z.literal('markdown') })
const pageEntry = z.looseObject({ id: z.string().min(1), type: z.literal('page'), page_id: z.string().min(1) })
const viewEntry = z.looseObject({
  id: z.string().min(1),
  type: z.literal('view'),
  view_id: z.string().optional(),
  source_id: z.string().optional()
})
const knownEntry = z.union([markdownEntry, pageEntry, viewEntry])

/** Type one raw `blocks[]` entry, or null for shapes this build doesn't know —
 *  the caller keeps the raw value either way (E-1: never strip, render inert). */
export function knownBlock(raw: unknown): BlockEntry | null {
  const parsed = knownEntry.safeParse(raw)
  return parsed.success ? (parsed.data as BlockEntry) : null
}

/** The doc as main hands it across IPC — layout + entries stay raw; the renderer
 *  decodes the layout (repairing) and lenses the entries. */
export interface BlockDoc {
  layout: unknown
  blocks: unknown[]
  locked: boolean
}

/** A partial write — only the present keys touch the sidecar. */
export interface BlockDocPatch {
  layout?: unknown
  blocks?: unknown[]
  locked?: boolean
}

export type BlocksGetResult = { ok: true; doc: BlockDoc } | { ok: false; error: string }
export type BlocksSaveResult = { ok: true } | { ok: false; error: string }
