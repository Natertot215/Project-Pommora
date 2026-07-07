// The custom registry glyphs (List's rounded-circle list, Cards' 2×3 stretch-horizontal bar stack).
// Registry-conforming forwardRef svgs at Lucide's default 2 stroke weight so they sit evenly beside it.
import { forwardRef } from 'react'
import { type LucideIcon, type LucideProps } from 'lucide-react'
import { IconProgressCheck } from '@tabler/icons-react'

// Tabler glyphs read slightly smaller than Lucide at the same box; this bump sits them at the same
// visual size (Nathan-tunable). Numeric sizes scale directly; the `1em` seam path scales via calc.
const TABLER_SCALE = 1.1
const scaleTabler = (size: LucideProps['size']): LucideProps['size'] =>
  typeof size === 'number' ? size * TABLER_SCALE : `calc(${size ?? '1em'} * ${TABLER_SCALE})`

const svgBase = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const
}

/** List — four rows, each a stroked circle bullet + a line (the default List type glyph). */
export const ListRounded = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <circle cx="4.5" cy="4.5" r="1.6" />
    <line x1="9" y1="4.5" x2="20" y2="4.5" />
    <circle cx="4.5" cy="9.5" r="1.6" />
    <line x1="9" y1="9.5" x2="20" y2="9.5" />
    <circle cx="4.5" cy="14.5" r="1.6" />
    <line x1="9" y1="14.5" x2="20" y2="14.5" />
    <circle cx="4.5" cy="19.5" r="1.6" />
    <line x1="9" y1="19.5" x2="20" y2="19.5" />
  </svg>
)) as unknown as LucideIcon

/** Cards — two columns of stretch-horizontal bars (three rows), a bar stack read wider-than-tall. */
export const CardsGrid = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <rect x="2.8" y="3.1" width="7.5" height="4.6" rx="1.4" />
    <rect x="13.7" y="3.1" width="7.5" height="4.6" rx="1.4" />
    <rect x="2.8" y="9.7" width="7.5" height="4.6" rx="1.4" />
    <rect x="13.7" y="9.7" width="7.5" height="4.6" rx="1.4" />
    <rect x="2.8" y="16.3" width="7.5" height="4.6" rx="1.4" />
    <rect x="13.7" y="16.3" width="7.5" height="4.6" rx="1.4" />
  </svg>
)) as unknown as LucideIcon

/** Tabler's progress-check (the Status type glyph), scaled up to sit at Lucide's visual size. */
const TablerProgressCheck = IconProgressCheck as unknown as LucideIcon
export const ProgressCheck = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, ...rest }, ref) => (
  <TablerProgressCheck ref={ref} size={scaleTabler(size)} {...rest} />
)) as unknown as LucideIcon
