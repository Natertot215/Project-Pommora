import { Menu, app, shell, BrowserWindow } from 'electron'
import type { MenuItemConstructorOptions } from 'electron'
import { basename } from 'node:path'
import { readAppConfig, writeAppConfig } from './appConfig'
import { pruneRecents, sessionRoot } from './session'
import { readDefaultViewScale } from './settings'
import { VIEW_SCALE_DEFAULT } from '@shared/types'

type AdoptFn = (path: string) => Promise<void>

// Build + install the native application menu. Renderer-driven items send a
// 'menu:action' string the renderer handles (reusing its store actions); main-side
// items (Open Recent, Reveal, Reload) act here. Rebuilt whenever the session or
// recents change, so Open Recent + the session-gated items stay current.
export async function installAppMenu(win: BrowserWindow, adopt: AdoptFn): Promise<void> {
  const userData = app.getPath('userData')
  const config = await readAppConfig(userData)
  // Drop deleted (trashed) nexuses so Open Recent never lists a dead path; self-heal the stored
  // list when the prune removes any, so the debris doesn't linger in the config.
  const recents = config.recents ? await pruneRecents(config.recents) : []
  if (config.recents && recents.length !== config.recents.length) {
    await writeAppConfig(userData, { ...config, recents })
  }
  const hasSession = sessionRoot() !== null
  const send = (action: string): void => {
    if (!win.isDestroyed()) win.webContents.send('menu:action', action)
  }

  const recentItems: MenuItemConstructorOptions[] =
    recents && recents.length
      ? recents.map((p) => ({
          label: basename(p),
          click: async () => {
            await adopt(p)
            send('reload-state')
          }
        }))
      : [{ label: 'No Recent Nexuses', enabled: false }]

  const template: MenuItemConstructorOptions[] = [
    { role: 'appMenu' },
    {
      label: 'File',
      submenu: [
        { label: 'Open Nexus…', accelerator: 'CmdOrCtrl+O', click: () => send('open') },
        { label: 'Open Recent', submenu: recentItems },
        { type: 'separator' },
        // Renderer-driven: the store resolves the target container from the current
        // selection. Enabled only with a nexus open (nothing to create into otherwise).
        { label: 'New Page', accelerator: 'CmdOrCtrl+N', enabled: hasSession, click: () => send('new-page') },
        { type: 'separator' },
        {
          label: 'Reveal in Finder',
          enabled: hasSession,
          click: () => {
            const root = sessionRoot()
            if (root) shell.showItemInFolder(root)
          }
        },
        {
          label: 'Reload',
          accelerator: 'CmdOrCtrl+R',
          // The captured `win` can be a stale/destroyed reference (the menu outlives a window
          // lifecycle); reload the live focused window, and guard so a dead one is a no-op, not a crash.
          click: () => {
            const w = BrowserWindow.getFocusedWindow() ?? win
            if (!w.isDestroyed()) w.webContents.reload()
          }
        },
        { type: 'separator' },
        { role: 'close' }
      ]
    },
    { role: 'editMenu' },
    {
      label: 'View',
      submenu: [
        { label: 'Toggle Sidebar', accelerator: 'CmdOrCtrl+\\', click: () => send('toggle-sidebar') },
        { type: 'separator' },
        // ⌘0 resets to the nexus's default view scale (personalization.defaultViewScale), not a
        // hardcoded 1.0 — read fresh so a settings.json edit takes effect without a relaunch.
        {
          label: 'Actual Size',
          accelerator: 'CmdOrCtrl+0',
          click: async () => {
            const root = sessionRoot()
            const scale = root ? await readDefaultViewScale(root) : VIEW_SCALE_DEFAULT
            const w = BrowserWindow.getFocusedWindow() ?? win
            if (!w.isDestroyed()) w.webContents.setZoomFactor(scale)
          }
        },
        { role: 'zoomIn' },
        { role: 'zoomOut' },
        { type: 'separator' },
        { role: 'togglefullscreen' },
        { role: 'toggleDevTools' }
      ]
    },
    { role: 'windowMenu' },
    { role: 'help', submenu: [{ label: 'About Pommora', click: () => app.showAboutPanel() }] }
  ]

  Menu.setApplicationMenu(Menu.buildFromTemplate(template))
}
