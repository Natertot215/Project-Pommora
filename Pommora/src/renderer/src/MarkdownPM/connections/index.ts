import { normalizeTitle, type LinkStatus } from '@shared/connections'
import type { CollectionNode, NexusTree, SetNode } from '@shared/types'

export interface ConnPage {
  id: string
  title: string
  path: string
  icon?: string
}

export interface ConnResolution {
  status: LinkStatus
  page?: ConnPage
}

export interface PageIndex {
  resolve: (rawTitle: string) => ConnResolution
  candidates: (query: string, limit?: number) => ConnPage[]
}

export interface ConnectionsApi extends PageIndex {
  open: (page: ConnPage) => void
}

export function flattenPages(tree: NexusTree): ConnPage[] {
  const out: ConnPage[] = []
  const add = (p: { id: string; title: string; path: string; icon?: string }): void => {
    out.push({ id: p.id, title: p.title, path: p.path, icon: p.icon })
  }
  const walkSet = (s: SetNode): void => {
    s.pages.forEach(add)
    for (const sub of s.sets ?? []) walkSet(sub)
  }
  const walkCollection = (c: CollectionNode): void => {
    c.pages.forEach(add)
    for (const s of c.sets) walkSet(s)
  }
  ;(tree.collections ?? []).forEach(walkCollection)
  tree.userSections.forEach((sec) => (sec.collections ?? []).forEach(walkCollection))
  return out
}

export function buildPageIndex(pages: ConnPage[]): PageIndex {
  const byTitle = new Map<string, ConnPage[]>()
  for (const p of pages) {
    const key = normalizeTitle(p.title)
    if (!key) continue
    const holders = byTitle.get(key)
    if (holders) holders.push(p)
    else byTitle.set(key, [p])
  }
  return {
    resolve(rawTitle) {
      const holders = byTitle.get(normalizeTitle(rawTitle))
      if (!holders || holders.length === 0) return { status: 'phantom' }
      if (holders.length > 1) return { status: 'ambiguous' }
      return { status: 'resolved', page: holders[0] }
    },
    candidates(query, limit = 20) {
      const q = normalizeTitle(query)
      if (!q) return []
      return pages
        .map((p) => ({ p, norm: normalizeTitle(p.title) }))
        .filter((x) => x.norm.startsWith(q))
        .sort((a, b) => {
          const exact = (a.norm === q ? 0 : 1) - (b.norm === q ? 0 : 1)
          if (exact !== 0) return exact
          if (a.p.title.length !== b.p.title.length) return a.p.title.length - b.p.title.length
          return a.p.title.localeCompare(b.p.title)
        })
        .slice(0, limit)
        .map((x) => x.p)
    }
  }
}
