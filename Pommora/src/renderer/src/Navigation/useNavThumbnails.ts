import { useEffect } from 'react'
import { useSession } from '../store'
import { navKey } from './navRecents'

// Capture-on-open: after the detail pane settles on a new entity, snapshot its `.content-pane` rect as
// a gallery thumbnail. Fires once per settled selection (debounced + fonts-ready + double-rAF, off the
// interaction path); pages wait for `ready`, other kinds render straight from the tree. A successful
// capture bumps the thumb version so the card image reloads the overwritten file. Skips error states.
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
        const rect = pane.getBoundingClientRect()
        const key = navKey(selection)
        const res = await window.nexus.capture.thumbnail(key, { x: rect.x, y: rect.y, width: rect.width, height: rect.height })
        if (!cancelled && res.ok) bumpThumb(key)
      })()
    }, 250)
    return () => {
      cancelled = true
      clearTimeout(timer)
    }
  }, [selection, pageStatus, bumpThumb])
}
