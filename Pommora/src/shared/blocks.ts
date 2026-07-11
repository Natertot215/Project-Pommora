// The block document — the host-agnostic contract a BlockHost carries (D-2/D-3):
// a SurfacePM layout tree under `layout`, tagged-union tile payloads under
// `blocks` (the Swift-reserved key, now modeled), and the host lock under
// `blocks_locked` (G-3). Entries ride RAW through reads and writes so foreign or
// future tile types survive rewrites (E-1); `knownBlock` is the read lens typing
// the entries this build understands. The layout's raw wire schemas live here so
// main and the renderer validate one shape; the renderer's SurfacePM codec owns
// the repair pass on top.

import { z } from 'zod'
import type { ViewButton, ViewStyle } from './types'

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

/** Per-tile chassis style (G-14): borderless hides the border until you reach for
 *  it — border/handle hover, drag, resize — and a locked host pins it hidden. */
export type BlockStyle = 'bordered' | 'borderless'
const styleField = z.enum(['bordered', 'borderless']).optional().catch(undefined)

/** Markdown block: body lives in `<id>.md` inside the host's own folder (D-11). */
export interface MarkdownBlockEntry {
  id: string
  type: 'markdown'
  style?: BlockStyle
}

/** Page embed (H-2): a scrollable, editable window onto the real page. `banner` /
 *  `title` are the chrome toggles (absent = shown, per G-4). */
export interface PageBlockEntry {
  id: string
  type: 'page'
  page_id: string
  style?: BlockStyle
  banner?: boolean
  title?: boolean
}

/** One view a view-embed tile carries (D-5a): its own source container + the copied
 *  config (D-12: snapshotted at pick time, never synced). The config's `id` is
 *  payload-local, minted at copy — never the source view's id and never the
 *  DEFAULT_VIEW_ID mint sentinel; both are live keys outside the payload. */
export interface EmbeddedView {
  source_id: string
  config?: unknown
}

/** View embed (H-4/H-5): `views` is the switcher's list; `active` indexes into it. The header
 *  chrome follows the page embed's absent-=-shown convention (G-4) — `title` hides the title row,
 *  `icon` the view icon beside it — and the switcher reuses the container presentation vocabulary
 *  (`view_button` icon/labeled pills, `view_style` toolbar/dropdown), defaulting labeled + toolbar. */
export interface ViewBlockEntry {
  id: string
  type: 'view'
  views: EmbeddedView[]
  active?: number
  style?: BlockStyle
  display_title?: string
  title?: boolean
  icon?: boolean
  /** Heading level for the title (1–6, absent = the #### default) — sized by markdownPM's own `.md-hN`. */
  title_level?: number
  view_button?: ViewButton
  view_style?: ViewStyle
}

export type BlockEntry = MarkdownBlockEntry | PageBlockEntry | ViewBlockEntry

const markdownEntry = z.looseObject({ id: z.string().min(1), type: z.literal('markdown'), style: styleField })
const pageEntry = z.looseObject({
  id: z.string().min(1),
  type: z.literal('page'),
  page_id: z.string().min(1),
  style: styleField,
  banner: z.boolean().optional().catch(undefined),
  title: z.boolean().optional().catch(undefined)
})
// Elements are looseObjects too — a strict element shape would strip nested foreign keys (E-1).
const embeddedView = z.looseObject({
  source_id: z.string().min(1),
  config: z.unknown().optional() // zod 4 treats a bare unknown() key as required
})
const viewEntry = z.looseObject({
  id: z.string().min(1),
  type: z.literal('view'),
  views: z.array(embeddedView).min(1),
  active: z.number().int().nonnegative().optional().catch(undefined),
  style: styleField,
  display_title: z.string().optional().catch(undefined),
  title: z.boolean().optional().catch(undefined),
  icon: z.boolean().optional().catch(undefined),
  title_level: z.number().int().min(1).max(6).optional().catch(undefined),
  view_button: z.enum(['icon', 'labeled']).optional().catch(undefined),
  view_style: z.enum(['dropdown', 'toolbar']).optional().catch(undefined)
})
const knownEntry = z.union([markdownEntry, pageEntry, viewEntry])

/** One node of a native returning drill menu (renderer-built — main has no tree).
 *  A node with `pick` resolves the menu; a node with `submenu` drills. */
export interface DrillPickItem<T> {
  label: string
  /** Leading glyph — locations carry their entity icon, views their view icon. */
  icon?: string
  pick?: T
  submenu?: Array<DrillPickItem<T>>
  /** Renders in the pane's pinned BottomRow instead of the scrolling body (+ Custom). */
  footer?: boolean
}

/** The Link Page drill resolves a page id. */
export type PagePickerItem = DrillPickItem<string>

/** The Link View drill resolves a source view to copy, or + Custom on a container (G-9/D-5a). */
export interface ViewPick {
  source_id: string
  view_id?: string
  custom?: boolean
}
export type ViewPickerItem = DrillPickItem<ViewPick>

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

/** Main-side gate for a blocks:save patch (the views:save convention) — a shape CHECK
 *  only: the ORIGINAL values are what get written, since zod's parse output strips
 *  unknown keys and foreign keys must survive (E-1). Returns the problem, or null. */
export function blockPatchProblem(patch: BlockDocPatch): string | null {
  if ('layout' in patch && !rawLayoutSchema.safeParse(patch.layout).success) return 'Malformed layout.'
  if ('blocks' in patch && !Array.isArray(patch.blocks)) return 'blocks must be an array.'
  if ('locked' in patch && typeof patch.locked !== 'boolean') return 'locked must be a boolean.'
  return null
}
