// Runs the axe story suite once per theme (A11Y_THEMES narrows them); exits non-zero if any run fails.
import { spawnSync } from 'node:child_process'

const themes = process.env.A11Y_THEMES?.split(',') ?? ['light', 'dark']
const failed = themes.filter(
  (theme) =>
    spawnSync('pnpm', ['exec', 'vitest', 'run', '--config', 'vitest.a11y.config.ts', ...process.argv.slice(2)], {
      stdio: 'inherit',
      env: { ...process.env, TZ: 'UTC', VITE_A11Y_THEME: theme },
    }).status !== 0,
)
if (failed.length) console.error(`a11y failed in: ${failed.join(', ')}`)
process.exit(failed.length ? 1 : 0)
