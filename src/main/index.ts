import { app, BrowserWindow, ipcMain } from 'electron'
import { isAbsolute, join, relative, resolve, sep } from 'node:path'
import { homedir } from 'node:os'
import type { OpenResult, PageResult } from '@shared/types'
import { readNexus } from './readNexus'
import { readPage } from './readPage'

// Phase 1: the test nexus path is config, not a picker. Override with TEST_NEXUS_PATH.
const TEST_NEXUS_PATH = process.env.TEST_NEXUS_PATH || join(homedir(), 'test')

function createWindow(): void {
  const win = new BrowserWindow({
    width: 1280,
    height: 832,
    show: false,
    titleBarStyle: 'hiddenInset',
    // Opaque window — no native vibrancy, so the sidebar glass samples the main
    // view (CSS backdrop-filter), never the desktop wallpaper.
    backgroundColor: '#1C1C1F',
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

  // Deny-by-default navigation hardening (cheap, ahead of user-Markdown links).
  win.webContents.setWindowOpenHandler(() => ({ action: 'deny' }))
  win.webContents.on('will-navigate', (event, url) => {
    if (url !== win.webContents.getURL()) event.preventDefault()
  })

  // electron-vite injects ELECTRON_RENDERER_URL in dev; load the built file otherwise.
  const devUrl = process.env['ELECTRON_RENDERER_URL']
  if (devUrl) {
    win.loadURL(devUrl)
  } else {
    win.loadFile(join(__dirname, '../renderer/index.html'))
  }
}

// The single read bridge — never throws across IPC.
ipcMain.handle('nexus:open', async (): Promise<OpenResult> => {
  try {
    const tree = await readNexus(TEST_NEXUS_PATH)
    return { ok: true, tree }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
})

// On-demand page read. The renderer passes a nexus-relative path (PageNode.path);
// we resolve it under the root and reject anything that escapes (traversal, absolute).
ipcMain.handle('page:open', async (_e, relPath: unknown): Promise<PageResult> => {
  try {
    if (typeof relPath !== 'string' || relPath.length === 0) {
      return { ok: false, error: 'A page path is required.' }
    }
    if (isAbsolute(relPath)) {
      return { ok: false, error: 'Absolute paths are not allowed.' }
    }
    const root = resolve(TEST_NEXUS_PATH)
    const target = resolve(root, relPath)
    const rel = relative(root, target)
    // Escapes the root if the relative path climbs out (`..`) or stays absolute.
    if (rel === '..' || rel.startsWith('..' + sep) || isAbsolute(rel)) {
      return { ok: false, error: 'Path escapes the nexus root.' }
    }
    const page = await readPage(root, relPath)
    return { ok: true, page }
  } catch (e) {
    return { ok: false, error: e instanceof Error ? e.message : String(e) }
  }
})

app
  .whenReady()
  .then(() => {
    createWindow()
    app.on('activate', () => {
      if (BrowserWindow.getAllWindows().length === 0) createWindow()
    })
  })
  .catch((e) => {
    console.error('Failed to create window:', e)
    app.quit()
  })

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') app.quit()
})
