// The editor's native right-click menu. Built from the OS `context-menu` event (so spelling,
// Share, Speech, and the system edit roles come native) plus Pommora formatting submenus drawn
// from the renderer's last-pushed FormatState (Electron's static params can't see CM6 state).
// Sidebar right-clicks (non-editable) fall through to their own React→IPC menu untouched.

import { Menu } from 'electron'
import type {
  BrowserWindow,
  ContextMenuParams,
  MenuItemConstructorOptions,
  WebContents,
} from 'electron'
import { EDITOR_ACTION_PREFIX, type FormatState } from '@shared/editorMenu'

let lastState: FormatState | null = null
export function setFormatState(s: FormatState): void {
  lastState = s
}

// The renderer flags when the pointer sits on a callout grip (set on hover, so it's live before the
// right-press). The callout grip is editable content — unlike the non-editable table widget — so the
// generic editor menu would otherwise fire over it; this lets the renderer's own callout menu be the only one.
let calloutGripHot = false
export function setCalloutGrip(on: boolean): void {
  calloutGripHot = on
}

const dispatch = (wc: WebContents, action: string) => () =>
  wc.send('menu:action', EDITOR_ACTION_PREFIX + action)

function systemItems(wc: WebContents, params: ContextMenuParams): MenuItemConstructorOptions[] {
  const f = params.editFlags
  const items: MenuItemConstructorOptions[] = []

  if (params.misspelledWord) {
    for (const s of params.dictionarySuggestions)
      items.push({ label: s, click: () => wc.replaceMisspelling(s) })
    items.push(
      { type: 'separator' },
      {
        label: 'Add to Dictionary',
        click: () => wc.session.addWordToSpellCheckerDictionary(params.misspelledWord),
      },
      { type: 'separator' },
    )
  }

  items.push(
    { role: 'undo', enabled: f.canUndo },
    { role: 'redo', enabled: f.canRedo },
    { type: 'separator' },
    { role: 'cut', enabled: f.canCut },
    { role: 'copy', enabled: f.canCopy },
    { role: 'paste', enabled: f.canPaste },
    { role: 'pasteAndMatchStyle', enabled: f.canPaste },
    { role: 'selectAll' },
  )
  return items
}

// OS sharing/speech — placed last so the Pommora formatting block sits directly under the edit items.
function speechShareItems(params: ContextMenuParams): MenuItemConstructorOptions[] {
  if (!params.selectionText) return []
  return [
    { type: 'separator' },
    { label: 'Speech', submenu: [{ role: 'startSpeaking' }, { role: 'stopSpeaking' }] },
    { role: 'shareMenu', sharingItem: { texts: [params.selectionText] } },
  ]
}

function pommoraItems(wc: WebContents, s: FormatState): MenuItemConstructorOptions[] {
  const act = (a: string): (() => void) => dispatch(wc, a)
  const heading = (label: string, level: number): MenuItemConstructorOptions => ({
    label,
    type: 'radio',
    checked: s.heading === level,
    click: act(`heading:${level}`),
  })
  return [
    { type: 'separator' },
    {
      label: 'Format',
      submenu: [
        // Accelerators are display-only (registerAccelerator: false); the keys are bound in formatKeymap.ts.
        {
          label: 'Bold',
          type: 'checkbox',
          checked: s.bold,
          accelerator: 'CmdOrCtrl+B',
          registerAccelerator: false,
          click: act('format:bold'),
        },
        {
          label: 'Italic',
          type: 'checkbox',
          checked: s.italic,
          accelerator: 'CmdOrCtrl+I',
          registerAccelerator: false,
          click: act('format:italic'),
        },
        {
          label: 'Strikethrough',
          type: 'checkbox',
          checked: s.strikethrough,
          accelerator: 'CmdOrCtrl+Shift+X',
          registerAccelerator: false,
          click: act('format:strikethrough'),
        },
        {
          label: 'Inline Code',
          type: 'checkbox',
          checked: s.inlineCode,
          click: act('format:inlineCode'),
        },
        {
          label: 'Link',
          type: 'checkbox',
          checked: s.link,
          accelerator: 'CmdOrCtrl+K',
          registerAccelerator: false,
          click: act('format:link'),
        },
        {
          label: 'Connection',
          type: 'checkbox',
          checked: s.connection,
          accelerator: 'CmdOrCtrl+Shift+K',
          registerAccelerator: false,
          click: act('format:connection'),
        },
      ],
    },
    {
      label: 'Heading',
      submenu: [
        heading('Paragraph', 0),
        heading('Heading 1', 1),
        heading('Heading 2', 2),
        heading('Heading 3', 3),
        heading('Heading 4', 4),
        heading('Heading 5', 5),
      ],
    },
    {
      label: 'Lists',
      submenu: [
        {
          label: 'Bullet List',
          type: 'checkbox',
          checked: s.list === 'bullet',
          click: act('list:bullet'),
        },
        {
          label: 'Numbered List',
          type: 'checkbox',
          checked: s.list === 'ordered',
          click: act('list:ordered'),
        },
        {
          label: 'Task List',
          type: 'checkbox',
          checked: s.list === 'task',
          click: act('list:task'),
        },
      ],
    },
    {
      label: 'Insert',
      submenu: [
        { label: 'Table', click: act('block:table') },
        {
          label: 'Blockquote',
          type: 'checkbox',
          checked: s.block === 'quote',
          click: act('block:quote'),
        },
        { label: 'Code Block', click: act('block:code') },
        { label: 'Horizontal Rule', click: act('block:hr') },
        { label: 'Callout', click: act('block:callout') },
      ],
    },
  ]
}

export function installEditorContextMenu(win: BrowserWindow): void {
  win.webContents.on('context-menu', (_e, params) => {
    if (calloutGripHot) return // a callout grip right-click → the renderer pops its own Delete Callout menu
    if (!params.isEditable) return // sidebar + read-only surfaces keep their own menus
    const items = systemItems(win.webContents, params)
    if (lastState?.focused) items.push(...pommoraItems(win.webContents, lastState))
    items.push(...speechShareItems(params))
    Menu.buildFromTemplate(items).popup({ window: win })
  })
}
