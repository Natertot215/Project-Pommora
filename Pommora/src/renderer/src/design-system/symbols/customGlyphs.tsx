// The custom registry glyphs (List's rounded-circle list, Cards' 2×3 grid) plus the wide Table — the
// Lucide Table rotated 90° so it reads wider-than-tall. Registry-conforming forwardRef svgs at Lucide's
// 1.75 stroke weight so they sit evenly beside the Lucide set.
import { forwardRef } from 'react'
import { Table, type LucideIcon, type LucideProps } from 'lucide-react'

/** The table glyph everywhere (view icon, rows, button, grid tile) — Lucide Table rotated 90° wide. */
export const TableWide = forwardRef<SVGSVGElement, LucideProps>(({ style, ...rest }, ref) => (
  <Table ref={ref} style={{ ...(style as object), transform: 'rotate(90deg)' }} {...rest} />
)) as unknown as LucideIcon

const svgBase = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 1.75,
  strokeLinecap: 'round' as const,
  strokeLinejoin: 'round' as const
}

/** List — three rows, each a stroked circle bullet + a line (the default List type glyph). */
export const ListRounded = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <circle cx="4.5" cy="6" r="1.6" />
    <line x1="9" y1="6" x2="20" y2="6" />
    <circle cx="4.5" cy="12" r="1.6" />
    <line x1="9" y1="12" x2="20" y2="12" />
    <circle cx="4.5" cy="18" r="1.6" />
    <line x1="9" y1="18" x2="20" y2="18" />
  </svg>
)) as unknown as LucideIcon

/** Cards — a 2×3 grid of rounded rects (a flatter card grid). */
export const CardsGrid = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <rect x="3.5" y="4" width="7.5" height="4.6" rx="1.4" />
    <rect x="13" y="4" width="7.5" height="4.6" rx="1.4" />
    <rect x="3.5" y="9.7" width="7.5" height="4.6" rx="1.4" />
    <rect x="13" y="9.7" width="7.5" height="4.6" rx="1.4" />
    <rect x="3.5" y="15.4" width="7.5" height="4.6" rx="1.4" />
    <rect x="13" y="15.4" width="7.5" height="4.6" rx="1.4" />
  </svg>
)) as unknown as LucideIcon
