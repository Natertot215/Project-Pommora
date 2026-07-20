import type { ColumnStyle } from '@shared/columnStyles'
import type { PropertyValue } from '@shared/propertyValue'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { useSession } from '../../../store'
import { formatDate } from './formatValue'

/**
 * The datetime editing surface every value view shares (cards, table cells, the preview inspector):
 * a range-less CalendarPicker seeded from the value's ISO, formatted through the column's
 * `date_format` (relative maps to short; unset falls to full), reading the nexus-wide time format,
 * and committing typed `datetime` values. The caller owns the mount + dismissal (a PickerMenu, or a
 * pane row); this owns the value↔ISO mapping so no call site rebuilds it.
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
