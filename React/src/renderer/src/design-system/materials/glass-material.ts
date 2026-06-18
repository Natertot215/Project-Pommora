import type { CSSProperties } from 'react'

// The Pommora glass recipe — CSS frost: a clear, slightly-dimmed blur (no fill, no
// saturate) with a glassy edge — a crisp top specular, a hairline inner ring, and a
// soft light pooling at the lower rim — so the edge reads like glass, not a flat panel.
// One source for surfaces + controls; layout (size / position / radius) is the consumer's.
export const frostMaterial: CSSProperties = {
  background: 'transparent', // no fill
  backdropFilter: 'blur(6px) brightness(95%)', // no saturate
  WebkitBackdropFilter: 'blur(6px) brightness(95%)',
  border: '1px solid #FFFFFF1F',
  boxShadow: [
    'inset 0 1px 0 #FFFFFF59', // top specular — the glassy edge highlight
    'inset 0 0 0 1px #FFFFFF14', // hairline inner ring
    'inset 0 -12px 18px -12px #FFFFFF14', // soft light pooling at the lower rim
    '0 8px 26px #00000047' // drop shadow
  ].join(', ')
}
