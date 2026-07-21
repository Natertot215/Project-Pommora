import { useEffect, useRef } from 'react'
import type { NexusLabels, ResolvedColumn, ViewRow } from '@shared/types'
import { isBlankValue, type PropertyValue } from '@shared/propertyValue'
import { isCompact, type SavedView } from '@shared/views'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { TextPicker } from '@renderer/design-system/components/TextPicker'
import type { ContextOption } from '../pipeline/contextOptions'
import { declaredType, resolveFieldValue } from '../pipeline/value'
import { styleFor } from '../Table/columnStyles'
import { parseLink, urlValueFromEdit } from '../Table/linkValue'
import { solidColorCss } from '../Table/solidColor'
import type { ResolveContext } from '../Table/resolveContext'
import { PropertyPicker, syntheticContextDef } from '../PropertyEditing/PropertyPicker'
import { DatetimeValuePicker } from '../PropertyEditing/DatetimeValuePicker'
import { CardAddPicker } from './CardAddPicker'
import { addColumn, addEntriesFor, type AddEntry } from './cardValueInput'

/** A value's request to open its picker — the anchor is the clicked value span. */
export type ValuePickerRequest = {
  rowId: string
  column: ResolvedColumn
  kind: 'picker' | 'datetime' | 'link'
  anchor: HTMLElement
  clickX?: number
  /** An add-menu-originated open: the property reveals on the FIRST commit (never on a dismissed,
   *  untouched picker — the add flow's never-mind rule). */
  revealOnCommit?: boolean
}
/** A card's request to open the add-property menu — the anchor is the card's text area. */
export type AddPickerRequest = {
  rowId: string
  anchor: HTMLElement
  initialEntry: AddEntry | null
}

/**
 * ONE grid-level home for the cards' portal pickers (the value picker, its datetime calendar, and
 * the add-property menu). Row churn — a commit that regroups, a band collapse, a re-sort — remounts
 * cards, and a picker owned by a card dies with it, skipping its Bloom-out. Hosted here, the picker
 * outlives the card: PickerMenu's placement freeze covers a dead anchor, live values resolve off the
 * CURRENT row by id, and a row that stops showing its column dismisses ANIMATED instead of by
 * teardown. Both pickers mount persistently and ride `open` — the Bloom law by construction.
 */
export function CardPickerHost({
  value,
  add,
  rowById,
  view,
  ctx,
  labels,
  columns,
  commitValue,
  contextOptionsFor,
  onReveal,
  onOpenValue,
  onDismissValue,
  onDismissAdd,
}: {
  value: ValuePickerRequest | null
  add: AddPickerRequest | null
  rowById: Map<string, ViewRow>
  view: SavedView
  ctx: ResolveContext
  labels: NexusLabels | undefined
  columns: ResolvedColumn[]
  commitValue: (row: ViewRow, column: ResolvedColumn, value: PropertyValue | null) => void
  contextOptionsFor: (column: ResolvedColumn) => ContextOption[] | null
  onReveal: (id: string) => void
  onOpenValue: (req: ValuePickerRequest) => void
  onDismissValue: () => void
  onDismissAdd: () => void
}): React.JSX.Element {
  // The last non-null requests render through the closing frames (exit presence keeps the pane
  // mounted after dismiss); the anchor rides a plain ref object PickerMenu can track.
  const lastValue = useRef(value)
  if (value) lastValue.current = value
  const lastAdd = useRef(add)
  if (add) lastAdd.current = add
  const valueAnchorRef = useRef<HTMLElement | null>(null)
  valueAnchorRef.current = (value ?? lastValue.current)?.anchor ?? null
  const addAnchorRef = useRef<HTMLElement | null>(null)
  addAnchorRef.current = (add ?? lastAdd.current)?.anchor ?? null

  const vReq = value ?? lastValue.current
  const vRow = vReq ? rowById.get(vReq.rowId) : undefined
  const vColumn = vReq?.column
  const vCurrent =
    vRow && vColumn ? resolveFieldValue(vRow, vColumn.id, ctx.schema) : { kind: 'null' as const }
  const vDef = vColumn
    ? (ctx.schema.find((d) => d.id === vColumn.id) ?? syntheticContextDef(vColumn.id))
    : syntheticContextDef('_none')
  const vStyle = vColumn ? styleFor(vColumn.id, ctx.schema, view) : {}
  const vType = vColumn?.kind === 'tier' ? 'context' : declaredType(vColumn?.id ?? '', ctx.schema)
  const vContextOptions = vColumn ? contextOptionsFor(vColumn) : null

  // A row that vanished (deleted) or a value Compact just dropped (emptied multi/context — the
  // signed-off close) dismisses the picker — ANIMATED, through the same exit as a click-out.
  const compactLayout = isCompact(view)
  useEffect(() => {
    if (!value) return
    const row = rowById.get(value.rowId)
    if (!row) return onDismissValue()
    // An add-originated open (revealOnCommit) is blank BY DEFINITION until its first commit — the
    // compact blank-drop close applies only to a value that was visible and just emptied.
    if (value.revealOnCommit) return
    const cur = resolveFieldValue(row, value.column.id, ctx.schema)
    const isCheckbox = ctx.schema.find((d) => d.id === value.column.id)?.type === 'checkbox'
    if (compactLayout && isBlankValue(cur) && !isCheckbox) onDismissValue()
  }, [value, rowById, ctx, compactLayout, onDismissValue])
  useEffect(() => {
    if (add && !rowById.get(add.rowId)) onDismissAdd()
  }, [add, rowById, onDismissAdd])

  const aReq = add ?? lastAdd.current
  const aRow = aReq ? rowById.get(aReq.rowId) : undefined
  const aEntries =
    aRow && labels ? addEntriesFor(aRow, view, ctx, labels, columns) : ([] as AddEntry[])

  // One commit gate for every value-picker surface: an add-originated open reveals on the first
  // real commit (revealProperty is idempotent + in-flight-deduped, so repeat commits no-op).
  const commitPicked = (nv: PropertyValue | null): void => {
    if (!vRow || !vColumn) return
    if (vReq?.revealOnCommit) onReveal(vColumn.id)
    commitValue(vRow, vColumn, nv)
  }
  // A dependent kind picked in the ADD menu exits it and opens the value's own dropdown at the same
  // anchor (the calendar's law, generalized): datetime → the calendar, url → the link dropdown.
  const pickDependent = (entry: AddEntry): void => {
    if (!aReq) return
    onDismissAdd()
    onOpenValue({
      rowId: aReq.rowId,
      column: addColumn(entry.id),
      kind: entry.type === 'datetime' ? 'datetime' : 'link',
      anchor: aReq.anchor,
      revealOnCommit: true,
    })
  }
  const vRaw = vCurrent.kind === 'url' ? vCurrent.value : undefined

  return (
    <>
      <PickerMenu
        solid
        open={value?.kind === 'datetime'}
        onDismiss={onDismissValue}
        triggerRef={valueAnchorRef}
      >
        <DatetimeValuePicker
          value={vCurrent}
          dateFormat={vStyle.date_format}
          onCommit={commitPicked}
        />
      </PickerMenu>
      <TextPicker
        open={value?.kind === 'link'}
        onDismiss={onDismissValue}
        triggerRef={valueAnchorRef}
        value={vRaw ? parseLink(vRaw).url : ''}
        accent={solidColorCss(vDef.link_color)}
        onCommit={(raw) => {
          // urlValueFromEdit rides an existing alias along; undefined = invalid (no write), null =
          // cleared — a clear only applies to an EXISTING value (an untouched add stays never-mind).
          const nv = urlValueFromEdit(raw, vRaw)
          if (nv !== undefined && (nv !== null || (!vReq?.revealOnCommit && vRaw))) commitPicked(nv)
          onDismissValue()
        }}
      />
      <PropertyPicker
        def={vDef}
        current={vCurrent}
        open={value?.kind === 'picker'}
        triggerRef={valueAnchorRef}
        anchorX={vReq?.clickX}
        look={vStyle.look}
        {...(vContextOptions ? { contextOptions: vContextOptions } : {})}
        onCommit={(nv) => {
          commitPicked(nv)
          if (vType !== 'multi_select' && vType !== 'context') onDismissValue()
        }}
        onDismiss={onDismissValue}
      />
      <CardAddPicker
        entries={aEntries}
        currentOf={(e) => (aRow ? resolveFieldValue(aRow, e.id, ctx.schema) : null)}
        contextOptionsOf={(e) => contextOptionsFor(addColumn(e.id))}
        open={add !== null}
        anchorRef={addAnchorRef}
        initialEntry={aReq?.initialEntry ?? null}
        onCommit={(e, v) => {
          onReveal(e.id)
          if (aRow) commitValue(aRow, addColumn(e.id), v)
        }}
        onReveal={(e) => onReveal(e.id)}
        onPickDependent={pickDependent}
        onDismiss={onDismissAdd}
      />
    </>
  )
}
