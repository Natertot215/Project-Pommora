import { useSyncExternalStore } from 'react'
import type { GlassOptics } from '@samasante/liquid-glass'

/**
 * Live store for the control-glass optics. GlassControls reads it via
 * useControlOptics(); the homepage slider panel writes it via setControlOptic().
 * Seeded with the tuned look — when a setting feels right, paste the panel's Copy
 * output here to make it the committed default.
 */

export type OpticKnob = { key: keyof GlassOptics; label: string; min: number; max: number; step: number }

export const CONTROL_KNOBS: OpticKnob[] = [
  { key: 'strength', label: 'Strength', min: 0, max: 1, step: 0.01 },
  { key: 'depth', label: 'Depth', min: 0, max: 1, step: 0.01 },
  { key: 'curvature', label: 'Curvature', min: 0, max: 1, step: 0.01 },
  { key: 'bend', label: 'Bend', min: 0, max: 1, step: 0.01 },
  { key: 'bendWidth', label: 'Bend width', min: 0.02, max: 0.5, step: 0.01 },
  { key: 'dispersion', label: 'Dispersion', min: 0, max: 1, step: 0.01 },
  { key: 'frost', label: 'Frost', min: 0, max: 20, step: 0.5 },
  { key: 'saturate', label: 'Saturate', min: 0, max: 2, step: 0.01 },
  { key: 'brightness', label: 'Brightness', min: -1, max: 1, step: 0.01 },
  { key: 'specular', label: 'Specular', min: 0, max: 2, step: 0.01 },
  { key: 'glow', label: 'Glow', min: 0, max: 1, step: 0.01 },
  { key: 'glowSpread', label: 'Glow spread', min: 0, max: 1, step: 0.01 },
  { key: 'glowFalloff', label: 'Glow falloff', min: 0, max: 4, step: 0.05 },
  { key: 'sheen', label: 'Sheen', min: 0, max: 1, step: 0.01 },
  { key: 'sheenWidth', label: 'Sheen width', min: 0, max: 40, step: 0.5 },
  { key: 'sheenFalloff', label: 'Sheen falloff', min: 0, max: 4, step: 0.05 },
  { key: 'sheenAngle', label: 'Sheen angle', min: 0, max: 360, step: 1 },
  { key: 'splay', label: 'Splay', min: 0, max: 1, step: 0.01 },
  { key: 'mapSize', label: 'Map size', min: 64, max: 512, step: 16 }
]

let optics: Partial<GlassOptics> = {
  strength: 0.5,
  depth: 0.3,
  curvature: 0.45,
  bend: 0.25,
  bendWidth: 0.16,
  dispersion: 0.25,
  frost: 3.5,
  saturate: 1,
  brightness: -0.05,
  specular: 0.7,
  glow: 0,
  glowSpread: 0.3,
  glowFalloff: 1.5,
  sheen: 0.3,
  sheenWidth: 12,
  sheenFalloff: 1.5,
  sheenAngle: 90,
  splay: 0,
  mapSize: 256,
  clipToShape: true,
  softEdge: true,
  sheenDark: false
}

const listeners = new Set<() => void>()

export function setControlOptic(key: keyof GlassOptics, value: number): void {
  optics = { ...optics, [key]: value }
  listeners.forEach((l) => l())
}

export function useControlOptics(): Partial<GlassOptics> {
  return useSyncExternalStore(
    (cb) => {
      listeners.add(cb)
      return () => listeners.delete(cb)
    },
    () => optics
  )
}
