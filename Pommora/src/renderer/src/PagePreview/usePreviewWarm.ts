import { useCallback, useEffect, useMemo, type RefObject } from 'react'
import type { WarmSeam } from '@renderer/MarkdownPM'
import { useSession } from '../store'
import { capturePreviewWarm, readPreviewWarm, type PreviewWarmEntry } from './previewWarm'

// The preview warm seam (H-8), shared by BOTH flavors' windows: editor state keys on the active
// preview-tab id; the BODY's scroll (the preview's one scroller) is captured live and restored
// after CM6's async height build. Captures are LIVENESS-GATED — the editor's unmount capture
// trails the store's drop, and ungated it would re-insert one ghost editorState per close.

export function usePreviewWarm(
  scrollerRef: RefObject<HTMLElement | null>,
  activePath: string | undefined,
): WarmSeam | undefined {
  const activeTabId = useSession((s) => s.preview?.activeTabId)

  const captureIfLive = useCallback((tabId: string, entry: PreviewWarmEntry): void => {
    const p = useSession.getState().preview
    if (p?.tabs.some((t) => t.id === tabId)) capturePreviewWarm(tabId, entry)
  }, [])

  const seam = useMemo<WarmSeam | undefined>(
    () =>
      activeTabId
        ? {
            restore: () => readPreviewWarm(activeTabId),
            capture: (state) => captureIfLive(activeTabId, state),
          }
        : undefined,
    [activeTabId, captureIfLive],
  )

  // A passive listener records the active tab's body scroll as it happens — never a switch-time
  // read of a maybe-clamped value.
  useEffect(() => {
    const el = scrollerRef.current
    if (!el || !activeTabId) return
    const onScroll = (): void => captureIfLive(activeTabId, { bodyScrollTop: el.scrollTop })
    el.addEventListener('scroll', onScroll, { passive: true })
    return () => el.removeEventListener('scroll', onScroll)
  }, [activeTabId, captureIfLive, scrollerRef])

  // CM6 builds the embed's height ASYNC after mount — an immediate set clamps to 0 (and the
  // listener records the clamp as truth). Double-rAF lands after its first measure/layout pass.
  useEffect(() => {
    if (!activeTabId || activePath === undefined) return
    const saved = readPreviewWarm(activeTabId)?.bodyScrollTop ?? 0
    let inner = 0
    const outer = requestAnimationFrame(() => {
      inner = requestAnimationFrame(() => {
        if (scrollerRef.current) scrollerRef.current.scrollTop = saved
      })
    })
    return () => {
      cancelAnimationFrame(outer)
      cancelAnimationFrame(inner)
    }
    // activePath IS the switch signal — the restore fires per content swap, not per tab-id.
    // biome-ignore lint/correctness/useExhaustiveDependencies: see above
  }, [activePath])

  return seam
}
