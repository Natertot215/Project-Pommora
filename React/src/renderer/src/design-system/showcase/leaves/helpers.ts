import { useEffect, useRef, useState, type RefObject } from 'react'

// Shared leaf helpers — label formatting + reading rendered values back off the DOM
// so the showcase shows the real computed token value and can't drift from it.

/** camelCase / kebab-case key -> "Title Case" label. */
export function humanize(key: string): string {
  return key
    .replace(/[-_]/g, ' ')
    .replace(/([a-z])([A-Z])/g, '$1 $2')
    .replace(/([a-zA-Z])(\d)/g, '$1 $2')
    .replace(/\b\w/g, (c) => c.toUpperCase())
}

/** Read back a rendered color → "#RRGGBB", or "#RRGGBB · NN%" when it carries an
 *  alpha (the opacity tokens), so the gallery shows base + percent, never an opaque
 *  A## byte. */
export function formatColor(rgb: string): string {
  const m = rgb.match(/\d+(\.\d+)?/g)
  if (!m || m.length < 3) return rgb
  const ch = (n: string): string => Math.round(Number(n)).toString(16).padStart(2, '0')
  const hex = ('#' + m.slice(0, 3).map(ch).join('')).toUpperCase()
  const a = m.length >= 4 ? Number(m[3]) : 1
  return a < 1 ? `${hex} · ${Math.round(a * 100)}%` : hex
}

/** Read a value back from a rendered node on mount — so a swatch/type sample shows
 *  its real computed value rather than a restated literal. */
export function useComputedStyleText<T extends HTMLElement>(
  read: (cs: CSSStyleDeclaration) => string
): [RefObject<T | null>, string] {
  const ref = useRef<T>(null)
  const [value, setValue] = useState('')
  useEffect(() => {
    if (ref.current) setValue(read(getComputedStyle(ref.current)))
  }, [read])
  return [ref, value]
}
