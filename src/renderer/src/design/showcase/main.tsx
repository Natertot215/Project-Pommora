import React from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/inter'
import '@renderer/design/tokens' // inject color + typography + chip CSS
import './showcase.css'
import { DesignSystem } from './DesignSystem'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <DesignSystem />
  </React.StrictMode>
)
