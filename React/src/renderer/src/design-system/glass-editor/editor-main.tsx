import React from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/inter'
import '@renderer/design-system/tokens'
import '../showcase/showcase.css'
import { GlassEditor } from './GlassEditor'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <GlassEditor />
  </React.StrictMode>
)
