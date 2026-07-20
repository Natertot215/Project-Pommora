import { type CSSProperties, type RefObject, useState } from 'react'
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
import { type AddEntry, orderAddableEntries, parseEditorValue } from './cardValueInput'
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
          // Stay open on change (mirrors the card value's datetime edit) so the day AND the time can be
          // set — the outside-click dismiss commits the pending via CalendarPicker's unmount flush.
          // onDone() here would close the pane on the first date click (the Compact add-path bug).
          onChange={(iso) => onCommit(iso ? { kind: 'datetime', value: iso } : null)}
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
 * The card's two-stage add-property menu: the list is everything NOT currently shown (hidden props,
 * tiers, and blank addable props). A pane entry (a blank addable-type prop) slides into a value pane
 * to set a value; a reveal-only entry (a hidden tier/context, a hidden-but-filled prop, a checkbox)
 * just unhides on pick. One PickerMenu hosting a PaneSlider, the SurfacePM multi-pane idiom.
 */
export function CardAddPicker({
  entries,
  currentOf,
  open,
  anchorRef,
  initialEntry,
  onCommit,
  onReveal,
  onDismiss,
}: {
  entries: AddEntry[]
  currentOf: (entry: AddEntry) => PropertyValue | null
  open: boolean
  anchorRef: RefObject<HTMLElement | null>
  /** Jump straight to this entry's value pane (the native Add Property ▸ pick on a pane entry). */
  initialEntry?: AddEntry | null
  onCommit: (entry: AddEntry, value: PropertyValue | null) => void
  onReveal: (entry: AddEntry) => void
  onDismiss: () => void
}): React.JSX.Element {
  const [picked, setPicked] = useState<AddEntry | null>(initialEntry ?? null)
  const dismiss = (): void => {
    setPicked(null)
    onDismiss()
  }
  return (
    <PickerMenu
      open={open}
      onDismiss={dismiss}
      triggerRef={anchorRef}
      solid
      // Tighten the "Properties" pane header for the add-picker's compact density (the shared
      // --top-row-block rhythm knob — paddingBlock + separator gap).
      style={{ '--top-row-block': '0px' } as CSSProperties}
    >
      <PaneSlider
        open={picked !== null}
        root={
          entries.length === 0 ? (
            <div style={{ minWidth: 96, height: 24 }} />
          ) : (
            <div>
              {orderAddableEntries(entries).map((e) => (
                <MenuItem
                  key={e.id}
                  className={cx(flushTrailing, compactRow)}
                  leading={
                    <Icon name={propertyTypeIconName(e.type) ?? 'square-dashed'} size={14} />
                  }
                  trailing={e.revealOnly ? undefined : <Icon name="chevron-right" size={14} />}
                  onClick={() => {
                    if (e.revealOnly) {
                      onReveal(e)
                      dismiss()
                    } else setPicked(e)
                  }}
                >
                  {e.name}
                </MenuItem>
              ))}
            </div>
          )
        }
        detail={
          picked?.def && (
            <div>
              <ValuePane
                def={picked.def}
                current={currentOf(picked)}
                onCommit={(v) => onCommit(picked, v)}
                onDone={dismiss}
                onBack={() => setPicked(null)}
              />
            </div>
          )
        }
        minWidth={120}
        minHeight={0}
      />
    </PickerMenu>
  )
}
