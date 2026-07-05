import { useId, useMemo, type CSSProperties } from 'react'

// Pommora's glass is Apple's "Liquid Glass" recipe, not frost: an edge-shaped bevel
// that bends the backdrop hard at the rim and stays flat (clear) in the centre, plus
// light blur, a specular rim, and subtle chromatic aberration. Chromium-native
// (SVG feImage + feDisplacementMap as a backdrop-filter); the app runs Chromium.

const FILL: CSSProperties = { position: 'absolute', inset: 0, pointerEvents: 'none' }

function hexA(hex6: string, pct: number): string {
  const a = Math.round((Math.max(0, Math.min(100, pct)) / 100) * 255)
  return hex6 + a.toString(16).padStart(2, '0').toUpperCase()
}

// Bake the convex-lens normal map once: R/G encode the inward surface normal × slope
// (128 = no displacement), steep at the rim and zero past the bevel. Strength is the
// live feDisplacementMap `scale`, so the map only depends on shape (size + radius + bevel).
function makeBevelMap(w: number, h: number, radius: number, bevel: number): string {
  const c = document.createElement('canvas')
  c.width = Math.max(1, Math.round(w))
  c.height = Math.max(1, Math.round(h))
  const ctx = c.getContext('2d')
  if (!ctx) return ''
  const img = ctx.createImageData(c.width, c.height)
  const d = img.data
  const r = Math.min(radius, c.width / 2, c.height / 2)
  const sdf = (px: number, py: number): number => {
    const qx = Math.abs(px - c.width / 2) - (c.width / 2 - r)
    const qy = Math.abs(py - c.height / 2) - (c.height / 2 - r)
    const out = Math.hypot(Math.max(qx, 0), Math.max(qy, 0))
    const ins = Math.min(Math.max(qx, qy), 0)
    return -(out + ins - r)
  }
  for (let y = 0; y < c.height; y++) {
    for (let x = 0; x < c.width; x++) {
      const dist = sdf(x, y)
      let nx = 0
      let ny = 0
      if (dist > 0 && dist < bevel) {
        const t = dist / bevel
        const slope = Math.pow(1 - t, 1.6)
        const gx = sdf(x + 1, y) - sdf(x - 1, y)
        const gy = sdf(x, y + 1) - sdf(x, y - 1)
        const len = Math.hypot(gx, gy) || 1
        nx = (gx / len) * slope
        ny = (gy / len) * slope
      }
      const i = (y * c.width + x) * 4
      d[i] = Math.max(0, Math.min(255, 128 + nx * 127))
      d[i + 1] = Math.max(0, Math.min(255, 128 + ny * 127))
      d[i + 2] = 128
      d[i + 3] = 255
    }
  }
  ctx.putImageData(img, 0, 0)
  return c.toDataURL()
}

export type EdgeLensProps = {
  width?: number
  height?: number
  scale: number
  bevel: number
  blur: number
  saturate: number
  aberration: number
  radius: number
  specular: number
}

export function EdgeLensGlass({
  width = 240,
  height = 148,
  scale,
  bevel,
  blur,
  saturate,
  aberration,
  radius,
  specular
}: EdgeLensProps): React.JSX.Element {
  const map = useMemo(() => makeBevelMap(width, height, radius, bevel), [width, height, radius, bevel])
  const fid = 'el' + useId().replace(/:/g, '')
  const bf = `blur(${blur}px) saturate(${saturate}%) url(#${fid})`
  const chan = (rgb: 'r' | 'g' | 'b'): string =>
    rgb === 'r'
      ? '1 0 0 0 0  0 0 0 0 0  0 0 0 0 0  0 0 0 1 0'
      : rgb === 'g'
        ? '0 0 0 0 0  0 1 0 0 0  0 0 0 0 0  0 0 0 1 0'
        : '0 0 0 0 0  0 0 0 0 0  0 0 1 0 0  0 0 0 1 0'
  return (
    <>
      <svg width="0" height="0" style={{ position: 'absolute' }} aria-hidden>
        <filter id={fid} x="0%" y="0%" width="100%" height="100%" colorInterpolationFilters="sRGB">
          <feImage href={map} x="0" y="0" width={width} height={height} preserveAspectRatio="none" result="map" />
          {aberration > 0 ? (
            <>
              <feDisplacementMap in="SourceGraphic" in2="map" scale={scale + aberration} xChannelSelector="R" yChannelSelector="G" result="dr" />
              <feColorMatrix in="dr" values={chan('r')} result="cr" />
              <feDisplacementMap in="SourceGraphic" in2="map" scale={scale} xChannelSelector="R" yChannelSelector="G" result="dg" />
              <feColorMatrix in="dg" values={chan('g')} result="cg" />
              <feDisplacementMap in="SourceGraphic" in2="map" scale={scale - aberration} xChannelSelector="R" yChannelSelector="G" result="db" />
              <feColorMatrix in="db" values={chan('b')} result="cb" />
              <feBlend in="cr" in2="cg" mode="screen" result="rg" />
              <feBlend in="rg" in2="cb" mode="screen" />
            </>
          ) : (
            <feDisplacementMap in="SourceGraphic" in2="map" scale={scale} xChannelSelector="R" yChannelSelector="G" />
          )}
        </filter>
      </svg>
      <div
        style={{
          ...FILL,
          borderRadius: radius,
          background: 'transparent',
          border: `1px solid ${hexA('#FFFFFF', 20)}`,
          backdropFilter: bf,
          WebkitBackdropFilter: bf,
          boxShadow: `inset 0 1px 0 ${hexA('#FFFFFF', Math.round(specular * 100))}, inset 0 0 0 1px #FFFFFF10, 0 10px 30px #00000055`
        }}
      />
    </>
  )
}
