import { useState } from 'react'
import { CalendarPicker } from '@renderer/design-system/components/CalendarPicker/CalendarPicker'
import { condensedDate, formatDate } from '@renderer/Detail/Views/PropertyEditing/formatValue'

/** One live picker mount + the ISO it last committed — the same formatter wiring as the
 *  table's datetime cell (formatValue is the Swift-parity source). */
function Mount({
  label,
  timeFormat,
  range
}: {
  label: string
  timeFormat: 'twelveHour' | 'twentyFourHour'
  range: boolean
}): React.JSX.Element {
  const [committed, setCommitted] = useState<string | null>(null)
  return (
    <div className="ds-picker-mount">
      <div className="ds-chip-rowlabel">{label}</div>
      <CalendarPicker
        range={range}
        timeFormat={timeFormat}
        formatDateValue={(iso, condensed) =>
          condensed ? condensedDate(iso, 'short', condensed.withYear) : formatDate(iso, 'full', 'none')
        }
        onChange={(iso) => setCommitted(iso)}
      />
      <div className="ds-swatch-hex">{committed ?? 'no commit yet'}</div>
    </div>
  )
}

export function CalendarPickerLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>CalendarPicker</h2>
        <div className="ds-picker-grid">
          <Mount label="Single · 12-hour" timeFormat="twelveHour" range={false} />
          <Mount label="Range · 24-hour" timeFormat="twentyFourHour" range />
        </div>
      </section>
    </div>
  )
}
