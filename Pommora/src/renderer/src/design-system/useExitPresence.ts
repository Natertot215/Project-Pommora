import { useEffect, useState } from 'react'

// `exitMs` must cover the slowest close animation — default 380 gives the menu Bloom (`slow` = 350ms)
// slack; the picker/autocomplete `dropdown` token (225ms) is covered by the same window.
export function useExitPresence(
  open: boolean,
  exitMs = 380,
): { mounted: boolean; closing: boolean } {
  const [mounted, setMounted] = useState(open)
  const [closing, setClosing] = useState(false)
  useEffect(() => {
    if (open) {
      setMounted(true)
      setClosing(false)
      return
    }
    if (!mounted) return
    setClosing(true)
    const t = setTimeout(() => {
      setMounted(false)
      setClosing(false)
    }, exitMs)
    return () => clearTimeout(t)
  }, [open, mounted, exitMs])
  return { mounted, closing }
}
