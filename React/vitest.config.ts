import { resolve } from 'path'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'

export default defineConfig({
  // react + vanilla-extract let component tests (*.test.tsx, per-file jsdom env) mount the real
  // editor/design-system chain; the bulk of the suite stays node-env logic tests.
  plugins: [react(), vanillaExtractPlugin()],
  test: {
    environment: 'node',
    include: ['src/**/*.test.ts', 'src/**/*.test.tsx']
  },
  resolve: {
    alias: {
      '@shared': resolve('src/shared'),
      '@renderer': resolve('src/renderer/src')
    }
  }
})
