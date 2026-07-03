import { useRef, useState } from 'react'
import { Icon } from '@renderer/design-system/symbols'
import { chipLabel, chipColor } from '@renderer/design-system/tokens'
import { chipColorFor } from '@renderer/design-system/tokens/colorMap'
import { addOption, recolorOption, fallbackTitle, type Option } from '@shared/optionModel'
import type { PropertyType } from '@shared/properties'
import { cx } from '@renderer/design-system/cx'
import { Chip } from '../Chip'
import { EditableInput } from '../EditableInput'
import { ColorPicker } from './ColorPicker'
import * as s from './viewPane.css'

/**
 * The Select / Multi-Select option editor — the flat option list inside a property's editor pane
 * (Planning 7-3, Phase 2). Options render as squared `label`-shape chips; a right-click chip menu
 * (native) drives Rename (inline) · Remove · Clear, and a hover palette icon opens the 2×5 recolor
 * picker. The caller owns persistence: each callback maps to a `property.*Option` write (+ error
 * surface + reload). Status layers grouping on top (Phase 3).
 */
export function OptionEditor({
  type,
  options,
  onSetOptions,
  onRenameOption,
  onRemoveOption,
  onClearOption
}: {
  type: PropertyType
  options: Option[]
  onSetOptions: (next: Option[]) => void
  onRenameOption: (oldValue: string, newTitle: string) => void
  onRemoveOption: (value: string) => void
  onClearOption: (value: string) => void
}): React.JSX.Element {
  const [adding, setAdding] = useState(false)
  const [renaming, setRenaming] = useState<string | null>(null)
  const [coloring, setColoring] = useState<string | null>(null)
  // The open row's recolor button — the ColorPicker measures + dismiss-exempts it (only one is open).
  const paletteBtnRef = useRef<HTMLButtonElement>(null)

  const commitAdd = (raw: string): void => {
    setAdding(false)
    onSetOptions(addOption(options, raw.trim() || fallbackTitle(type)))
  }
  const commitRename = (oldValue: string, raw: string): void => {
    setRenaming(null)
    const title = raw.trim() || fallbackTitle(type)
    if (title !== oldValue) onRenameOption(oldValue, title)
  }
  const openMenu = async (o: Option): Promise<void> => {
    const action = await window.nexus.optionMenu({ name: o.label })
    if (action === 'option:rename') setRenaming(o.value)
    else if (action === 'option:remove') onRemoveOption(o.value)
    else if (action === 'option:clear') onClearOption(o.value)
  }
  const pickColor = (o: Option, color: string | undefined): void => {
    setColoring(null)
    onSetOptions(recolorOption(options, o.value, color))
  }

  return (
    <div className={s.optionEditor}>
      <div className={s.optionsRow}>
        <span className={s.optionsLabel}>Options</span>
        <button type="button" className={s.optionsAdd} aria-label="Add Option" onClick={() => setAdding(true)}>
          <Icon name="plus" size={s.ICON.optionsAdd} />
        </button>
      </div>
      <div className={s.optionList}>
        {options.map((o) => {
          const isColoring = coloring === o.value
          return (
          <div
            key={o.value}
            className={s.optionRow}
            onContextMenu={(e) => {
              e.preventDefault()
              void openMenu(o)
            }}
          >
            {renaming === o.value ? (
              <span className={cx(chipLabel, chipColor[chipColorFor(o.color)])}>
                <EditableInput
                  value={o.label}
                  autoSize
                  className={s.optionInput}
                  onCommit={(raw) => commitRename(o.value, raw)}
                  onCancel={() => setRenaming(null)}
                />
              </span>
            ) : (
              <>
                <Chip shape="label" color={chipColorFor(o.color)} label={o.label} />
                <span className={s.paletteAnchor}>
                  <button
                    ref={isColoring ? paletteBtnRef : undefined}
                    type="button"
                    className={s.paletteButton}
                    style={isColoring ? { opacity: 1 } : undefined}
                    aria-label="Recolor"
                    onClick={() => setColoring((v) => (v === o.value ? null : o.value))}
                  >
                    <Icon name="palette" size={s.ICON.palette} />
                  </button>
                  <ColorPicker
                    open={isColoring}
                    selected={chipColorFor(o.color)}
                    onPick={(color) => pickColor(o, color)}
                    onDismiss={() => setColoring(null)}
                    triggerRef={paletteBtnRef}
                  />
                </span>
              </>
            )}
          </div>
          )
        })}
        {adding ? (
          <div className={s.optionRow}>
            <span className={cx(chipLabel, chipColor.default)}>
              <EditableInput value="" autoSize className={s.optionInput} onCommit={commitAdd} onCancel={() => setAdding(false)} />
            </span>
          </div>
        ) : null}
      </div>
    </div>
  )
}
