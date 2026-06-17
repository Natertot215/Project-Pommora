import { Menu, app, shell } from 'electron'
import type { MenuItemConstructorOptions, BrowserWindow } from 'electron'
import { basename } from 'node:path'
import { readAppConfig } from './appConfig'
import { sessionRoot } from './session'

type AdoptFn = (path: string) => Promise<void>

// Build + install the native application menu. Renderer-driven items send a
// 'menu:action' string the renderer handles (reusing its store actions); main-side
// items (Open Recent, Reveal, Reload) act here. Rebuilt whenever the session or
// recents change, so Open Recent + the session-gated items stay current.
export async function installAppMenu(win: BrowserWindow, adopt: AdoptFn): Promise<void> {
  const { recents } = await readAppConfig(app.getPath('userData'))
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
        { label: 'Reload', accelerator: 'CmdOrCtrl+R', click: () => win.webContents.reload() },
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
        { role: 'resetZoom' },
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
