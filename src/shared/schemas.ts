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

const ulidList = z.array(z.string()).optional()

/** Fields shared by every folder sidecar. Loose ⇒ unknown keys are retained. */
const baseSidecar = z.looseObject({
  id: z.string(),
  icon: z.string().optional(),
  schema_version: z.number().optional(),
  modified_at: z.string().optional()
})

export const pageTypeSidecar = baseSidecar.extend({
  collection_order: ulidList,
  page_order: ulidList,
  // Loose at the sidecar level so one malformed def never sinks the whole type read;
  // the per-def codec + normalization is `parseDefinitions` (main/properties/schema.ts),
  // and the authoritative model is `propertyDefinition` (shared/properties.ts).
  property_definitions: z.array(z.looseObject({})).optional()
})
export type PageTypeSidecar = z.infer<typeof pageTypeSidecar>

export const pageCollectionSidecar = baseSidecar.extend({
  type_id: z.string().optional(),
  vault_id: z.string().optional(), // legacy fallback for type_id
  set_order: ulidList,
  page_order: ulidList
})
export type PageCollectionSidecar = z.infer<typeof pageCollectionSidecar>

export const pageSetSidecar = baseSidecar.extend({
  collection_id: z.string().optional(),
  page_order: ulidList
})
export type PageSetSidecar = z.infer<typeof pageSetSidecar>

/** Areas/Topics/Projects share tier + the reserved `blocks` array (which rides as a
 *  foreign key — not modeled, per "catch up to Swift, don't go ahead"). */
const contextBase = baseSidecar.extend({
  tier: z.number()
})
export const topicSidecar = contextBase
export const projectSidecar = contextBase
export const areaSidecar = contextBase.extend({ color: z.string().optional() })
export type TopicSidecar = z.infer<typeof topicSidecar>
export type ProjectSidecar = z.infer<typeof projectSidecar>
export type AreaSidecar = z.infer<typeof areaSidecar>

/** Page (.md) frontmatter. tier1/2/3 are BARE ULID arrays at the root (NOT $rel-tagged
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
