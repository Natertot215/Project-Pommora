// Resolved connection edges for one source page: scan its body, resolve each scanned
// title against the index. Pure — composes scan + resolve into the page→page edge list.

import { scanConnections } from './scan'
import { resolveTitle } from './resolve'
import type { ConnectionEdge, LinkIndex } from '@shared/connections'

/** The resolved page→page edges originating from `sourceId`'s body. */
export function connectionEdges(sourceId: string, body: string, index: LinkIndex): ConnectionEdge[] {
  return scanConnections(body).map((c) => {
    const { status, targetId } = resolveTitle(c.normalizedTitle, index)
    const edge: ConnectionEdge = {
      sourceId,
      normalizedTitle: c.normalizedTitle,
      status,
      multiplicity: c.multiplicity
    }
    if (targetId !== undefined) edge.targetId = targetId
    return edge
  })
}
