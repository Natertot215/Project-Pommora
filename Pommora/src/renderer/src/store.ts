import { create } from 'zustand'
import {
  DEFAULT_COMMANDS,
  type AgendaEntry,
  type NavFavorite,
  type NavTarget,
  type NexusTree,
  type PageDetail,
  type Personalization,
  type PinEntry,
  type PreviewSetRecord,
  type PreviewsFile,
  type RecentEntry,
  type SelectionState,
  type SelectTarget,
  type SetNode,
  type Tab,
} from '@shared/types'
import { DEFAULT_NEW_NAME, type MutableKind, type MutateRequest } from '@shared/mutate'
import { buildReconcileIndex, reconcileSelection, reconcileWith } from './selection'
import {
  closeTabIn,
  deriveTarget,
  openTabIn,
  type PreviewState,
  type PreviewTab,
} from './PagePreview/previewTabs'
import { navKey, recordRecent, removeRecentByKey, RECENTS_CAP } from './Navigation/navRecents'
import { byOrder, cleanPinTarget, pinFor, reorderTo } from './Navigation/navPins'
import {
  activeUnpinnedTab,
  closeTab as closeTabModel,
  derivePinnedTabs,
  insertUnpinned,
  isPinned,
  newTabTab,
  openNewTab as openNewTabModel,
  openTab as openTabModel,
  pinTabId,
  pushMru,
  reconcileTabs,
  reorderWithinZone,
  tabKey,
} from './Tabs/tabsModel'
import { captureWarm, clearWarm, dropWarmTab, readWarm } from './Tabs/warmCache'
import { flushActivePage, flushPreviewPage } from './Detail/pageFlush'
import { dropCapturedOutside } from './Navigation/useNavThumbnails'
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
const clampSidebar = (w: number): number =>
  Math.max(SIDEBAR_MIN, Math.min(SIDEBAR_MAX, Math.round(w)))
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
const clampInspector = (w: number): number =>
  Math.max(INSPECTOR_MIN, Math.min(INSPECTOR_MAX, Math.round(w)))
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

/** The Page Preview floating window's target page. */
export type PreviewTarget = { id: string; path: string }

/** A breadcrumb ghost crumb's target — the last page visited in a given container. */
export interface TrailEntry {
  id: string
  path: string
  title: string
}

/** Nexus-relative path of a top Collection or any nested Set by id (ungrouped + sectioned). */
function findContainerPath(tree: NexusTree, id: string): string | null {
  const cols = [
    ...(tree.collections ?? []),
    ...tree.userSections.flatMap((s) => s.collections ?? []),
  ]
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
  /** Cold-switch pause: the outgoing view is input-frozen (its last frame stays up) while the
   *  incoming page fetches — the swap then lands in one commit (no loading intermediate). */
  pageFrozen: boolean
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
  /** Reorder within the unpinned strip (D-4b) — pinned reorder is the pins slice's reorderPin. */
  reorderTabs: (activeId: string, overId: string) => void
  /** Pin an unpinned tab: the entity joins the pins set and the tab graduates to the derived pinned
   *  zone (C-6 — never dual-stored). */
  pinTab: (id: string) => void
  /** Unpin a pinned tab: the pin is removed and the entity re-enters the unpinned strip at the
   *  front (D-11 promote-to-front). */
  unpinTab: (pinId: string) => void
  /** Step the ACTIVE tab's own Back/Forward history (D-7), skipping deleted entries. */
  goBack: () => void
  goForward: () => void
  /** Transient direction stamp for a navigation that swaps the shown view: a Back/Forward step
   *  ('history'), a tab switch ('tab', direction by strip order), or a genuine select from any surface
   *  ('select' — sidebar, NavWindow, gallery; always forward). The detail view slides in this direction
   *  when the swap commits; the active tab's label slides for every source but 'tab' (a tab switch
   *  doesn't change it); seq re-triggers per step. */
  navSlide: {
    tabId: string
    dir: 'back' | 'forward'
    seq: number
    source: 'history' | 'tab' | 'select'
  } | null

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
  applyNavChanged: (nav: {
    recents: RecentEntry[]
    favorites: NavFavorite[]
    pins: PinEntry[]
  }) => void
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
  /** Reorder within the recents flow (gallery drag) — the nudge becomes the persisted order; a later
   *  visit only re-fronts the one visited entry (recordRecent). */
  reorderRecent: (activeKey: string, overKey: string) => void
  /** Persist an explicit recents order (the NavWindow's frozen-view drag): the listed keys take that
   *  exact relative order; unlisted (newer) entries keep their MRU slots ahead of them. */
  setRecentsOrder: (keys: string[]) => void
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

  /** The Page Preview floating window (Decision Log H): null = closed. One floating window
   *  total (D-8): opening either the preview or the NavWindow closes the other. */
  preview: PreviewState | null
  /** The in-memory mirror of `page-previews.json` (H-3) — loaded once per nexus, updated on every
   *  preview mutation, saved fire-and-forget (main debounces + drains). */
  previewsFile: PreviewsFile
  /** DERIVED from `preview` (the active page tab) — kept in lockstep by every preview action so
   *  the window's consumers read one stable shape. */
  previewTarget: PreviewTarget | null
  /** The preview's own slide stamp (H-11) — the app-wide navSlide is a single slot it can't share. */
  previewSlide: { dir: 'back' | 'fwd'; seq: number } | null
  openPreview: (target: PreviewTarget) => void
  openNavPreview: () => void
  openPreviewTab: (target: PreviewTarget) => void
  activatePreviewTab: (id: string) => void
  closePreviewTab: (id: string) => void
  closePreview: () => void

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
  mutate: (
    req: MutateRequest,
    onCreated?: (created: { id: string; path: string }) => void | Promise<void>,
  ) => Promise<boolean>
}

/** Whether a select target IS the currently-shown selection (same entity, same file) — a re-click
 *  that dedups to a no-op. Gates the select slide: nothing swaps, so nothing moves. */
function sameShownTarget(sel: SelectionState, t: SelectTarget): boolean {
  if (sel.kind !== t.kind) return false
  if (sel.kind === 'homepage') return true
  if (sel.kind === 'page') return t.kind === 'page' && sel.id === t.id && sel.path === t.path
  return 'id' in t && 'id' in sel && sel.id === t.id
}

// Cold page-fetch bookkeeping for the pause-on-change switch: every navigation bumps the seq so an
// in-flight fetch (and its deadline timer) can tell it was superseded; the deadline is how long the
// outgoing view may hold as a frozen frame before the loading view takes over. KNOB.
let pageFetchSeq = 0
const COLD_SWAP_DEADLINE = 200
// The navSlide seq an in-flight cold fetch is carrying — superseding that fetch abandons its
// navigation, so exactly that stamp (never a newer one, e.g. the superseder's own) must be cleared,
// or a later stampless selection change (a reconcile refetch) replays the abandoned slide.
let coldStampSeq = -1

// Homepage-lock writes in flight. applyTree reseeds `homepageLocked` from the canonical tree on
// every push, but the lock's own write is echo-suppressed (no self-push) — so an UNRELATED push
// landing mid-write would read the pre-commit homepage.json and revert the optimistic value with no
// follow-up push to heal it. While a local write is in flight we trust the optimistic value instead.
let homepageLockWritesInFlight = 0

export const useSession = create<SessionState>((set, get) => {
  // The wholesale per-nexus session reset (I-10): every adopt path clears the same state —
  // openVia BEFORE its adopt IPC (D-9 ordering), applyTree's foreign-root guard for adopts that
  // arrive main-first (the menu's reload-state). Clearing activeTabId marks the tab set
  // never-seeded, so load() re-reads the new nexus's sidecars.
  const resetNexusSession = (): void => {
    pageFetchSeq++
    set({
      selection: { kind: 'none' },
      pageStatus: 'idle',
      pageDetail: null,
      pageError: undefined,
      pageFrozen: false,
      liveBody: null,
      tabs: [],
      activeTabId: '',
      tabMru: [],
      preview: null,
      previewsFile: EMPTY_PREVIEWS,
      previewTarget: null,
      previewSlide: null,
    })
    clearWarm() // warmth is per-nexus AND session-only — never crosses an adoption (I-10)
  }

  // Shared "open attempt" path for the picker and drag-to-open: run the bridge
  // call; on success re-read state via load() (one read path). A rejected bridge
  // call routes to the error state instead of an unhandled rejection.
  const openVia = async (attempt: () => Promise<boolean>): Promise<void> => {
    try {
      // Close the preview BEFORE the root can flip (D-9), and AWAIT its registered flush — the
      // exit presence defers the unmount past the adopt, so the unmount flush alone would bind the
      // NEW root. Closed even if the adopt is then cancelled: data safety beats window persistence.
      set({ preview: null, previewTarget: null })
      await flushPreviewPage()
      // Flush the active page's pending body write to the CURRENT nexus before an adopt flips the root —
      // else the editor's unmount-flush (fired by the selection-clear below, after the root already moved)
      // writes the old body into the NEW nexus, overwriting a same-relative-path file there. Awaited so main
      // binds the OLD root; the flush clears the pending save, so that unmount-flush is then a no-op.
      await flushActivePage()
      if (await attempt()) {
        // A new nexus was adopted — reset before re-reading, so stale state doesn't linger
        // against the new tree (main drained the outgoing writes during the adopt).
        resetNexusSession()
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

  // The preview's slide stamp (H-11): direction = strip order (the app-tab rule), its own counter.
  let previewSlideSeq = 0
  const stampByOrder = (
    cur: PreviewState,
    nextId: string,
  ): { dir: 'back' | 'fwd'; seq: number } => {
    const from = cur.tabs.findIndex((t) => t.id === cur.activeTabId)
    const to = cur.tabs.findIndex((t) => t.id === nextId)
    return { dir: to < from ? 'back' : 'fwd', seq: ++previewSlideSeq }
  }

  const EMPTY_PREVIEWS: PreviewsFile = { navSet: null, origins: {}, open: null }

  const toPreviewRecord = (p: PreviewState): PreviewSetRecord => ({
    tabs: p.tabs.map((t) => ({ target: t.target })),
    activeIndex: Math.max(
      0,
      p.tabs.findIndex((t) => t.id === p.activeTabId),
    ),
  })

  // Mirror the slice into the sidecar (H-3/H-10): the live window updates its record + the open
  // pointer; `retire` drops a re-keyed or emptied origin (H-6). Fire-and-forget — main debounces
  // and drains at quit/switch; the optional chain tolerates test stubs without the bridge.
  const mirrorPreviews = (retire?: string): void => {
    const s = get()
    const p = s.preview
    let file = s.previewsFile
    if (retire && retire !== p?.originId) {
      const { [retire]: _dropped, ...origins } = file.origins
      file = { ...file, origins }
    }
    if (p) {
      const rec = toPreviewRecord(p)
      file =
        p.flavor === 'nav'
          ? { ...file, navSet: rec, open: { flavor: 'nav', originId: p.originId } }
          : {
              ...file,
              origins: { ...file.origins, [p.originId]: rec },
              open: { flavor: 'page', originId: p.originId },
            }
    } else {
      file = { ...file, open: null }
    }
    savePreviewsFile(file)
  }

  const savePreviewsFile = (file: PreviewsFile): void => {
    set({ previewsFile: file })
    void (window as { nexus?: typeof window.nexus }).nexus?.previews
      ?.save(file)
      .catch(() => undefined)
  }

  // Reconcile a remembered set's page tabs against the live tree (the H-10 restore): dead paths
  // drop, renames re-path, dupes dedup, ids re-mint. The stored-active survivor comes back so the
  // caller can keep it focused; sentinels are the caller's business (nav prepends its own).
  const reconcileRecord = (
    rec: PreviewSetRecord | null | undefined,
  ): { tabs: PreviewTab[]; activeTab: PreviewTab | null } => {
    if (!rec) return { tabs: [], activeTab: null }
    const tree = get().tree
    const index = tree ? buildReconcileIndex(tree) : null
    const seen = new Set<string>()
    const tabs: PreviewTab[] = []
    let activeTab: PreviewTab | null = null
    rec.tabs.forEach((t, i) => {
      if (t.target.kind !== 'page') return
      let target = t.target
      if (index) {
        const r = reconcileWith(index, target)
        if (r.kind === 'none') return
        if (r.kind === 'page' && r.path !== target.path) target = { ...target, path: r.path }
      }
      if (seen.has(target.id)) return
      seen.add(target.id)
      const tab = { id: makeTabId(), target }
      tabs.push(tab)
      if (i === rec.activeIndex) activeTab = tab
    })
    return { tabs, activeTab }
  }

  // The preview and its derived target move in lockstep (previewTarget is a Phase-2 casualty); commit
  // both from one place so no action can let them drift, and mirror the sidecar on every commit —
  // a window emptied or re-parented away from its origin retires the old key (H-6).
  const commitPreview = (
    next: PreviewState | null,
    extra?: { previewSlide: ReturnType<typeof stampByOrder> },
  ): void => {
    const prev = get().preview
    set({ preview: next, previewTarget: deriveTarget(next), ...extra })
    const retire =
      prev && prev.flavor === 'page' && prev.originId !== next?.originId ? prev.originId : undefined
    mirrorPreviews(retire)
  }

  // The active tab — an unpinned tab, or a derived pinned tab (which carries no unpinned back-history).
  const findActiveTab = (): Tab | undefined => {
    const s = get()
    return (
      s.tabs.find((t) => t.id === s.activeTabId) ??
      derivePinnedTabs(s.pins).find((t) => t.id === s.activeTabId)
    )
  }

  // Re-surface the active tab into the detail pane (a plain switch): a newtab tab routes to the empty
  // state; anything else re-selects WITHOUT recording (record:false). The target reconciles against
  // the live tree first — a derived pinned tab's stored path can be stale (pins are storage, tabs
  // reconcile live) — falling back to the raw target on a miss, mirroring the nav layer's click path.
  const syncActiveDetail = (): void => {
    const active = findActiveTab()
    if (!active || active.target.kind === 'newtab') {
      pageFetchSeq++
      set({
        selection: { kind: 'none' },
        pageStatus: 'idle',
        pageDetail: null,
        pageError: undefined,
        pageFrozen: false,
      })
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

  // Commit a tab-model result (close / tree-reconcile share this tail): only refetch the
  // detail when the active tab actually changed, and always persist. Warm-drops are per-caller (each
  // drops a different set) and order-independent of this commit, so they stay at the call site.
  const applyTabResult = (r: { tabs: Tab[]; activeTabId: string; mru: string[] }): void => {
    const activeChanged = r.activeTabId !== get().activeTabId
    set({ tabs: r.tabs, activeTabId: r.activeTabId, tabMru: r.mru })
    if (activeChanged) syncActiveDetail()
    persistTabs()
  }

  // C-6's live twin (the load-time filter covers only seeding): when an OPEN entity becomes pinned —
  // locally (pinTarget from any surface) or via a synced-in pin (applyNavChanged) — its unpinned tab
  // graduates to the derived pinned zone instead of duplicating beside it. The active pointer follows.
  const graduatePinCovered = (): void => {
    const s = get()
    const covered = s.tabs.filter((t) => t.target.kind !== 'newtab' && isPinned(t.target, s.pins))
    if (covered.length === 0) return
    const activeCovered = covered.find((t) => t.id === s.activeTabId)
    set({
      tabs: s.tabs.filter((t) => !covered.includes(t)),
      tabMru: s.tabMru.filter((m) => !covered.some((c) => c.id === m)),
    })
    for (const t of covered) dropWarmTab(t.id)
    if (activeCovered && activeCovered.target.kind !== 'newtab') {
      const pinId = pinTabId(activeCovered.target)
      set((st) => ({ activeTabId: pinId, tabMru: pushMru(st.tabMru, pinId) }))
    }
    persistTabs()
  }

  // Capture the outgoing page detail into the warm cache BEFORE a switch mutates selection —
  // `select` nulls pageDetail synchronously, so a capture any later would read the incoming tab's
  // state. Runs at the top of every path that changes what's shown; no-op off a ready page.
  const captureOutgoingDetail = (): void => {
    const s = get()
    if (s.selection.kind !== 'page' || s.pageStatus !== 'ready' || !s.pageDetail) return
    // Fold the live editing buffer in — pageDetail.body is the LOAD snapshot (autosave never updates
    // it), so a warm return would otherwise show pre-edit stats in the Subfield.
    const body = s.liveBody?.path === s.selection.path ? s.liveBody.body : s.pageDetail.body
    const detail = body === s.pageDetail.body ? s.pageDetail : { ...s.pageDetail, body }
    captureWarm(s.activeTabId, navKey(s.selection), { pageDetail: detail })
  }

  // Back/Forward replay over the ACTIVE tab's own history (D-7): walk in `delta` direction, resolving
  // each entry by id against the live tree (a renamed/moved entity → its fresh path) and skipping
  // deleted entries. A pinned/newtab active tab has no unpinned back-history, so this is a no-op.
  const stepActiveHistory = (delta: number): void => {
    const s = get()
    const active = activeUnpinnedTab(s.tabs, s.activeTabId)
    if (!active || active.target.kind === 'newtab') return
    for (let i = active.navIndex + delta; i >= 0 && i < active.navStack.length; i += delta) {
      const resolved = s.tree ? reconcileSelection(s.tree, active.navStack[i]) : active.navStack[i]
      if (resolved.kind === 'none') continue // entity gone — skip to the next live entry in this direction
      captureOutgoingDetail() // the entry being left stays warm for the return trip (I-7)
      // target moves in lockstep with navIndex — openTab's dedup keys off `target`, so a stale one
      // would mis-dedup the very next click on the shown entity (destroying the Forward stack).
      set({
        tabs: get().tabs.map((t) =>
          t.id === active.id ? { ...t, navIndex: i, target: resolved } : t,
        ),
        navSlide: {
          tabId: active.id,
          dir: delta < 0 ? 'back' : 'forward',
          seq: (s.navSlide?.seq ?? 0) + 1,
          source: 'history',
        },
      })
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
              set(
                nav.ok
                  ? { recents: nav.recents, favorites: nav.favorites }
                  : { recents: [], favorites: [] },
              )
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
              // The previews sidecar loads on the same once-per-nexus trigger; the stored `open`
              // pointer is a record, never an auto-summon (H-10).
              const previews = await window.nexus.previews?.load().catch(() => null)
              if (previews?.ok) set({ previewsFile: previews.file })
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
              // A pin whose entity vanished while the app was closed render-hides — it must NOT count as
              // live, or a stored active pointer at it dangles onto an error pane. The cold restore filters
              // pins for liveness exactly as the live applyTree path does; `active` is chosen off the live
              // set (not just handed to reconcileTabs, which short-circuits when no unpinned tab changed).
              const tree = get().tree
              const index = tree ? buildReconcileIndex(tree) : null
              const livePinnedTabs = index
                ? pinnedTabs.filter(
                    (t) =>
                      t.target.kind === 'newtab' || reconcileWith(index, t.target).kind !== 'none',
                  )
                : pinnedTabs
              const storedActive = storedSet?.activeTabId ?? ''
              const liveIds = new Set([...livePinnedTabs, ...tabs].map((t) => t.id))
              const active = liveIds.has(storedActive)
                ? storedActive
                : (tabs[0]?.id ?? livePinnedTabs[0]?.id ?? '')
              if (active === '') {
                // Nothing persisted and no live pins — a fresh nexus opens onto one NavView tab (E-2).
                const seeded = newTabTab(makeTabId())
                set({ tabs: [seeded], activeTabId: seeded.id, tabMru: [seeded.id] })
              } else {
                // Reconcile the restored set against the just-loaded tree — the app was closed while
                // entities moved or vanished: renames refresh in place, and a deleted entity's tab
                // closes instead of restoring onto an error pane.
                let restored = { tabs, activeTabId: active, mru: [active] }
                if (index) {
                  const rec = reconcileTabs(
                    tabs,
                    active,
                    [active],
                    livePinnedTabs.map((t) => t.id),
                    (t) => {
                      const r = reconcileWith(index, t)
                      return r.kind === 'none' ? null : r
                    },
                    makeTabId(),
                  )
                  restored = {
                    tabs: rec.tabs,
                    activeTabId: rec.activeTabId,
                    mru: rec.mru.length ? rec.mru : [rec.activeTabId],
                  }
                }
                set({
                  tabs: restored.tabs,
                  activeTabId: restored.activeTabId,
                  tabMru: restored.mru,
                })
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
      // ONE reset invariant for every adopt path: a tree from a DIFFERENT nexus (the menu's
      // reload-state adopts in main and never runs openVia's clear) wipes the per-nexus session
      // state BEFORE any reconcile below can mirror the old nexus's tabs/previews into the new
      // one's synced sidecars.
      const prevRoot = get().tree?.nexus.rootPath
      if (prevRoot !== undefined && prevRoot !== incoming.nexus.rootPath) resetNexusSession()
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
          pageFetchSeq++
          set({
            selection: next,
            pageStatus: 'idle',
            pageDetail: null,
            pageError: undefined,
            pageFrozen: false,
          })
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
          // A deleted entity's pinned tab render-hides — its id must NOT count as live, or an active
          // pointer at it would dangle with nothing focused.
          derivePinnedTabs(s.pins)
            .filter(
              (t) => t.target.kind === 'newtab' || reconcileWith(index, t.target).kind !== 'none',
            )
            .map((t) => t.id),
          (t) => {
            const r = reconcileWith(index, t)
            return r.kind === 'none' ? null : r
          },
          makeTabId(),
        )
        if (rec.changed) {
          for (const t of s.tabs) if (!rec.tabs.some((n) => n.id === t.id)) dropWarmTab(t.id) // deleted-entity closes
          applyTabResult({ tabs: rec.tabs, activeTabId: rec.activeTabId, mru: rec.mru })
        }
      }
      // The preview's tabs reconcile like app tabs (D-6): re-path on rename/move; a deleted page
      // closes its tab (the keyed embed unmounts; its flush hits a dead path, which the crud guard
      // refuses — the stale body is never written anywhere). Dead tabs fold through closeTabIn so
      // active-falls-left / origin re-parent / window-close-on-empty stay in one place.
      {
        const cur = get().preview
        if (cur) {
          const deadIds: string[] = []
          const repath = new Map<string, string>()
          for (const t of cur.tabs) {
            if (t.target.kind !== 'page') continue
            const r = reconcileWith(index, t.target)
            if (r.kind === 'none') deadIds.push(t.id)
            else if (r.kind === 'page' && r.path !== t.target.path) repath.set(t.id, r.path)
          }
          if (deadIds.length > 0 || repath.size > 0) {
            let next: PreviewState | null = cur
            for (const id of deadIds) next = next && closeTabIn(next, id)
            if (next && repath.size > 0)
              next = {
                ...next,
                tabs: next.tabs.map((t) => {
                  const path = repath.get(t.id)
                  return path && t.target.kind === 'page'
                    ? { ...t, target: { ...t.target, path } }
                    : t
                }),
              }
            commitPreview(next)
          }
        }
        // Sidecar hygiene: an origins key whose page no longer exists can never be re-summoned —
        // prune it (records re-path lazily at restore; only key liveness matters here).
        const file = get().previewsFile
        const dead = Object.keys(file.origins).filter((id) => {
          const own = file.origins[id].tabs.find(
            (t) => t.target.kind === 'page' && t.target.id === id,
          )?.target
          const path = own?.kind === 'page' ? own.path : ''
          return reconcileWith(index, { kind: 'page', id, path }).kind === 'none'
        })
        if (dead.length > 0) {
          const origins = { ...file.origins }
          for (const id of dead) delete origins[id]
          savePreviewsFile({ ...file, origins })
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
      void window.nexus.subfield
        .set({ order: s.subfieldOrder, expanded: s.subfieldExpanded })
        .catch(() => undefined)
    },
    subfieldOrder: {},
    setSubfieldOrder: (kind, ids) => {
      set((s) => ({ subfieldOrder: { ...s.subfieldOrder, [kind]: ids } }))
      const s = get()
      void window.nexus.subfield
        .set({ order: s.subfieldOrder, expanded: s.subfieldExpanded })
        .catch(() => undefined)
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
    pageFrozen: false,
    pageDetail: null,
    pageError: undefined,
    liveBody: null,
    setLiveBody: (path, body) => set({ liveBody: { path, body } }),
    tabs: [],
    activeTabId: '',
    tabMru: [],
    goBack: () => stepActiveHistory(-1),
    goForward: () => stepActiveHistory(1),
    navSlide: null,
    activateTab: (id) => {
      const s = get()
      if (s.activeTabId === id) return
      captureOutgoingDetail()
      // Direction by the strip's visual order (pinned zone, then the unpinned strip): the view slides
      // toward the tab you moved to.
      const order = [...derivePinnedTabs(s.pins).map((t) => t.id), ...s.tabs.map((t) => t.id)]
      const dir: 'back' | 'forward' =
        order.indexOf(id) < order.indexOf(s.activeTabId) ? 'back' : 'forward'
      set((st) => ({
        activeTabId: id,
        tabMru: pushMru(st.tabMru, id),
        navSlide: { tabId: id, dir, seq: (st.navSlide?.seq ?? 0) + 1, source: 'tab' },
      }))
      syncActiveDetail()
      persistTabs()
    },
    openNewTab: () => {
      captureOutgoingDetail()
      const s = get()
      const res = openNewTabModel(s.tabs, makeTabId())
      // No stamp when the + merely re-focuses the NavView already on screen — nothing swaps.
      const swaps = res.activeTabId !== s.activeTabId || s.selection.kind !== 'none'
      set({
        tabs: res.tabs,
        activeTabId: res.activeTabId,
        tabMru: pushMru(s.tabMru, res.activeTabId),
        ...(swaps
          ? {
              navSlide: {
                tabId: res.activeTabId,
                dir: 'forward' as const,
                seq: (s.navSlide?.seq ?? 0) + 1,
                source: 'tab' as const,
              },
            }
          : {}),
      })
      syncActiveDetail()
      persistTabs()
    },
    closeTab: (id) => {
      const s = get()
      const pinnedIds = derivePinnedTabs(s.pins).map((t) => t.id)
      const res = closeTabModel(s.tabs, s.activeTabId, s.tabMru, pinnedIds, id, makeTabId())
      dropWarmTab(id) // a closed tab's warm stack dies with it
      applyTabResult(res)
    },
    reorderTabs: (activeId, overId) => {
      const s = get()
      const to = s.tabs.findIndex((t) => t.id === overId)
      if (to === -1) return
      const next = reorderWithinZone(s.tabs, activeId, to)
      if (next === s.tabs) return
      set({ tabs: next })
      persistTabs()
    },
    // Pinning graduates the tab (pinTarget's C-6 twin does the tab-side move; pinTarget itself
    // refuses adopted ids, in which case nothing moves and the tab stays).
    pinTab: (id) => {
      const tab = get().tabs.find((t) => t.id === id)
      if (!tab || tab.target.kind === 'newtab') return
      get().pinTarget(tab.target)
    },
    unpinTab: (pinId) => {
      const pinnedTab = derivePinnedTabs(get().pins).find((t) => t.id === pinId)
      if (!pinnedTab || pinnedTab.target.kind === 'newtab') return
      const target = pinnedTab.target
      get().unpinTarget(navKey(target))
      // I-1: if the entity somehow already holds an unpinned tab, focus it instead of duplicating.
      const existing = get().tabs.find(
        (t) => t.target.kind !== 'newtab' && navKey(t.target) === navKey(target),
      )
      const tab: Tab = existing ?? { id: makeTabId(), target, navStack: [target], navIndex: 0 }
      if (!existing) set((s) => ({ tabs: insertUnpinned(s.tabs, s.activeTabId, tab) }))
      if (get().activeTabId === pinId)
        set((s) => ({
          activeTabId: tab.id,
          tabMru: pushMru(
            s.tabMru.filter((m) => m !== pinId),
            tab.id,
          ),
        }))
      dropWarmTab(pinId)
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
      graduatePinCovered()
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
      set({
        pins: get()
          .pins.map((p) => (navKey(p) === activeKey ? moved : p))
          .sort(byOrder),
      })
      void window.nexus.nav.reorderPin(moved)
    },
    loadPins: async () => {
      const res = await window.nexus.nav.loadPins().catch(() => null)
      if (res?.ok) set({ pins: [...res.pins].sort(byOrder) })
    },
    // Only pins swap on a live refresh — recents are debounce-written so in-memory leads disk; replacing
    // them from a pin/favorite-triggered push would clobber the user's latest (unsaved) navigations.
    applyNavChanged: (nav) => {
      set({ pins: [...nav.pins].sort(byOrder) })
      graduatePinCovered() // a synced-in pin covers a locally-open tab exactly like a local pin does
      // A synced-in UNPIN can orphan the active pointer: the pinned tab it derived vanishes, but nothing
      // refocuses the pointer (graduatePinCovered only handles the add case). Refocus MRU-top so it
      // doesn't dangle onto a stale pane (mirror reconcileTabs' focus).
      const s = get()
      const live = new Set([
        ...derivePinnedTabs(s.pins).map((t) => t.id),
        ...s.tabs.map((t) => t.id),
      ])
      if (!live.has(s.activeTabId)) {
        const focus =
          s.tabMru.find((id) => live.has(id)) ?? s.tabs[0]?.id ?? derivePinnedTabs(s.pins)[0]?.id
        if (focus !== undefined) {
          // pushMru covers the fallback focus (a tab absent from the MRU) — the top must be the active.
          set({
            activeTabId: focus,
            tabMru: pushMru(
              s.tabMru.filter((id) => live.has(id)),
              focus,
            ),
          })
          syncActiveDetail()
        }
      }
    },
    thumbVersions: {},
    bumpThumb: (key) =>
      set((s) => ({
        thumbVersions: { ...s.thumbVersions, [key]: (s.thumbVersions[key] ?? 0) + 1 },
      })),
    evictThumbs: () => {
      const live = [...get().recents.map(navKey), ...get().pins.map(navKey)]
      dropCapturedOutside(new Set(live)) // the capture gate's markers die with the files they vouch for
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
    reorderRecent: (activeKey, overKey) => {
      const recents = get().recents
      const from = recents.findIndex((r) => navKey(r) === activeKey)
      const to = recents.findIndex((r) => navKey(r) === overKey)
      if (from === -1 || to === -1 || from === to) return
      const next = [...recents]
      const [moved] = next.splice(from, 1)
      next.splice(to, 0, moved)
      set({ recents: next })
      void window.nexus.nav.saveRecents(next, true) // immediate, like the pin toggle
    },
    setRecentsOrder: (keys) => {
      // The frozen NavWindow view can lag the store (a click re-fronts its entry mid-open), so an
      // (active, over) splice against the LIVE order lands elsewhere than the drop showed. Writing the
      // shown order wholesale is the faithful commit; entries recorded since the snapshot (unlisted)
      // keep their newer MRU slots ahead of it.
      const s = get()
      const pos = new Map(keys.map((k, i) => [k, i]))
      const listed = s.recents.filter((r) => pos.has(navKey(r)))
      listed.sort((a, b) => (pos.get(navKey(a)) ?? 0) - (pos.get(navKey(b)) ?? 0))
      const next = [...s.recents.filter((r) => !pos.has(navKey(r))), ...listed]
      if (next.every((r, i) => r === s.recents[i])) return
      set({ recents: next })
      void window.nexus.nav.saveRecents(next, true)
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
      const hadPreview = get().preview !== null
      set({ navOpen: true, preview: null, previewTarget: null })
      if (hadPreview) mirrorPreviews() // D-8 closed the preview — record `open` cleared
    },
    closeNav: () => set({ navOpen: false }),
    toggleNav: () => {
      if (!get().navOpen) void get().ensureAgendaSnapshot()
      const hadPreview = get().preview !== null
      set((s) => ({ navOpen: !s.navOpen, preview: null, previewTarget: null }))
      if (hadPreview) mirrorPreviews()
    },
    preview: null,
    previewsFile: EMPTY_PREVIEWS,
    previewTarget: null,
    previewSlide: null,
    openPreview: (target) => {
      const cur = get().preview
      if (cur?.flavor === 'page' && cur.originId === target.id) return // I-1: same-origin no-op
      // H-3: a summon restores the origin's remembered set, reconciled; an emptied or absent
      // record falls back to the bare origin.
      const { tabs: restored, activeTab } = reconcileRecord(get().previewsFile.origins[target.id])
      const tabs =
        restored.length > 0
          ? restored
          : [{ id: makeTabId(), target: { kind: 'page' as const, ...target } }]
      const preview: PreviewState = {
        flavor: 'page',
        originId: target.id,
        tabs,
        activeTabId: (activeTab ?? tabs[0]).id,
      }
      set({ preview, previewTarget: deriveTarget(preview), navOpen: false })
      mirrorPreviews()
    },
    openNavPreview: () => {
      if (get().preview?.flavor === 'nav') return
      // H-2: the map sentinel is always tab 1; the remembered page tabs restore after it.
      const { tabs: pages, activeTab } = reconcileRecord(get().previewsFile.navSet)
      const sentinel = { id: makeTabId(), target: { kind: 'navwindow' as const } }
      const preview: PreviewState = {
        flavor: 'nav',
        originId: 'navwindow',
        tabs: [sentinel, ...pages],
        activeTabId: (activeTab ?? sentinel).id,
      }
      set({ preview, previewTarget: deriveTarget(preview), navOpen: false })
      mirrorPreviews()
    },
    openPreviewTab: (target) => {
      const cur = get().preview
      // H-7 lives at the caller (the behind-the-window gate needs the main selection); here a
      // tab-less call is a summon.
      if (!cur) {
        get().openPreview(target)
        return
      }
      const next = openTabIn(cur, makeTabId, target)
      if (next === cur) return
      const spawned = next.tabs.length > cur.tabs.length
      commitPreview(next, {
        previewSlide: spawned
          ? { dir: 'fwd', seq: ++previewSlideSeq }
          : stampByOrder(cur, next.activeTabId),
      })
    },
    activatePreviewTab: (id) => {
      const cur = get().preview
      if (!cur || cur.activeTabId === id || !cur.tabs.some((t) => t.id === id)) return
      const next = { ...cur, activeTabId: id }
      commitPreview(next, { previewSlide: stampByOrder(cur, id) })
    },
    closePreviewTab: (id) => {
      const cur = get().preview
      if (!cur) return
      const next = closeTabIn(cur, id)
      if (next === cur) return
      commitPreview(next)
    },
    closePreview: () => {
      // X/Escape: the window closes but its set stays remembered (H-3) — only `open` clears.
      set({ preview: null, previewTarget: null })
      mirrorPreviews()
    },
    select: async (target, opts) => {
      // Every navigation supersedes an in-flight cold page fetch (its response drops on the seq fence
      // below) and releases a pause left by one.
      pageFetchSeq++
      if (get().pageFrozen) {
        const s = get()
        set(
          s.navSlide?.seq === coldStampSeq
            ? { pageFrozen: false, navSlide: null }
            : { pageFrozen: false },
        )
      }
      // A genuine navigation (record !== false) maintains the tab set — dedup/replace/spawn per the
      // active tab's pin state (D-3b) — and records recents. A programmatic re-select (Back/Forward, a
      // path refetch, a tab activation) passes { record: false } and does neither; it only refreshes the
      // shown detail below. Recents record ONLY when a tab actually opened (a spawn or in-place replace),
      // never on a focus/re-surface of an already-open tab (C-5).
      if (opts?.record !== false) {
        captureOutgoingDetail()
        const s = get()
        const pinned = derivePinnedTabs(s.pins)
        const res = openTabModel(
          s.tabs,
          s.activeTabId,
          pinned,
          target,
          { newTab: opts?.newTab },
          makeTabId(),
        )
        const opened = res.tabs !== s.tabs
        // A genuine select slides the view in (forward — new ground) — but never on a re-click of the
        // entity already shown (a dedup no-op swaps nothing, so it must move nothing).
        set({
          tabs: res.tabs,
          activeTabId: res.activeTabId,
          tabMru: pushMru(s.tabMru, res.activeTabId),
          ...(sameShownTarget(s.selection, target)
            ? {}
            : {
                navSlide: {
                  tabId: res.activeTabId,
                  dir: 'forward' as const,
                  seq: (s.navSlide?.seq ?? 0) + 1,
                  source: 'select' as const,
                },
              }),
        })
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
          set({
            selection: { kind: 'homepage' },
            pageStatus: 'idle',
            pageDetail: null,
            pageError: undefined,
          })
          return
        case 'context':
          // A context (area/topic/project) renders a blank page from the loaded tree — no fetch.
          set({
            selection: { kind: 'context', id: target.id },
            pageStatus: 'idle',
            pageDetail: null,
            pageError: undefined,
          })
          return
        case 'collection': {
          // Collection detail renders from the loaded tree (banner + its pages) — no fetch.
          set({
            selection: { kind: 'collection', id: target.id },
            pageStatus: 'idle',
            pageDetail: null,
            pageError: undefined,
          })
          // Entry-mint (G-1): a view-bearing container with an empty views[] gets its default minted
          // here, the sole mint site. A fired side-effect — the case stays synchronous for render.
          const col = findCollection(get().tree, target.id)
          if (col) ensureContainerView(col, col.properties ?? [], get().load)
          return
        }
        case 'set': {
          // A depth-1 Set's detail renders from the loaded tree (banner + its pages) — no fetch.
          set({
            selection: { kind: 'set', id: target.id, path: target.path },
            pageStatus: 'idle',
            pageDetail: null,
            pageError: undefined,
          })
          // Only a DEPTH-1 Set carries views (a reparented Sub-Set can reach here via Back-nav).
          const setNode = findSet(get().tree, target.id)
          if (setNode && isDepth1Set(get().tree, target.id))
            ensureContainerView(
              setNode,
              findCollectionForSet(get().tree, target.id)?.properties ?? [],
              get().load,
            )
          return
        }
        case 'page': {
          // Warm-instant (B-3): a warm entity under the active tab renders its cached detail with no
          // fetch and no loading flash. The path equality keeps it honest across renames — a stale-path
          // detail would route saves at the old file — and a miss falls through to the cold fetch.
          const cached = readWarm(get().activeTabId, navKey(target))?.pageDetail
          if (cached && cached.path === target.path) {
            // liveBody repoints with the restore so the Subfield reads the restored page, not the one
            // last typed in.
            set({
              selection: { kind: 'page', id: target.id, path: target.path },
              pageStatus: 'ready',
              pageDetail: cached,
              pageError: undefined,
              liveBody: { path: cached.path, body: cached.body },
            })
            return
          }
          // Pause-on-change: the outgoing view holds as its last frame (input-frozen) while the fetch
          // runs, and selection + detail land in ONE commit — no loading intermediate on the common
          // fast fetch. Past the deadline the loading view takes over so a slow read never feels dead.
          // The seq fence drops a stale response (and a stale deadline) after any newer navigation.
          const seq = pageFetchSeq
          coldStampSeq = get().navSlide?.seq ?? -1
          const pageSel = { kind: 'page' as const, id: target.id, path: target.path }
          set({ pageFrozen: true })
          const fallback = setTimeout(() => {
            if (seq !== pageFetchSeq) return
            set({
              selection: pageSel,
              pageStatus: 'loading',
              pageDetail: null,
              pageError: undefined,
              pageFrozen: false,
            })
          }, COLD_SWAP_DEADLINE)
          let res: Awaited<ReturnType<typeof window.nexus.openPage>>
          try {
            res = await window.nexus.openPage(target.path)
          } catch (e) {
            res = { ok: false, error: e instanceof Error ? e.message : String(e) }
          }
          clearTimeout(fallback)
          if (seq !== pageFetchSeq) return
          if (res.ok) {
            set({
              selection: pageSel,
              pageStatus: 'ready',
              pageDetail: res.page,
              pageError: undefined,
              pageFrozen: false,
            })
          } else {
            set({
              selection: pageSel,
              pageStatus: 'error',
              pageDetail: null,
              pageError: res.error,
              pageFrozen: false,
            })
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
      if (selection.kind === 'collection' || selection.kind === 'set')
        parentPath = findContainerPath(tree, selection.id)
      else if (selection.kind === 'page')
        parentPath = selection.path.split('/').slice(0, -1).join('/')
      if (parentPath === null) {
        parentPath =
          (tree.collections ?? [])[0]?.path ??
          tree.userSections.flatMap((s) => s.collections ?? [])[0]?.path ??
          null
      }
      if (parentPath === null) return // no container to create into
      // main disambiguates the name on collision; select the new page once it lands.
      await get().mutate({ op: 'createPage', parentPath, name: DEFAULT_NEW_NAME }, (created) =>
        get().select({ kind: 'page', id: created.id, path: created.path }),
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
      const res = await window.nexus.schema.rename(
        target.collectionPath,
        target.propertyId,
        newName,
      )
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
    },
  }
})
