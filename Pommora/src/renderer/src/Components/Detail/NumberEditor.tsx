import type { NumberConfig, NumberFamily } from '@shared/properties'
import { CURRENCY_CODES } from '@shared/properties'
import { Switch } from '@renderer/design-system/components/Switches/Switch'
import { PickerControl, type PickerChoice } from './PickerControl'
import { Reveal } from '../../design-system/components/Reveal'
import { configEditor, configLabel, configRow, optionsLabel, switchScale } from './settingsPane.css'
import * as s from './numberEditor.css'

export type NumberLook = 'number' | 'bar'

const FAMILY_OPTIONS: PickerChoice<NumberFamily>[] = [
  { value: 'number', label: 'Number' },
  { value: 'percent', label: 'Percent' },
  { value: 'currency', label: 'Currency' }
]
const CURRENCY_OPTIONS: PickerChoice<string>[] = CURRENCY_CODES.map((code) => ({ value: code, label: code }))
const STYLE_OPTIONS: PickerChoice<NumberLook>[] = [
  { value: 'number', label: 'Number' },
  { value: 'bar', label: 'Bar' }
]
// 'hidden' + 1..10, all as picker strings (PickerControl is <T extends string>).
const DECIMAL_OPTIONS: PickerChoice<string>[] = [
  { value: 'hidden', label: 'Hidden' },
  ...Array.from({ length: 10 }, (_, i) => ({ value: String(i + 1), label: String(i + 1) }))
]

const decimalsToPicker = (d: NumberConfig['number_decimals']): string => (typeof d === 'number' ? String(d) : 'hidden')
const pickerToDecimals = (v: string): 'hidden' | number => (v === 'hidden' ? 'hidden' : Number(v))

/** The Number property editor — property-wide Format config (Family · conditional Currency · Separators ·
 *  Decimals · conditional Fraction + Value) plus a per-view Style row (Number/Bar). Def-level fields
 *  write `onSetConfig` (the batched IPC); the look writes `onSetStyle` (the active view's column_styles).
 *  Conditional rows ride the Reveal disclosure — the DateTimeEditor Day-row pattern. */
export function NumberEditor({
  config,
  look,
  onSetConfig,
  onSetStyle
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
    <div className={configEditor}>
      <span className={optionsLabel}>Format</span>

      <div className={configRow}>
        <span className={configLabel}>Format</span>
        <PickerControl ariaLabel="Number format" value={family} options={FAMILY_OPTIONS} onPick={(v) => onSetConfig({ number_family: v })} />
      </div>

      <Reveal open={family === 'currency'} fill>
        <div className={configRow}>
          <span className={configLabel}>Currency</span>
          <PickerControl
            ariaLabel="Currency"
            value={config.number_currency ?? 'USD'}
            options={CURRENCY_OPTIONS}
            onPick={(v) => onSetConfig({ number_currency: v })}
          />
        </div>
      </Reveal>

      <Reveal open={!isPercent} fill>
        <div className={configRow}>
          <span className={configLabel}>Separators</span>
          <span className={switchScale}>
            <Switch checked={config.number_separators ?? true} onChange={(next) => onSetConfig({ number_separators: next })} ariaLabel="Separators" />
          </span>
        </div>
      </Reveal>

      <div className={configRow}>
        <span className={configLabel}>Decimals</span>
        <PickerControl
          ariaLabel="Decimal places"
          value={decimalsToPicker(config.number_decimals)}
          options={DECIMAL_OPTIONS}
          onPick={(v) => onSetConfig({ number_decimals: pickerToDecimals(v) })}
        />
      </div>

      <Reveal open={!isPercent} fill>
        <div className={configRow}>
          <span className={configLabel}>Fraction</span>
          <span className={switchScale}>
            <Switch checked={fraction} onChange={(next) => onSetConfig({ number_fraction: next })} ariaLabel="Fraction" />
          </span>
        </div>
      </Reveal>

      <Reveal open={!isPercent && fraction} fill>
        <div className={configRow}>
          <span className={configLabel}>Value</span>
          <input
            className={s.valueInput}
            type="number"
            aria-label="Fraction value"
            defaultValue={config.number_denominator ?? ''}
            onBlur={(e) => {
              const n = Number.parseFloat(e.target.value)
              onSetConfig({ number_denominator: Number.isNaN(n) ? undefined : n })
            }}
          />
        </div>
      </Reveal>

      <Reveal open={isPercent || fraction} fill>
        <div className={configRow}>
          <span className={configLabel}>Style</span>
          <PickerControl ariaLabel="Number style" value={look} options={STYLE_OPTIONS} onPick={onSetStyle} />
        </div>
      </Reveal>
    </div>
  )
}
