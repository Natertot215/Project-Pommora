import { create } from 'zustand'
import type { NexusTree, PageDetail, SelectionState, SetNode } from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind, type MutateRequest } from '@shared/mutate'
import { reconcileSelection } from './selection'
import { applyAccent, applySystemAccent } from './design-system/accent'

// Sidebar width bounds — Swift's min:180 / ideal:240, max widened +50 past Swift's 330 for extra drag room.
const SIDEBAR_MIN = 180
const SIDEBAR_MAX = 380
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

// Inspector (right pane) width bounds — its own range, max carrying the same +50 headroom.
const INSPECTOR_MIN = 240
const INSPECTOR_MAX = 420
const INSPECTOR_DEFAULT = 300
const INSPECTOR_WIDTH_KEY = 'pommora.inspectorWidth'
const clampInspector = (w: number): number => Math.max(INSPECTOR_MIN, Math.min(INSPECTOR_MAX, Math.round(w)))
function readStoredInspectorWidth(): number {
  try {
    const n = Number(localStorage.getItem(INSPECTOR_WIDTH_KEY))
    return Number.isFinite(n) && n > 0 ? clampInspector(n) : INSPECTOR_DEFAULT
  } catch {
    return INSPECTOR_DEFAULT
  }
}

/** What a sidebar row hands to `select` — mirrors the selectable SelectionState cases. */
export type SelectTarget =
  | { kind: 'homepage' }
  | { kind: 'context'; id: string }
  | { kind: 'collection'; id: string }
  | { kind: 'set'; id: string; path: string }
  | { kind: 'page'; id: string; path: string }

/** A breadcrumb ghost crumb's target — the last page visited in a given container. */
export interface TrailEntry {
  id: string
  path: string
  title: string
}

/** Nexus-relative path of a top Collection or any nested Set by id (ungrouped + sectioned). */
function findContainerPath(tree: NexusTree, id: string): string | null {
  const cols = [...(tree.collections ?? []), ...tree.userSections.flatMap((s) => s.collections ?? [])]
  const inSets = (sets: SetNode[] | undefined): string | null => {
    for (const s of sets ?? []) {
      if (s.id === id) return s.path
      const deep = inSets(s.sets)
      if (deep) return deep
    }
    return null
  }
  for (const c of cols) {
    if (c.id === id) return c.path
    const hit = inSets(c.sets)
    if (hit) return hit
  }
  return null
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
  /** Inspector (right pane) width in px (clamped, persisted to localStorage). */
  inspectorWidth: number
  setInspectorWidth: (w: number) => void
  /** Subfield (footer) — one app-level expanded flag; all views collapse together. */
  subfieldExpanded: boolean
  setSubfieldExpanded: (expanded: boolean) => void
  /** Last-visited page per container id — drives the breadcrumb's dimmed "forward" ghost crumb. */
  trail: Record<string, TrailEntry>
  recordTrail: (containerId: string, entry: TrailEntry) => void
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
  /** Re-fetch the open page's detail (after a frontmatter write like a page banner/cover). No-op if no page. */
  reloadPage: () => Promise<void>
  /** Create a page in the selected container (or the selected page's parent), then select it. */
  newPage: () => Promise<void>
  /** Create a top-level Collection at the nexus root, then inline-rename it. */
  newCollection: () => Promise<void>

  /** The path of the sidebar row in inline-rename edit mode, or null. */
  renamingPath: string | null
  beginRename: (path: string) => void
  cancelRename: () => void
  /** Commit an inline rename via the mutate op, then refetch (selection reconciles the path).
   *  Resolves `true` on success, `false` if the op failed (so a caller can revert its draft). */
  submitRename: (path: string, kind: MutableKind, newName: string) => Promise<boolean>
  /** The one write path: run a mutate op, surface its error or refetch on success. On a create,
   *  the new entity is handed to `onCreated` (to select it, begin-renaming it, …). Every sidebar
   *  mutation — drops, renames, creates — routes through here. Resolves the op's success. */
  mutate: (req: MutateRequest, onCreated?: (created: { id: string; path: string }) => void | Promise<void>) => Promise<boolean>
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
      // Always read the OS accent: it feeds --accent only when the setting is `system`,
      // but --system-accent (external-link color) reflects it unconditionally.
      const systemColor = await window.nexus.systemAccent()
      applyAccent(tree.accent, systemColor)
      applySystemAccent(systemColor)
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

    inspectorWidth: readStoredInspectorWidth(),
    setInspectorWidth: (w) => {
      const next = clampInspector(w)
      set({ inspectorWidth: next })
      try {
        localStorage.setItem(INSPECTOR_WIDTH_KEY, String(next))
      } catch {
        // private mode / disabled storage — width just won't persist
      }
    },

    subfieldExpanded: true,
    setSubfieldExpanded: (expanded) => set({ subfieldExpanded: expanded }),
    trail: {},
    recordTrail: (containerId, entry) =>
      set((s) => ({ trail: { ...s.trail, [containerId]: entry } })),

    selection: { kind: 'none' },
    pageStatus: 'idle',
    pageDetail: null,
    pageError: undefined,
    select: async (target) => {
      switch (target.kind) {
        case 'homepage':
          // The homepage view renders from the loaded tree (banner + future widgets) — no fetch.
          set({ selection: { kind: 'homepage' }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          return
        case 'context':
          // A context (area/topic/project) renders a blank page from the loaded tree — no fetch.
          set({ selection: { kind: 'context', id: target.id }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          return
        case 'collection':
          // Collection detail renders from the loaded tree (banner + its pages) — no fetch.
          set({ selection: { kind: 'collection', id: target.id }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          return
        case 'set':
          // A depth-1 Set's detail renders from the loaded tree (banner + its pages) — no fetch.
          set({ selection: { kind: 'set', id: target.id, path: target.path }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
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

    reloadPage: async () => {
      const { selection } = get()
      if (selection.kind !== 'page') return
      const res = await window.nexus.openPage(selection.path).catch(() => null)
      if (res?.ok) set({ pageDetail: res.page })
    },

    newPage: async () => {
      const { tree, selection } = get()
      if (!tree) return
      // Target container: the selected Collection/Set, the selected page's parent folder, else the
      // first Collection. (Page paths are POSIX, so the parent is the path minus its last segment.)
      let parentPath: string | null = null
      if (selection.kind === 'collection' || selection.kind === 'set') parentPath = findContainerPath(tree, selection.id)
      else if (selection.kind === 'page') parentPath = selection.path.split('/').slice(0, -1).join('/')
      if (parentPath === null) {
        parentPath = (tree.collections ?? [])[0]?.path ?? tree.userSections.flatMap((s) => s.collections ?? [])[0]?.path ?? null
      }
      if (parentPath === null) return // no container to create into
      // main disambiguates the name on collision; select the new page once it lands.
      await get().mutate({ op: 'createPage', parentPath, name: DEFAULT_NEW_NAME }, (created) =>
        get().select({ kind: 'page', id: created.id, path: created.path })
      )
    },

    newCollection: async () => {
      // create a top-level Collection, then drop it straight into inline-rename mode
      await get().mutate({ op: 'createContainer', parentPath: '', kind: 'collection', name: DEFAULT_NEW_NAME }, (created) =>
        get().beginRename(created.path)
      )
    },

    renamingPath: null,
    beginRename: (path) => set({ renamingPath: path }),
    cancelRename: () => set({ renamingPath: null }),
    submitRename: async (path, kind, newName) => {
      set({ renamingPath: null }) // exit edit mode immediately, regardless of outcome
      return get().mutate({ op: 'rename', path, kind, newName })
    },
    mutate: async (req, onCreated) => {
      const res = await window.nexus.mutate(req)
      if (!res.ok) {
        await window.nexus.showError(res.error.message)
        return false
      }
      await get().load() // refetch; reconcileSelection refreshes a moved/renamed page's path
      if (res.created && onCreated) await onCreated(res.created)
      return true
    }
  }
})
