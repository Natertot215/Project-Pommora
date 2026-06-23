import { useEffect, useRef, useState } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import { markdownInput } from './editor/input'
import { tableExtension } from './Tables'
import { connectionClicks } from './editor/connections'
import { externalLinkClicks } from './editor/links'
import { markdownFolding, applySavedFolds, type FoldsApi } from './editor/folding'
import { applyEditorAction, type EditorMenuApi } from './editor/menu'
import { formatKeymap } from './editor/formatKeymap'
import { readFormatState } from './editor/formatState'
import { autocompleteQuery, connectionInsert } from './autocomplete'
import { AutocompletePanel } from './AutocompletePanel'
import type { ConnectionsApi, ConnPage } from './connections'
import type { IconName } from '@renderer/design-system/symbols'
import { PageHeader } from './PageHeader'
import { ZOOM_DEFAULT, zoomFontSize } from './zoom'
import './Styles.css'

const AC_MAX = 6
// Panel geometry — keep in sync with .mdpm-ac in Styles.css. Used to flip the panel above the caret near the viewport bottom.
const AC_ROW_H = 28
const AC_PADDING = 8
const AC_MAX_ROWS = 4
const AC_GAP = 4

interface AcState {
  query: string
  from: number
  to: number
  left: number
  caretTop: number
  caretBottom: number
}

interface Props {
  initialBody: string
  onChange: (body: string) => void
  title?: string
  onRename?: (newName: string) => void | Promise<boolean>
  /** Page identity + chrome for the header (banner cover + title icon + Edit Icon). */
  path?: string
  icon?: IconName
  cover?: string
  onEditIcon?: () => void
  zoom?: number
  connections?: ConnectionsApi
  folds?: FoldsApi
  menu?: EditorMenuApi
}

export function MarkdownEditor({
  initialBody,
  onChange,
  title,
  onRename,
  path,
  icon,
  cover,
  onEditIcon,
  zoom = ZOOM_DEFAULT,
  connections,
  folds,
  menu
}: Props): React.JSX.Element {
  const host = useRef<HTMLDivElement>(null)
  const shellRef = useRef<HTMLDivElement>(null)
  const titleRef = useRef<HTMLDivElement>(null)
  const viewRef = useRef<EditorView | null>(null)
  const onChangeRef = useRef(onChange)
  onChangeRef.current = onChange
  const connectionsRef = useRef(connections)
  connectionsRef.current = connections
  const foldsRef = useRef(folds)
  foldsRef.current = folds
  const menuRef = useRef(menu)
  menuRef.current = menu
  const lastFormatRef = useRef('')

  // CM6 extensions are built once at mount, so they read live state + actions through refs.
  const [ac, setAc] = useState<AcState | null>(null)
  const [acIndex, setAcIndex] = useState(0)
  const candidates =
    ac && connectionsRef.current
      ? connectionsRef.current
          .candidates(ac.query, AC_MAX + 1)
          .filter((p) => p.title !== title)
          .slice(0, AC_MAX)
      : []

  const commit = (page: ConnPage): void => {
    const view = viewRef.current
    if (!view || !ac) return
    const { insert, caret } = connectionInsert(page.title, ac.from)
    view.dispatch({ changes: { from: ac.from, to: ac.to, insert }, selection: { anchor: caret }, userEvent: 'input' })
    setAc(null)
    view.focus()
  }

  const acCtl = useRef({ open: false, pick: () => {}, move: (_d: number) => {}, close: () => {} })
  acCtl.current = {
    open: ac !== null && candidates.length > 0,
    pick: () => {
      const p = candidates[acIndex]
      if (p) commit(p)
    },
    move: (d) => setAcIndex((i) => Math.max(0, Math.min(i + d, candidates.length - 1))),
    close: () => setAc(null)
  }
  const setAcRef = useRef(setAc)
  setAcRef.current = setAc

  useEffect(() => setAcIndex(0), [ac?.query])

  // Anchor below the caret; flip above when the panel would overflow the viewport bottom.
  const panelHeight = Math.min(candidates.length, AC_MAX_ROWS) * AC_ROW_H + AC_PADDING
  const acTop = ac
    ? ac.caretBottom + AC_GAP + panelHeight > window.innerHeight
      ? ac.caretTop - panelHeight - AC_GAP
      : ac.caretBottom + AC_GAP
    : 0

  useEffect(() => {
    const parent = host.current
    if (!parent) return
    const view = new EditorView({
      doc: initialBody,
      parent,
      extensions: [
        history(),
        Prec.highest(
          keymap.of([
            { key: 'ArrowDown', run: () => (acCtl.current.open ? (acCtl.current.move(1), true) : false) },
            { key: 'ArrowUp', run: () => (acCtl.current.open ? (acCtl.current.move(-1), true) : false) },
            { key: 'Enter', run: () => (acCtl.current.open ? (acCtl.current.pick(), true) : false) },
            { key: 'Escape', run: () => (acCtl.current.open ? (acCtl.current.close(), true) : false) }
          ])
        ),
        markdownInput,
        formatKeymap,
        keymap.of([...defaultKeymap, ...historyKeymap]),
        markdown(),
        EditorView.lineWrapping,
        markdownDecorations(() => connectionsRef.current),
        // Keep tableExtension AFTER the autocomplete keymap above: both bind Enter at Prec.highest, so the
        // tie resolves by registration order — autocomplete must run first so Enter-to-accept still works in a cell.
        tableExtension(),
        connectionClicks(() => connectionsRef.current),
        externalLinkClicks(),
        markdownFolding((keys) => foldsRef.current?.save(keys)),
        EditorView.updateListener.of((u) => {
          if (!(u.docChanged || u.selectionSet || u.focusChanged)) return // skip scroll/geometry-only updates
          const doc = u.state.doc.toString()
          const sel = u.state.selection.main
          if (u.docChanged) onChangeRef.current(doc)

          const fs = readFormatState(doc, sel.from, sel.to, u.view.hasFocus)
          const json = JSON.stringify(fs)
          if (json !== lastFormatRef.current) {
            lastFormatRef.current = json
            menuRef.current?.pushState(fs)
          }

          if (u.docChanged || u.selectionSet) {
            let next: AcState | null = null
            if (sel.empty) {
              const q = autocompleteQuery(doc, sel.head)
              const c = q && u.view.coordsAtPos(sel.head)
              if (q && c) next = { ...q, left: Math.round(c.left), caretTop: Math.round(c.top), caretBottom: Math.round(c.bottom) }
            }
            setAcRef.current(next)
          }
        })
      ]
    })
    viewRef.current = view
    // Restore this page's saved folds once the view's lines exist (the widget clones them).
    void foldsRef.current?.load().then((keys) => applySavedFolds(view, keys))
    // The header parks on scroll via a CSS scroll-driven animation (Styles.css) — no JS scroll handler.
    const unsubMenu = menuRef.current?.onAction((action) => applyEditorAction(view, action))
    return () => {
      unsubMenu?.()
      view.destroy()
      viewRef.current = null
    }
    // Mount once per page — the host keys on path; initialBody is the seed, not a live binding.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  // Body top-padding tracks the header height, so toggling the banner resizes the gutter automatically.
  useEffect(() => {
    const header = titleRef.current
    const shell = shellRef.current
    if (!header || !shell) return
    // --header-zone lives on the shell so both the body's top padding and the header's scroll-park range read it.
    const apply = (): void => shell.style.setProperty('--header-zone', `${header.offsetHeight}px`)
    apply()
    const ro = new ResizeObserver(apply)
    ro.observe(header)
    return () => ro.disconnect()
  }, [])

  return (
    <div ref={shellRef} className="mdpm-shell" style={{ '--editor-font-size': `${zoomFontSize(zoom)}px` } as React.CSSProperties}>
      {title !== undefined && path !== undefined && (
        <PageHeader
          ref={titleRef}
          path={path}
          title={title}
          icon={icon}
          cover={cover}
          onRename={onRename ?? ((): void => {})}
          onEditIcon={onEditIcon ?? ((): void => {})}
        />
      )}
      <div ref={host} className="mdpm-editor" />
      {ac && (
        <AutocompletePanel
          candidates={candidates}
          index={acIndex}
          left={ac.left}
          top={acTop}
          query={ac.query}
          onPick={commit}
        />
      )}
    </div>
  )
}
