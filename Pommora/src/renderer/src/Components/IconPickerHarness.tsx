import { useLayoutEffect, useRef, useState } from 'react'
import { IconPicker } from './IconPicker'
import { lucideGlyph } from '@renderer/design-system/symbols/AllSymbols'

const DIRECTIONS = ['down', 'up', 'left', 'right'] as const
type Dir = (typeof DIRECTIONS)[number]

const ctl: React.CSSProperties = {
  padding: '4px 10px',
  borderRadius: 8,
  border: '1px solid var(--fill-secondary)',
  background: 'transparent',
  color: 'var(--label-primary)',
  fontSize: 13,
  cursor: 'pointer'
}

/**
 * Homepage sizing/beak harness for the Icon Picker — NOT app chrome. Toggles the four beak directions
 * and drives `--icon-picker-w/h` so the min/max footprint can be eyeballed live. Removed once the real
 * consumers are wired.
 */
export function IconPickerHarness(): React.JSX.Element {
  const [open, setOpen] = useState(false)
  const [dir, setDir] = useState<Dir>('down')
  const [picked, setPicked] = useState<string | undefined>(undefined)
  const [w, setW] = useState(224)
  const [h, setH] = useState(204)
  const triggerRef = useRef<HTMLButtonElement>(null)

  useLayoutEffect(() => {
    const root = document.documentElement
    root.style.setProperty('--icon-picker-w', `${w}px`)
    root.style.setProperty('--icon-picker-h', `${h}px`)
  }, [w, h])

  const Picked = picked ? lucideGlyph(picked) : undefined

  return (
    <div style={{ padding: 48, display: 'flex', flexDirection: 'column', gap: 20, alignItems: 'flex-start' }}>
      <div style={{ display: 'flex', gap: 8 }}>
        {DIRECTIONS.map((d) => (
          <button
            key={d}
            type="button"
            style={{ ...ctl, ...(d === dir ? { borderColor: 'var(--accent)', color: 'var(--accent)' } : null) }}
            onClick={() => setDir(d)}
          >
            {d}
          </button>
        ))}
      </div>

      <label style={{ display: 'flex', gap: 10, alignItems: 'center', color: 'var(--label-secondary)', fontSize: 13 }}>
        Width {w}
        <input type="range" min={200} max={480} value={w} onChange={(e) => setW(Number(e.target.value))} />
      </label>
      <label style={{ display: 'flex', gap: 10, alignItems: 'center', color: 'var(--label-secondary)', fontSize: 13 }}>
        Height {h}
        <input type="range" min={160} max={480} value={h} onChange={(e) => setH(Number(e.target.value))} />
      </label>

      <button ref={triggerRef} type="button" style={{ ...ctl, display: 'inline-flex', gap: 8, alignItems: 'center' }} onClick={() => setOpen((o) => !o)}>
        {Picked ? <Picked size={16} /> : null}
        {picked ?? 'Open Icon Picker'}
      </button>

      <IconPicker open={open} onClose={() => setOpen(false)} triggerRef={triggerRef} direction={dir} value={picked} onSelect={setPicked} />
    </div>
  )
}
