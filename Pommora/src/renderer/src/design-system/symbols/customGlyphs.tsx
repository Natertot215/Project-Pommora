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

/** List — a solid left rail bar + four lines beside it, sized to the table/gallery glyph height. */
export const ListRounded = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} {...svgBase} {...rest}>
    <rect x="3.6" y="3.1" width="2.4" height="17.8" rx="1.2" fill="currentColor" stroke="none" />
    <line x1="9" y1="5.1" x2="20" y2="5.1" />
    <line x1="9" y1="9.7" x2="20" y2="9.7" />
    <line x1="9" y1="14.3" x2="20" y2="14.3" />
    <line x1="9" y1="18.9" x2="20" y2="18.9" />
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


// ── SF Symbols (phranck/sf-symbols-lib, monochrome) — fill-based glyphs, boxed so they sit
// at Lucide's visual coverage (~80% of the box). SF_BOX is the Nathan-tunable seat.
const SF_LOCK_BOX = 31.5 // glyph is 17.5×25.2051; 25.2/31.5 ≈ 80% coverage, Lucide-level

/** SF Symbols `lock` — THE lock glyph (Nathan's pick over Lucide's). */
export const SFLock = forwardRef<SVGSVGElement, LucideProps>(({ size = 24, color, ...rest }, ref) => (
  <svg ref={ref} width={size} height={size} viewBox={`0 0 ${SF_LOCK_BOX} ${SF_LOCK_BOX}`} fill="none" {...rest}>
    <g transform={`translate(${(SF_LOCK_BOX - 17.5) / 2} ${(SF_LOCK_BOX - 25.2051) / 2})`}>
      <path
        d="M2.73438 24.541L14.4043 24.541C16.1523 24.541 17.1387 23.5352 17.1387 21.6602L17.1387 12.7734C17.1387 10.8984 16.1523 9.89258 14.4043 9.89258L2.73438 9.89258C0.976562 9.89258 0 10.8984 0 12.7734L0 21.6602C0 23.5352 0.976562 24.541 2.73438 24.541ZM2.77344 22.9102C2.13867 22.9102 1.73828 22.4805 1.73828 21.7676L1.73828 12.6562C1.73828 11.9434 2.13867 11.5234 2.77344 11.5234L14.375 11.5234C15.0098 11.5234 15.3906 11.9434 15.3906 12.6562L15.3906 21.7676C15.3906 22.4805 15.0098 22.9102 14.375 22.9102ZM2.23633 10.7129L3.95508 10.7129L3.95508 6.72852C3.95508 3.47656 6.01562 1.63086 8.56445 1.63086C11.1133 1.63086 13.1934 3.47656 13.1934 6.72852L13.1934 10.7129L14.9121 10.7129L14.9121 6.92383C14.9121 2.38281 11.9434 0 8.56445 0C5.19531 0 2.23633 2.38281 2.23633 6.92383Z"
        fill="currentColor"
        fillOpacity="0.85"
      />
    </g>
  </svg>
)) as unknown as LucideIcon
