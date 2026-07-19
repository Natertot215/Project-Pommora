import { type RefObject, useState } from 'react'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { isValidLink } from '@shared/links'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { MenuItem, MenuPaneTopRow } from '@renderer/design-system/components/menu'
import { flushTrailing } from '@renderer/design-system/components/menu/menu.css'
import { PaneSlider } from '@renderer/Components/Detail/PaneSlider'
import { propertyTypeIconName } from '@renderer/Components/Detail/PropertyTypes'
import { useSession } from '../../../store'
import { PropertyOptionRows, pickSemantics } from '../PropertyEditing/PropertyPicker'
import { PropertyEditor } from '../PropertyEditing/PropertyEditor'
import { formatDate } from '../PropertyEditing/formatValue'
import { orderAddableDefs, parseEditorValue } from './cardValueInput'
import { compactRow } from './cardAddPicker.css'
import { cx } from '@renderer/design-system/cx'

/** The kinds the add-picker can author. Chip kinds + checkbox commit from the list/pane directly;
 *  date/number/url slide into a value pane mirroring the card value editor. */
export const ADDABLE_TYPES: ReadonlySet<string> = new Set([
  'select',
  'status',
  'multi_select',
  'datetime',
  'number',
  'url',
  'checkbox',
])

/** The value pane — routes the picked def to its editing surface (chip options, the calendar, or the
 *  text editor). pickSemantics is pure, so the branch is safe. */
function ValuePane({
  def,
  current,
  onCommit,
  onDone,
  onBack,
}: {
  def: PropertyDefinition
  current: PropertyValue | null
  onCommit: (value: PropertyValue | null) => void
  onDone: () => void
  onBack: () => void
}): React.JSX.Element {
  const topRow = <MenuPaneTopRow label="Properties" current={def.name} onBack={onBack} />
  if (def.type === 'datetime') {
    return (
      <>
        {topRow}
        <CalendarPicker
          range={false}
          value={current?.kind === 'datetime' ? current.value : null}
          timeFormat={useSession.getState().tree?.timeFormat}
          formatDateValue={(k) => formatDate(k, 'full', 'none')}
          onChange={(iso) => {
            onCommit(iso ? { kind: 'datetime', value: iso } : null)
            onDone()
          }}
        />
      </>
    )
  }
  if (def.type === 'number' || def.type === 'url') {
    return (
      <>
        {topRow}
        <PropertyEditor
          initial=""
          numeric={def.type === 'number'}
          validate={def.type === 'url' ? isValidLink : undefined}
          onCommit={(raw) => {
            const parsed = parseEditorValue(def.type, raw)
            if (parsed !== undefined) onCommit(parsed)
            onDone()
          }}
          onCancel={onBack}
        />
      </>
    )
  }
  const { options, selected, pick } = pickSemantics(def, current, onCommit, onDone)
  return (
    <>
      {topRow}
      <PropertyOptionRows def={def} options={options} selected={selected} onPick={pick} />
    </>
  )
}

/**
 * The card's two-stage add-picker (G-1): the reserved property zone's empty space opens a property
 * list (the page's blank, pickable properties) that slides into the picked property's value pane —
 * one PickerMenu hosting a PaneSlider, the SurfacePM multi-pane idiom. A checkbox commits straight
 * from the list; multi toggles stay open; single picks commit and dismiss.
 */
export function CardAddPicker({
  defs,
  currentOf,
  open,
  anchorRef,
  initialDef,
  onCommit,
  onDismiss,
}: {
  defs: PropertyDefinition[]
  currentOf: (def: PropertyDefinition) => PropertyValue | null
  open: boolean
  anchorRef: RefObject<HTMLElement | null>
  /** Jump straight to this property's value pane (the native Add Property ▸ pick), skipping the list. */
  initialDef?: PropertyDefinition | null
  onCommit: (def: PropertyDefinition, value: PropertyValue | null) => void
  onDismiss: () => void
}): React.JSX.Element {
  const [picked, setPicked] = useState<PropertyDefinition | null>(initialDef ?? null)
  const dismiss = (): void => {
    setPicked(null)
    onDismiss()
  }
  return (
    <PickerMenu open={open} onDismiss={dismiss} triggerRef={anchorRef} solid>
      <PaneSlider
        open={picked !== null}
        root={
          defs.length === 0 ? (
            <div style={{ minWidth: 96, height: 24 }} />
          ) : (
            <div>
              {orderAddableDefs(defs).map((d) => (
                <MenuItem
                  key={d.id}
                  className={cx(flushTrailing, compactRow)}
                  leading={
                    <Icon name={propertyTypeIconName(d.type) ?? 'square-dashed'} size={14} />
                  }
                  trailing={
                    d.type === 'checkbox' ? undefined : <Icon name="chevron-right" size={14} />
                  }
                  onClick={() => {
                    if (d.type === 'checkbox') {
                      onCommit(d, { kind: 'checkbox', value: true })
                      dismiss()
                    } else setPicked(d)
                  }}
                >
                  {d.name}
                </MenuItem>
              ))}
            </div>
          )
        }
        detail={
          picked && (
            <div>
              <ValuePane
                def={picked}
                current={currentOf(picked)}
                onCommit={(v) => onCommit(picked, v)}
                onDone={dismiss}
                onBack={() => setPicked(null)}
              />
            </div>
          )
        }
        minWidth={155}
        minHeight={0}
      />
    </PickerMenu>
  )
}
