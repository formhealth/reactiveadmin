// Runs the axe story suite once per theme; exits non-zero if either run fails.
import { spawnSync } from 'node:child_process'

const failed = ['light', 'dark'].filter(
  (theme) =>
    spawnSync('pnpm', ['exec', 'vitest', 'run', '--config', 'vitest.a11y.config.ts', ...process.argv.slice(2)], {
      stdio: 'inherit',
      env: { ...process.env, TZ: 'UTC', VITE_A11Y_THEME: theme },
    }).status !== 0,
)
if (failed.length) console.error(`a11y failed in: ${failed.join(', ')}`)
process.exit(failed.length ? 1 : 0)
