import { resolve } from 'path'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'

// Standalone Vite build of the APP renderer — the mobile/web build target. Mirrors
// electron.vite.config.ts's renderer block; the desktop electron-vite build is untouched
// (this config only loads via `vite -c vite.config.app.ts`). Entry: src/renderer/index.html.
export default defineConfig({
  root: resolve('src/renderer'),
  base: './',
  plugins: [react(), vanillaExtractPlugin()],
  resolve: {
    alias: {
      '@shared': resolve('src/shared'),
      '@renderer': resolve('src/renderer/src'),
    },
  },
  build: { outDir: resolve('dist-app'), emptyOutDir: true },
})
