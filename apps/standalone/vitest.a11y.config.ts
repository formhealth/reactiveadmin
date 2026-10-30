import path from 'node:path'
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { playwright } from '@vitest/browser-playwright'
import { defineConfig } from 'vitest/config'
import { a11yReport } from './.storybook/a11yReport'

// Runs every story in a real browser and fails on serious/critical axe violations. See .storybook/vitest.setup.ts.
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    // `a11y-skip` marks stories whose play functions don't run reliably under the a11y runner (iframes served by msw, toast timing).
    storybookTest({ configDir: path.resolve(import.meta.dirname, '.storybook'), tags: { skip: ['a11y-skip'] } }),
  ],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src') } },
  test: {
    name: 'a11y',
    retry: 1, // a story's first load can race msw's service worker
    setupFiles: ['./.storybook/vitest.setup.ts'],
    browser: {
      enabled: true,
      headless: true,
      provider: playwright(),
      instances: [{ browser: 'chromium' }],
      commands: { a11yReport },
    },
  },
})
