import { contextBridge, ipcRenderer, webUtils } from 'electron'
import type { IpcRendererEvent } from 'electron'
import type { NexusState, NexusTree, PageResult, SubfieldConfig } from '@shared/types'
import type { MutateRequest, MutateResult, ContextTarget } from '@shared/mutate'
import type { FormatState } from '@shared/editorMenu'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'
import type { CalloutMenuAction } from '@shared/calloutMenu'
import type { CellMenuAction, CellMenuContext } from '@shared/cellMenu'
import type { PropertyMenuAction, PropertyMenuContext } from '@shared/propertyMenu'
import type { OptionMenuAction, OptionMenuContext } from '@shared/optionMenu'
import type { ColumnMenuAction, ColumnMenuContext } from '@shared/columnMenu'
import type { SavedView } from '@shared/views'
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
  updatePageBody: (relPath: string, body: string): Promise<{ ok: true } | { ok: false; error: string }> =>
    ipcRenderer.invoke('page:updateBody', relPath, body),
  // Heading-fold UI state — local `.nexus/folds.json`, keyed by page id (per-machine, not frontmatter).
  folds: {
    get: (): Promise<Record<string, string[]>> => ipcRenderer.invoke('folds:get'),
    set: (pageId: string, keys: string[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('folds:set', pageId, keys)
  },
  // Active-view pointer — local `.nexus/activeViews.json`, container id → active view id (per-machine).
  activeViews: {
    get: (): Promise<Record<string, string>> => ipcRenderer.invoke('activeViews:get'),
    set: (containerId: string, viewId: string): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('activeViews:set', containerId, viewId)
  },
  // Sorted-view manual order — local `.nexus/viewOrders.json`, view id → page-id tiebreaker (per-machine).
  viewOrders: {
    get: (): Promise<Record<string, string[]>> => ipcRenderer.invoke('viewOrders:get'),
    set: (viewId: string, order: string[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('viewOrders:set', viewId, order)
  },
  // View persistence — save / reorder / delete a SavedView in a Collection/Set sidecar's views[].
  views: {
    save: (
      containerPath: string,
      kind: 'collection' | 'set',
      view: SavedView
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:save', containerPath, kind, view),
    reorder: (
      containerPath: string,
      kind: 'collection' | 'set',
      orderedIds: string[]
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:reorder', containerPath, kind, orderedIds),
    delete: (
      containerPath: string,
      kind: 'collection' | 'set',
      viewId: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('views:delete', containerPath, kind, viewId)
  },
  // Property schema CRUD on a Collection's page schema. containerPath is the schema-owning
  // Collection's folder (a Set inherits, so the renderer passes its ancestor Collection's path).
  schema: {
    add: (
      containerPath: string,
      def: PropertyDefinition
    ): Promise<{ ok: true; id: string } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:add', containerPath, def),
    rename: (
      containerPath: string,
      propertyId: string,
      newName: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:rename', containerPath, propertyId, newName),
    reorder: (
      containerPath: string,
      propertyId: string,
      toIndex: number
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:reorder', containerPath, propertyId, toIndex),
    delete: (
      containerPath: string,
      propertyId: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:delete', containerPath, propertyId),
    assign: (
      containerPath: string,
      propertyId: string,
      toIndex?: number
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:assign', containerPath, propertyId, toIndex),
    changeType: (
      containerPath: string,
      propertyId: string,
      newType: PropertyType,
      opts?: { dropConflictingValues?: boolean }
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('schema:changeType', containerPath, propertyId, newType, opts)
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
      options: { value: string; label: string; color?: string }[]
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:setOptions', propertyId, options),
    renameOption: (
      propertyId: string,
      oldValue: string,
      newTitle: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:renameOption', propertyId, oldValue, newTitle),
    removeOption: (
      propertyId: string,
      value: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:removeOption', propertyId, value),
    clearOption: (
      propertyId: string,
      value: string
    ): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('property:clearOption', propertyId, value)
  },
  // The nexus-wide cosmetic property order (B-1) — how every collection's All Properties lists.
  registry: {
    reorder: (propertyId: string, toIndex: number): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('registry:reorder', propertyId, toIndex)
  },
  // Batch frontmatter read for a container's view pipeline (pageId → frontmatter), lazy on open.
  loadValues: (containerPath: string): Promise<Record<string, PageFrontmatter>> =>
    ipcRenderer.invoke('view:loadValues', containerPath),
  // Table heading-column UI state — local `.nexus/tableHeadingColumns.json`, keyed by page id. Holds the
  // indices of the tables whose first column renders as a heading (a Pommora-only visual, not in the .md).
  tableHeadingColumns: {
    get: (): Promise<Record<string, number[]>> => ipcRenderer.invoke('tableHeadingCols:get'),
    set: (pageId: string, indices: number[]): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('tableHeadingCols:set', pageId, indices)
  },
  // Subfield (footer) config — React-owned `subfield` key in `.nexus/settings.json`.
  subfield: {
    get: (): Promise<SubfieldConfig | null> => ipcRenderer.invoke('subfield:get'),
    set: (config: SubfieldConfig): Promise<{ ok: true } | { ok: false; error: string }> =>
      ipcRenderer.invoke('subfield:set', config)
  },
  // Renderer-initiated write (relative paths only); main resolves under the session root.
  mutate: (req: MutateRequest): Promise<MutateResult> => ipcRenderer.invoke('mutate', req),
  // Right-click an entity → main pops a native context menu + acts on it.
  contextMenu: (target: ContextTarget): Promise<void> => ipcRenderer.invoke('context-menu', target),
  // Push the editor's active formatting state so the native right-click menu renders accurate state.
  setEditorFormatState: (state: FormatState): void => ipcRenderer.send('editor:format-state', state),
  // Pop a native "New …" menu (e.g. the context tiers) + run the chosen create main-side.
  popCreateMenu: (items: { label: string; req: MutateRequest }[]): Promise<void> =>
    ipcRenderer.invoke('create-menu', items),
  // Surface a failure natively (renderer can't show a native dialog itself).
  showError: (message: string): Promise<void> => ipcRenderer.invoke('error:show', message),
  // Open an external link (http/https/mailto) in the OS default browser/app.
  openExternal: (url: string): Promise<void> => ipcRenderer.invoke('link:open', url),
  // Open a page-attached file (nexus-relative path) in its OS default app.
  openFile: (path: string): Promise<{ ok: true } | { ok: false; error: string }> =>
    ipcRenderer.invoke('file:open', path),
  systemAccent: (): Promise<string | null> => ipcRenderer.invoke('theme:systemAccent'),
  // Pop a native "Add Photo" menu → native image picker; resolves the chosen image as a data URL (null if dismissed/canceled).
  photoMenu: (): Promise<string | null> => ipcRenderer.invoke('nexus:photoMenu'),
  // Open the native image picker directly → data URL (null if canceled). Banner Add / Change.
  pickImage: (): Promise<string | null> => ipcRenderer.invoke('nexus:pickImage'),
  // Pop the native Change / Remove banner menu → the chosen action (null if dismissed).
  bannerMenu: (): Promise<'change' | 'remove' | null> => ipcRenderer.invoke('nexus:bannerMenu'),
  // Pop the native Rename / Edit Icon menu for a detail title → the chosen action (null if dismissed).
  titleMenu: (): Promise<'rename' | 'editIcon' | null> => ipcRenderer.invoke('nexus:titleMenu'),
  // Pop the table grip's native right-click menu → the chosen action (null if dismissed).
  tableMenu: (ctx: TableMenuContext): Promise<TableMenuAction | null> => ipcRenderer.invoke('table-menu', ctx),
  // Pop the callout grip's native right-click menu → the chosen action (null if dismissed).
  calloutMenu: (): Promise<CalloutMenuAction | null> => ipcRenderer.invoke('callout-menu'),
  // Pop the table-view column header's native right-click menu → the chosen action (null if dismissed).
  columnMenu: (ctx: ColumnMenuContext): Promise<ColumnMenuAction | null> => ipcRenderer.invoke('column-menu', ctx),
  // Pop a table cell's native right-click menu (title meta / per-type Style / Edit) — same contract.
  cellMenu: (ctx: CellMenuContext): Promise<CellMenuAction | null> => ipcRenderer.invoke('cell-menu', ctx),
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
  // The live watcher pushed a fresh tree (external FS change) — swap it in place; returns an unsubscribe.
  onNexusChanged: (cb: (tree: NexusTree) => void): (() => void) => {
    const listener = (_e: IpcRendererEvent, tree: NexusTree): void => cb(tree)
    ipcRenderer.on('nexus:changed', listener)
    return () => {
      ipcRenderer.removeListener('nexus:changed', listener)
    }
  }
}

contextBridge.exposeInMainWorld('nexus', api)

export type NexusApi = typeof api
