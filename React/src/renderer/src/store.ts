import { create } from 'zustand'
import type { NexusTree, PageDetail, SelectionState } from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind } from '@shared/mutate'
import { reconcileSelection } from './selection'
import { applyAccent } from './design-system/accent'

// Sidebar width bounds mirror the Swift app (ContentView `navigationSplitViewColumnWidth(min:180, ideal:240, max:330)`).
const SIDEBAR_MIN = 180
const SIDEBAR_MAX = 330
const SIDEBAR_DEFAULT = 240
const SIDEBAR_WIDTH_KEY = 'pommora.sidebarWidth'
const clampSidebar = (w: number): number => Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, Math.round(w)))
function readStoredSidebarWidth(): number {
  try {
    const n = Number(localStorage.getItem(SIDEBAR_WIDTH_KEY))
    return Number.isFinite(n) && n > 0 ? clampSidebar(n) : SIDEBAR_DEFAULT
  } catch {
    return SIDEBAR_DEFAULT
  }
}

/** What a sidebar row hands to `select` — mirrors the selectable SelectionState cases. */
export type SelectTarget =
  | { kind: 'vault'; id: string }
  | { kind: 'page'; id: string; path: string }

/** A PageType's nexus-relative path by id, searched across ungrouped + sectioned vaults. */
function findVaultPath(tree: NexusTree, id: string): string | null {
  const all = [...tree.vaults, ...tree.userSections.flatMap((s) => s.vaults)]
  return all.find((v) => v.id === id)?.path ?? null
}

/** Lifecycle of the on-demand page-detail fetch for the current page selection. */
type PageStatus = 'idle' | 'loading' | 'ready' | 'error'

interface SessionState {
  status: 'idle' | 'loading' | 'ready' | 'error' | 'empty'
  tree: NexusTree | null
  error?: string
  sidebarVisible: boolean
  /** Sidebar width in px (clamped to the Swift min/max); persisted to localStorage. */
  sidebarWidth: number
  setSidebarWidth: (w: number) => void
  load: () => Promise<void>
  /** Swap in a freshly-read tree (from load() or the live watcher): set it, reconcile the selection, re-apply accent. */
  applyTree: (tree: NexusTree) => Promise<void>
  choose: () => Promise<void>
  openDropped: (file: File) => Promise<void>
  toggleSidebar: () => void

  selection: SelectionState
  pageStatus: PageStatus
  pageDetail: PageDetail | null
  pageError?: string
  select: (target: SelectTarget) => Promise<void>
  /** Create a page in the selected container (or the selected page's parent), then select it. */
  newPage: () => Promise<void>
  /** Create a top-level vault (page type at the nexus root), then inline-rename it. */
  newVault: () => Promise<void>

  /** The path of the sidebar row in inline-rename edit mode, or null. */
  renamingPath: string | null
  beginRename: (path: string) => void
  cancelRename: () => void
  /** Commit an inline rename via the mutate op, then refetch (selection reconciles the path). */
  submitRename: (path: string, kind: MutableKind, newName: string) => Promise<void>
}

export const useSession = create<SessionState>((set, get) => {
  // Shared "open attempt" path for the picker and drag-to-open: run the bridge
  // call; on success re-read state via load() (one read path). A rejected bridge
  // call routes to the error state instead of an unhandled rejection.
  const openVia = async (attempt: () => Promise<boolean>): Promise<void> => {
    try {
      if (await attempt()) {
        // A new nexus was adopted — clear selection/detail from the old one before
        // re-reading, so stale page detail doesn't linger against the new tree.
        // (Scoped to the adopt path, not load(), which also serves launch + refresh.)
        set({ selection: { kind: 'none' }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
        await get().load()
      }
    } catch (e) {
      set({ status: 'error', error: e instanceof Error ? e.message : String(e) })
    }
  }

  return {
    status: 'idle',
    tree: null,
    error: undefined,
    load: async () => {
      // Only show the full-screen loading state on the FIRST load (nothing on screen yet).
      // A refetch after a mutation keeps the tree mounted, so the sidebar's expand/collapse
      // state + selection survive the in-place swap instead of flashing + "resetting".
      if (!get().tree) set({ status: 'loading', error: undefined })
      try {
        const res = await window.nexus.state()
        switch (res.status) {
          case 'open':
            await get().applyTree(res.tree)
            break
          case 'empty':
            set({ status: 'empty', tree: null })
            break
          case 'error':
            set({ status: 'error', error: res.error })
            break
        }
      } catch (e) {
        // ipcRenderer.invoke rejects if the bridge/handler is absent — route it
        // to the designed error state instead of hanging on 'loading'.
        set({ status: 'error', error: e instanceof Error ? e.message : String(e) })
      }
    },

    // Swap in a freshly-read tree (load() after a fetch, or the live watcher's push).
    // No 'loading' flash — the tree's already on screen — and the selection reconciles
    // so the detail pane never strands on a gone page (delete) or stale path (rename/move).
    applyTree: async (tree) => {
      set({ status: 'ready', tree })
      const prev = get().selection
      const next = reconcileSelection(tree, prev)
      if (next !== prev) {
        if (next.kind === 'none') {
          set({ selection: next, pageStatus: 'idle', pageDetail: null, pageError: undefined })
        } else if (next.kind === 'page') {
          void get().select(next) // refetch the detail at the page's new path
        }
      }
      const systemColor = tree.accent === 'system' ? await window.nexus.systemAccent() : null
      applyAccent(tree.accent, systemColor)
    },

    // Native folder picker; on a pick, the session changed → re-read.
    choose: () => openVia(() => window.nexus.choose()),

    // A folder dropped onto the window; on a valid folder, the session changed → re-read.
    openDropped: (file) => openVia(() => window.nexus.openDropped(file)),

    sidebarVisible: true,
    toggleSidebar: () => set((s) => ({ sidebarVisible: !s.sidebarVisible })),

    sidebarWidth: readStoredSidebarWidth(),
    setSidebarWidth: (w) => {
      const next = clampSidebar(w)
      set({ sidebarWidth: next })
      try {
        localStorage.setItem(SIDEBAR_WIDTH_KEY, String(next))
      } catch {
        // private mode / disabled storage — width just won't persist
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
    },

    newPage: async () => {
      const { tree, selection } = get()
      if (!tree) return
      // Target container: the selected vault, the selected page's parent folder, else the
      // first vault. (Page paths are POSIX, so the parent is the path minus its last segment.)
      let parentPath: string | null = null
      if (selection.kind === 'vault') parentPath = findVaultPath(tree, selection.id)
      else if (selection.kind === 'page') parentPath = selection.path.split('/').slice(0, -1).join('/')
      if (parentPath === null) {
        parentPath = tree.vaults[0]?.path ?? tree.userSections.flatMap((s) => s.vaults)[0]?.path ?? null
      }
      if (parentPath === null) return // no container to create into
      // main disambiguates the name on collision; on success refetch + select the new page,
      // on failure surface the error natively (this path has no context-menu dialog).
      const res = await window.nexus.mutate({ op: 'createPage', parentPath, name: DEFAULT_NEW_NAME })
      if (res.ok) {
        await get().load()
        if (res.created) await get().select({ kind: 'page', id: res.created.id, path: res.created.path })
      } else {
        await window.nexus.showError(res.error.message)
      }
    },

    newVault: async () => {
      const res = await window.nexus.mutate({ op: 'createContainer', parentPath: '', kind: 'pageType', name: DEFAULT_NEW_NAME })
      if (res.ok) {
        await get().load()
        if (res.created) get().beginRename(res.created.path) // appears in inline-rename mode
      } else {
        await window.nexus.showError(res.error.message)
      }
    },

    renamingPath: null,
    beginRename: (path) => set({ renamingPath: path }),
    cancelRename: () => set({ renamingPath: null }),
    submitRename: async (path, kind, newName) => {
      set({ renamingPath: null }) // exit edit mode immediately
      const res = await window.nexus.mutate({ op: 'rename', path, kind, newName })
      if (res.ok) await get().load() // reconcileSelection refreshes the selected page's path
      else await window.nexus.showError(res.error.message)
    }
  }
})
