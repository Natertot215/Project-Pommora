import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, protocol, shell, systemPreferences } from 'electron'
import type { OpenDialogOptions } from 'electron'
import { basename, dirname, extname, join, sep } from 'node:path'
import { readFile, rename } from 'node:fs/promises'
import type { NexusState, PageResult, SubfieldConfig } from '@shared/types'
import type { MutateRequest, MutateResult, ContextTarget } from '@shared/mutate'
import { WINDOW_BG } from '@shared/theme'
import { readNexus } from './readNexus'
import { readPage } from './readPage'
import { pathExists } from './io/atomicWrite'
import { readAppConfig, writeAppConfig, addRecent, DEFAULT_TRASH_MODE } from './appConfig'
import { sessionRoot, openSession, resolveRestorePath, isExistingDir } from './session'
import { openSessionIndex, closeSessionIndex } from './sessionIndex'
import { stampAdopted } from './adopt'
import { ensureIdentity } from './identity'
import { ensureSettings, readSubfield, writeSubfield } from './settings'
import { startWatcher, stopWatcher } from './watcher'
import { resolveUnderRoot } from './pathSafety'
import { updatePageBody } from './crud/page'
import { readFolds, writeFolds, type FoldState } from './io/folds'
import { readActiveViews, writeActiveViews, type ActiveViews } from './io/activeViews'
import { readViewOrders, writeViewOrders, type ViewOrders } from './io/viewOrders'
import { saveView, reorderViews, deleteView } from './crud/views'
import { loadValues } from './crud/loadValues'
import { addProperty, renameProperty, reorderProperty, deleteProperty, changePropertyType } from './crud/schema'
import { savedView } from '@shared/views'
import { propertyDefinition, propertyType } from '@shared/properties'
import type { PageFrontmatter } from '@shared/schemas'
import {
  readTableHeadingColumns,
  writeTableHeadingColumns,
  type TableHeadingColState
} from './io/tableHeadingColumns'
import { handleMutate, type MutateDeps } from './mutate'
import { showContextMenu } from './contextMenu'
import { installAppMenu } from './menu'
import { popTableMenu } from './tableMenu'
import type { TableMenuContext } from '@shared/tableMenu'
import { popCalloutMenu } from './calloutMenu'
import { popColumnMenu } from './columnMenu'
import { installEditorContextMenu, setFormatState, setCalloutGrip } from './editorMenu'
import type { FormatState } from '@shared/editorMenu'
import { isValidLink, normalizeLinkUrl } from '@shared/links'

// Dev affordance: opt-in CDP endpoint for headless screenshots / automation. Inert unless
// POMMORA_DEBUG_PORT is set; must be appended before the app is ready.
if (process.env.POMMORA_DEBUG_PORT) {
  app.commandLine.appendSwitch('remote-debugging-port', process.env.POMMORA_DEBUG_PORT)
}

// The production renderer is served over a custom secure scheme (app://) rather
// than file://: ES-module scripts fetch in CORS mode and every file:// resource is
// an opaque origin, so a file://-loaded module bundle is blocked (blank window). A
// standard secure scheme gives the renderer a real origin (like the dev http
// server), so the bundle loads normally. Must be registered before app is ready.
const RENDERER_SCHEME = 'app'
// Banner/avatar assets ride their own privileged scheme so the renderer can <img src> them
// without inlining bytes into the reloaded state tree (see registerAssetProtocol). Must be
// registered before app is ready, alongside the renderer scheme.
const ASSET_SCHEME = 'nexus-asset'
protocol.registerSchemesAsPrivileged([
  { scheme: RENDERER_SCHEME, privileges: { standard: true, secure: true, supportFetchAPI: true } },
  { scheme: ASSET_SCHEME, privileges: { standard: true, secure: true, supportFetchAPI: true, stream: true } }
])

const RENDERER_MIME: Record<string, string> = {
  '.html': 'text/html',
  '.js': 'text/javascript',
  '.css': 'text/css',
  '.woff2': 'font/woff2',
  '.woff': 'font/woff',
  '.json': 'application/json',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.ico': 'image/x-icon'
}

// Serve the built renderer over app://: resolve each request under out/renderer and
// return the file with its MIME type. fs.readFile is asar-aware (the bundle lives
// inside app.asar); a containment check rejects any path escaping the bundle dir.
function registerRendererProtocol(): void {
  const rendererRoot = join(__dirname, '../renderer')
  protocol.handle(RENDERER_SCHEME, async (request) => {
    const { pathname } = new URL(request.url)
    const rel = pathname === '/' ? '/index.html' : decodeURIComponent(pathname)
    const filePath = join(rendererRoot, rel)
    if (filePath !== rendererRoot && !filePath.startsWith(rendererRoot + sep)) {
      return new Response('Forbidden', { status: 403 })
    }
    try {
      const data = await readFile(filePath)
      const type = RENDERER_MIME[extname(filePath).toLowerCase()] ?? 'application/octet-stream'
      return new Response(new Uint8Array(data), { headers: { 'Content-Type': type } })
    } catch {
      return new Response('Not found', { status: 404 })
    }
  })
}

// Serve banner/avatar assets over nexus-asset://nexus/<nexus-relative-path>: read-only and
// confined to the open nexus's .nexus/assets/ (resolveUnderRoot realpaths + contains; the
// prefix check pins it to that dir). Keeps image bytes out of the reloaded state tree.
const ASSET_MIME: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.gif': 'image/gif',
  '.webp': 'image/webp'
}
function registerAssetProtocol(): void {
  protocol.handle(ASSET_SCHEME, async (request) => {
    const root = sessionRoot()
    if (!root) return new Response('No nexus open', { status: 404 })
    const rel = decodeURIComponent(new URL(request.url).pathname).replace(/^\/+/, '')
    if (!rel.startsWith('.nexus/assets/')) return new Response('Forbidden', { status: 403 })
    const resolved = await resolveUnderRoot(root, rel)
    if (!resolved.ok) return new Response('Not found', { status: 404 })
    try {
      const data = await readFile(resolved.value)
      const type = ASSET_MIME[extname(resolved.value).toLowerCase()] ?? 'application/octet-stream'
      // no-store: banners change in place; never let the renderer serve a stale cached image.
      return new Response(new Uint8Array(data), { headers: { 'Content-Type': type, 'Cache-Control': 'no-store' } })
    } catch {
      return new Response('Not found', { status: 404 })
    }
  })
}

// The single main window + a menu-rebuild hook. The menu (Open Recent + the
// session-gated items) is rebuilt whenever the session / recents change.
let mainWindow: BrowserWindow | null = null
function refreshMenu(): void {
  if (mainWindow) void installAppMenu(mainWindow, adoptNexus)
}

function createWindow(): void {
  const win = new BrowserWindow({
    width: 1280,
    height: 832,
    show: false,
    // Native frame kept (macOS draws the standard window corner radius + shadow, matching
    // Swift apps) but the title bar is hidden; the traffic lights are positioned into the
    // sidebar's top-left. Opaque so the sidebar glass samples the window background.
    titleBarStyle: 'hidden',
    trafficLightPosition: { x: 18, y: 18 },
    backgroundColor: WINDOW_BG, // single source (@shared/theme) — also drives the background.window token + --bg-window
    webPreferences: {
      preload: join(__dirname, '../preload/index.js'),
      // CommonJS preload (package is not type:module) → sandbox can stay ON.
      // Plus contextIsolation on + nodeIntegration off; the preload exposes only
      // the narrow nexus read API.
      sandbox: true,
      contextIsolation: true,
      nodeIntegration: false
    }
  })

  win.on('ready-to-show', () => win.show())
  installEditorContextMenu(win)
  mainWindow = win
  win.on('closed', () => {
    if (mainWindow === win) mainWindow = null
  })

  // Deny-by-default navigation hardening (cheap, ahead of user-Markdown links).
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (event, url) => {
    if (url !== win.webContents.getURL()) event.preventDefault()
  })

  // electron-vite injects ELECTRON_RENDERER_URL in dev; in production load the
  // bundle over the app:// scheme (see registerRendererProtocol).
  const devUrl = process.env['ELECTRON_RENDERER_URL']
  if (devUrl) {
    win.loadURL(devUrl)
  } else {
    win.loadURL(`${RENDERER_SCHEME}://bundle/index.html`)
  }
}

// What's currently open — the renderer's launch + post-change read. Empty when no
// nexus is open (not an error); reads the session root's tree otherwise.
ipcMain.handle('nexus:state', async (): Promise<NexusState> => {
  const root = sessionRoot()
  if (root === null) return { status: 'empty' }
  try {
    const tree = await readNexus(root)
    return { status: 'open', tree }
  } catch (e) {
    return { status: 'error', error: e instanceof Error ? e.message : String(e) }
  }
})

// Open-time prep shared by EVERY path that opens a nexus (explicit open + launch-restore),
// run after openSession and before the index reads anything:
//   1. Ensure `.nexus/nexus.json` + `settings.json` exist in Swift's shape (matches Swift's
//      eager create-on-open) — identity flips a raw folder into sidecar mode; a full settings
//      file keeps Swift's decoder from reseeding (losing data) when it later opens the folder.
//   2. Stamp any un-adopted entity (raw folder / externally-authored page) with a real ULID so
//      the index + every later write capture a stable id, not a transient `adopted-` placeholder.
// Best-effort: a failure here must never block opening the folder.
async function prepareOpenedNexus(path: string): Promise<void> {
  try {
    await ensureIdentity(path)
    await ensureSettings(path)
  } catch (e) {
    console.error('ensure config-on-open failed:', e)
  }
  try {
    await stampAdopted(path)
  } catch (e) {
    console.error('Adopt/stamp pass failed:', e)
  }
}

// Open a chosen nexus folder: make it the session, persist it as last-opened, and
// push it onto the recents (deduped, capped) + the OS Recent Documents list.
async function adoptNexus(path: string): Promise<void> {
  openSession(path)
  await prepareOpenedNexus(path)
  // Open (cold-build if needed) the index for the new session. Best-effort + off the read
  // path — the renderer's tree comes from readNexus, so a null index just means no live
  // query acceleration until the next rebuild. Replaces any prior session's handle.
  await openSessionIndex(path)
  // Live-watch the new nexus (startWatcher replaces any prior session's watcher).
  // A user-initiated open always has a window; launch-restore starts its watcher
  // after createWindow below.
  if (mainWindow) startWatcher(path, mainWindow)
  // Persistence (last-opened + recents + OS list) is best-effort: a config-write
  // failure must not block opening the folder this session, nor leave a half-open
  // "ghost" session the renderer never re-reads.
  try {
    const userData = app.getPath('userData')
    const config = await readAppConfig(userData)
    await writeAppConfig(userData, {
      ...config,
      lastNexusPath: path,
      recents: addRecent(config.recents ?? [], path)
    })
    app.addRecentDocument(path)
  } catch (e) {
    console.error('Could not persist recents / last-opened:', e)
  }
  refreshMenu() // recents + session changed → refresh Open Recent / session-gated items
}

// Native folder picker (a sheet on the calling window). Returns whether a folder
// was chosen; on success the renderer re-reads nexus:state.
ipcMain.handle('nexus:choose', async (e): Promise<boolean> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  const opts = {
    properties: ['openDirectory', 'createDirectory'],
    message: 'Choose a nexus folder'
  } satisfies OpenDialogOptions
  const result = win ? await dialog.showOpenDialog(win, opts) : await dialog.showOpenDialog(opts)
  if (result.canceled) return false
  const [chosen] = result.filePaths
  if (!chosen) return false
  await adoptNexus(chosen)
  return true
})

// Open a folder dropped onto the window. The preload resolves the dropped File to
// an absolute path (webUtils) and sends it here — the one place a renderer-origin
// path enters. Accept it only if it's an existing directory (rejects dropped files
// / non-folders), then adopt it like a picked folder.
ipcMain.handle('nexus:openPath', async (_e, p: unknown): Promise<boolean> => {
  if (typeof p !== 'string' || p.length === 0) return false
  if (!(await isExistingDir(p))) return false
  await adoptNexus(p)
  return true
})

// On-demand page read. The renderer passes a nexus-relative path (PageNode.path);
// resolveUnderRoot canonicalizes it under the open nexus root and rejects anything
// that escapes (traversal, absolute, or an in-nexus symlink pointing out).
ipcMain.handle('page:open', async (_e, relPath: unknown): Promise<PageResult> => {
  try {
    const root = sessionRoot()
    if (root === null) {
      return { ok: false, error: 'No nexus is open.' }
    }
    if (typeof relPath !== 'string') {
      return { ok: false, error: 'A page path is required.' }
    }
    const resolved = await resolveUnderRoot(root, relPath)
    if (!resolved.ok) {
      return { ok: false, error: resolved.error.message }
    }
    // resolveUnderRoot is the guard; readPage re-joins root + relPath and keeps the
    // relative path as the page's identity (PageDetail.path), so pass relPath, not
    // the canonical absolute (which would leak an abs path + mis-key the detail).
    const page = await readPage(root, relPath)
    return { ok: true, page }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
})

// Debounced body writes from the editor. Reconstructs the file via updatePageBody
// (frontmatter-preserving) + atomic write; the renderer sends a relative path, main
// resolves it under the session root. Structurally distinct from the one-shot `mutate`
// ops, so it gets its own channel.
ipcMain.handle(
  'page:updateBody',
  async (_e, relPath: unknown, body: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof relPath !== 'string') return { ok: false, error: 'A page path is required.' }
      if (typeof body !== 'string') return { ok: false, error: 'A body string is required.' }
      const resolved = await resolveUnderRoot(root, relPath)
      if (!resolved.ok) return { ok: false, error: resolved.error.message }
      const r = await updatePageBody(resolved.value, body)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Heading-fold UI state — local `.nexus/folds.json` (out of frontmatter + index).
ipcMain.handle('folds:get', async (): Promise<FoldState> => {
  const root = sessionRoot()
  return root === null ? {} : readFolds(root)
})
ipcMain.handle(
  'folds:set',
  async (_e, pageId: unknown, keys: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof pageId !== 'string') return { ok: false, error: 'A page id is required.' }
      if (!Array.isArray(keys) || !keys.every((k) => typeof k === 'string')) {
        return { ok: false, error: 'Fold keys must be a string array.' }
      }
      await writeFolds(root, pageId, keys)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Active-view pointer — local `.nexus/activeViews.json`, container id → active view id (per-machine).
ipcMain.handle('activeViews:get', async (): Promise<ActiveViews> => {
  const root = sessionRoot()
  return root === null ? {} : readActiveViews(root)
})
ipcMain.handle(
  'activeViews:set',
  async (_e, containerId: unknown, viewId: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof containerId !== 'string') return { ok: false, error: 'A container id is required.' }
      if (typeof viewId !== 'string') return { ok: false, error: 'A view id is required.' }
      await writeActiveViews(root, containerId, viewId)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Sorted/grouped manual-order cache — local `.nexus/viewOrders.json`, view id → page-id tiebreaker (per-machine).
ipcMain.handle('viewOrders:get', async (): Promise<ViewOrders> => {
  const root = sessionRoot()
  return root === null ? {} : readViewOrders(root)
})
ipcMain.handle(
  'viewOrders:set',
  async (_e, viewId: unknown, order: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof viewId !== 'string') return { ok: false, error: 'A view id is required.' }
      if (!Array.isArray(order) || !order.every((x) => typeof x === 'string'))
        return { ok: false, error: 'An order array of page ids is required.' }
      await writeViewOrders(root, viewId, order)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// View persistence — save / reorder / delete a SavedView in a container's synced `views[]` sidecar.
// (View SELECTION is the per-machine activeViews pointer above; this is the view DEFINITION.)
type ResolvedViewContainer =
  | { ok: true; folder: string; kind: 'collection' | 'set' }
  | { ok: false; error: string }
async function resolveViewContainer(containerPath: unknown, kind: unknown): Promise<ResolvedViewContainer> {
  const root = sessionRoot()
  if (root === null) return { ok: false, error: 'No nexus is open.' }
  if (typeof containerPath !== 'string') return { ok: false, error: 'A container path is required.' }
  if (kind !== 'collection' && kind !== 'set') return { ok: false, error: 'kind must be "collection" or "set".' }
  const resolved = await resolveUnderRoot(root, containerPath)
  if (!resolved.ok) return { ok: false, error: resolved.error.message }
  return { ok: true, folder: resolved.value, kind }
}
ipcMain.handle(
  'views:save',
  async (_e, containerPath: unknown, kind: unknown, view: unknown): Promise<{ ok: true; id: string } | { ok: false; error: string }> => {
    try {
      const c = await resolveViewContainer(containerPath, kind)
      if (!c.ok) return c
      const parsed = savedView.safeParse(view)
      if (!parsed.success) return { ok: false, error: 'Invalid view payload.' }
      const r = await saveView(c.folder, c.kind, parsed.data)
      return r.ok ? { ok: true, id: r.value.id } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)
ipcMain.handle(
  'views:reorder',
  async (_e, containerPath: unknown, kind: unknown, orderedIds: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveViewContainer(containerPath, kind)
      if (!c.ok) return c
      if (!Array.isArray(orderedIds) || !orderedIds.every((x) => typeof x === 'string')) {
        return { ok: false, error: 'orderedIds must be a string array.' }
      }
      const r = await reorderViews(c.folder, c.kind, orderedIds)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)
ipcMain.handle(
  'views:delete',
  async (_e, containerPath: unknown, kind: unknown, viewId: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveViewContainer(containerPath, kind)
      if (!c.ok) return c
      if (typeof viewId !== 'string') return { ok: false, error: 'A view id is required.' }
      const r = await deleteView(c.folder, c.kind, viewId)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Batch frontmatter read for a container's view pipeline (pageId → frontmatter), lazy on open.
ipcMain.handle('view:loadValues', async (_e, containerPath: unknown): Promise<Record<string, PageFrontmatter>> => {
  const root = sessionRoot()
  if (root === null || typeof containerPath !== 'string') return {}
  const resolved = await resolveUnderRoot(root, containerPath)
  if (!resolved.ok) return {}
  return loadValues(root, containerPath)
})

// Property schema CRUD on a Collection's page schema (_pagecollection.json `properties`). containerPath
// is the schema-owning Collection's folder — a Set inherits the schema, so the renderer passes the
// ancestor Collection's path. Mirrors the views:* envelope contract.
async function resolveSchemaFolder(
  containerPath: unknown
): Promise<{ ok: true; folder: string } | { ok: false; error: string }> {
  const root = sessionRoot()
  if (root === null) return { ok: false, error: 'No nexus is open.' }
  if (typeof containerPath !== 'string') return { ok: false, error: 'A container path is required.' }
  const resolved = await resolveUnderRoot(root, containerPath)
  return resolved.ok ? { ok: true, folder: resolved.value } : { ok: false, error: resolved.error.message }
}

ipcMain.handle(
  'schema:add',
  async (_e, containerPath: unknown, def: unknown): Promise<{ ok: true; id: string } | { ok: false; error: string }> => {
    try {
      const c = await resolveSchemaFolder(containerPath)
      if (!c.ok) return c
      const parsed = propertyDefinition.safeParse(def)
      if (!parsed.success) return { ok: false, error: 'Invalid property definition.' }
      const r = await addProperty(c.folder, parsed.data)
      return r.ok ? { ok: true, id: r.value.id } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

ipcMain.handle(
  'schema:rename',
  async (
    _e,
    containerPath: unknown,
    propertyId: unknown,
    newName: unknown
  ): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveSchemaFolder(containerPath)
      if (!c.ok) return c
      if (typeof propertyId !== 'string' || typeof newName !== 'string') {
        return { ok: false, error: 'propertyId and newName must be strings.' }
      }
      const r = await renameProperty(c.folder, propertyId, newName)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

ipcMain.handle(
  'schema:reorder',
  async (
    _e,
    containerPath: unknown,
    propertyId: unknown,
    toIndex: unknown
  ): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveSchemaFolder(containerPath)
      if (!c.ok) return c
      if (typeof propertyId !== 'string' || typeof toIndex !== 'number') {
        return { ok: false, error: 'propertyId (string) and toIndex (number) are required.' }
      }
      const r = await reorderProperty(c.folder, propertyId, toIndex)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

ipcMain.handle(
  'schema:delete',
  async (_e, containerPath: unknown, propertyId: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveSchemaFolder(containerPath)
      if (!c.ok) return c
      if (typeof propertyId !== 'string') return { ok: false, error: 'A property id is required.' }
      const r = await deleteProperty(c.folder, propertyId)
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

ipcMain.handle(
  'schema:changeType',
  async (
    _e,
    containerPath: unknown,
    propertyId: unknown,
    newType: unknown,
    opts: unknown
  ): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const c = await resolveSchemaFolder(containerPath)
      if (!c.ok) return c
      if (typeof propertyId !== 'string') return { ok: false, error: 'A property id is required.' }
      const parsedType = propertyType.safeParse(newType)
      if (!parsedType.success) return { ok: false, error: 'Invalid property type.' }
      const dropConflictingValues =
        typeof opts === 'object' && opts !== null && (opts as { dropConflictingValues?: unknown }).dropConflictingValues === true
      const r = await changePropertyType(c.folder, propertyId, parsedType.data, { dropConflictingValues })
      return r.ok ? { ok: true } : { ok: false, error: r.error.message }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Table heading-column UI state — local `.nexus/tableHeadingColumns.json` (out of frontmatter + index).
ipcMain.handle('tableHeadingCols:get', async (): Promise<TableHeadingColState> => {
  const root = sessionRoot()
  return root === null ? {} : readTableHeadingColumns(root)
})
ipcMain.handle(
  'tableHeadingCols:set',
  async (_e, pageId: unknown, indices: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (typeof pageId !== 'string') return { ok: false, error: 'A page id is required.' }
      if (!Array.isArray(indices) || !indices.every((i) => Number.isInteger(i) && i >= 0)) {
        return { ok: false, error: 'Table indices must be a non-negative-integer array.' }
      }
      await writeTableHeadingColumns(root, pageId, indices)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// Subfield (footer) config — a React-owned `subfield` foreign key in `.nexus/settings.json`.
ipcMain.handle('subfield:get', async (): Promise<SubfieldConfig | null> => {
  const root = sessionRoot()
  return root === null ? null : readSubfield(root)
})
ipcMain.handle(
  'subfield:set',
  async (_e, config: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
    try {
      const root = sessionRoot()
      if (root === null) return { ok: false, error: 'No nexus is open.' }
      if (!config || typeof config !== 'object') return { ok: false, error: 'Invalid subfield config.' }
      await writeSubfield(root, config as SubfieldConfig)
      return { ok: true }
    } catch (e) {
      return { ok: false, error: e instanceof Error ? e.message : String(e) }
    }
  }
)

// The renderer pushes the editor's active formatting state here so the native context menu
// (built in editorMenu.ts on right-click) can render accurate checkmarks/radios.
ipcMain.on('editor:format-state', (_e, state: FormatState) => setFormatState(state))

// The renderer flags (on hover) when the pointer sits on a callout grip, so the generic editor menu can
// stand down and the renderer's own Delete Callout menu is the only one that pops on the right-press.
ipcMain.on('editor:callout-grip', (_e, on: boolean) => setCalloutGrip(on))

// The Electron-side bits the write orchestration needs: trashMode from app config +
// system-trash injected. Shared by the mutate IPC + the native context menu.
async function mutateDeps(): Promise<MutateDeps> {
  const config = await readAppConfig(app.getPath('userData'))
  return { trashMode: config.trashMode ?? DEFAULT_TRASH_MODE, trashToSystem: (p) => shell.trashItem(p) }
}

// The single write path. The renderer sends a relative-path request; main resolves it
// under the session root, runs the orchestration, and best-effort refreshes the index.
ipcMain.handle('mutate', async (_e, req: MutateRequest): Promise<MutateResult> => handleMutate(req, await mutateDeps()))

// Pop a native per-kind context menu for a right-clicked sidebar entity; its items act
// main-side (handleMutate / confirm / Finder) and signal the renderer to refetch on change.
ipcMain.handle('context-menu', async (e, target: ContextTarget): Promise<void> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (!win) return
  await showContextMenu(win, target, await mutateDeps(), () => {
    if (!win.isDestroyed()) win.webContents.send('menu:action', 'reload-state')
  })
})

// Pop a native "New …" menu (the section-header "+" for contexts: New Area/Topic/Project).
// Runs the chosen create main-side, then signals the renderer to refetch + inline-rename the
// new entity — same pattern as the context menu (act in main, signal the renderer).
ipcMain.handle('create-menu', async (e, items: { label: string; req: MutateRequest }[]): Promise<void> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (!win) return
  const deps = await mutateDeps()
  const menu = Menu.buildFromTemplate(
    items.map((it) => ({
      label: it.label,
      click: async () => {
        const res = await handleMutate(it.req, deps)
        if (win.isDestroyed()) return
        if (res.ok) {
          win.webContents.send('menu:action', 'reload-state')
          if (res.created) win.webContents.send('begin-rename', res.created.path)
        } else {
          await dialog.showMessageBox(win, { type: 'error', message: 'Couldn’t create that.', detail: res.error.message })
        }
      }
    }))
  )
  menu.popup({ window: win })
})

// Surface a renderer-side failure as a native dialog (renderer-initiated mutations — e.g.
// New Page ⌘N — have no native dialog of their own, unlike the context menu).
ipcMain.handle('error:show', async (e, message: unknown): Promise<void> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (win && typeof message === 'string') {
    await dialog.showMessageBox(win, { type: 'error', message: 'Couldn’t complete that action.', detail: message })
  }
})

// Open an external markdown link in the OS default app. Invalid links (same check that dims them in
// the editor) are rejected — the renderer never opens links itself.
ipcMain.handle('link:open', async (_e, url: unknown): Promise<void> => {
  if (typeof url !== 'string' || !isValidLink(url)) return
  await shell.openExternal(normalizeLinkUrl(url))
})

// The OS accent (macOS 10.14+), for accent === 'system'. Electron returns
// RRGGBBAA; surface just the RGB as '#RRGGBB'. null when unsupported/unavailable.
ipcMain.handle('theme:systemAccent', (): string | null => {
  try {
    const c = systemPreferences.getAccentColor?.()
    return c ? `#${c.slice(0, 6)}` : null
  } catch {
    return null
  }
})

// The native image picker → the chosen file as a data URL (null if canceled). The one owner of
// "pick an image file"; reuses ASSET_MIME for the ext→mime mapping (single source for both).
const IMAGE_EXTS = Object.keys(ASSET_MIME).map((e) => e.slice(1))
async function pickImageDataUrl(win: BrowserWindow): Promise<string | null> {
  const result = await dialog.showOpenDialog(win, {
    properties: ['openFile'],
    filters: [{ name: 'Images', extensions: IMAGE_EXTS }]
  })
  if (result.canceled || !result.filePaths[0]) return null
  try {
    const p = result.filePaths[0]
    const buf = await readFile(p)
    const mime = ASSET_MIME[extname(p).toLowerCase()] ?? 'application/octet-stream'
    return `data:${mime};base64,${buf.toString('base64')}`
  } catch {
    return null
  }
}

// Pop a native single-item "Add Photo" menu; on click open the image picker and resolve the
// chosen file as a data URL. Resolves null if the menu is dismissed or the picker canceled.
ipcMain.handle('nexus:photoMenu', async (e): Promise<string | null> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (!win) return null
  return await new Promise<string | null>((resolve) => {
    let acted = false
    const menu = Menu.buildFromTemplate([
      { label: 'Add Photo', click: async () => { acted = true; resolve(await pickImageDataUrl(win)) } }
    ])
    menu.popup({ window: win, callback: () => { if (!acted) resolve(null) } })
  })
})

// Open the native image picker directly (no menu) → data URL or null. The banner's Add/Change
// affordances use this (the photo's "Add Photo" menu wraps the same picker).
ipcMain.handle('nexus:pickImage', async (e): Promise<string | null> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  return win ? pickImageDataUrl(win) : null
})

// Pop a native macOS Change / Remove menu for an existing banner (mirrors Swift's .contextMenu).
// Resolves the chosen action, or null if the menu is dismissed.
ipcMain.handle('nexus:bannerMenu', async (e): Promise<'change' | 'remove' | null> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (!win) return null
  return await new Promise<'change' | 'remove' | null>((resolve) => {
    let acted = false
    const choose = (action: 'change' | 'remove'): void => {
      acted = true
      resolve(action)
    }
    const menu = Menu.buildFromTemplate([
      { label: 'Change Banner', click: () => choose('change') },
      { label: 'Remove Banner', click: () => choose('remove') }
    ])
    menu.popup({ window: win, callback: () => { if (!acted) resolve(null) } })
  })
})

// Pop a native Rename / Edit Icon menu for a detail title (matches Swift's DetailTitleHeader).
ipcMain.handle('nexus:titleMenu', async (e): Promise<'rename' | 'editIcon' | null> => {
  const win = BrowserWindow.fromWebContents(e.sender)
  if (!win) return null
  return await new Promise<'rename' | 'editIcon' | null>((resolve) => {
    let acted = false
    const choose = (action: 'rename' | 'editIcon'): void => {
      acted = true
      resolve(action)
    }
    const menu = Menu.buildFromTemplate([
      { label: 'Rename', click: () => choose('rename') },
      { label: 'Edit Icon', click: () => choose('editIcon') }
    ])
    menu.popup({ window: win, callback: () => { if (!acted) resolve(null) } })
  })
})

// Pop the table grip's native right-click menu → the chosen action (null if dismissed); renderer applies it.
ipcMain.handle('table-menu', async (e, ctx: TableMenuContext) => {
  const win = BrowserWindow.fromWebContents(e.sender)
  return win ? popTableMenu(win, ctx) : null
})

// Pop the callout grip's native right-click menu → the chosen action (null if dismissed); renderer applies it.
ipcMain.handle('callout-menu', async (e) => {
  const win = BrowserWindow.fromWebContents(e.sender)
  return win ? popCalloutMenu(win) : null
})

// Pop the table-view column header's native right-click menu → the chosen action (null if dismissed); renderer applies it.
ipcMain.handle('column-menu', async (e) => {
  const win = BrowserWindow.fromWebContents(e.sender)
  return win ? popColumnMenu(win) : null
})


// Rename the OPEN nexus's ROOT folder within its parent dir, then RE-POINT the live session
// to the new path. A dedicated IPC (not a mutate op) because it re-targets the whole session:
// after the fs.rename, adoptNexus re-opens the session, index, watcher, and recents at the new
// path. Never throws across the boundary.
ipcMain.handle('nexus:rename', async (_e, newName: unknown): Promise<{ ok: true } | { ok: false; error: string }> => {
  const root = sessionRoot()
  if (root === null) return { ok: false, error: 'No nexus is open.' }
  try {
    if (typeof newName !== 'string') return { ok: false, error: 'A name is required.' }
    const trimmed = newName.trim()
    if (trimmed.length === 0) return { ok: false, error: 'The name can’t be empty.' }
    if (trimmed.includes('/') || trimmed.includes('\\')) return { ok: false, error: 'The name can’t contain a slash.' }
    if (trimmed === basename(root)) return { ok: false, error: 'That’s already the nexus name.' }
    const newRoot = join(dirname(root), trimmed)
    if (await pathExists(newRoot)) return { ok: false, error: 'A folder with that name already exists.' }
    await rename(root, newRoot)
    // RE-POINT: adoptNexus does exactly the re-target work (openSession + openSessionIndex +
    // startWatcher + lastNexusPath/recents + addRecentDocument + refreshMenu) with no
    // adoption-only side effects to skip, so reuse it rather than replicate the calls.
    await adoptNexus(newRoot)
    return { ok: true }
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) }
  }
})

app
  .whenReady()
  .then(async () => {
    // Restore the last nexus if it's still an existing directory; otherwise launch
    // empty. No picker/modal here — a launch must never block (headless / tests).
    // Restore failures degrade to empty state (never fatal); only a failure to
    // create the window reaches the fatal .catch below.
    try {
      const config = await readAppConfig(app.getPath('userData'))
      const restore = await resolveRestorePath(config)
      if (restore) {
        openSession(restore)
        await prepareOpenedNexus(restore) // same ensure+stamp prep as an explicit open
        await openSessionIndex(restore)
      }
    } catch (e) {
      console.error('Restore skipped (config unreadable):', e)
    }

    // Dark-only app: force the native chrome dark to match the renderer (a light
    // theme + `themeSource = 'system'` is a later task).
    nativeTheme.themeSource = 'dark'
    app.setAboutPanelOptions({ applicationName: 'Pommora', applicationVersion: app.getVersion() })

    registerRendererProtocol()
    registerAssetProtocol()
    createWindow()
    refreshMenu()
    // A restored nexus opened before the window existed — start its watcher now.
    const restored = sessionRoot()
    if (restored && mainWindow) startWatcher(restored, mainWindow)
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) {
        createWindow()
        // Re-attach the watcher to the fresh window (the session stays open across a close).
        const root = sessionRoot()
        if (root && mainWindow) startWatcher(root, mainWindow)
      }
    })
  })
  .catch((e) => {
    console.error('Failed to start:', e)
    app.quit()
  })

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})

// Release the index handle on quit (regeneratable, so a clean close isn't required —
// just tidy + frees the WAL files).
app.on('before-quit', () => {
  stopWatcher()
  closeSessionIndex()
})
