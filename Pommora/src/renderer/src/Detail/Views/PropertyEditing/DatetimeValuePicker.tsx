import type { ColumnStyle } from '@shared/columnStyles'
import type { PropertyValue } from '@shared/propertyValue'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { useSession } from '../../../store'
import { formatDate } from './formatValue'

/**
 * The shared datetime editing surface (card values, table cells, the preview inspector): owns the
 * value↔ISO mapping, the date_format remap, and the reactive time format so no call site rebuilds them.
 * The caller owns the mount + dismissal (a PickerMenu or a pane row).
 */
export function DatetimeValuePicker({
  value,
  dateFormat,
  onCommit,
}: {
  value: PropertyValue | null
  dateFormat?: ColumnStyle['date_format']
  onCommit: (value: PropertyValue | null) => void
}): React.JSX.Element {
  const timeFormat = useSession((s) => s.tree?.timeFormat)
  const fmt = dateFormat === 'relative' ? 'short' : (dateFormat ?? 'full')
  return (
    <CalendarPicker
      range={false}
      value={value?.kind === 'datetime' ? value.value : null}
      timeFormat={timeFormat}
      formatDateValue={(k) => formatDate(k, fmt, 'none')}
      onChange={(iso) => onCommit(iso ? { kind: 'datetime', value: iso } : null)}
    />
  )
}
