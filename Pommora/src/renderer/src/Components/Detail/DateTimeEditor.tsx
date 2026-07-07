import type { ColumnStyle, DateFormat, TimeFormat, WeekdayFormat } from '@shared/columnStyles'
import { Icon, type IconName } from '@renderer/design-system/symbols'
import { PickerControl } from './PickerControl'
import { Reveal } from '../../design-system/components/Reveal'
import { optionsLabel } from './settingsPane.css'
import * as s from './dateTimeEditor.css'

const DATE_OPTIONS: { value: DateFormat; label: string }[] = [
  { value: 'monthDayYear', label: 'MM/DD/YYYY' },
  { value: 'dayMonthYear', label: 'DD/MM/YYYY' },
  { value: 'short', label: 'Short Date' },
  { value: 'full', label: 'Full Date' },
  { value: 'relative', label: 'Relative' }
]
const WEEKDAY_OPTIONS: { value: WeekdayFormat; label: string }[] = [
  { value: 'long', label: 'Full' },
  { value: 'short', label: 'Short' },
  { value: 'none', label: 'Hidden' }
]
const TIME_OPTIONS: { value: TimeFormat; label: string }[] = [
  { value: 'twelveHour', label: '12 Hours' },
  { value: 'twentyFourHour', label: '24 Hours' },
  { value: 'none', label: 'Hidden' }
]
function PickerRow<T extends string>({
  glyph,
  label,
  ariaLabel,
  value,
  options,
  onPick
}: {
  glyph: IconName
  label: string
  ariaLabel: string
  value: T
  options: { value: T; label: string }[]
  onPick: (v: T) => void
}): React.JSX.Element {
  return (
    <div className={s.row}>
      <span className={s.leading}>
        <Icon name={glyph} size={16} />
      </span>
      <span className={s.label}>{label}</span>
      <PickerControl ariaLabel={ariaLabel} value={value} options={options} onPick={onPick} />
    </div>
  )
}

/** The datetime property's per-view Format section — Date · (conditional) Day · Time. The Day row
 *  (weekday) reveals only for the worded date formats (short/full); Relative and the numeric formats
 *  carry no weekday. Time stays visible under Relative (it gates the "at <clock>" rendering). */
export function DateTimeEditor({
  style,
  onChange
}: {
  style: ColumnStyle
  onChange: (patch: Partial<ColumnStyle>) => void
}): React.JSX.Element {
  const dateFmt: DateFormat = style.date_format ?? 'full'
  const showDay = dateFmt === 'short' || dateFmt === 'full'
  return (
    <div className={s.section}>
      <span className={optionsLabel}>Format</span>
      <PickerRow
        glyph="calendar-days"
        label="Date"
        ariaLabel="Date format"
        value={dateFmt}
        options={DATE_OPTIONS}
        onPick={(v) => onChange({ date_format: v })}
      />
      <Reveal open={showDay} fill>
        <PickerRow
          glyph="calendar"
          label="Day"
          ariaLabel="Weekday format"
          value={style.weekday ?? 'none'}
          options={WEEKDAY_OPTIONS}
          onPick={(v) => onChange({ weekday: v })}
        />
      </Reveal>
      <PickerRow
        glyph="clock"
        label="Time"
        ariaLabel="Time format"
        value={style.time_format ?? 'none'}
        options={TIME_OPTIONS}
        onPick={(v) => onChange({ time_format: v })}
      />
    </div>
  )
}
