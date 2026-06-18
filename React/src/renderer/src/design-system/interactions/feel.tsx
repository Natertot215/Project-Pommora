import { createContext, useContext, type ReactNode } from 'react'

// The shared displacement feel — dnd-kit sorts via a CSS transition, so "smooth, not snappy"
// is a duration + easing. One source, tuned live; also exposed to CSS (expand/caret) via vars.
export type Feel = { duration: number; easing: string }

export const EASINGS: Record<string, string> = {
  'Ease out': 'cubic-bezier(0.22, 1, 0.36, 1)',
  Standard: 'cubic-bezier(0.25, 0.1, 0.25, 1)',
  Linear: 'linear'
}
export const FEEL_PRESETS: Record<string, Feel> = {
  Glide: { duration: 340, easing: EASINGS['Ease out'] },
  Smooth: { duration: 230, easing: EASINGS['Ease out'] },
  Snappy: { duration: 130, easing: EASINGS.Standard }
}
export const DEFAULT_FEEL = FEEL_PRESETS.Smooth

const FeelContext = createContext<Feel>(DEFAULT_FEEL)
export function FeelProvider({ feel, children }: { feel: Feel; children: ReactNode }): React.JSX.Element {
  return <FeelContext.Provider value={feel}>{children}</FeelContext.Provider>
}
export function useFeel(): Feel {
  return useContext(FeelContext)
}
