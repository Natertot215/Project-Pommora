import { contextBridge, ipcRenderer, webUtils } from 'electron'
import type { IpcRendererEvent } from 'electron'
import type {
  AgendaListResult,
  NavChanged,
  NavFavorite,
  NavStateResult,
  NavTarget,
  NavViewModes,
  NexusState,
  NexusTree,
  OpenIn,
  PageResult,
  Personalization,
  PinEntry,
  PinsResult,
  PreviewsFile,
  PreviewsResult,
  RecentEntry,
  SubfieldConfig,
  TabSet,
  TabsResult,
  ThumbRect,
  ThumbResult,
  ViewButton,
  ViewStyle,
} from '@shared/types'
import type { MutateRequest, MutateResult, ContextTarget } from '@shared/mutate'
import type { FormatState } from '@shared/editorMenu'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'
import type { CalloutMenuAction } from '@shared/calloutMenu'
import type { CellMenuAction, CellMenuContext } from '@shared/cellMenu'
import type { CardMenuAction, CardMenuContext } from '@shared/cardMenu'
import type { ConnMenuAction } from '@shared/connections'
import type { TabMenuAction, TabMenuContext } from '@shared/tabMenu'
import type { NavRowMenuAction, NavRowMenuContext } from '@shared/navRowMenu'
import type { PropertyMenuAction, PropertyMenuContext } from '@shared/propertyMenu'
import type { OptionMenuAction, OptionMenuContext } from '@shared/optionMenu'
import type { ColumnMenuAction, ColumnMenuContext } from '@shared/columnMenu'
import type { SavedView } from '@shared/views'
import type {
  BlockDocPatch,
  BlockHostRef,
  BlockStyle,
  BlocksGetResult,
  BlocksSaveResult,
  EmbeddedView,
} from '@shared/blocks'
import type { StatusGroup } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import type { PropertyDefinition, PropertyType } from '@shared/properties'

// The ONLY API the renderer can see. Narrow read surface; no fs, no Node.
const api = {
  state: (): Promise<NexusState> => ipcRenderer.invoke('nexus:state'),
  choose: (): Promise<boolean> => ipcRenderer.invoke('nexus:choose'),
  // Resolve a dropped folder's path here (the renderer can't) and send only the
  // path to main — the absolute path never enters web content.
  openDropped: (file: File): Promise<boolean> =>
    ipcRenderer.invoke('nexus:openPath', webUtils.getPathForFile(file)),
  openPage: (relPath: string): Promise<PageResult> => ipcRenderer.invoke('page:open', relPath),
  // Debounced editor body write (relative path); main resolves under the session root + preserves frontmatter.
  updatePageBody: (
    relPath: string,
    body: string,
  ): Promise<{ ok: true } | { ok: false; error: string }> =>
    ipcRenderer.invoke('page:updateBody', relPath, body),
  // Heading-fold UI state — local `.nexus/folds.json`, keyed by page id (per-machine, not frontmatter).
  folds: {
    get: (): Promise<Record<string, string[]>> => ipcRenderer.invoke('folds:get'),
    set: (pageId: string, keys: string[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('folds:set', pageId, keys),
  },
  // Active-view pointer — local `.nexus/activeViews.json`, container id → active view id (per-machine).
  activeViews: {
    get: (): Promise<Record<string, string>> => ipcRenderer.invoke('activeViews:get'),
    set: (
      containerId: string,
      viewId: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('activeViews:set', containerId, viewId),
  },
  // Sorted-view manual order — local `.nexus/viewOrders.json`, view id → page-id tiebreaker (per-machine).
  viewOrders: {
    get: (): Promise<Record<string, string[]>> => ipcRenderer.invoke('viewOrders:get'),
    set: (viewId: string, order: string[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('viewOrders:set', viewId, order),
  },
  // View persistence — save / reorder / delete a SavedView in a Collection/Set sidecar's views[].
  views: {
    save: (
      containerPath: string,
      kind: 'collection' | 'set',
      view: SavedView,
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:save', containerPath, kind, view),
    reorder: (
      containerPath: string,
      kind: 'collection' | 'set',
      orderedIds: string[],
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:reorder', containerPath, kind, orderedIds),
    delete: (
      containerPath: string,
      kind: 'collection' | 'set',
      viewId: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:delete', containerPath, kind, viewId),
  },
  // Per-container non-view settings (open_in is collection-only; view_button / view_style either tier).
  container: {
    configure: (
      containerPath: string,
      kind: 'collection' | 'set',
      patch: { open_in?: OpenIn; view_button?: ViewButton; view_style?: ViewStyle },
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('container:configure', containerPath, kind, patch),
  },
  // The ViewDropdown right-click menu — resolves the picked action (or null on dismiss).
  viewButtonMenu: (current: {
    viewButton: ViewButton
    viewStyle: ViewStyle
  }): Promise<'toggle-title' | 'style-dropdown' | 'style-toolbar' | null> =>
    ipcRenderer.invoke('view-button-menu', current),
  // The view embed's title-row right-click menu (Hide/Show Icon · Title Size · Hide Title).
  viewEmbedTitleMenu: (arg: {
    iconShown: boolean
    level: number
  }): Promise<'toggle-icon' | 'hide-title' | `size-${number}` | null> =>
    ipcRenderer.invoke('view-embed-title-menu', arg),
  // The view embed switcher area's right-click menu (Hide/Show Titles · New View · Style).
  viewEmbedAreaMenu: (current: {
    viewButton: ViewButton
    viewStyle: ViewStyle
    titleShown: boolean
  }): Promise<
    'toggle-pill-titles' | 'show-title' | 'new-view' | 'style-dropdown' | 'style-toolbar' | null
  > => ipcRenderer.invoke('view-embed-area-menu', current),
  // The ViewSettings ⋮ menu (Duplicate / Delete); Delete disabled when the view can't be removed.
  viewItemMenu: (canDelete: boolean): Promise<'view:duplicate' | 'view:delete' | null> =>
    ipcRenderer.invoke('view-item-menu', canDelete),
  // A ViewPane view row's right-click menu (Rename / Edit Icon / Delete); Delete disabled on the last view.
  viewRowMenu: (
    canDelete: boolean,
  ): Promise<'view:rename' | 'view:edit-icon' | 'view:delete' | null> =>
    ipcRenderer.invoke('view-row-menu', canDelete),
  // The icon picker's right-click Favorite/Remove menu — resolves 'toggle' on click, null on dismiss.
  iconFavoriteMenu: (favorited: boolean): Promise<'toggle' | null> =>
    ipcRenderer.invoke('icon-favorite-menu', favorited),
  // Property schema CRUD on a Collection's page schema. containerPath is the schema-owning
  // Collection's folder (a Set inherits, so the renderer passes its ancestor Collection's path).
  schema: {
    add: (
      containerPath: string,
      def: PropertyDefinition,
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:add', containerPath, def),
    rename: (
      containerPath: string,
      propertyId: string,
      newName: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:rename', containerPath, propertyId, newName),
    reorder: (
      containerPath: string,
      propertyId: string,
      toIndex: number,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:reorder', containerPath, propertyId, toIndex),
    delete: (
      containerPath: string,
      propertyId: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:delete', containerPath, propertyId),
    assign: (
      containerPath: string,
      propertyId: string,
      toIndex?: number,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:assign', containerPath, propertyId, toIndex),
    changeType: (
      containerPath: string,
      propertyId: string,
      newType: PropertyType,
      opts?: { dropConflictingValues?: boolean },
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:changeType', containerPath, propertyId, newType, opts),
  },
  // Nexus-wide property ops (registry-level, no container scope). `property.delete` is the
  // global destructive op — snapshot, scrub every collection, purge caches, drop the def;
  // `schema.delete` above is the per-Collection Remove (strip + cache restorably). The option
  // ops edit a Select/Multi property's options globally: setOptions (add/recolor/reorder),
  // renameOption (cascades the value onto pages), removeOption/clearOption (strip pages).
  property: {
    delete: (propertyId: string): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:delete', propertyId),
    setOptions: (
      propertyId: string,
      options: { value: string; label: string; color?: string }[],
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setOptions', propertyId, options),
    setStatusGroups: (
      propertyId: string,
      groups: StatusGroup[],
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setStatusGroups', propertyId, groups),
    // Registry-only display config for a URL / Link property (underline, full-url ⇄ title, color).
    setLinkConfig: (
      propertyId: string,
      patch: {
        link_underline?: boolean
        link_display?: 'link-url' | 'link-title'
        link_color?: string
      },
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setLinkConfig', propertyId, patch),
    // Registry-only display config for a Checkbox property: its property-wide color (undefined = Default).
    setCheckboxColor: (
      propertyId: string,
      color: string | undefined,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setCheckboxColor', propertyId, color),
    // Registry-only: a property's icon (a symbol id; undefined = the type's default glyph).
    setIcon: (
      propertyId: string,
      icon: string | undefined,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setIcon', propertyId, icon),
    // Registry-only display config for a Number property: its property-wide format fields.
    setNumberFormat: (
      propertyId: string,
      patch: {
        number_family?: 'number' | 'percent' | 'currency'
        number_currency?: string
        number_separators?: boolean
        number_decimals?: 'hidden' | number
        number_fraction?: boolean
        number_denominator?: number
      },
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setNumberFormat', propertyId, patch),
    renameOption: (
      propertyId: string,
      oldValue: string,
      newTitle: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:renameOption', propertyId, oldValue, newTitle),
    removeOption: (
      propertyId: string,
      value: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:removeOption', propertyId, value),
    clearOption: (
      propertyId: string,
      value: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:clearOption', propertyId, value),
    // Status variants of the page-touching ops — same cascade, keyed on the Status property's
    // `status_groups`. Rename cascades the new value onto pages; remove/clear strip it.
    renameStatusOption: (
      propertyId: string,
      oldValue: string,
      newTitle: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:renameStatusOption', propertyId, oldValue, newTitle),
    removeStatusOption: (
      propertyId: string,
      value: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:removeStatusOption', propertyId, value),
    clearStatusOption: (
      propertyId: string,
      value: string,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:clearStatusOption', propertyId, value),
  },
  // The nexus-wide cosmetic property order (B-1) — how every collection's All Properties lists.
  registry: {
    reorder: (
      propertyId: string,
      toIndex: number,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('registry:reorder', propertyId, toIndex),
  },
  // Batch frontmatter read for a container's view pipeline (pageId → frontmatter), lazy on open.
  loadValues: (containerPath: string): Promise<Record<string, PageFrontmatter>> =>
    ipcRenderer.invoke('view:loadValues', containerPath),
  // Table heading-column UI state — local `.nexus/tableHeadingColumns.json`, keyed by page id. Holds the
  // indices of the tables whose first column renders as a heading (a Pommora-only visual, not in the .md).
  tableHeadingColumns: {
    get: (): Promise<Record<string, number[]>> => ipcRenderer.invoke('tableHeadingCols:get'),
    set: (
      pageId: string,
      indices: number[],
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('tableHeadingCols:set', pageId, indices),
  },
  // The block document behind the BlockHost seam — targeted per-host load + locked
  // partial writes (layout / blocks / locked) on the host's config.
  blocks: {
    get: (host: BlockHostRef): Promise<BlocksGetResult> => ipcRenderer.invoke('blocks:get', host),
    save: (host: BlockHostRef, patch: BlockDocPatch): Promise<BlocksSaveResult> =>
      ipcRenderer.invoke('blocks:save', host, patch),
    // Markdown-block lifecycle: create mints the ULID + file + entry (the renderer splices
    // the layout after); remove drops the entry + trashes a markdown tile's file; the
    // read/write pair is the tile editor's pure-body persistence.
    createMarkdown: (
      host: BlockHostRef,
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('blocks:createMarkdown', host),
    removeTile: (host: BlockHostRef, tileId: string): Promise<BlocksSaveResult> =>
      ipcRenderer.invoke('blocks:removeTile', host, tileId),
    readMarkdown: (
      host: BlockHostRef,
      tileId: string,
    ): Promise<{ ok: true; body: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('blocks:readMarkdown', host, tileId),
    writeMarkdown: (host: BlockHostRef, tileId: string, body: string): Promise<BlocksSaveResult> =>
      ipcRenderer.invoke('blocks:writeMarkdown', host, tileId, body),
    // Link Page: the entry becomes a page embed; a markdown tile's .md trashes.
    convertToPage: (
      host: BlockHostRef,
      tileId: string,
      pageId: string,
    ): Promise<BlocksSaveResult> =>
      ipcRenderer.invoke('blocks:convertToPage', host, tileId, pageId),
    // Link View: the entry becomes a view embed carrying the COPIED config (D-12);
    // main re-mints each config id payload-local.
    convertToView: (
      host: BlockHostRef,
      tileId: string,
      views: EmbeddedView[],
    ): Promise<BlocksSaveResult> => ipcRenderer.invoke('blocks:convertToView', host, tileId, views),
    // Duplicate a tile — raw-entry copy under a fresh id; markdown copies its file,
    // a view tile re-mints its config ids.
    duplicateTile: (
      host: BlockHostRef,
      tileId: string,
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('blocks:duplicateTile', host, tileId),
    // Delete keeps the native confirm (Nathan's call).
    confirmRemove: (): Promise<boolean> => ipcRenderer.invoke('blocks:confirmRemove'),
  },
  // Subfield (footer) config — React-owned `subfield` key in `.nexus/settings.json`.
  subfield: {
    get: (): Promise<SubfieldConfig | null> => ipcRenderer.invoke('subfield:get'),
    set: (config: SubfieldConfig): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('subfield:set', config),
  },
  // Nav view modes (List/Gallery per surface) — React-owned `navViewModes` key.
  navViewModes: {
    get: (): Promise<NavViewModes | null> => ipcRenderer.invoke('navViewModes:get'),
    set: (modes: NavViewModes): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('navViewModes:set', modes),
  },
  // Agenda read for the sidebar's Agenda mode — lazy, called only when that mode is active.
  agenda: {
    list: (): Promise<AgendaListResult> => ipcRenderer.invoke('agenda:list'),
  },
  // Navigation layer — recents/favorites persistence. The renderer owns the arrays; main persists.
  // saveRecents debounces main-side (immediate=true for the pin toggle); saveFavorites is immediate.
  nav: {
    load: (): Promise<NavStateResult> => ipcRenderer.invoke('nav:load'),
    saveRecents: (
      entries: RecentEntry[],
      immediate?: boolean,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:saveRecents', entries, immediate),
    saveFavorites: (entries: NavFavorite[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:saveFavorites', entries),
    loadPins: (): Promise<PinsResult> => ipcRenderer.invoke('nav:loadPins'),
    addPin: (pin: PinEntry): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:addPin', pin),
    reorderPin: (pin: PinEntry): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:reorderPin', pin),
    removePin: (
      target: NavTarget,
      order: number,
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:removePin', target, order),
  },
  // The tab set — synced tabs.json (unpinned tabs + active + per-tab history targets); saves debounce main-side.
  tabs: {
    load: (): Promise<TabsResult> => ipcRenderer.invoke('tabs:load'),
    save: (set: TabSet): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('tabs:save', set),
  },
  // The preview tab sets — synced page-previews.json (nav set + per-origin sets + open pointer).
  previews: {
    load: (): Promise<PreviewsResult> => ipcRenderer.invoke('previews:load'),
    save: (file: PreviewsFile): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('previews:save', file),
  },
  // Gallery thumbnails — capture the detail-pane rect (main writes under .nexus/assets and returns the
  // nexus-asset:// URL); evict prunes thumbnails outside the live recents∪pins set.
  capture: {
    thumbnail: (navKey: string, rect: ThumbRect, scaleFactor: number): Promise<ThumbResult> =>
      ipcRenderer.invoke('capture:thumbnail', navKey, rect, scaleFactor),
    evict: (liveKeys: string[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('nav:evictThumbs', liveKeys),
  },
  // Personalization (accent, connection color, interface toggles) — persist one key; the tree
  // surfaces current values (state → tree.personalization), so there's no get.
  personalization: {
    set: <K extends keyof Personalization>(
      key: K,
      value: Personalization[K],
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('personalization:set', key, value),
  },
  // Renderer-initiated write (relative paths only); main resolves under the session root.
  mutate: (req: MutateRequest): Promise<MutateResult> => ipcRenderer.invoke('mutate', req),
  // Right-click an entity → main pops a native context menu + acts on it.
  contextMenu: (target: ContextTarget): Promise<void> => ipcRenderer.invoke('context-menu', target),
  // Push the editor's active formatting state so the native right-click menu renders accurate state.
  setEditorFormatState: (state: FormatState): void =>
    ipcRenderer.send('editor:format-state', state),
  // JS window mover for hover-bearing chrome (the tab bar): a native app-region never delivers hover,
  // so the bar drives the move itself — per-pointermove screen deltas, fire-and-forget. Double-click
  // zooms, the macOS titlebar convention.
  winDragBy: (dx: number, dy: number): void => ipcRenderer.send('win:dragBy', dx, dy),
  winZoom: (): void => ipcRenderer.send('win:zoom'),
  // Pop a native "New …" menu (e.g. the context tiers) + run the chosen create main-side.
  popCreateMenu: (items: { label: string; req: MutateRequest }[]): Promise<void> =>
    ipcRenderer.invoke('create-menu', items),
  // Surface a failure natively (renderer can't show a native dialog itself).
  showError: (message: string): Promise<void> => ipcRenderer.invoke('error:show', message),
  // Open an external link (http/https/mailto) in the OS default browser/app.
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('link:open', url),
  // Fetched page-title cache for URL properties in the `link-title` look. `get` returns the whole
  // cached map (hydrated into the store on open); `fetch` resolves one URL (cache hit or live fetch).
  linkTitles: {
    get: (): Promise<Record<string, string>> => ipcRenderer.invoke('linkTitles:get'),
    fetch: (
      url: string,
    ): Promise<{ ok: true; title: string | null } | { ok: false; error: string }> =>
      ipcRenderer.invoke('linkTitles:fetch', url),
  },
  // Open a page-attached file (nexus-relative path) in its OS default app.
  openFile: (path: string): Promise<{ ok: true } | { ok: false; error: string }> =>
    ipcRenderer.invoke('file:open', path),
  systemAccent: (): Promise<string | null> => ipcRenderer.invoke('theme:systemAccent'),
  // Pop the native nexus-identity icon menu (Change Icon / Add·Change Photo / removes) → the chosen action.
  iconMenu: (opts: {
    hasPhoto: boolean
    hasGlyph: boolean
  }): Promise<'changeIcon' | 'addPhoto' | 'removePhoto' | 'removeIcon' | null> =>
    ipcRenderer.invoke('nexus:iconMenu', opts),
  // Open the native image picker directly → data URL (null if canceled). Banner Add / Change.
  pickImage: (): Promise<string | null> => ipcRenderer.invoke('nexus:pickImage'),
  // Pop the native Change / Remove banner menu → the chosen action (null if dismissed).
  // `noRemove` drops the Remove item (an inherited banner has nothing of its own to remove).
  bannerMenu: (opts?: { noRemove?: boolean }): Promise<'change' | 'remove' | null> =>
    ipcRenderer.invoke('nexus:bannerMenu', opts),
  // Pop the native Rename / Edit Icon menu for a detail title → the chosen action (null if dismissed).
  titleMenu: (opts?: {
    toggleIcon?: boolean
    iconHidden?: boolean
    noEditIcon?: boolean
  }): Promise<'rename' | 'editIcon' | 'toggleIcon' | null> =>
    ipcRenderer.invoke('nexus:titleMenu', opts),
  // Pop the table grip's native right-click menu → the chosen action (null if dismissed).
  tableMenu: (ctx: TableMenuContext): Promise<TableMenuAction | null> =>
    ipcRenderer.invoke('table-menu', ctx),
  // Pop the callout grip's native right-click menu → the chosen action (null if dismissed).
  calloutMenu: (): Promise<CalloutMenuAction | null> => ipcRenderer.invoke('callout-menu'),
  // Pop the table-view column header's native right-click menu → the chosen action (null if dismissed).
  columnMenu: (ctx: ColumnMenuContext): Promise<ColumnMenuAction | null> =>
    ipcRenderer.invoke('column-menu', ctx),
  // Pop a table cell's native right-click menu (title meta / per-type Style / Edit) — same contract.
  cellMenu: (ctx: CellMenuContext): Promise<CellMenuAction | null> =>
    ipcRenderer.invoke('cell-menu', ctx),
  // Pop a card's native right-click menu (page meta + Add Property ▸) → the chosen action.
  cardMenu: (ctx: CardMenuContext): Promise<CardMenuAction | null> =>
    ipcRenderer.invoke('card-menu', ctx),
  tabMenu: (ctx: TabMenuContext): Promise<TabMenuAction | null> =>
    ipcRenderer.invoke('tab-menu', ctx),
  // Pop a NavWindow row/card's native right-click menu (Open · Pin · Favorite · Remove) → the action.
  navRowMenu: (ctx: NavRowMenuContext): Promise<NavRowMenuAction | null> =>
    ipcRenderer.invoke('nav-row-menu', ctx),
  // Pop a wikilink's native right-click menu (Open in Preview) → the chosen action.
  connMenu: (): Promise<ConnMenuAction | null> => ipcRenderer.invoke('conn-menu'),
  // Pop a property's native menu (editor ⋮ / row right-click); Delete confirms in main first.
  propertyMenu: (ctx: PropertyMenuContext): Promise<PropertyMenuAction | null> =>
    ipcRenderer.invoke('property-menu', ctx),
  // Pop an option chip's native menu (Rename / Remove / Clear); Remove + Clear confirm in main first.
  optionMenu: (ctx: OptionMenuContext): Promise<OptionMenuAction | null> =>
    ipcRenderer.invoke('option-menu', ctx),
  // Flag (on hover) whether the pointer sits on a callout grip, so the generic editor menu stands down there.
  setCalloutGrip: (on: boolean): void => ipcRenderer.send('editor:callout-grip', on),
  // Rename the open nexus's root folder + re-point the live session to the new path.
  renameNexus: (newName: string): Promise<{ ok: true } | { ok: false; error: string }> =>
    ipcRenderer.invoke('nexus:rename', newName),
  // Native-menu actions pushed from main; returns an unsubscribe.
  onMenuAction: (cb: (action: string) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, action: string): void => cb(action)
    ipcRenderer.on('menu:action', listener)
    return () => {
      ipcRenderer.removeListener('menu:action', listener)
    }
  },
  // Main asks the renderer to start inline-renaming the row at this nexus-relative path
  // (from the context-menu Rename item); returns an unsubscribe.
  onBeginRename: (cb: (path: string) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, path: string): void => cb(path)
    ipcRenderer.on('begin-rename', listener)
    return () => {
      ipcRenderer.removeListener('begin-rename', listener)
    }
  },
  // The context-menu "Open in New Tab" push-back — the action runs renderer-side (main can't know
  // the tab set); returns an unsubscribe.
  onOpenInNewTab: (cb: (target: ContextTarget) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, target: ContextTarget): void => cb(target)
    ipcRenderer.on('open-in-new-tab', listener)
    return () => {
      ipcRenderer.removeListener('open-in-new-tab', listener)
    }
  },
  // The context-menu "Open in Preview" push-back — same contract as onOpenInNewTab.
  onOpenInPreview: (cb: (target: ContextTarget) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, target: ContextTarget): void => cb(target)
    ipcRenderer.on('open-in-preview', listener)
    return () => {
      ipcRenderer.removeListener('open-in-preview', listener)
    }
  },
  // The live watcher pushed fresh nav state (external/synced sidecar or pin change) — no tree walk.
  onNavChanged: (cb: (nav: NavChanged) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, nav: NavChanged): void => cb(nav)
    ipcRenderer.on('nav:changed', listener)
    return () => {
      ipcRenderer.removeListener('nav:changed', listener)
    }
  },
  // The live watcher pushed a fresh tree (external FS change) — swap it in place; returns an unsubscribe.
  onNexusChanged: (cb: (tree: NexusTree) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, tree: NexusTree): void => cb(tree)
    ipcRenderer.on('nexus:changed', listener)
    return () => {
      ipcRenderer.removeListener('nexus:changed', listener)
    }
  },
}

contextBridge.exposeInMainWorld('nexus', api)

export type NexusApi = typeof api
