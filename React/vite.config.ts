import { resolve } from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'

// Standalone Vite server/build for the design-system showcase — a plain browser
// site decoupled from Electron. Three pages: landing (index), the design system,
// and the glass lab. Dev: `npm run showcase`. Static build: `npm run build:showcase`.
export default defineConfig({
  plugins: [react(), vanillaExtractPlugin()],
  resolve: {
    alias: {
      '@renderer': resolve('src/renderer/src'),
      '@shared': resolve('src/shared')
    }
  },
  build: {
    rollupOptions: {
      input: {
        index: resolve('index.html'),
        'design-system': resolve('design-system.html'),
        'glass-lab': resolve('glass-lab.html')
      }
    }
  }
})
