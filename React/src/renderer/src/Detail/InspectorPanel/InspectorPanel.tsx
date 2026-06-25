import { GlassWindow } from '@renderer/design-system/materials'
import './inspector-panel.css'

/**
 * InspectorPanel — the trailing window pane (Swift's `.inspector`), the right-side
 * twin of the Sidebar: a full-height GlassWindow seam aligned with the sidebar that,
 * when open, reserves space and pushes/resizes the content (driven by the shell's
 * `.inspector-open` class). Empty scaffold for now — selection-aware content
 * (frontmatter → properties → page info) mounts in `.inspector-body`.
 */
export function InspectorPanel({ open }: { open: boolean }): React.JSX.Element {
  return (
    <GlassWindow className="inspector-glass" aria-hidden={!open}>
      <div className="inspector-head">Inspector</div>
      <div className="inspector-body" />
    </GlassWindow>
  )
}
