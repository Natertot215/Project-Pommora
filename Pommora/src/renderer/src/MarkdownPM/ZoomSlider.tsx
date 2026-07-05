import { ZOOM_MIN, ZOOM_MAX, ZOOM_DEFAULT, zoomFontSize } from './zoom'

interface Props {
  value?: number
  onChange: (zoom: number) => void
}

export function ZoomSlider({ value = ZOOM_DEFAULT, onChange }: Props): React.JSX.Element {
  return (
    <label className="mdpm-zoom" title={`Zoom — ${Math.round(zoomFontSize(value))}pt`}>
      <input
        type="range"
        min={ZOOM_MIN}
        max={ZOOM_MAX}
        step={0.05}
        value={value}
        onChange={(e) => onChange(Number(e.target.value))}
        aria-label="Editor zoom"
      />
    </label>
  )
}
