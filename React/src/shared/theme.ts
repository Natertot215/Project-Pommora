// Single source for the app substrate colour (the window background). The main
// process can't read renderer CSS vars or vanilla-extract tokens, so this plain
// constant is the seam both sides share:
//   main/index.ts → BrowserWindow backgroundColor: WINDOW_BG
//   color.css.ts  → background.window token = WINDOW_BG → --bg-window bridge var
//   styles.css    → --main-bg: var(--bg-window)
// Change it here and all three follow.
export const WINDOW_BG = '#1B1B1D'
