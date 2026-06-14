import { create } from 'zustand'
import type { NexusTree } from '@shared/types'

interface SessionState {
  status: 'idle' | 'loading' | 'ready' | 'error'
  tree: NexusTree | null
  error?: string
  load: () => Promise<void>
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
  }
}))
