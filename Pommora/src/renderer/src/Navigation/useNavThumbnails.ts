import { useEffect } from 'react'
import { useSession } from '../store'
import { navKey } from './navRecents'

// The `.content-pane` fills the whole window; the sidebar, toolbar, and inspector are floating overlays
// painted on top of it. Carve them off so the thumbnail is page content alone: start right of the sidebar,
// below the toolbar strip, and left of the inspector. Each overlay is skipped when it's parked off-screen
// (its edge falls outside the pane), so a hidden sidebar / closed inspector contributes nothing.
function contentRect(pane: Element): { x: number; y: number; width: number; height: number } {
  const p = pane.getBoundingClientRect()
  let { left, top, right, bottom } = p
  const sidebar = document.querySelector('.surface-glass')?.getBoundingClientRect()
  if (sidebar && sidebar.right > left && sidebar.right < right) left = sidebar.right
  const toolbar = document.querySelector('.app-toolbar')?.getBoundingClientRect()
  if (toolbar && toolbar.bottom > top && toolbar.bottom < bottom) top = toolbar.bottom
  const inspector = document.querySelector('.inspector-glass')?.getBoundingClientRect()
  if (inspector && inspector.left > left && inspector.left < right) right = inspector.left
  return { x: left, y: top, width: right - left, height: bottom - top }
}

// Capture-on-open: after the detail pane settles on a new entity, snapshot its content rect as a gallery
// thumbnail. Fires once per settled selection (debounced + fonts-ready + double-rAF, off the interaction
// path); pages wait for `ready`, other kinds render straight from the tree. A successful capture bumps the
// thumb version so the card image reloads the overwritten file. Skips error states.
export function useNavThumbnails(): void {
  const selection = useSession((s) => s.selection)
  const pageStatus = useSession((s) => s.pageStatus)
  const bumpThumb = useSession((s) => s.bumpThumb)

  useEffect(() => {
    if (selection.kind === 'none') return
    if (selection.kind === 'page' && pageStatus !== 'ready') return
    let cancelled = false
    const timer = setTimeout(() => {
      void (async () => {
        const pane = document.querySelector('.content-pane')
        if (!pane || cancelled) return
        await document.fonts?.ready
        await new Promise<void>((r) => requestAnimationFrame(() => requestAnimationFrame(() => r())))
        // Never capture with the NavPane overlay up — it would bake into the (synced) thumbnail.
        if (cancelled || useSession.getState().navOpen) return
        const rect = contentRect(pane)
        const key = navKey(selection)
        const res = await window.nexus.capture.thumbnail(key, rect, window.devicePixelRatio)
        if (!cancelled && res.ok) bumpThumb(key)
      })()
    }, 250)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [selection, pageStatus, bumpThumb])
}
