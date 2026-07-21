// Optimistic tree patches: reflect a just-written move or create in the in-memory tree INSTANTLY —
// the reload confirms canon a beat later (and heals any mismatch, since most-recent-wins). Pure: no
// fs, no React. A request that can't be resolved here returns null → the caller skips optimism and
// waits for the reload.

import type { MutateRequest, StateOrderKey } from '@shared/mutate'
import type {
  AreaNode,
  CollectionNode,
  NexusTree,
  PageNode,
  ProjectNode,
  SetNode,
  TopicNode,
} from '@shared/types'

const basename = (path: string): string => path.slice(path.lastIndexOf('/') + 1)
// '' for a root-level path — a bare slice(0, lastIndexOf) would eat the name's last character.
const parentOf = (path: string): string => {
  const i = path.lastIndexOf('/')
  return i === -1 ? '' : path.slice(0, i)
}
const joinPath = (parent: string, name: string): string => (parent ? `${parent}/${name}` : name)

/** Rewrite a moved subtree's paths: every descendant's `path` swaps the old prefix for the new.
 *  The ORIGINAL oldPath/newPath thread through the whole recursion — swapping against a child's
 *  already-swapped path would re-prepend its segment and corrupt every grandchild. */
function reparentPaths<T extends PageNode | SetNode | CollectionNode>(
  node: T,
  oldPath: string,
  newPath: string,
): T {
  const swap = (p: string): string => (p === oldPath ? newPath : newPath + p.slice(oldPath.length))
  if (node.kind === 'page') return { ...node, path: swap(node.path) }
  const set = node as SetNode
  return {
    ...set,
    path: swap(set.path),
    sets: set.sets?.map((s) => reparentPaths(s, oldPath, newPath)),
    pages: set.pages.map((pg) => ({ ...pg, path: swap(pg.path) })),
  } as T
}

/** Extract the page/set at `path` from its container; returns the pruned container tree + the node. */
function extract(
  containers: (CollectionNode | SetNode)[],
  path: string,
): { containers: (CollectionNode | SetNode)[]; node: PageNode | SetNode | null } {
  let node: PageNode | SetNode | null = null
  const next = containers.map((c) => {
    if (node) return c
    const page = c.pages.find((p) => p.path === path)
    if (page) {
      node = page
      return { ...c, pages: c.pages.filter((p) => p.path !== path) }
    }
    const set = c.sets?.find((s) => s.path === path)
    if (set) {
      node = set
      return { ...c, sets: (c.sets ?? []).filter((s) => s.path !== path) }
    }
    if (c.sets?.length) {
      const r = extract(c.sets, path)
      if (r.node) {
        node = r.node
        return { ...c, sets: r.containers as SetNode[] }
      }
    }
    return c
  })
  return { containers: next, node }
}

/** Insert `node` into the container at `parentPath` (its pages for a page, sets for a set). */
function insert(
  containers: (CollectionNode | SetNode)[],
  parentPath: string,
  node: PageNode | SetNode,
): { containers: (CollectionNode | SetNode)[]; done: boolean } {
  let done = false
  const next = containers.map((c) => {
    if (done) return c
    if (c.path === parentPath) {
      done = true
      return node.kind === 'page'
        ? { ...c, pages: [...c.pages, node] }
        : { ...c, sets: [...(c.sets ?? []), node] }
    }
    if (c.sets?.length) {
      const r = insert(c.sets, parentPath, node)
      if (r.done) {
        done = true
        return { ...c, sets: r.containers as SetNode[] }
      }
    }
    return c
  })
  return { containers: next, done }
}

/** Collections live at the top and under user sections — each root patches back independently. */
function rootsOf(
  tree: NexusTree,
): { collections: CollectionNode[]; assign: (cs: CollectionNode[]) => NexusTree }[] {
  const roots: { collections: CollectionNode[]; assign: (cs: CollectionNode[]) => NexusTree }[] = [
    { collections: tree.collections, assign: (cs) => ({ ...tree, collections: cs }) },
  ]
  tree.userSections.forEach((_, i) => {
    roots.push({
      collections: tree.userSections[i].collections,
      assign: (cs) => ({
        ...tree,
        userSections: tree.userSections.map((s, j) => (j === i ? { ...s, collections: cs } : s)),
      }),
    })
  })
  return roots
}

/** Relocate the node at `path` under `newParentPath`, updating paths. Null if unresolved or a no-op. */
export function relocateNodeInTree(
  tree: NexusTree,
  path: string,
  newParentPath: string,
): NexusTree | null {
  if (parentOf(path) === newParentPath) return null // already there
  const newPath = joinPath(newParentPath, basename(path))
  for (const root of rootsOf(tree)) {
    const pulled = extract(root.collections, path)
    if (!pulled.node) continue
    const moved = reparentPaths(pulled.node, path, newPath)
    const placed = insert(pulled.containers, newParentPath, moved)
    if (!placed.done) return null // destination not in this root — skip optimism, let the reload settle it
    return root.assign(placed.containers as CollectionNode[])
  }
  return null
}

/** Insert a just-created entity provisionally so its row (icon + rename input) appears before the
 *  confirming reload. Handles the create ops whose result lands in the tree; null → no optimism. */
export function insertCreatedInTree(
  tree: NexusTree,
  req: MutateRequest,
  created: { id: string; path: string },
): NexusTree | null {
  if (req.op === 'createContext') {
    const title = basename(created.path)
    const c = tree.contexts
    const contexts =
      req.tier === 1
        ? {
            ...c,
            areas: [
              ...c.areas,
              { id: created.id, kind: 'area' as const, title, path: created.path },
            ],
          }
        : req.tier === 2
          ? {
              ...c,
              topics: [
                ...c.topics,
                { id: created.id, kind: 'topic' as const, title, path: created.path },
              ],
            }
          : {
              ...c,
              projects: [
                ...c.projects,
                { id: created.id, kind: 'project' as const, title, path: created.path },
              ],
            }
    return { ...tree, contexts }
  }
  if (req.op === 'createContainer' && req.kind === 'collection') {
    // Only top-level collections are walked as CollectionNodes — a nested one gets no optimism
    // (returning a set-shaped node here would render the wrong kind for a beat).
    if (req.parentPath !== '') return null
    const node: CollectionNode = {
      id: created.id,
      kind: 'collection',
      title: basename(created.path),
      path: created.path,
      sets: [],
      pages: [],
    }
    return { ...tree, collections: [...tree.collections, node] }
  }
  if (req.op === 'createContainer' || req.op === 'createPage') {
    const node: PageNode | SetNode =
      req.op === 'createPage'
        ? {
            kind: 'page',
            id: created.id,
            title: basename(created.path).replace(/\.md$/, ''),
            path: created.path,
          }
        : {
            kind: 'set',
            id: created.id,
            title: basename(created.path),
            path: created.path,
            sets: [],
            pages: [],
          }
    for (const root of rootsOf(tree)) {
      const placed = insert(root.collections, req.parentPath, node)
      if (placed.done) return root.assign(placed.containers as CollectionNode[])
    }
    return null
  }
  return null
}

type TreeEntity = PageNode | SetNode | CollectionNode | AreaNode | TopicNode | ProjectNode

/** Apply `fn` to the entity at `path`, wherever it lives (a context tier, a top collection, a
 *  user section, a nested set, a page). `fn` returns the replacement — or null to remove it. */
export function updateNodeInTree(
  tree: NexusTree,
  path: string,
  fn: (node: TreeEntity) => TreeEntity | null,
): NexusTree | null {
  const c = tree.contexts
  for (const tier of ['areas', 'topics', 'projects'] as const) {
    const i = c[tier].findIndex((n) => n.path === path)
    if (i === -1) continue
    const next = fn(c[tier][i])
    const arr = [...c[tier]]
    if (next === null) arr.splice(i, 1)
    else arr[i] = next as (typeof arr)[number]
    return { ...tree, contexts: { ...c, [tier]: arr } }
  }
  for (const root of rootsOf(tree)) {
    const r = updateInContainers(root.collections, path, fn)
    if (r.found) return root.assign(r.containers as CollectionNode[])
  }
  return null
}

function updateInContainers(
  containers: (CollectionNode | SetNode)[],
  path: string,
  fn: (node: TreeEntity) => TreeEntity | null,
): { containers: (CollectionNode | SetNode)[]; found: boolean } {
  let found = false
  const out: (CollectionNode | SetNode)[] = []
  for (const cont of containers) {
    if (found) {
      out.push(cont)
      continue
    }
    if (cont.path === path) {
      found = true
      const next = fn(cont)
      if (next !== null) out.push(next as CollectionNode | SetNode)
      continue
    }
    const pi = cont.pages.findIndex((p) => p.path === path)
    if (pi !== -1) {
      found = true
      const next = fn(cont.pages[pi])
      const pages = [...cont.pages]
      if (next === null) pages.splice(pi, 1)
      else pages[pi] = next as PageNode
      out.push({ ...cont, pages })
      continue
    }
    if (cont.sets?.length) {
      const r = updateInContainers(cont.sets, path, fn)
      if (r.found) {
        found = true
        out.push({ ...cont, sets: r.containers as SetNode[] })
        continue
      }
    }
    out.push(cont)
  }
  return { containers: out, found }
}

/** Rename the entity at `path` (filename = title): title, path, and descendant paths update.
 *  Only valid after the write succeeded — a collision fails main-side and never patches. */
export function renameNodeInTree(tree: NexusTree, path: string, newName: string): NexusTree | null {
  const parent = parentOf(path)
  return updateNodeInTree(tree, path, (node) => {
    if (node.kind === 'page')
      return { ...node, title: newName, path: joinPath(parent, `${newName}.md`) }
    if (node.kind === 'collection' || node.kind === 'set')
      return { ...reparentPaths(node, path, joinPath(parent, newName)), title: newName }
    return { ...node, title: newName, path: joinPath(parent, newName) }
  })
}

/** Remove the entity at `path` (a just-confirmed delete). */
export function removeNodeInTree(tree: NexusTree, path: string): NexusTree | null {
  return updateNodeInTree(tree, path, () => null)
}

/** Patch renderer-knowable display fields on the entity at `path` (icon / heading-icon chrome). */
export function patchNodeInTree(
  tree: NexusTree,
  path: string,
  patch: { icon?: string | null; headingIconHidden?: boolean },
): NexusTree | null {
  return updateNodeInTree(tree, path, (node) => {
    const next = { ...node }
    if ('icon' in patch) {
      if (patch.icon === null || patch.icon === undefined) delete next.icon
      else next.icon = patch.icon
    }
    if (patch.headingIconHidden !== undefined) next.headingIconHidden = patch.headingIconHidden
    return next
  })
}

/** Stable order-by-id: listed ids in `order` order, unknown ids after in their current order. */
function byOrder<T extends { id: string }>(arr: T[], order: string[]): T[] {
  const pos = new Map(order.map((id, i) => [id, i]))
  return [...arr].sort(
    (a, b) =>
      (pos.get(a.id) ?? Number.MAX_SAFE_INTEGER) - (pos.get(b.id) ?? Number.MAX_SAFE_INTEGER),
  )
}

/** Reorder a top-level group (top Collections or a context tier) to the given id order. */
export function reorderTopInTree(tree: NexusTree, key: StateOrderKey, order: string[]): NexusTree {
  const c = tree.contexts
  switch (key) {
    case 'collection_order':
      return { ...tree, collections: byOrder(tree.collections, order) }
    case 'area_order':
      return { ...tree, contexts: { ...c, areas: byOrder(c.areas, order) } }
    case 'topic_order':
      return { ...tree, contexts: { ...c, topics: byOrder(c.topics, order) } }
    case 'project_order':
      return { ...tree, contexts: { ...c, projects: byOrder(c.projects, order) } }
  }
}

/** Reorder a container's child containers ('' = the vault's top collections). */
export function reorderChildrenInTree(
  tree: NexusTree,
  parentPath: string,
  order: string[],
): NexusTree | null {
  if (parentPath === '') return { ...tree, collections: byOrder(tree.collections, order) }
  return updateNodeInTree(tree, parentPath, (node) =>
    node.kind === 'collection' || node.kind === 'set'
      ? { ...node, sets: byOrder(node.sets ?? [], order) }
      : node,
  )
}
