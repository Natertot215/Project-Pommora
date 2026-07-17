import type { ConnectionColorSetting, Personalization } from '@shared/types'
import { vars } from './tokens'

// The personalization apply-map: each nexus-wide knob → its DOM effect (a CSS-var write or a
// root-class toggle). Called with the whole block on nexus open, and per-key on a live change, so
// adding a toggle is one field on Personalization plus one case here. Accent is applied separately
// (applyAccent — it drives three vars + the OS-follow), and defaultIcons is resolved per-render from
// the tree, so neither is a DOM effect here.

/** Inline [[connection]] link color: 'accent' (or unset) tracks --accent live; a solid pins it. */
function connectionColorCss(setting: ConnectionColorSetting | undefined): string {
  return !setting || setting === 'accent' ? 'var(--accent)' : vars.color.solid[setting]
}

/** Apply one personalization key to `:root` — the apply-map's single row per knob. */
export function applyPersonalizationKey<K extends keyof Personalization>(
  key: K,
  value: Personalization[K],
): void {
  if (typeof document === 'undefined') return
  const el = document.documentElement
  switch (key) {
    case 'connectionColor':
      el.style.setProperty(
        '--connection',
        connectionColorCss(value as ConnectionColorSetting | undefined),
      )
      return
    case 'hideChevrons':
      el.classList.toggle('hide-chevrons', value === true)
      return
    case 'outlinerLines':
      el.classList.toggle('outliner-lines', value === true)
      return
    default: // accent → applyAccent; defaultIcons → resolved per-render — no DOM effect here.
      return
  }
}

/** Apply the whole personalization block — on nexus open. */
export function applyPersonalization(p: Personalization): void {
  applyPersonalizationKey('connectionColor', p.connectionColor)
  applyPersonalizationKey('hideChevrons', p.hideChevrons)
  applyPersonalizationKey('outlinerLines', p.outlinerLines)
}
