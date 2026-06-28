import { resolve } from 'path'
import { fileURLToPath } from 'url'
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import { vanillaExtractPlugin } from '@vanilla-extract/vite-plugin'

// Resolve aliases against this config's own directory, not the process CWD — so the suite runs
// correctly regardless of where vitest is invoked from.
const __dirname = resolve(fileURLToPath(import.meta.url), '..')

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
      '@shared': resolve(__dirname, 'src/shared'),
      '@renderer': resolve(__dirname, 'src/renderer/src')
    }
  }
})
