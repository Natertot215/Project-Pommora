import { useRef, useState, type CSSProperties } from 'react'
import type { NexusTree } from '@shared/types'
import { chip, chipColor, chipLabel, vars } from '@renderer/design-system/tokens'
import { cx } from '@renderer/design-system/cx'
import { useDismiss } from '@renderer/design-system/components/Popover'
import { useExitPresence } from '@renderer/design-system/useExitPresence'
import { PickerMenu, PickerOption } from '@renderer/design-system/components/PickerMenu'
import { DetailScaffold } from './DetailScaffold'

type ChipColorName = keyof typeof chipColor

// A few options, some intentionally long, to show the chip cap + scroll-on-hover.
const OPTIONS: Array<{ color: ChipColorName; text: string }> = [
  { color: 'blue', text: 'Personal' },
  { color: 'red', text: 'Urgent — needs review before end of day' },
  { color: 'green', text: 'Done' },
  { color: 'purple', text: 'Someday / maybe' },
  { color: 'orange', text: 'Waiting on a reply from the vendor team' },
  { color: 'cyan', text: 'Reference' },
  { color: 'yellow', text: 'Follow up' }
]

/**
 * The homepage view — the live nexus entity (the sidebar header). v1 renders a blank page under
 * its banner; dynamic widgets are future work, composed here at the view level (not the banner's).
 */
export function HomepageView({ tree }: { tree: NexusTree | null }): React.JSX.Element {
  return (
    <DetailScaffold owner={{ path: '', kind: 'homepage', name: tree?.nexus.name ?? 'Home', banner: tree?.homepage.banner }}>
      <PickerDemo />
    </DetailScaffold>
  )
}

// ---- TEMP: live mount + notch-shape tuner for the inline-edit PickerMenu (motion is the canonical
// dropdown-menu Bloom, not tunable here). Rip out once a real inline-edit surface consumes PickerMenu. ----

type Shape = { radius: number; notchWidth: number; notchHeight: number; notchCurve: number }

function PickerDemo(): React.JSX.Element {
  const [shape, setShape] = useState<Shape>({ radius: 14, notchWidth: 28, notchHeight: 8, notchCurve: 0.25 })
  const [color, setColor] = useState<ChipColorName>('blue')
  const [open, setOpen] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  useDismiss(ref, () => setOpen(false), open)
  const picker = useExitPresence(open)
  const current = OPTIONS.find((o) => o.color === color) ?? OPTIONS[0]

  return (
    <div style={{ display: 'flex', gap: '48px', alignItems: 'flex-start', flexWrap: 'wrap', margin: '40px' }}>
      <PickerDashboard shape={shape} setShape={setShape} />
      <div ref={ref} style={{ position: 'relative' }}>
        <button type="button" className={cx(chip, chipColor[color])} onClick={() => setOpen((o) => !o)}>
          <span className={chipLabel}>{current.text}</span>
        </button>
        {picker.mounted && (
          <PickerMenu
            closing={picker.closing}
            radius={shape.radius}
            notchWidth={shape.notchWidth}
            notchHeight={shape.notchHeight}
            notchCurve={shape.notchCurve}
          >
            {OPTIONS.map((o) => (
              <PickerOption
                key={o.color}
                selected={o.color === color}
                onClick={() => {
                  setColor(o.color)
                  setOpen(false)
                }}
              >
                <span className={cx(chip, chipColor[o.color])}>
                  <span className={chipLabel}>{o.text}</span>
                </span>
              </PickerOption>
            ))}
          </PickerMenu>
        )}
      </div>
    </div>
  )
}

const dashStyle: CSSProperties = {
  display: 'flex',
  flexDirection: 'column',
  gap: '6px',
  width: '260px',
  padding: '14px',
  borderRadius: '12px',
  border: `1px solid ${vars.color.separator.line}`,
  background: vars.color.fill.quaternary
}
const dashTitleStyle: CSSProperties = {
  fontSize: '10px',
  fontWeight: 600,
  textTransform: 'uppercase',
  letterSpacing: '0.04em',
  color: vars.color.label.secondary
}
const rowStyle: CSSProperties = { display: 'flex', alignItems: 'center', gap: '8px', fontSize: '11px' }
const rowLabelStyle: CSSProperties = { flex: '0 0 92px', color: vars.color.label.secondary }
const rowValueStyle: CSSProperties = { flex: '0 0 36px', textAlign: 'right', color: vars.color.label.primary }

function PickerDashboard({
  shape,
  setShape
}: {
  shape: Shape
  setShape: React.Dispatch<React.SetStateAction<Shape>>
}): React.JSX.Element {
  return (
    <div style={dashStyle}>
      <div style={dashTitleStyle}>Picker — Notch</div>
      <Slider label="Corner" v={shape.radius} min={4} max={24} step={1} set={(v) => setShape((s) => ({ ...s, radius: v }))} />
      <Slider label="Notch width" v={shape.notchWidth} min={20} max={160} step={2} set={(v) => setShape((s) => ({ ...s, notchWidth: v }))} />
      <Slider label="Notch height" v={shape.notchHeight} min={4} max={30} step={1} set={(v) => setShape((s) => ({ ...s, notchHeight: v }))} />
      <Slider label="Notch curve" v={shape.notchCurve} min={0} max={1.2} step={0.05} set={(v) => setShape((s) => ({ ...s, notchCurve: v }))} />
    </div>
  )
}

function Slider({
  label,
  v,
  min,
  max,
  step,
  set
}: {
  label: string
  v: number
  min: number
  max: number
  step: number
  set: (v: number) => void
}): React.JSX.Element {
  return (
    <label style={rowStyle}>
      <span style={rowLabelStyle}>{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={v}
        onChange={(e) => set(Number.parseFloat(e.target.value))}
        style={{ flex: '1 1 auto', accentColor: 'var(--accent)' }}
      />
      <span style={rowValueStyle}>{v}</span>
    </label>
  )
}
