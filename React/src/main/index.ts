import { app, BrowserWindow, dialog, ipcMain, Menu, nativeTheme, protocol, shell, systemPreferences } from 'electron'
import type { OpenDialogOptions } from 'electron'
import { basename, dirname, extname, join, sep } from 'node:path'
import { readFile, rename } from 'node:fs/promises'
import type { NexusState, PageResult } from '@shared/types'
import type { MutateRequest, MutateResult, ContextTarget } from '@shared/mutate'
import { WINDOW_BG } from '@shared/theme'
import { readNexus } from './readNexus'
import { readPage } from './readPage'
import { atomicWriteBinary, mutateJson, pathExists } from './io/atomicWrite'
import { nexusConfig, nexusDir, NEXUS_CONFIG_FILES } from './paths'
import { newId } from './ids'
import { readAppConfig, writeAppConfig, addRecent, DEFAULT_TRASH_MODE } from './appConfig'
import { sessionRoot, openSession, resolveRestorePath, isExistingDir } from './session'
import { openSessionIndex, closeSessionIndex } from './sessionIndex'
import { startWatcher, stopWatcher } from './watcher'
import { resolveUnderRoot } from './pathSafety'
import { updatePageBody } from './crud/page'
import { handleMutate, type MutateDeps } from './mutate'
import { showContextMenu } from './contextMenu'
import { installAppMenu } from './menu'

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

// Open a chosen nexus folder: make it the session, persist it as last-opened, and
// push it onto the recents (deduped, capped) + the OS Recent Documents list.
async function adoptNexus(path: string): Promise<void> {
  openSession(path)
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

// Persist a cropped PNG data URL: write .nexus/photo.png atomically, then record
// `photo: "photo.png"` in nexus.json. Never throws across the boundary.
ipcMain.handle('nexus:saveNexusPhoto', async (_e, dataUrl: string): Promise<{ ok: true } | { ok: false; error: string }> => {
  const root = sessionRoot()
  if (root === null) return { ok: false, error: 'No nexus is open.' }
  try {
    const m = /^data:image\/png;base64,(.+)$/s.exec(dataUrl)
    if (!m) return { ok: false, error: 'Invalid image data.' }
    const buf = Buffer.from(m[1], 'base64')
    await atomicWriteBinary(join(nexusDir(root), 'photo.png'), buf)
    await mutateJson<Record<string, unknown>>(nexusConfig(root, NEXUS_CONFIG_FILES.identity), () => ({ id: newId() }), (cur) => ({ ...cur, photo: 'photo.png' }))
    return { ok: true }
  } catch (err) {
    return { ok: false, error: err instanceof Error ? err.message : String(err) }
  }
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
