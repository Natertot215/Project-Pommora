import type { CollectionNode, NexusTree, SetNode } from '@shared/types'
import { navKey } from './navRecents'

/** Every navKey that currently exists in the tree — the complete set an entity's thumbnail can be
 *  keyed to. Capture fires only on a SelectionState (`useNavThumbnails`), whose kinds are exactly
 *  homepage · context · collection · set · page, so enumerating those from the tree is the closed set:
 *  existence-pruning against it drops only a deleted entity's orphan, never a live cover. Contexts
 *  (areas/topics/projects) all select as `context:<id>`, so their key comes from navKey's context
 *  member — never their node kind. */
export function existingNavKeys(tree: NexusTree): string[] {
  const keys: string[] = ['homepage'] // the id-less singleton — navKey({ kind: 'homepage' })
  const walk = (c: CollectionNode | SetNode): void => {
    keys.push(
      c.kind === 'collection'
        ? navKey({ kind: 'collection', id: c.id })
        : navKey({ kind: 'set', id: c.id, path: c.path }),
    )
    for (const p of c.pages) keys.push(navKey({ kind: 'page', id: p.id, path: p.path }))
    for (const s of c.sets ?? []) walk(s)
  }
  for (const c of tree.collections) walk(c)
  for (const u of tree.userSections) for (const c of u.collections) walk(c)
  for (const ctx of [...tree.contexts.areas, ...tree.contexts.topics, ...tree.contexts.projects])
    keys.push(navKey({ kind: 'context', id: ctx.id }))
  return keys
}
