import { create } from 'zustand'
import { DEFAULT_COMMANDS, type AgendaEntry, type NavFavorite, type NavTarget, type NexusTree, type PageDetail, type Personalization, type PinEntry, type RecentEntry, type SelectionState, type SelectTarget, type SetNode, type Tab } from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind, type MutateRequest } from '@shared/mutate'
import { buildReconcileIndex, reconcileSelection, reconcileWith } from './selection'
import { navKey, recordRecent, removeRecentByKey, RECENTS_CAP } from './Navigation/navRecents'
import { byOrder, cleanPinTarget, pinFor, reorderTo } from './Navigation/navPins'
import { closeTab as closeTabModel, derivePinnedTabs, isPinned, newTabTab, openNewTab as openNewTabModel, openTab as openTabModel, pushMru, reconcileTabs, tabKey } from './Tabs/tabsModel'
import { captureWarm, clearWarm, dropWarmTab, readWarm } from './Tabs/warmCache'
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

// `SelectTarget` (what a sidebar row or tab hands to `select`) is the shared drivable-target type,
// re-exported so existing `../store` importers keep resolving it.
export type { SelectTarget }

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
  /** Ribbon (the mode-switch icon strip inside the sidebar) — transient like sidebarVisible. */
  ribbonVisible: boolean
  toggleRibbon: () => void
  /** Nexus-wide keyboard commands (settings.json `commands`), seeded from the tree — every id
   *  resolves (defaults overlaid in main), so consumers index without fallbacks. */
  commands: Record<string, string>
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
  /** The homepage board lock (G-3), seeded from `tree.homepage.locked` on every applyTree and
   *  the single cross-subtree source: the toolbar-dropdown SettingsPane toggles it, the detail-pane
   *  BlockSurface reads it to freeze the board (a React scope can't bridge the two subtrees). */
  homepageLocked: boolean
  setHomepageLocked: (v: boolean) => Promise<void>
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
  /** Navigate to a target: maintains the tab set (dedup/replace/spawn per the active tab, D-3b),
   *  records recents, and fetches the detail. `{ record: false }` is a programmatic re-select — a path
   *  refetch, Back/Forward, or a tab activation — that refreshes the shown detail WITHOUT touching the
   *  tab set or recents. `{ newTab: true }` forces a new tab ("Open in New Tab"). Preview opens (once
   *  they land) also pass `{ record: false }` so Back/Forward never lands on a preview. */
  select: (target: SelectTarget, opts?: { record?: boolean; newTab?: boolean }) => Promise<void>
  /** Open tabs — the UNPINNED set (pinned tabs derive from the pins slice). The ACTIVE tab always drives
   *  the singular `selection`/`pageDetail`. Persisted as the synced tab set (Phase 1). */
  tabs: Tab[]
  activeTabId: string
  /** Tab-activation MRU (ids, most-recent-first) — governs close-focus (D-9). */
  tabMru: string[]
  /** Activate an existing tab (a plain switch) — re-surfaces its target without recording (C-5); a
   *  newtab tab routes to the empty state. */
  activateTab: (id: string) => void
  /** Open a fresh NavView tab (the `+`), or focus the existing one (I-1). */
  openNewTab: () => void
  /** Close a tab — MRU-focus the next (D-9); reseed a NavView when the last closes (I-5). */
  closeTab: (id: string) => void
  /** Step the ACTIVE tab's own Back/Forward history (D-7), skipping deleted entries. */
  goBack: () => void
  goForward: () => void

  /** Navigation layer (recents + favorites) — the shared, UI-agnostic wayfinding state NavWindow +
   *  NavPane read. Persisted per-nexus (synced) via the `nav` bridge; the store owns the arrays and
   *  the MRU/pin/cap/prune logic. Loaded + wholesale-reset on every nexus open (E-11), recorded in
   *  `select`. Entries store only {kind,id,path} — title/icon/location resolve live (navResolve). */
  recents: RecentEntry[]
  favorites: NavFavorite[]
  /** Durable, user-ordered pins — per-pin files under `.nexus/pins/` (synced). pin/unpin/reorder each
   *  persist a single file immediately; loaded (+ one-time legacy-pinned migration) on nexus open. */
  pins: PinEntry[]
  pinTarget: (target: NavTarget) => void
  unpinTarget: (key: string) => void
  reorderPin: (activeKey: string, overKey: string) => void
  loadPins: () => Promise<void>
  /** Apply a live nav refresh from the watcher (an external/synced sidecar or pin change) — swaps the
   *  nav slices without a tree re-walk. */
  applyNavChanged: (nav: { recents: RecentEntry[]; favorites: NavFavorite[]; pins: PinEntry[] }) => void
  /** Gallery thumbnail cache-bust versions, keyed by navKey — bumped after a successful capture so the
   *  card `<img>` reloads the overwritten file. */
  thumbVersions: Record<string, number>
  bumpThumb: (key: string) => void
  /** Prune thumbnails outside the live recents∪pins set (fire-and-forget, on nexus open). */
  evictThumbs: () => void
  /** Add a durable favorite (no-op if already present), remove one, or reorder; each persists immediately. */
  addFavorite: (target: NavTarget) => void
  removeFavorite: (key: string) => void
  reorderFavorites: (from: number, to: number) => void
  /** Drop a recents-stream entry (the NavList row's Remove action); persists immediately. */
  removeRecent: (key: string) => void
  /** Cached `agenda:list` snapshot for search — a full disk walk, so it's fetched ONCE and reused
   *  across summons, invalidated on any tree push + nexus switch. Null until first fetched. */
  agendaSnapshot: { tasks: AgendaEntry[]; events: AgendaEntry[] } | null
  /** Fetch the agenda snapshot if not already cached (lazy — the search surface calls it on open). */
  ensureAgendaSnapshot: () => Promise<void>
  /** NavWindow (the ribbon-summoned floating mini-shell) open state; opening warms the agenda snapshot. */
  navOpen: boolean
  openNav: () => void
  closeNav: () => void
  toggleNav: () => void

  /** Re-fetch the open page's detail (after a frontmatter write like a page banner/cover). No-op if no page. */
  reloadPage: () => Promise<void>
  /** Create a page in the selected container (or the selected page's parent), then select it. */
  newPage: () => Promise<void>

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

// Homepage-lock writes in flight. applyTree reseeds `homepageLocked` from the canonical tree on
// every push, but the lock's own write is echo-suppressed (no self-push) — so an UNRELATED push
// landing mid-write would read the pre-commit homepage.json and revert the optimistic value with no
// follow-up push to heal it. While a local write is in flight we trust the optimistic value instead.
let homepageLockWritesInFlight = 0

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
        // Clearing activeTabId marks the tab set never-seeded, so load() re-reads the
        // new nexus's sidecar (I-10 wholesale reset; main drained the outgoing writes).
        set({ selection: { kind: 'none' }, pageStatus: 'idle', pageDetail: null, pageError: undefined, liveBody: null, tabs: [], activeTabId: '', tabMru: [] })
        clearWarm() // warmth is per-nexus AND session-only — never crosses an adoption (I-10)
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

  // A unique tab id (session-scoped; persisted tab ids reload from the sidecar). crypto is available in
  // the renderer's secure context.
  const makeTabId = (): string => crypto.randomUUID()

  // The active tab — an unpinned tab, or a derived pinned tab (which carries no unpinned back-history).
  const findActiveTab = (): Tab | undefined => {
    const s = get()
    return s.tabs.find((t) => t.id === s.activeTabId) ?? derivePinnedTabs(s.pins).find((t) => t.id === s.activeTabId)
  }

  // Re-surface the active tab into the detail pane (a plain switch): a newtab tab routes to the empty
  // state; anything else re-selects WITHOUT recording (record:false). The target reconciles against
  // the live tree first — a derived pinned tab's stored path can be stale (pins are storage, tabs
  // reconcile live) — falling back to the raw target on a miss, mirroring the nav layer's click path.
  const syncActiveDetail = (): void => {
    const active = findActiveTab()
    if (!active || active.target.kind === 'newtab') {
      set({ selection: { kind: 'none' }, pageStatus: 'idle', pageDetail: null, pageError: undefined })
      return
    }
    const tree = get().tree
    const reconciled = tree ? reconcileSelection(tree, active.target) : active.target
    void get().select(reconciled.kind === 'none' ? active.target : reconciled, { record: false })
  }

  // Persist the tab set (fire-and-forget; main debounces + drains at quit/switch, D-8).
  const persistTabs = (): void => {
    const s = get()
    void window.nexus.tabs.save({ tabs: s.tabs, activeTabId: s.activeTabId }).catch(() => undefined)
  }

  // Capture the outgoing page detail into the warm cache BEFORE a switch mutates selection —
  // `select` nulls pageDetail synchronously, so a capture any later would read the incoming tab's
  // state. Runs at the top of every path that changes what's shown; no-op off a ready page.
  const captureOutgoingDetail = (): void => {
    const s = get()
    if (s.selection.kind !== 'page' || s.pageStatus !== 'ready' || !s.pageDetail) return
    captureWarm(s.activeTabId, navKey(s.selection), { pageDetail: s.pageDetail })
  }

  // Back/Forward replay over the ACTIVE tab's own history (D-7): walk in `delta` direction, resolving
  // each entry by id against the live tree (a renamed/moved entity → its fresh path) and skipping
  // deleted entries. A pinned/newtab active tab has no unpinned back-history, so this is a no-op.
  const stepActiveHistory = (delta: number): void => {
    const s = get()
    const active = s.tabs.find((t) => t.id === s.activeTabId)
    if (!active || active.target.kind === 'newtab') return
    for (let i = active.navIndex + delta; i >= 0 && i < active.navStack.length; i += delta) {
      const resolved = s.tree ? reconcileSelection(s.tree, active.navStack[i]) : active.navStack[i]
      if (resolved.kind === 'none') continue // entity gone — skip to the next live entry in this direction
      captureOutgoingDetail() // the entry being left stays warm for the return trip (I-7)
      // target moves in lockstep with navIndex — openTab's dedup keys off `target`, so a stale one
      // would mis-dedup the very next click on the shown entity (destroying the Forward stack).
      set({ tabs: get().tabs.map((t) => (t.id === active.id ? { ...t, navIndex: i, target: resolved } : t)) })
      void get().select(resolved, { record: false })
      persistTabs()
      return
    }
  }

  return {
    status: 'idle',
    tree: null,
    error: undefined,
    homepageLocked: false,
    // Optimistic + persist; the in-flight counter fences the applyTree reseed against a concurrent
    // unrelated push (see homepageLockWritesInFlight). The disk write self-suppresses at the watcher.
    setHomepageLocked: async (v) => {
      homepageLockWritesInFlight++
      set({ homepageLocked: v })
      try {
        await window.nexus.blocks.save({ kind: 'homepage' }, { locked: v })
      } finally {
        homepageLockWritesInFlight--
      }
    },
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
            // Navigation layer — wholesale per-nexus reset (E-11): replace every slice from disk and
            // drop the stale agenda snapshot before any record/render happens in the new nexus. Pins
            // load (+ first-open legacy migration) through their own bridge.
            try {
              const nav = await window.nexus.nav.load()
              set(nav.ok ? { recents: nav.recents, favorites: nav.favorites } : { recents: [], favorites: [] })
            } catch {
              set({ recents: [], favorites: [] })
            }
            set({ pins: [] })
            await get().loadPins()
            get().evictThumbs() // prune thumbnails outside the fresh recents∪pins set
            set({ agendaSnapshot: null })
            // The tab set — loaded ONCE per nexus (an empty activeTabId marks never-seeded; the adopt
            // path clears it). A mutation refetch must NOT re-read the sidecar: its debounced write
            // trails the in-memory set, so a re-read would roll the tabs backward.
            if (get().activeTabId === '') {
              const stored = await window.nexus.tabs.load().catch(() => null)
              const storedSet = stored?.ok ? stored.set : null
              const pins = get().pins
              const seen = new Set<string>()
              // Drop any stored tab now covered by a pin (C-6 — pinned tabs derive, never dual-store)
              // and dedupe by entity (I-1 — a cross-device merge can't produce duplicate tabs).
              const tabs = (storedSet?.tabs ?? []).filter((t) => {
                if (t.target.kind !== 'newtab' && isPinned(t.target, pins)) return false
                const k = tabKey(t.target)
                if (seen.has(k)) return false
                seen.add(k)
                return true
              })
              const pinnedTabs = derivePinnedTabs(pins)
              const storedActive = storedSet?.activeTabId ?? ''
              const liveIds = new Set([...pinnedTabs, ...tabs].map((t) => t.id))
              const active = liveIds.has(storedActive) ? storedActive : (tabs[0]?.id ?? pinnedTabs[0]?.id ?? '')
              if (active === '') {
                // Nothing persisted and no pins — a fresh nexus opens onto one NavView tab (E-2).
                const seeded = newTabTab(makeTabId())
                set({ tabs: [seeded], activeTabId: seeded.id, tabMru: [seeded.id] })
              } else {
                set({ tabs, activeTabId: active, tabMru: [active] })
              }
              syncActiveDetail() // restore the active tab's entity (cold — warmth is session-only)
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
      // ONE tree flatten serves the selection reconcile AND every tab's (never a per-tab walk).
      const index = buildReconcileIndex(tree)
      const prev = get().selection
      const next = reconcileWith(index, prev)
      if (next !== prev) {
        if (next.kind === 'none') {
          set({ selection: next, pageStatus: 'idle', pageDetail: null, pageError: undefined })
        } else if (next.kind === 'page') {
          void get().select(next, { record: false }) // refetch the detail at the page's new path — not a nav
        }
      }
      // I-2a: every tab reconciles, not just the active selection — an inactive tab whose entity was
      // renamed/moved refreshes in place; a deleted entity closes its unpinned tab (pinned tabs derive
      // from pins, which render-prune, never storage-prune). Reference-preserving: an unchanged set
      // skips the write entirely.
      {
        const s = get()
        const rec = reconcileTabs(
          s.tabs,
          s.activeTabId,
          s.tabMru,
          derivePinnedTabs(s.pins).map((t) => t.id),
          (t) => {
            const r = reconcileWith(index, t)
            return r.kind === 'none' ? null : r
          },
          makeTabId()
        )
        if (rec.changed) {
          for (const t of s.tabs) if (!rec.tabs.some((n) => n.id === t.id)) dropWarmTab(t.id) // deleted-entity closes
          const activeChanged = rec.activeTabId !== s.activeTabId
          set({ tabs: rec.tabs, activeTabId: rec.activeTabId, tabMru: rec.mru })
          if (activeChanged) syncActiveDetail()
          persistTabs()
        }
      }
      // Always read the OS accent: it feeds --accent only when the setting is `system`,
      // but --system-accent (external-link color) reflects it unconditionally.
      const systemColor = await window.nexus.systemAccent()
      applyAccent(tree.accent, systemColor)
      applySystemAccent(systemColor)
      set({ personalization: tree.personalization, commands: tree.commands ?? DEFAULT_COMMANDS })
      applyPersonalization(tree.personalization)
      if (homepageLockWritesInFlight === 0) set({ homepageLocked: tree.homepage.locked })
      // A tree push may reflect an agenda-file change — drop the cached snapshot so the next search
      // re-walks. Lazy: nothing re-fetches until search actually runs.
      if (get().agendaSnapshot) set({ agendaSnapshot: null })
    },

    // Native folder picker; on a pick, the session changed → re-read.
    choose: () => openVia(() => window.nexus.choose()),

    // A folder dropped onto the window; on a valid folder, the session changed → re-read.
    openDropped: (file) => openVia(() => window.nexus.openDropped(file)),

    sidebarVisible: true,
    toggleSidebar: () => set((s) => ({ sidebarVisible: !s.sidebarVisible })),

    ribbonVisible: true,
    toggleRibbon: () => set((s) => ({ ribbonVisible: !s.ribbonVisible })),
    commands: DEFAULT_COMMANDS,

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
    tabs: [],
    activeTabId: '',
    tabMru: [],
    goBack: () => stepActiveHistory(-1),
    goForward: () => stepActiveHistory(1),
    activateTab: (id) => {
      if (get().activeTabId === id) return
      captureOutgoingDetail()
      set((s) => ({ activeTabId: id, tabMru: pushMru(s.tabMru, id) }))
      syncActiveDetail()
      persistTabs()
    },
    openNewTab: () => {
      captureOutgoingDetail()
      const s = get()
      const res = openNewTabModel(s.tabs, makeTabId())
      set({ tabs: res.tabs, activeTabId: res.activeTabId, tabMru: pushMru(s.tabMru, res.activeTabId) })
      syncActiveDetail()
      persistTabs()
    },
    closeTab: (id) => {
      const s = get()
      const pinnedIds = derivePinnedTabs(s.pins).map((t) => t.id)
      const res = closeTabModel(s.tabs, s.activeTabId, s.tabMru, pinnedIds, id, makeTabId())
      const activeChanged = res.activeTabId !== s.activeTabId
      set({ tabs: res.tabs, activeTabId: res.activeTabId, tabMru: res.mru })
      dropWarmTab(id) // a closed tab's warm stack dies with it
      if (activeChanged) syncActiveDetail()
      persistTabs()
    },

    recents: [],
    favorites: [],
    pins: [],
    pinTarget: (target) => {
      // Agenda kinds have no durable resolver yet; adopted ids re-mint on adoption (would orphan the file).
      if (target.kind === 'task' || target.kind === 'event') return
      if ('id' in target && target.id.startsWith('adopted-')) return
      const key = navKey(target)
      if (get().pins.some((p) => navKey(p) === key)) return
      const pin = pinFor(target, get().pins)
      set({ pins: [...get().pins, pin].sort(byOrder) })
      void window.nexus.nav.addPin(pin)
    },
    unpinTarget: (key) => {
      const pin = get().pins.find((p) => navKey(p) === key)
      if (!pin) return
      set({ pins: get().pins.filter((p) => navKey(p) !== key) })
      void window.nexus.nav.removePin(cleanPinTarget(pin), pin.order)
    },
    reorderPin: (activeKey, overKey) => {
      const moved = reorderTo(get().pins, activeKey, overKey)
      if (!moved) return
      set({ pins: get().pins.map((p) => (navKey(p) === activeKey ? moved : p)).sort(byOrder) })
      void window.nexus.nav.reorderPin(moved)
    },
    loadPins: async () => {
      const res = await window.nexus.nav.loadPins().catch(() => null)
      if (res?.ok) set({ pins: [...res.pins].sort(byOrder) })
    },
    // Only pins swap on a live refresh — recents are debounce-written so in-memory leads disk; replacing
    // them from a pin/favorite-triggered push would clobber the user's latest (unsaved) navigations.
    applyNavChanged: (nav) => set({ pins: [...nav.pins].sort(byOrder) }),
    thumbVersions: {},
    bumpThumb: (key) => set((s) => ({ thumbVersions: { ...s.thumbVersions, [key]: (s.thumbVersions[key] ?? 0) + 1 } })),
    evictThumbs: () => {
      const live = [...get().recents.map(navKey), ...get().pins.map(navKey)]
      void window.nexus.capture.evict(live)
    },
    addFavorite: (target) => {
      // v1 favorites are tree kinds only (R3-F2): an agenda favorite would resolve to null and render
      // as an invisible, un-removable entry until the agenda resolver ships.
      if (target.kind === 'task' || target.kind === 'event') return
      const key = navKey(target)
      if (get().favorites.some((f) => navKey(f) === key)) return
      const favorites = [...get().favorites, target]
      set({ favorites })
      void window.nexus.nav.saveFavorites(favorites)
    },
    removeFavorite: (key) => {
      const favorites = get().favorites.filter((f) => navKey(f) !== key)
      set({ favorites })
      void window.nexus.nav.saveFavorites(favorites)
    },
    reorderFavorites: (from, to) => {
      const favorites = [...get().favorites]
      const [moved] = favorites.splice(from, 1)
      if (!moved) return
      favorites.splice(to, 0, moved)
      set({ favorites })
      void window.nexus.nav.saveFavorites(favorites)
    },
    removeRecent: (key) => {
      const next = removeRecentByKey(get().recents, key)
      if (next === get().recents) return // nothing matched — no state churn, no write
      set({ recents: next })
      void window.nexus.nav.saveRecents(next, true) // immediate, like the pin toggle
    },
    agendaSnapshot: null,
    ensureAgendaSnapshot: async () => {
      if (get().agendaSnapshot) return
      try {
        const res = await window.nexus.agenda.list()
        if (res.ok) set({ agendaSnapshot: { tasks: res.tasks, events: res.events } })
      } catch {
        // bridge/handler absent — search runs over the tree alone until the next attempt
      }
    },
    navOpen: false,
    openNav: () => {
      void get().ensureAgendaSnapshot() // warm the agenda snapshot so search can list Tasks/Events
      set({ navOpen: true })
    },
    closeNav: () => set({ navOpen: false }),
    toggleNav: () => {
      if (!get().navOpen) void get().ensureAgendaSnapshot()
      set((s) => ({ navOpen: !s.navOpen }))
    },
    select: async (target, opts) => {
      // A genuine navigation (record !== false) maintains the tab set — dedup/replace/spawn per the
      // active tab's pin state (D-3b) — and records recents. A programmatic re-select (Back/Forward, a
      // path refetch, a tab activation) passes { record: false } and does neither; it only refreshes the
      // shown detail below. Recents record ONLY when a tab actually opened (a spawn or in-place replace),
      // never on a focus/re-surface of an already-open tab (C-5).
      if (opts?.record !== false) {
        captureOutgoingDetail()
        const s = get()
        const pinned = derivePinnedTabs(s.pins)
        const res = openTabModel(s.tabs, s.activeTabId, pinned, target, { newTab: opts?.newTab }, makeTabId())
        const opened = res.tabs !== s.tabs
        set({ tabs: res.tabs, activeTabId: res.activeTabId, tabMru: pushMru(s.tabMru, res.activeTabId) })
        if (opened) {
          const recents = recordRecent(s.recents, target, RECENTS_CAP)
          set({ recents })
          void window.nexus.nav.saveRecents(recents)
        }
        persistTabs()
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
          // Warm-instant (B-3): a warm entity under the active tab renders its cached detail with no
          // fetch and no loading flash. The path equality keeps it honest across renames — a stale-path
          // detail would route saves at the old file — and a miss falls through to the cold fetch.
          const cached = readWarm(get().activeTabId, navKey(target))?.pageDetail
          if (cached && cached.path === target.path) {
            set({ selection: { kind: 'page', id: target.id, path: target.path }, pageStatus: 'ready', pageDetail: cached, pageError: undefined })
            return
          }
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
