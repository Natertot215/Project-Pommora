import { useRef, useState } from 'react'
import type { ResolvedColumn, ViewRow } from '@shared/types'
import { isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { isValidLink } from '@shared/links'
import type { ColumnStyle } from '@shared/columnStyles'
import { cellMenuContextFor } from '@shared/cellMenu'
import { parseStyleAction } from '@shared/columnMenu'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { useSession } from '../../../store'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { Cell } from '../Table/Cell'
import { parseLink } from '../Table/linkValue'
import { parseEditorValue } from './cardValueInput'
import type { ResolveContext } from '../Table/resolveContext'
import { PropertyPicker } from '../PropertyEditing/PropertyPicker'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { formatDate } from '../PropertyEditing/formatValue'
import { nextCycleValue } from '../PropertyEditing/statusCycle'

type ContextOption = { value: string; label: string; color?: string }

/**
 * One interactive property value on a card — the ratified cell gesture matrix (portable to
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
}: {
  row: ViewRow
  column: ResolvedColumn
  ctx: ResolveContext
  style: ColumnStyle
  contextOptions: ContextOption[] | null
  onCommit: (column: ResolvedColumn, value: PropertyValue | null) => void
  onStyle: (colId: string, key: keyof ColumnStyle & string, value: string) => void
}): React.JSX.Element {
  const anchorRef = useRef<HTMLSpanElement>(null)
  const [mode, setMode] = useState<null | 'picker' | 'editor' | 'datetime'>(null)
  const dismiss = (): void => setMode(null)
  const commit = (v: PropertyValue | null): void => onCommit(column, v)

  const t = column.kind === 'tier' ? 'context' : declaredType(column.id, ctx.schema)
  const v = resolveFieldValue(row, column.id, ctx.schema)

  const onClick = (e: React.MouseEvent): void => {
    if (e.ctrlKey) return // macOS secondary-click — let the (future) context menu win
    e.stopPropagation()
    if (t === 'status' && style.look === 'checkbox') {
      const current = v.kind === 'status' || v.kind === 'select' ? v.value : undefined
      if (current === undefined) return setMode('picker') // empty never cycles blind — assign
      const next = nextCycleValue(
        current,
        ctx.schema.find((d) => d.id === column.id),
      )
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
      const url = v.kind === 'url' ? parseLink(v.value).url : ''
      if (url) void window.nexus.openExternal(url)
      else setMode('editor')
    }
    // file: each chip opens its own file (Cell's file branch stops propagation) — no dispatch here.
  }

  // Right-click a value → its native menu (A-13/I-6: always a menu, never an action), the shared
  // per-kind matrix (Clear · Style · Edit). stopPropagation keeps it off the card-level menu.
  const onContextMenu = async (e: React.MouseEvent): Promise<void> => {
    e.preventDefault()
    e.stopPropagation()
    const menuCtx = cellMenuContextFor(
      column,
      declaredType(column.id, ctx.schema),
      style,
      !isBlankValue(v),
    )
    if (!menuCtx) return
    const action = await window.nexus.cellMenu(menuCtx)
    if (!action) return
    if (action === 'cell:clear') commit(null)
    else if (action === 'cell:edit' || action === 'cell:rename') setMode('editor')
    else if (action.startsWith('style:')) {
      const parsed = parseStyleAction(action)
      if (parsed) onStyle(column.id, parsed.key, parsed.value)
    }
  }

  const editorInitial = (): string => {
    if (v.kind === 'number') return String(v.value)
    if (v.kind === 'url') return parseLink(v.value).url
    return ''
  }
  const commitEditor = (raw: string): void => {
    setMode(null)
    const parsed = parseEditorValue(t, raw)
    if (parsed !== undefined) commit(parsed)
  }

  const editing = mode === 'editor'
  return (
    // biome-ignore lint/a11y/noStaticElementInteractions: the value is the click surface for its picker.
    <span ref={anchorRef} className="card-value" onClick={onClick} onContextMenu={onContextMenu}>
      {editing ? (
        <PropertyEditor
          initial={editorInitial()}
          numeric={t === 'number'}
          validate={t === 'url' ? isValidLink : undefined}
          onCommit={commitEditor}
          onCancel={dismiss}
        />
      ) : (
        <Cell
          row={row}
          column={column}
          ctx={ctx}
          hideIcon={false}
          style={style}
          remove={(next) => commit(next)}
        />
      )}
      {mode === 'datetime' && (
        <PickerMenu solid open onDismiss={dismiss} triggerRef={anchorRef}>
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
      {mode === 'picker' && (
        <PropertyPicker
          def={
            ctx.schema.find((d) => d.id === column.id) ?? {
              id: column.id,
              name: '',
              type: 'context' as const,
            }
          }
          current={v}
          open
          triggerRef={anchorRef}
          look={style.look}
          {...(contextOptions ? { contextOptions } : {})}
          onCommit={(nv) => {
            commit(nv)
            if (t !== 'multi_select' && t !== 'context') dismiss()
          }}
          onDismiss={dismiss}
        />
      )}
    </span>
  )
}
