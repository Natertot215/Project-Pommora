import { create } from 'zustand'
import type { NexusTree, PageDetail, SelectionState } from '@shared/types'

/** What a sidebar row hands to `select` — mirrors the selectable SelectionState cases. */
export type SelectTarget =
  | { kind: 'vault'; id: string }
  | { kind: 'page'; id: string; path: string }

/** Lifecycle of the on-demand page-detail fetch for the current page selection. */
type PageStatus = 'idle' | 'loading' | 'ready' | 'error'

interface SessionState {
  status: 'idle' | 'loading' | 'ready' | 'error'
  tree: NexusTree | null
  error?: string
  load: () => Promise<void>

  selection: SelectionState
  pageStatus: PageStatus
  pageDetail: PageDetail | null
  pageError?: string
  select: (target: SelectTarget) => Promise<void>
}

export const useSession = create<SessionState>((set) => ({
  status: 'idle',
  tree: null,
  error: undefined,
  load: async () => {
    set({ status: 'loading', error: undefined })
    try {
      const res = await window.nexus.open()
      if (res.ok) set({ status: 'ready', tree: res.tree })
      else set({ status: 'error', error: res.error })
    } catch (e) {
      // ipcRenderer.invoke rejects if the bridge/handler is absent — route it
      // to the designed error state instead of hanging on 'loading'.
      set({ status: 'error', error: e instanceof Error ? e.message : String(e) })
    }
  },

  selection: { kind: 'none' },
  pageStatus: 'idle',
  pageDetail: null,
  pageError: undefined,
  select: async (target) => {
    switch (target.kind) {
      case 'vault':
        // Vault detail is a view rendered from the already-loaded tree — no fetch.
        set({
          selection: { kind: 'vault', id: target.id },
          pageStatus: 'idle',
          pageDetail: null,
          pageError: undefined
        })
        return
      case 'page': {
        set({
          selection: { kind: 'page', id: target.id, path: target.path },
          pageStatus: 'loading',
          pageDetail: null,
          pageError: undefined
        })
        try {
          const res = await window.nexus.openPage(target.path)
          if (res.ok) set({ pageStatus: 'ready', pageDetail: res.page })
          else set({ pageStatus: 'error', pageError: res.error })
        } catch (e) {
          set({ pageStatus: 'error', pageError: e instanceof Error ? e.message : String(e) })
        }
        return
      }
    }
  }
}))
