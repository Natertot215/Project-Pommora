import { useRef, useState } from 'react'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { isValidLink } from '@shared/links'
import type { ColumnStyle } from '@shared/columnStyles'
import { cellMenuContextFor } from '@shared/cellMenu'
import { parseStyleAction } from '@shared/columnMenu'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { cx } from '@renderer/design-system/cx'
import { text } from '@renderer/design-system/tokens/typography.css'
import { useSession } from '../../../store'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import type { ContextOption } from '../pipeline/contextOptions'
import { Cell } from '../Table/Cell'
import { parseLink, urlClickTarget, urlValueFromEdit, urlValueFromRename } from '../Table/linkValue'
import { parseEditorValue } from './cardValueInput'
import type { ResolveContext } from '../Table/resolveContext'
import { PropertyPicker } from '../PropertyEditing/PropertyPicker'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { formatDate } from '../PropertyEditing/formatValue'
import { nextCycleValue } from '../PropertyEditing/statusCycle'

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
  contextOptions,
  onCommit,
  onStyle,
  onHide,
  allowInlineRemove,
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  style: ColumnStyle
  contextOptions: ContextOption[] | null
  onCommit: (column: ResolvedColumn, value: PropertyValue | null) => void
  onStyle: (colId: string, key: keyof ColumnStyle & string, value: string) => void
  onHide: (colId: string) => void
  /** True at a large-enough card scale (D-1). Gates ONLY the multi-select hover-× — on a small chip the
   *  × zone overlaps the whole chip and steals the picker click, dropping one value; select/context keep
   *  their × always (it clears the whole value, an expected affordance). */
  allowInlineRemove: boolean
}): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const [mode, setMode] = useState<null | 'picker' | 'editor' | 'rename' | 'datetime'>(null)
  const [clickX, setClickX] = useState<number>()
  const dismiss = (): void => setMode(null)
  const commit = (v: PropertyValue | null): void => onCommit(column, v)

  const dt = declaredType(column.id, ctx.schema)
  const t = column.kind === 'tier' ? 'context' : dt
  const v = resolveFieldValue(row, column.id, ctx.schema)
  const schemaDef = ctx.schema.find((d) => d.id === column.id)
  // The kinds a click on a blank value can fill in place — status/select/multi/context open the picker,
  // datetime the calendar, number/url the editor. A checkbox draws its own box; file/last-edited have no
  // fill path, so those get no "Empty" affordance (it would be a dead click).
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
    setClickX(e.clientX) // the value picker drops from the click point, not the value's fixed centre
    if (t === 'status' && style.look === 'checkbox') {
      const current = v.kind === 'status' || v.kind === 'select' ? v.value : undefined
      if (current === undefined) return setMode('picker') // empty never cycles blind — assign
      const next = nextCycleValue(current, schemaDef)
      if (next !== null) commit({ kind: 'status', value: next })
    } else if (t === 'checkbox') {
      const checked = v.kind === 'checkbox' && v.value
      commit(checked ? null : { kind: 'checkbox', value: true })
    } else if (
      t === 'status' ||
      t === 'select' ||
      t === 'multi_select' ||
      t === 'context' ||
      t === 'datetime'
    ) {
      setMode(t === 'datetime' ? 'datetime' : 'picker')
    } else if (t === 'number') {
      setMode('editor')
    } else if (t === 'url') {
      const url = urlClickTarget(v.kind === 'url' ? v.value : undefined)
      if (url) void window.nexus.openExternal(url)
      else setMode('editor')
    }
    // file: each chip opens its own file (Cell's file branch stops propagation) — no dispatch here.
  }

  // Right-click a value → its native menu (always a menu, never an action), the shared per-kind matrix
  // (Clear · Style · Edit) plus a trailing Remove — cards pass hideable, so any property can be dropped
  // from the view here. stopPropagation keeps it off the card-level menu.
  const onContextMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    const menuCtx = cellMenuContextFor(column, dt, style, !isBlankValue(v), true)
    if (!menuCtx) return
    const action = await window.nexus.cellMenu(menuCtx)
    if (!action) return
    if (action === 'cell:clear') commit(null)
    else if (action === 'cell:hide') onHide(column.id)
    else if (action === 'cell:edit') setMode('editor')
    else if (action === 'cell:rename')
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
    <span
      ref={anchorRef}
      className="card-value"
      onClick={onClick}
      onContextMenu={onContextMenu}
      // The card is a whole-surface drag handle (it pointer-captures on pointerdown, which would steal
      // this value's click). Stopping pointerdown keeps the value clickable; the card still drags from
      // its thumb/title.
      onPointerDown={(e) => e.stopPropagation()}
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
          // The hover-× rides every pill EXCEPT a multi-select's below the scale floor: there a stray
          // click on the × zone drops just ONE of several values (silent partial loss). A select/context
          // × clears the whole value — an expected affordance — so it always stays.
          {...(t !== 'multi_select' || allowInlineRemove
            ? { remove: (next: PropertyValue | null) => commit(next) }
            : {})}
        />
      )}
      {/* The pickers mount persistently and ride a dynamic `open` (the table's pattern), so a dismiss
          flips open→false on a surviving instance and its Bloom-out plays — a conditional mount would
          tear the instance out in one commit, skipping the exit animation. The datetime calendar is
          gated on the column TYPE (a static per-cell fact, not `open`), so a non-datetime value never
          allocates it and datetime cells keep the persistent instance. */}
      {t === 'datetime' && (
        <PickerMenu solid open={mode === 'datetime'} onDismiss={dismiss} triggerRef={anchorRef}>
          <CalendarPicker
            range={false}
            value={v.kind === 'datetime' ? v.value : null}
            timeFormat={useSession.getState().tree?.timeFormat}
            formatDateValue={(k) =>
              formatDate(
                k,
                style.date_format === 'relative' ? 'short' : (style.date_format ?? 'full'),
                'none',
              )
            }
            onChange={(iso) => commit(iso ? { kind: 'datetime', value: iso } : null)}
          />
        </PickerMenu>
      )}
      <PropertyPicker
        def={schemaDef ?? { id: column.id, name: '', type: 'context' as const }}
        current={v}
        open={mode === 'picker'}
        triggerRef={anchorRef}
        anchorX={clickX}
        look={style.look}
        {...(contextOptions ? { contextOptions } : {})}
        onCommit={(nv) => {
          commit(nv)
          if (t !== 'multi_select' && t !== 'context') dismiss()
        }}
        onDismiss={dismiss}
      />
    </span>
  )
}
