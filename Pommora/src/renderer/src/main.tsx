import React from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import { initNativeCaret } from './nativeCaret'
import '@fontsource-variable/inter'
import './design-system/tokens'
import './design-system/interactions/autoscroll.css'
import './design-system/edge-fade.css'
import './styles.css'
import './Carets.css'
import './Sidebar/Sidebar.css'
import './Detail/Detail.css'
import './Detail/Banner/Banner.css'
import './Detail/Views/Table/table-tokens.css'
import './Detail/Views/Table/Table.css'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)

// One global drawn caret for every native text field (CodeMirror surfaces have their own).
initNativeCaret()

// Dev-only CDP drive seam: agents verify UI headlessly by calling store actions (never synthetic
// clicks near an editor — those risk real-Nexus writes).
if (import.meta.env.DEV) {
  void import('./store').then(({ useSession }) => {
    ;(window as unknown as { __pommora: unknown }).__pommora = useSession
  })
}
