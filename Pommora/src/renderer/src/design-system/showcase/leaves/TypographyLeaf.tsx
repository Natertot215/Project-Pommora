import { text } from '@renderer/design-system/tokens'
import { humanize, useComputedStyleText } from './helpers'

type RampStyle = { standard: string; emphasized: string }

const ALL_TYPE_KEYS: Array<keyof typeof text> = [
  'largeTitle',
  'title1',
  'title2',
  'title3',
  'headline',
  'body',
  'callout',
  'control',
  'caption',
  'footnote',
  'subline',
]

const TYPE_COLUMNS: Array<{ label: string; colorVar: string }> = [
  { label: 'Primary', colorVar: '--label-primary' },
  { label: 'Secondary', colorVar: '--label-secondary' },
  { label: 'Tertiary', colorVar: '--label-tertiary' },
]

function TypeEntry({
  name,
  t,
  colorVar,
}: {
  name: string
  t: RampStyle
  colorVar: string
}): React.JSX.Element {
  const [ref, meta] = useComputedStyleText<HTMLSpanElement>(
    (cs) => `${parseFloat(cs.fontSize)}px · ${cs.fontWeight}`,
  )
  const color = `var(${colorVar})`
  return (
    <div className="ds-type-entry">
      <div className="ds-type-entry-label">
        {name}
        <span className="ds-type-entry-meta">{meta}</span>
      </div>
      <div className="ds-type-entry-samples" style={{ color }}>
        <span ref={ref} className={t.standard}>
          {name}
        </span>
        <span className={t.emphasized}>{name}</span>
      </div>
    </div>
  )
}

function TypeColumn({ label, colorVar }: { label: string; colorVar: string }): React.JSX.Element {
  return (
    <div className="ds-type-col">
      <div className="ds-type-col-header">{label}</div>
      {ALL_TYPE_KEYS.map((key) => (
        <TypeEntry key={key} name={humanize(key)} t={text[key]} colorVar={colorVar} />
      ))}
    </div>
  )
}

export function TypographyLeaf(): React.JSX.Element {
  return (
    <div className="ds-leaf">
      <section className="ds-section">
        <h2>Typography · Inter</h2>
        <div className="ds-type-grid">
          {TYPE_COLUMNS.map((col) => (
            <TypeColumn key={col.label} label={col.label} colorVar={col.colorVar} />
          ))}
        </div>
      </section>
    </div>
  )
}
