import { create } from 'zustand'
import type { NexusTree, PageDetail, Personalization, SelectionState, SetNode } from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind, type MutateRequest } from '@shared/mutate'
import { reconcileSelection } from './selection'
import { stabilize } from './treeStabilize'
import { applyAccent, applySystemAccent } from './design-system/accent'
import { applyPersonalization, applyPersonalizationKey } from './design-system/personalization'
import { findCollection, findSet, findCollectionForSet, isDepth1Set } from './Detail/Scope'
import { ensureContainerView } from './Detail/Views/viewMint'

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

/** Identity of a nav target for history dedupe — consecutive re-selects of the same view collapse. */
const navKey = (t: SelectTarget): string => ('id' in t ? `${t.kind}:${t.id}` : t.kind)

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
  /** Per-view-kind ordered Subfield item ids (persisted per nexus); absent kinds use registry defaults. */
  subfieldOrder: Partial<Record<SelectionState['kind'], string[]>>
  setSubfieldOrder: (kind: SelectionState['kind'], ids: string[]) => void
  /** Nexus-wide interface personalization (settings.json) — the DRY config the apply-map consumes.
   *  Seeded from the tree; setPersonalization updates it, applies the DOM effect, and persists. */
  personalization: Personalization
  setPersonalization: <K extends keyof Personalization>(key: K, value: Personalization[K]) => void
  /** Last-visited page per container id — drives the breadcrumb's dimmed "forward" ghost crumb. */
  trail: Record<string, TrailEntry>
  recordTrail: (containerId: string, entry: TrailEntry) => void
  /** Fetched page titles for URL cells in the `link-title` look, keyed by URL. Hydrated from main's
   *  `.nexus/linkTitles.json` cache on open; a url cell requests any it's missing via resolveLinkTitle.
   *  A url with no entry falls back to its bare domain (loading or a failed fetch look identical). */
  linkTitles: Record<string, string>
  /** Resolve one URL's title out-of-band: no-op if known / in-flight / already-failed this session;
   *  otherwise asks main (cache hit or live fetch) and folds a success into `linkTitles`. */
  resolveLinkTitle: (url: string) => void
  /** Per-machine active-view pointer (container id → view id), hydrated on open. The single shared
   *  source every view surface reads, so a switch repaints the table AND the button together. */
  activeViews: Record<string, string>
  /** Switch a container's active view: persist to `.nexus/activeViews.json`, then update the slice
   *  (no tree reload — the pointer isn't in the tree). */
  setActiveView: (containerId: string, viewId: string) => Promise<void>
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
  /** Live editing buffer for the open page (keyed by path) so the Subfield's stats track keystrokes,
   *  ahead of the debounced save. `pageDetail.body` stays the loaded/saved snapshot. */
  liveBody: { path: string; body: string } | null
  setLiveBody: (path: string, body: string) => void
  /** Navigation history. `select` records by default; pass `{ record: false }` for programmatic
   *  re-selects (e.g. a path refetch). IMPORTANT: once page previews land, preview opens MUST pass
   *  `{ record: false }` too, so Back/Forward never lands on a page you only previewed. */
  select: (target: SelectTarget, opts?: { record?: boolean }) => Promise<void>
  navStack: SelectTarget[]
  navIndex: number
  goBack: () => void
  goForward: () => void
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

  /** The property row in inline-rename edit mode (A-10) — its OWN channel: properties are
   *  id-keyed registry entities, not paths, so `renamingPath`/`submitRename` can't carry them. */
  renamingProperty: { collectionPath: string; propertyId: string } | null
  beginPropertyRename: (target: { collectionPath: string; propertyId: string }) => void
  cancelPropertyRename: () => void
  /** Commit through `schema:rename`, then refetch. Resolves the write's success. */
  submitPropertyRename: (newName: string) => Promise<boolean>
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
        set({ selection: { kind: 'none' }, pageStatus: 'idle', pageDetail: null, pageError: undefined, liveBody: null })
        await get().load()
      }
    } catch (e) {
      set({ status: 'error', error: e instanceof Error ? e.message : String(e) })
    }
  }

  // Link-title fetch de-dup (not render state, so plain closures): `inFlight` blocks a concurrent
  // second request per URL and clears when it settles; `failed` remembers a URL whose fetch yielded no
  // title so a re-render never re-hammers it this session (next session retries once, via a fresh store).
  const inFlightTitles = new Set<string>()
  const failedTitles = new Set<string>()

  // Back/Forward replay: walk the nav history in `delta` direction, resolving each entry by id against
  // the live tree (a renamed/moved entity → its fresh path) and skipping entries whose entity was
  // deleted — the stored path is never trusted blind, mirroring how every other selection reconciles.
  const stepHistory = (delta: number): void => {
    const { navStack, navIndex, tree } = get()
    for (let i = navIndex + delta; i >= 0 && i < navStack.length; i += delta) {
      const resolved = tree ? reconcileSelection(tree, navStack[i]) : navStack[i]
      if (resolved.kind === 'none') continue // entity gone — skip to the next live entry in this direction
      set({ navIndex: i })
      void get().select(resolved, { record: false })
      return
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
            // Per-nexus Subfield config (settings.json) — load once on open; keep defaults if absent.
            try {
              const cfg = await window.nexus.subfield.get()
              if (cfg) set({ subfieldExpanded: cfg.expanded, subfieldOrder: cfg.order })
            } catch {
              // bridge/handler absent — keep the in-memory defaults
            }
            // The fetched link-title cache — hydrate the whole map from main so cached titles render
            // with no flash (only never-seen URLs fetch). A superset of what's in the store, so it never
            // drops a session-fetched title; per-url selectors keep identity when values are unchanged.
            try {
              set({ linkTitles: await window.nexus.linkTitles.get() })
            } catch {
              // bridge/handler absent — url cells fall back to the domain
            }
            // The per-machine active-view pointer — the shared slice every view surface reads.
            try {
              set({ activeViews: await window.nexus.activeViews.get() })
            } catch {
              // bridge/handler absent — surfaces fall back to the first saved view
            }
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
    applyTree: async (incoming) => {
      // Recycle unchanged subtrees from the prior tree — IPC strips identity, so without this
      // every push re-rendered every consumer. An echo lands as the SAME tree (a zustand no-op);
      // an unrelated change keeps the open container's identity and its memoized pipeline.
      const tree = stabilize(incoming, get().tree)
      set({ status: 'ready', tree })
      const prev = get().selection
      const next = reconcileSelection(tree, prev)
      if (next !== prev) {
        if (next.kind === 'none') {
          set({ selection: next, pageStatus: 'idle', pageDetail: null, pageError: undefined })
        } else if (next.kind === 'page') {
          void get().select(next, { record: false }) // refetch the detail at the page's new path — not a nav
        }
      }
      // Always read the OS accent: it feeds --accent only when the setting is `system`,
      // but --system-accent (external-link color) reflects it unconditionally.
      const systemColor = await window.nexus.systemAccent()
      applyAccent(tree.accent, systemColor)
      applySystemAccent(systemColor)
      set({ personalization: tree.personalization })
      applyPersonalization(tree.personalization)
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
    setSubfieldExpanded: (expanded) => {
      set({ subfieldExpanded: expanded })
      const s = get()
      void window.nexus.subfield.set({ order: s.subfieldOrder, expanded: s.subfieldExpanded }).catch(() => undefined)
    },
    subfieldOrder: {},
    setSubfieldOrder: (kind, ids) => {
      set((s) => ({ subfieldOrder: { ...s.subfieldOrder, [kind]: ids } }))
      const s = get()
      void window.nexus.subfield.set({ order: s.subfieldOrder, expanded: s.subfieldExpanded }).catch(() => undefined)
    },
    personalization: {},
    setPersonalization: (key, value) => {
      set((s) => ({ personalization: { ...s.personalization, [key]: value } }))
      applyPersonalizationKey(key, value)
      void window.nexus.personalization.set(key, value).catch(() => undefined)
    },
    trail: {},
    recordTrail: (containerId, entry) =>
      set((s) => ({ trail: { ...s.trail, [containerId]: entry } })),

    linkTitles: {},
    resolveLinkTitle: (url) => {
      if (inFlightTitles.has(url) || failedTitles.has(url) || get().linkTitles[url]) return
      inFlightTitles.add(url)
      window.nexus.linkTitles
        .fetch(url)
        .then((res) => {
          // A late fetch resolving after a nexus switch merges into the new map harmlessly: a URL's
          // <title> is identical in any nexus, and main won't persist it cross-nexus (cacheRoot === root).
          const title = res.ok ? res.title : null
          if (title) set((s) => ({ linkTitles: { ...s.linkTitles, [url]: title } }))
          else failedTitles.add(url) // no title (offline / non-2xx / none) — don't re-hammer this session
        })
        .catch(() => failedTitles.add(url))
        .finally(() => inFlightTitles.delete(url))
    },

    activeViews: {},
    setActiveView: async (containerId, viewId) => {
      await window.nexus.activeViews.set(containerId, viewId)
      set((s) => ({ activeViews: { ...s.activeViews, [containerId]: viewId } }))
    },

    selection: { kind: 'none' },
    pageStatus: 'idle',
    pageDetail: null,
    pageError: undefined,
    liveBody: null,
    setLiveBody: (path, body) => set({ liveBody: { path, body } }),
    navStack: [],
    navIndex: -1,
    goBack: () => stepHistory(-1),
    goForward: () => stepHistory(1),
    select: async (target, opts) => {
      // Record into history unless this is a programmatic re-select — a path refetch, Back/Forward,
      // or (once previews land) a preview open — which pass { record: false } so they don't push.
      if (opts?.record !== false) {
        set((s) => {
          const cur = s.navStack[s.navIndex]
          if (cur && navKey(cur) === navKey(target)) return {} // same view re-selected — no dup entry
          const stack = s.navStack.slice(0, s.navIndex + 1)
          stack.push(target)
          return { navStack: stack, navIndex: stack.length - 1 }
        })
      }
      switch (target.kind) {
        case 'homepage':
          // The homepage view renders from the loaded tree (banner + future widgets) — no fetch.
          set({ selection: { kind: 'homepage' }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          return
        case 'context':
          // A context (area/topic/project) renders a blank page from the loaded tree — no fetch.
          set({ selection: { kind: 'context', id: target.id }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          return
        case 'collection': {
          // Collection detail renders from the loaded tree (banner + its pages) — no fetch.
          set({ selection: { kind: 'collection', id: target.id }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          // Entry-mint (G-1): a view-bearing container with an empty views[] gets its default minted
          // here, the sole mint site. A fired side-effect — the case stays synchronous for render.
          const col = findCollection(get().tree, target.id)
          if (col) ensureContainerView(col, col.properties ?? [], get().load)
          return
        }
        case 'set': {
          // A depth-1 Set's detail renders from the loaded tree (banner + its pages) — no fetch.
          set({ selection: { kind: 'set', id: target.id, path: target.path }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
          // Only a DEPTH-1 Set carries views (a reparented Sub-Set can reach here via Back-nav).
          const setNode = findSet(get().tree, target.id)
          if (setNode && isDepth1Set(get().tree, target.id))
            ensureContainerView(setNode, findCollectionForSet(get().tree, target.id)?.properties ?? [], get().load)
          return
        }
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

    renamingProperty: null,
    beginPropertyRename: (target) => set({ renamingProperty: target }),
    cancelPropertyRename: () => set({ renamingProperty: null }),
    submitPropertyRename: async (newName) => {
      const target = get().renamingProperty
      set({ renamingProperty: null }) // exit edit mode immediately, regardless of outcome
      if (!target) return false
      const res = await window.nexus.schema.rename(target.collectionPath, target.propertyId, newName)
      if (!res.ok) {
        await window.nexus.showError(res.error)
        return false
      }
      await get().load()
      return true
    },
    mutate: async (req, onCreated) => {
      const res = await window.nexus.mutate(req)
      if (!res.ok) {
        await window.nexus.showError(res.error.message)
        return false
      }
      // Value-only writes (a cell edit, a status cycle, a tier pick) never change the TREE —
      // the caller's optimistic patch shows the change and the fs watcher settles canon, so the
      // full-nexus re-walk is skipped for them (it's THE "reload the entire Y" on a hot path).
      // Structural ops still refetch immediately; reconcileSelection refreshes a moved/renamed path.
      if (req.op !== 'setProperty' && req.op !== 'setTier') await get().load()
      if (res.created && onCreated) await onCreated(res.created)
      return true
    }
  }
})
