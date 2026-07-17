import { useState } from 'react'
import type { NumberConfig, NumberFamily } from '@shared/properties'
import { CURRENCY_CODES } from '@shared/properties'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { Icon } from '@renderer/design-system/symbols'
import { EditableInput } from '@renderer/Components/EditableInput'
import { cx } from '../../design-system/cx'
import { PickerControl, type PickerChoice } from './PickerControl'
import { Reveal } from '../../design-system/components/Reveal'
import { configLabel, configRow, switchScale } from './settingsPane.css'
import { value as pickerValue } from './pickerControl.css'
import * as s from './numberEditor.css'

export type NumberLook = 'number' | 'bar'

const FAMILY_OPTIONS: PickerChoice<NumberFamily>[] = [
  { value: 'number', label: 'Number' },
  { value: 'percent', label: 'Percent' },
  { value: 'currency', label: 'Currency' },
]
const CURRENCY_OPTIONS: PickerChoice<string>[] = CURRENCY_CODES.map((code) => ({
  value: code,
  label: code,
}))
const STYLE_OPTIONS: PickerChoice<NumberLook>[] = [
  { value: 'number', label: 'Number' },
  { value: 'bar', label: 'Bar' },
]
// 'hidden' + 1..10, all as picker strings (PickerControl is <T extends string>).
const DECIMAL_OPTIONS: PickerChoice<string>[] = [
  { value: 'hidden', label: 'Hidden' },
  ...Array.from({ length: 10 }, (_, i) => ({ value: String(i + 1), label: String(i + 1) })),
]

const decimalsToPicker = (d: NumberConfig['number_decimals']): string =>
  typeof d === 'number' ? String(d) : 'hidden'
const pickerToDecimals = (v: string): 'hidden' | number => (v === 'hidden' ? 'hidden' : Number(v))

/** One labelled config row — label left, control (child) right. The shared configRow/configLabel
 *  primitive, wrapped once so each row below is just its label + control. */
function Row({ label, children }: { label: string; children: React.ReactNode }): React.JSX.Element {
  return (
    <div className={cx(configRow, s.row)}>
      <span className={configLabel}>{label}</span>
      {children}
    </div>
  )
}

/** The fraction denominator control — reads like the picker rows (secondary value + double-chevron) at
 *  rest, and reveals the accent input only while editing; committing (Enter/blur) returns to the trigger.
 *  Mirrors PickerControl's trigger so it sits identically among the other rows. */
function ValueField({
  value,
  onCommit,
}: {
  value: number | undefined
  onCommit: (n: number | undefined) => void
}): React.JSX.Element {
  const [editing, setEditing] = useState(false)
  const chevron = <Icon name="chevrons-up-down" size={12} />
  if (editing) {
    return (
      <span className={s.valueControl}>
        <EditableInput
          value={value !== undefined ? String(value) : ''}
          className={s.valueCaret}
          caretAtEnd
          onCommit={(text) => {
            const t = text.trim()
            const n = Number.parseFloat(t)
            onCommit(t === '' || Number.isNaN(n) ? undefined : n)
            setEditing(false)
          }}
          onCancel={() => setEditing(false)}
        />
        {chevron}
      </span>
    )
  }
  return (
    <button type="button" className={s.valueControl} onClick={() => setEditing(true)}>
      <span className={pickerValue}>{value ?? ''}</span>
      {chevron}
    </button>
  )
}

/** The Number property editor — property-wide Format config (Family · conditional Currency · Separators ·
 *  Decimals · conditional Fraction + Value) plus a per-view Style row (Number/Bar). Def-level fields
 *  write `onSetConfig` (the batched IPC); the look writes `onSetStyle` (the active view's column_styles).
 *  Conditional rows ride the Reveal disclosure — the DateTimeEditor Day-row pattern. */
export function NumberEditor({
  config,
  look,
  onSetConfig,
  onSetStyle,
}: {
  config: NumberConfig
  look: NumberLook
  onSetConfig: (patch: Partial<NumberConfig>) => void
  onSetStyle: (look: NumberLook) => void
}): React.JSX.Element {
  const family: NumberFamily = config.number_family ?? 'number'
  const isPercent = family === 'percent'
  const fraction = config.number_fraction ?? false

  return (
    <div className={s.section}>
      <Row label="Format">
        <PickerControl
          ariaLabel="Number format"
          value={family}
          options={FAMILY_OPTIONS}
          onPick={(v) => onSetConfig({ number_family: v })}
        />
      </Row>

      <Reveal open={family === 'currency'} fill>
        <Row label="Currency">
          <PickerControl
            ariaLabel="Currency"
            value={config.number_currency ?? 'USD'}
            options={CURRENCY_OPTIONS}
            onPick={(v) => onSetConfig({ number_currency: v })}
          />
        </Row>
      </Reveal>

      <Reveal open={!isPercent} fill>
        <Row label="Separators">
          <span className={switchScale}>
            <Switch
              checked={config.number_separators ?? true}
              onChange={(next) => onSetConfig({ number_separators: next })}
              ariaLabel="Separators"
            />
          </span>
        </Row>
      </Reveal>

      <Row label="Decimals">
        <PickerControl
          ariaLabel="Decimal places"
          value={decimalsToPicker(config.number_decimals)}
          options={DECIMAL_OPTIONS}
          onPick={(v) => onSetConfig({ number_decimals: pickerToDecimals(v) })}
        />
      </Row>

      <Reveal open={!isPercent} fill>
        <Row label="Fraction">
          <span className={switchScale}>
            <Switch
              checked={fraction}
              onChange={(next) => onSetConfig({ number_fraction: next })}
              ariaLabel="Fraction"
            />
          </span>
        </Row>
      </Reveal>

      <Reveal open={!isPercent && fraction} fill>
        <Row label="Value">
          <ValueField
            value={config.number_denominator}
            onCommit={(n) => onSetConfig({ number_denominator: n })}
          />
        </Row>
      </Reveal>

      <Reveal open={isPercent || fraction} fill>
        <Row label="Style">
          <PickerControl
            ariaLabel="Number style"
            value={look}
            options={STYLE_OPTIONS}
            onPick={onSetStyle}
          />
        </Row>
      </Reveal>
    </div>
  )
}
