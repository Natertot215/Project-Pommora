import { useRef, useState } from 'react'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { isValidLink } from '@shared/links'
import type { ColumnStyle } from '@shared/columnStyles'
import { cellMenuContextFor } from '@shared/cellMenu'
import { parseStyleAction } from '@shared/columnMenu'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens/typography.css'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { Cell } from '../Table/Cell'
import { parseLink, urlValueFromEdit, urlValueFromRename } from '../Table/linkValue'
import { parseEditorValue } from './cardValueInput'
import type { ResolveContext } from '../Table/resolveContext'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { numberDivisor } from '../PropertyEditing/formatValue'
import { sharedValueClickAction } from '../PropertyEditing/valueClick'

/**
 * One interactive property value on a card — the cell gesture matrix (portable to
 * Gallery/List/Cards, TableView.md), anchored per-value rather than per-table: the value renders
 * through the shared `Cell`, and a click opens the right surface for its kind — status/select/
 * multi/context/tier → the PropertyPicker dropdown; a checkbox-look status cycles (or opens the
 * picker when empty); a checkbox toggles; a date → the CalendarPicker; a number → the inline
 * editor; a url opens (filled) or edits (empty); a file chip opens its own file. Pill chips carry
 * the hover-× remove. `onCommit` owns the write routing (tier vs property).
 */
export function CardValue({
  row,
  column,
  ctx,
  style,
  onCommit,
  onStyle,
  onHide,
  onOpenPicker,
  allowInlineRemove,
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  style: ColumnStyle
  onCommit: (column: ResolvedColumn, value: PropertyValue | null) => void
  onStyle: (colId: string, key: keyof ColumnStyle & string, value: string) => void
  onHide: (colId: string) => void
  /** Open this value's portal picker at the GRID-LEVEL host (CardPickerHost) — the picker outlives
   *  this card's remounts. kind 'picker' = the option picker; 'datetime' = the calendar. */
  onOpenPicker: (
    column: ResolvedColumn,
    kind: 'picker' | 'datetime' | 'link',
    anchor: HTMLElement,
    clickX?: number,
  ) => void
  /** False only when the EMBED zoom shrinks chips (≤0.8 effective — chips don't scale with
   *  card_size). Gates ONLY the multi-select hover-×; select keeps its × always (clears the whole
   *  value) and context keeps its × always (removes that ONE context). The × itself is inert until
   *  hover-revealed (ChipRemoveButton), so an un-hovered click opens the picker at every size. */
  allowInlineRemove: boolean
}): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const [mode, setMode] = useState<null | 'editor' | 'rename'>(null)
  const dismiss = (): void => setMode(null)
  const commit = (v: PropertyValue | null): void => onCommit(column, v)

  const dt = declaredType(column.id, ctx.schema)
  const t = column.kind === 'tier' ? 'context' : dt
  const v = resolveFieldValue(row, column.id, ctx.schema)
  const schemaDef = ctx.schema.find((d) => d.id === column.id)
  // Kinds a click on a blank value fills in place (picker / calendar / editor). A checkbox draws its own
  // box; file/last-edited have no fill path — no "Empty" affordance for them (it would be a dead click).
  const canFillBlank =
    t === 'status' ||
    t === 'select' ||
    t === 'multi_select' ||
    t === 'context' ||
    t === 'datetime' ||
    t === 'number' ||
    t === 'url'

  const onClick = (e: React.MouseEvent): void => {
    if (e.ctrlKey) return // macOS secondary-click — let the (future) context menu win
    e.stopPropagation()
    // React events cross portals along the component tree: a click inside the picker (an option, the
    // backdrop) bubbles back through its trigger — this span — and would re-open what the pick/outside
    // click just dismissed. Swallow it here (the stopPropagation above still keeps it off the card).
    if (!e.currentTarget.contains(e.target as Node)) return
    // The portal pickers open at the grid-level host, anchored here, dropping from the click point.
    const openPicker = (kind: 'picker' | 'datetime' | 'link'): void => {
      if (anchorRef.current) onOpenPicker(column, kind, anchorRef.current, e.clientX)
    }
    // The shared click semantics (cycle/toggle/picker/datetime) live in one router; only the
    // surface-specific tails (number/url placement) stay here.
    const shared = sharedValueClickAction(t, style.look, v, schemaDef)
    if (shared) {
      if (shared.kind === 'commit') commit(shared.value)
      else openPicker(shared.kind)
    } else if (t === 'number') {
      setMode('editor')
    } else if (t === 'url') {
      // The value click opens the LINK DROPDOWN (filled or empty); opening the URL itself belongs to
      // the rendered anchor inside LinkCell, which stops propagation before this handler.
      openPicker('link')
    }
    // file: each chip opens its own file (Cell's file branch stops propagation) — no dispatch here.
  }

  // Right-click a value → its native menu (always a menu, never an action), the shared per-kind matrix
  // (Clear · Style · Edit) plus a trailing Remove — cards pass hideable, so any property can be dropped
  // from the view here. stopPropagation keeps it off the card-level menu.
  const onContextMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    // Portal events bubble the component tree: a right-click inside an open picker (backdrop/layer)
    // arrives here too — swallow it, never pop a mis-targeted menu (the onClick guard's twin).
    if (!e.currentTarget.contains(e.target as Node)) return
    const barCapable = dt === 'number' && numberDivisor(schemaDef) !== undefined
    const menuCtx = cellMenuContextFor(column, dt, style, !isBlankValue(v), true, barCapable)
    if (!menuCtx) return
    const action = await window.nexus.cellMenu(menuCtx)
    if (!action) return
    if (action === 'cell:clear') commit(null)
    else if (action === 'cell:hide') onHide(column.id)
    else if (action === 'cell:edit') {
      if (t === 'url' && anchorRef.current) onOpenPicker(column, 'link', anchorRef.current)
      else setMode('editor')
    } else if (action === 'cell:rename')
      setMode('rename') // url alias edit (keeps the URL)
    else if (action.startsWith('style:')) {
      const parsed = parseStyleAction(action)
      if (parsed) onStyle(column.id, parsed.key, parsed.value)
    }
  }

  const editorInitial = (): string => {
    if (mode === 'rename') return v.kind === 'url' ? (parseLink(v.value).alias ?? '') : ''
    if (v.kind === 'number') return String(v.value)
    if (v.kind === 'url') return parseLink(v.value).url
    return ''
  }
  const commitEditor = (raw: string): void => {
    setMode(null)
    // Rename sets the url's alias (keeps the URL); a url Edit rewrites the URL but rides the existing
    // alias along; everything else parses normally. `undefined` = invalid, so don't commit.
    const parsed =
      mode === 'rename'
        ? urlValueFromRename(raw, v.kind === 'url' ? v.value : '')
        : t === 'url'
          ? urlValueFromEdit(raw, v.kind === 'url' ? v.value : undefined)
          : parseEditorValue(t, raw)
    if (parsed !== undefined) commit(parsed)
  }

  const editing = mode === 'editor' || mode === 'rename'
  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: the value is the click surface for its picker.
    // data-drag-slop: the whole card is a drag handle, so a press that begins on a value gets a larger
    // drag-activation threshold — a tap-wobble opens the picker instead of lifting the card.
    <span
      ref={anchorRef}
      className="card-value"
      data-drag-slop=""
      onClick={onClick}
      onContextMenu={onContextMenu}
    >
      {editing ? (
        <PropertyEditor
          initial={editorInitial()}
          numeric={mode === 'editor' && t === 'number'}
          validate={mode === 'editor' && t === 'url' ? isValidLink : undefined}
          onCommit={commitEditor}
          onCancel={dismiss}
        />
      ) : isBlankValue(v) && canFillBlank ? (
        // A visible-but-empty property (Standard shows every visible property, filled or not): a clickable
        // placeholder so the row fills in place — only for kinds a blank click actually fills.
        <span className={cx('card-value-empty', text.caption.emphasized)}>--</span>
      ) : (
        <Cell
          row={row}
          column={column}
          ctx={ctx}
          hideIcon={false}
          style={style}
          // Drop the hover-× only on a small multi-select chip (see allowInlineRemove).
          {...(t !== 'multi_select' || allowInlineRemove
            ? { remove: (next: PropertyValue | null) => commit(next) }
            : {})}
        />
      )}
    </span>
  )
}
