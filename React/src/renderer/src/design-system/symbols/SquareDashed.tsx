import type { ComponentPropsWithoutRef } from 'react'

/** Pommora's own dashed-square glyph (Nathan: no library counterpart fits) — slot-shaped like a
 *  library icon: 24 grid, currentColor, size/strokeWidth props. Dash rhythm tuned so the pattern
 *  loops the rounded perimeter without a seam; adjust strokeDasharray to retune. */
export function SquareDashed({
  size = 24,
  strokeWidth = 2,
  ...rest
}: {
  size?: number | string
  strokeWidth?: number | string
} & Omit<ComponentPropsWithoutRef<'svg'>, 'stroke' | 'strokeWidth'>): React.JSX.Element {
  return (
    <svg
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 24 24"
      width={size}
      height={size}
      fill="none"
      stroke="currentColor"
      strokeWidth={strokeWidth}
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
      {...rest}
    >
      <rect x="4" y="4" width="16" height="16" rx="2.5" strokeDasharray="3.2 2.8" strokeDashoffset="1.6" />
    </svg>
  )
}
