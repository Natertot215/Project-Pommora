import React from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/inter'
import '@renderer/design-system/tokens' // inject color + typography + chip CSS
import './showcase.css'
import { Showcase } from './Showcase'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <Showcase />
  </React.StrictMode>,
)
