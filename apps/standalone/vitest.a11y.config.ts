import path from 'node:path'
import { storybookTest } from '@storybook/addon-vitest/vitest-plugin'
import tailwindcss from '@tailwindcss/vite'
import react from '@vitejs/plugin-react'
import { playwright } from '@vitest/browser-playwright'
import { defineConfig } from 'vitest/config'
import { a11yReport } from './.storybook/a11yReport'

// Runs every story in a real browser and fails on serious/critical axe violations (VITE_SKIP_AXE=1 runs only the plays). See .storybook/vitest.setup.ts.
export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    storybookTest({ configDir: path.resolve(import.meta.dirname, '.storybook') }),
  ],
  resolve: { alias: { '@': path.resolve(import.meta.dirname, 'src') } },
  test: {
    name: 'a11y',
    retry: 1, // Node.form's select stories can flake under a full parallel run (#119)
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
