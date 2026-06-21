// Renderer-side connection resolution + autocomplete candidates, derived from the loaded nexus tree
// (no IPC — every page is already in memory). Title-only `[[Title]]` links resolve by normalized
// title; ranking mirrors the Swift autocomplete (prefix → exact, shortest, A–Z).
import { normalizeTitle, type LinkStatus } from '@shared/connections'
import type { NexusTree, PageTypeNode } from '@shared/types'

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

/** What the editor needs from the host: resolution + candidates + a navigate callback. */
export interface ConnectionsApi extends PageIndex {
  open: (page: ConnPage) => void
}

/** Every page in the nexus, flattened from the tree (vault → collection → [set] → pages). */
export function flattenPages(tree: NexusTree): ConnPage[] {
  const out: ConnPage[] = []
  const add = (p: { id: string; title: string; path: string; icon?: string }): void => {
    out.push({ id: p.id, title: p.title, path: p.path, icon: p.icon })
  }
  const walkVault = (v: PageTypeNode): void => {
    for (const c of v.collections) {
      c.pages.forEach(add)
      for (const s of c.sets) s.pages.forEach(add)
    }
  }
  tree.vaults.forEach(walkVault)
  tree.userSections.forEach((sec) => sec.vaults.forEach(walkVault))
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
      const matches = pages.filter((p) => normalizeTitle(p.title).startsWith(q))
      matches.sort((a, b) => {
        const exactA = normalizeTitle(a.title) === q ? 0 : 1
        const exactB = normalizeTitle(b.title) === q ? 0 : 1
        if (exactA !== exactB) return exactA - exactB
        if (a.title.length !== b.title.length) return a.title.length - b.title.length
        return a.title.localeCompare(b.title)
      })
      return matches.slice(0, limit)
    }
  }
}
