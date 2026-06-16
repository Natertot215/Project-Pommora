import React from 'react'
import { createRoot } from 'react-dom/client'
import '@fontsource-variable/inter'
import './glass-lab.css'
import { GlassLab } from './GlassLab'

createRoot(document.getElementById('root') as HTMLElement).render(
  <React.StrictMode>
    <GlassLab />
  </React.StrictMode>
)
