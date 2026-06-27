import { contextBridge, ipcRenderer, webUtils } from 'electron'
import type { IpcRendererEvent } from 'electron'
import type { NexusState, NexusTree, PageResult, SubfieldConfig } from '@shared/types'
import type { MutateRequest, MutateResult, ContextTarget } from '@shared/mutate'
import type { FormatState } from '@shared/editorMenu'
import type { TableMenuAction, TableMenuContext } from '@shared/tableMenu'

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
