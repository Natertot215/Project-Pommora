import { app, BrowserWindow, ipcMain } from 'electron'
import { join } from 'node:path'
import { homedir } from 'node:os'
import type { OpenResult } from '@shared/types'
import { readNexus } from './readNexus'

// Phase 1: the test nexus path is config, not a picker. Override with TEST_NEXUS_PATH.
const TEST_NEXUS_PATH = process.env.TEST_NEXUS_PATH || join(homedir(), 'test')

function createWindow(): void {
  const win = new BrowserWindow({
    width: 1280,
    height: 832,
    show: false,
    titleBarStyle: 'hiddenInset',
    vibrancy: 'sidebar', // native macOS material under the CSS glass layer
    backgroundColor: '#00000000',
    webPreferences: {
      preload: join(__dirname, '../preload/index.mjs'),
      // sandbox must be false for an ESM preload (electron-vite emits .mjs).
      // Security still holds: contextIsolation on + nodeIntegration off, and the
      // preload exposes only the narrow nexus read API. Restoring sandbox later
      // would require emitting a CommonJS preload.
      sandbox: false,
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
