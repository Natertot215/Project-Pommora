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
  // property_definitions are modeled in detail in Phase 4; for now they ride as
  // loose array members so they round-trip untouched.
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
