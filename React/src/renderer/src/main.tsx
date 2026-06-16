import React from 'react'
import { createRoot } from 'react-dom/client'
import { App } from './App'
import '@fontsource-variable/inter'
import './design-system/tokens'
import './styles.css'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>
)
