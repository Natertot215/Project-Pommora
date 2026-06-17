// Per-kind native context menu for a sidebar entity. The renderer captures the right-click
// and hands main a ContextTarget; main pops a native Menu whose items run main-side
// (handleMutate / a native confirm / Finder), then signals the renderer to refetch on change.
// Rename is intentionally absent here — it needs an inline rename in the renderer.

import { Menu, dialog, shell } from 'electron'
import type { BrowserWindow, MenuItemConstructorOptions } from 'electron'
import { sessionRoot } from './session'
import { resolveUnderRoot } from './pathSafety'
import { handleMutate, type MutateDeps } from './mutate'
import { DEFAULT_NEW_NAME } from '@shared/mutate'
import type { ContextTarget, MutableKind, MutateRequest } from '@shared/mutate'

/** The "New …" creators a container offers; pages + free-standing contexts offer none. */
function creatorsFor(kind: MutableKind, parentPath: string): { label: string; req: MutateRequest }[] {
  const name = DEFAULT_NEW_NAME
  switch (kind) {
    case 'pageType':
      return [
        { label: 'New Page', req: { op: 'createPage', parentPath, name } },
        { label: 'New Collection', req: { op: 'createContainer', parentPath, kind: 'collection', name } }
      ]
    case 'collection':
      return [
        { label: 'New Page', req: { op: 'createPage', parentPath, name } },
        { label: 'New Set', req: { op: 'createContainer', parentPath, kind: 'set', name } }
      ]
    case 'set':
      return [{ label: 'New Page', req: { op: 'createPage', parentPath, name } }]
    default:
      return [] // page, area, topic, project
  }
}

/** Build + pop the native context menu for `target`, applying actions main-side. `onChanged`
 *  fires after any mutation so the renderer refetches its tree. */
export async function showContextMenu(
  win: BrowserWindow,
  target: ContextTarget,
  deps: MutateDeps,
  onChanged: () => void
): Promise<void> {
  const root = sessionRoot()
  if (root === null) return

  const run = async (req: MutateRequest): Promise<void> => {
    const res = await handleMutate(req, deps)
    if (res.ok) onChanged()
    else await dialog.showMessageBox(win, { type: 'error', message: 'Couldn’t complete that action.', detail: res.error.message })
  }

  const items: MenuItemConstructorOptions[] = []

  const creators = creatorsFor(target.kind, target.path)
  for (const c of creators) items.push({ label: c.label, click: () => void run(c.req) })
  if (creators.length) items.push({ type: 'separator' })

  // Rename is inline in the renderer (native menus can't take text), so this only signals
  // the renderer to put the matching row into edit mode; the commit goes through mutate.
  items.push({
    label: 'Rename',
    click: () => {
      if (!win.isDestroyed()) win.webContents.send('begin-rename', target.path)
    }
  })

  items.push({
    label: 'Delete',
    click: async () => {
      const { response } = await dialog.showMessageBox(win, {
        type: 'warning',
        buttons: ['Delete', 'Cancel'],
        defaultId: 0,
        cancelId: 1,
        message: `Delete “${target.title}”?`,
        detail:
          deps.trashMode === 'system'
            ? 'It will be moved to the system Trash.'
            : 'It will be moved to the nexus’s .trash folder (recoverable).'
      })
      if (response === 0) await run({ op: 'delete', path: target.path, kind: target.kind })
    }
  })

  items.push({ type: 'separator' })
  items.push({
    label: 'Reveal in Finder',
    // Validate through resolveUnderRoot — target.path is renderer-supplied, and an
    // unguarded join(root, path) would let `..` reveal files outside the nexus.
    click: async () => {
      const r = await resolveUnderRoot(root, target.path)
      if (r.ok) shell.showItemInFolder(r.value)
    }
  })

  Menu.buildFromTemplate(items).popup({ window: win })
}
