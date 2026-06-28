import { useEffect, useRef } from 'react'
import { EditorView, keymap } from '@codemirror/view'
import { Prec } from '@codemirror/state'
import { history, historyKeymap, defaultKeymap } from '@codemirror/commands'
import { markdown } from '@codemirror/lang-markdown'
import { markdownDecorations } from './editor/decorations'
import { markdownInput } from './editor/input'
import { tableWidgetExtension, applySavedHeadingCols, type TableHeadingColsApi } from './Tables'
import { listDragExtension } from './editor/listDrag'
import { blockHandles, blockGripHover } from './editor/blockHandles'
import { blockDragExtension } from './editor/blockDrag'
import { customCaret } from './editor/caret'
import { calloutAtomic } from './editor/calloutAtomic'
import { calloutGuard } from './editor/calloutGuard'
import { connectionClicks } from './editor/connections'
import { externalLinkClicks } from './editor/links'
import { markdownFolding, applySavedFolds, type FoldsApi } from './editor/folding'
import { applyEditorAction, type EditorMenuApi } from './editor/menu'
import { formatKeymap } from './editor/formatKeymap'
import { readFormatState } from './editor/formatState'
import { AC_MAX } from './autocomplete'
import { useConnectionAutocomplete, detectConnectionQuery } from './useConnectionAutocomplete'
import { AutocompletePanel } from './AutocompletePanel'
import type { ConnectionsApi } from './connections'
import type { IconName } from '@renderer/design-system/symbols'
import { PageHeader } from './PageHeader'
import { ZOOM_DEFAULT, zoomFontSize } from './zoom'
import './Styles.css'

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
  tableHeadingColumns?: TableHeadingColsApi
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
  tableHeadingColumns,
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
  const tableHeadingColsRef = useRef(tableHeadingColumns)
  tableHeadingColsRef.current = tableHeadingColumns
  const menuRef = useRef(menu)
  menuRef.current = menu
  const lastFormatRef = useRef('')

  // CM6 extensions are built once at mount, so they read live state + actions through refs. The `[[…]]`
  // autocomplete state machine is shared with table cells; this editor's seams are the candidate source
  // (over-fetch one to drop the page's own title) and the inline panel placement (rendered below).
  const { ac, setAc, candidates, acIndex, acTop, commit, acCtl } = useConnectionAutocomplete(
    viewRef,
    (query) =>
      connectionsRef.current
        ? connectionsRef.current.candidates(query, AC_MAX + 1).filter((p) => p.title !== title).slice(0, AC_MAX)
        : []
  )

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
        // Interactive table widget — renders each Markdown table as an editable HTML table over the GFM
        // source; the connections getter lets `[[…]]` render + autocomplete inside cells.
        tableWidgetExtension(
          () => connectionsRef.current,
          (indices) => tableHeadingColsRef.current?.save(indices)
        ),
        // Grab a list glyph (•, number, or checkbox) to drag-reorder the item; click toggles/places caret.
        listDragExtension,
        // Block-drag rail handles: a hover grip on each draggable block's first line (paragraph/code/quote/list).
        blockHandles,
        // Reveal each grip only while the pointer is in its gutter strip (not over the line's text).
        blockGripHover,
        // Press a block grip → drag the whole block → drop it at the nearest block boundary.
        blockDragExtension,
        // Drawn caret (rounded bar in text, I-beam on empty lines, smooth fade) — native caret hidden in CSS.
        customCaret,
        // The hidden `> [!type] ` callout head is atomic — caret can't enter it, so the tag can't be corrupted.
        calloutAtomic,
        // Reject any delete that would erode a callout body line's `>` prefix in place (drop it out of the box).
        calloutGuard,
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

          if (u.docChanged || u.selectionSet) detectConnectionQuery(u.view, setAc)
        })
      ]
    })
    viewRef.current = view
    // Restore this page's saved folds once the view's lines exist (the widget clones them).
    void foldsRef.current?.load().then((keys) => applySavedFolds(view, keys))
    // Restore this page's heading-column tables (rebuilds the affected table widgets).
    void tableHeadingColsRef.current?.load().then((indices) => applySavedHeadingCols(view, indices))
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
