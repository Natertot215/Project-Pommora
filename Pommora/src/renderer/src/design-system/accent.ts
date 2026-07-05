import { DEFAULT_ACCENT, type AccentSetting } from '@shared/types'
import { vars } from './tokens'

/**
 * Resolve an accent setting to a CSS value for `--accent`. A spectrum solid maps
 * to its token's `var(--…)` reference (so the accent tracks the design system);
 * `system` maps to the OS accent (read per-runtime — Electron or CSS AccentColor),
 * falling back to the default spectrum solid when the OS value is unavailable.
 * There is no separate "accent" color — it's always one of the spectrum solids.
 */
export function accentValue(setting: AccentSetting, systemColor: string | null): string {
  if (setting === 'system') return systemColor ?? vars.color.solid[DEFAULT_ACCENT]
  return vars.color.solid[setting]
}

/**
 * Apply the accent to `:root`. `--accent-fill` / `--accent-text` are color-mix
 * derivations of `--accent` (theme-vars.css.ts), so setting this one property
 * recolors every accented surface. No-op without a DOM (e.g. node tests).
 */
export function applyAccent(setting: AccentSetting, systemColor: string | null): void {
  if (typeof document === 'undefined') return
  document.documentElement.style.setProperty('--accent', accentValue(setting, systemColor))
}

/**
 * Reflect the OS accent on `--system-accent`, ALWAYS — independent of the Pommora
 * `--accent` setting. External `[text](url)` links bind to this (internal connections
 * bind to `--accent`). Falls back to the CSS `AccentColor` probe, then the default
 * spectrum solid, when no OS value is supplied. No-op without a DOM.
 */
export function applySystemAccent(systemColor: string | null): void {
  if (typeof document === 'undefined') return
  const value = systemColor ?? readCssAccentColor() ?? vars.color.solid[DEFAULT_ACCENT]
  document.documentElement.style.setProperty('--system-accent', value)
}

/**
 * Read the OS accent in a pure-web context (no Electron) via the CSS `AccentColor`
 * system color: paint it on an off-screen probe and read back the computed value.
 * Returns an `rgb(…)` string, or null if the browser doesn't resolve it.
 */
export function readCssAccentColor(): string | null {
  if (typeof document === 'undefined') return null
  const probe = document.createElement('span')
  probe.style.color = 'AccentColor'
  document.body.appendChild(probe)
  const rgb = getComputedStyle(probe).color
  probe.remove()
  return rgb || null
}
