import type { GroupKind } from '@shared/types'

/** The hover "+" (add a page to this band) shows on structural Set bands only — a property or
 *  ungrouped bucket has no inferable create location (I-2 / D-5). Visual + gating for v1; the
 *  create-page routing is Nathan's creation-affordance design, deferred. */
export function bandShowsAdd(kind: GroupKind): boolean {
  return kind === 'structural-set'
}
