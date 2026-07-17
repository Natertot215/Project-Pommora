import { resolve } from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'

// Standalone Vite server/build for the design-system showcase — a plain browser
// site decoupled from Electron. Single page: the design system (served at `/` via
// the vercel.json rewrite). Dev: `npm run showcase`. Static build: `npm run build:showcase`.
export default defineConfig({
  plugins: [react(), vanillaExtractPlugin()],
  resolve: {
    alias: {
      '@renderer': resolve('src/renderer/src'),
      '@shared': resolve('src/shared'),
    },
  },
  build: {
    rollupOptions: {
      input: {
        'design-system': resolve('design-system.html'),
        interactions: resolve('interactions.html'),
      },
    },
  },
})
