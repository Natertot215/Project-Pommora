// The custom registry glyphs (List's rounded-circle list, Cards' 2×3 grid, Gallery's 2×3 bar stack).
// Registry-conforming forwardRef svgs at Lucide's default 2 stroke weight so they sit evenly beside it.
import { forwardRef } from 'react'
import { type LucideIcon, type LucideProps } from 'lucide-react'

const svgBase = {
  viewBox: '0 0 24 24',
  fill: 'none',
  stroke: 'currentColor',
  strokeWidth: 2,
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

/** Gallery — two columns of stretch-horizontal bars (three rows), a bar stack read wider-than-tall. */
export const GalleryStack = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <rect x="3.2" y="5" width="7.6" height="2.8" rx="1.4" />
    <rect x="13.2" y="5" width="7.6" height="2.8" rx="1.4" />
    <rect x="3.2" y="10.6" width="7.6" height="2.8" rx="1.4" />
    <rect x="13.2" y="10.6" width="7.6" height="2.8" rx="1.4" />
    <rect x="3.2" y="16.2" width="7.6" height="2.8" rx="1.4" />
    <rect x="13.2" y="16.2" width="7.6" height="2.8" rx="1.4" />
  </svg>
)) as unknown as LucideIcon
