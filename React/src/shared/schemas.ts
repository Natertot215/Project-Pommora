// zod schemas for the JSON sidecars. Each schema IS the codec AND the type
// (`z.infer`) — one source of truth, replacing Swift's hand-written Codable +
// CodingKeys + a separate struct per entity.
//
// DEVIATIONS FROM SWIFT (enhancements):
// 1. `z.looseObject` ⇒ FOREIGN keys survive a rewrite. Swift's Codable silently
//    dropped unknown keys on JSON sidecars (only pages preserved foreign data);
//    this closes that cloud-sync / agent-legibility data-loss gap.
// 2. Shared builders (baseSidecar, contextBase) collapse what Swift expressed as
//    three byte-identical context managers/schemas — one source, DRY.
// 3. The schema is simultaneously runtime validation and the static type, so they
//    can never drift (Swift maintained the struct and the Codable impl separately).

import { z } from 'zod'
import { AREA_COLORS } from './types'
import { savedView } from './views'

const ulidList = z.array(z.string()).optional()

/** Fields shared by every folder sidecar. Loose ⇒ unknown keys are retained. */
const baseSidecar = z.looseObject({
  id: z.string(),
  icon: z.string().optional(),
  schema_version: z.number().optional(),
  modified_at: z.string().optional()
})

// `_pagecollection.json` is the schema-bearing TOP tier (a top Collection has no parent).
// The schema lives in `properties` (Swift's key); loose per-def, so one malformed def never
// sinks the whole read (per-def codec is parseDefinitions, main/properties/schema.ts).
export const pageCollectionSidecar = baseSidecar.extend({
  banner: z.string().optional(),
  set_order: ulidList,
  page_order: ulidList,
  properties: z.array(z.looseObject({})).optional(),
  default_sort: z.looseObject({}).optional(),
  views: z.array(savedView).optional(),
  open_in: z.enum(['compact', 'window']).optional()
})
export type PageCollectionSidecar = z.infer<typeof pageCollectionSidecar>

// `_pageset.json` is the RECURSIVE tier at any depth. `parent_id` is the immediate parent
// (a Collection at depth-1, a Set deeper). `set_order` orders child Sets; `views`/`banner`
// apply only at depth-1 (ignored deeper — read leniently, never seeded).
export const pageSetSidecar = baseSidecar.extend({
  parent_id: z.string().optional(),
  page_order: ulidList,
  set_order: ulidList,
  banner: z.string().optional(),
  views: z.array(savedView).optional()
})
export type PageSetSidecar = z.infer<typeof pageSetSidecar>

/** Areas/Topics/Projects share tier + the reserved `blocks` array (which rides as a
 *  foreign key — not modeled, per "catch up to Swift, don't go ahead"). */
const contextBase = baseSidecar.extend({
  tier: z.number(),
  // Nexus-relative POSIX path to this context's banner image (a per-entity assets file).
  banner: z.string().optional()
})
export const topicSidecar = contextBase
export const projectSidecar = contextBase
// color validates against the shared AreaColor palette but degrades to undefined on an
// unknown value (lenient — an unrecognized color never fails the whole sidecar).
export const areaSidecar = contextBase.extend({
  color: z.enum(AREA_COLORS).optional().catch(undefined)
})
export type TopicSidecar = z.infer<typeof topicSidecar>
export type ProjectSidecar = z.infer<typeof projectSidecar>
export type AreaSidecar = z.infer<typeof areaSidecar>

/** Agenda config sidecar (`_taskconfig.json` / `_eventconfig.json`) — a property schema
 *  for its agenda items. property_definitions stay loose (per-def codec is parseDefinitions);
 *  views + default_sort ride through untouched. */
export const agendaConfigSidecar = baseSidecar.extend({
  property_definitions: z.array(z.looseObject({})).optional(),
  views: z.array(z.looseObject({})).optional(),
  default_sort: z.looseObject({}).optional()
})
export type AgendaConfigSidecar = z.infer<typeof agendaConfigSidecar>

/** Page (.md) frontmatter. tier1/2/3 are BARE ULID arrays at the root (NOT $ctx-tagged
 *  — that shape is only for user/agenda properties); `properties` maps property-id to
 *  an encoded PropertyValue. Loose ⇒ foreign keys ride through. */
export const pageFrontmatter = z.looseObject({
  id: z.string(),
  icon: z.string().optional(),
  tier1: z.array(z.string()).optional(),
  tier2: z.array(z.string()).optional(),
  tier3: z.array(z.string()).optional(),
  properties: z.record(z.string(), z.unknown()).optional(),
  created_at: z.string().optional(),
  modified_at: z.string().optional(),
  folded_headings: z.array(z.string()).optional(),
  cover: z.string().optional()
})
export type PageFrontmatter = z.infer<typeof pageFrontmatter>

/** The modeled top-level page keys a FULL page rewrite governs (set if present, else
 *  delete). Partial updates pass a narrower key set so they touch nothing else. */
export const PAGE_MODELED_KEYS = [
  'id',
  'icon',
  'tier1',
  'tier2',
  'tier3',
  'properties',
  'created_at',
  'modified_at',
  'folded_headings',
  'cover'
] as const
