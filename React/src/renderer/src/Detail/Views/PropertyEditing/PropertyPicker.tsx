import type { RefObject } from 'react'
import type { ColumnLook } from '@shared/columnStyles'
import type { PropertyDefinition } from '@shared/properties'
import type { PropertyValue } from '@shared/propertyValue'
import { PickerMenu, PickerOption } from '@renderer/design-system/components/PickerMenu/PickerMenu'
import { Chip, chipShapeForType } from '@renderer/Components/Chip'
import { ContextChip } from '@renderer/Components/ContextChip'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { statusGroupOf } from './statusCycle'
import { StatusCapsule } from './StatusCapsule'

/** A pickable option — status options flatten out of their groups, select/multi read
 *  `select_options`. Values are shown regardless of name (a seed-shaped option is still a real
 *  value); the groups themselves are containers, never pickable chips. */
const optionsOf = (def: PropertyDefinition): Array<{ value: string; label: string; color?: string }> => {
  return def.type === 'status' ? (def.status_groups ?? []).flatMap((g) => g.options) : (def.select_options ?? [])
}

const selectedValues = (current: PropertyValue | null): string[] => {
  if (!current) return []
  if (current.kind === 'multiSelect' || current.kind === 'context') return current.value
  if (current.kind === 'select' || current.kind === 'status') return [current.value]
  return []
}

/**
 * The value dropdown every container view's status/select/multi cells share (F-2: PickerMenu for
 * values, native menus for meta). Table-agnostic and stateless: props in, `onCommit(PropertyValue)`
 * out — the caller owns the write + the optimistic patch. Self-managed: PickerMenu portals to a body
 * top layer off `triggerRef` (escaping the table's overflow clip), owns its Bloom-in/out off `open`,
 * and dismisses (outside-click / Escape) via its own backdrop. Single-value types commit + dismiss on
 * pick; multi toggles against `current` and stays open.
 */
export function PropertyPicker({
  def,
  current,
  open,
  triggerRef,
  look,
  contextOptions,
  onCommit,
  onDismiss
}: {
  def: PropertyDefinition
  current: PropertyValue | null
  /** Self-managed open state — PickerMenu blooms in on true, out on false. */
  open: boolean
  /** The cell the picker hangs off — measured for placement, so it escapes the table's clip. */
  triggerRef: RefObject<HTMLElement | null>
  /** The column's resolved look — a status column on a glyph look (checkbox/capsule) renders
   *  its OPTIONS as capsule chips too (Nathan); pill columns keep labeled pills. */
  look?: ColumnLook
  /** Context columns (the reserved tiers + user context props) pick from the NEXUS's contexts,
   *  not the def — the caller supplies the tier's list. Toggles like multi; commits `context`. */
  contextOptions?: Array<{ value: string; label: string; color?: string }>
  onCommit: (value: PropertyValue | null) => void
  onDismiss: () => void
}): React.JSX.Element | null {
  const options = contextOptions ?? optionsOf(def)
  const multi = def.type === 'multi_select' || contextOptions !== undefined
  const selected = selectedValues(current)

  const pick = (value: string): void => {
    if (multi) {
      const next = selected.includes(value) ? selected.filter((v) => v !== value) : [...selected, value]
      onCommit(contextOptions ? { kind: 'context', value: next } : { kind: 'multiSelect', value: next })
      return
    }
    onCommit(def.type === 'status' ? { kind: 'status', value } : { kind: 'select', value })
    onDismiss()
  }

  return (
    <PickerMenu open={open} onDismiss={onDismiss} triggerRef={triggerRef} solid>
        {options.length === 0 ? (
          // An empty option list (a Select/Multi with all options removed) — the spacer keeps the
          // notch pane's proportions so it doesn't collapse into a degenerate beak. Tune here.
          <div style={{ minWidth: 96, height: 24 }} />
        ) : (
          options.map((o) => {
            const capsule = def.type === 'status' && (look === 'checkbox' || look === 'capsule')
            const group = capsule ? statusGroupOf(o.value, def) : undefined
            return (
              <PickerOption key={o.value} selected={selected.includes(o.value)} onClick={() => pick(o.value)}>
                {capsule ? (
                  <StatusCapsule color={o.color} group={group} />
                ) : contextOptions ? (
                  <ContextChip color={chipColorFor(o.color)} title={o.label} />
                ) : (
                  <Chip
                    color={chipColorFor(o.color)}
                    label={o.label}
                    shape={chipShapeForType(def.type)}
                  />
                )}
              </PickerOption>
            )
          })
        )}
      </PickerMenu>
  )
}
