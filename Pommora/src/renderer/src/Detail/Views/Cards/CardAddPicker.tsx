import { type RefObject, useState } from 'react'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { Icon } from '@renderer/design-system/symbols'
import { PickerMenu } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { MenuItem, MenuPaneTopRow } from '@renderer/design-system/components/menu'
import { flushTrailing } from '@renderer/design-system/components/menu/menu.css'
import { PaneSlider } from '@renderer/Components/Detail/PaneSlider'
import { propertyTypeIconName } from '@renderer/Components/Detail/PropertyTypes'
import { PropertyOptionRows, pickSemantics } from '../PropertyEditing/PropertyPicker'

/** The kinds the add-picker's value pane can author today — the chip-pickable set. */
export const ADDABLE_TYPES: ReadonlySet<string> = new Set(['select', 'status', 'multi_select'])

/** The value pane — its own component so the pick-semantics hook keys off the picked def. */
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
  const { options, selected, pick } = pickSemantics(def, current, onCommit, onDone)
  return (
    <>
      <MenuPaneTopRow label="Properties" current={def.name} onBack={onBack} />
      <PropertyOptionRows def={def} options={options} selected={selected} onPick={pick} />
    </>
  )
}

/**
 * The card's two-stage add-picker (G-1): the reserved property zone's empty space opens a property
 * list (the page's blank, pickable properties) that slides into the picked property's value pane —
 * one PickerMenu hosting a PaneSlider, the SurfacePM multi-pane idiom. Multi toggles stay open;
 * single picks commit and dismiss.
 */
export function CardAddPicker({
  defs,
  currentOf,
  open,
  anchorRef,
  onCommit,
  onDismiss,
}: {
  defs: PropertyDefinition[]
  currentOf: (def: PropertyDefinition) => PropertyValue | null
  open: boolean
  anchorRef: RefObject<HTMLElement | null>
  onCommit: (def: PropertyDefinition, value: PropertyValue | null) => void
  onDismiss: () => void
}): React.JSX.Element {
  const [picked, setPicked] = useState<PropertyDefinition | null>(null)
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
              {defs.map((d) => (
                <MenuItem
                  key={d.id}
                  className={flushTrailing}
                  leading={
                    <Icon name={propertyTypeIconName(d.type) ?? 'square-dashed'} size={14} />
                  }
                  trailing={<Icon name="chevron-right" size={14} />}
                  onClick={() => setPicked(d)}
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
        minWidth={170}
        minHeight={120}
      />
    </PickerMenu>
  )
}
