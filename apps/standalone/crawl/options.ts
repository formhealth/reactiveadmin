import { existsSync } from 'node:fs'
import { homedir } from 'node:os'
import path from 'node:path'
import { parseArgs } from 'node:util'
import { SCREEN_KINDS, type ScreenKind } from './plan.ts'

export type Options = {
  baseUrl: string
  apiPrefix: string
  resources?: string[]
  kinds: ScreenKind[]
  limit: number
  concurrency: number
  headed: boolean
  timeoutMs: number
  theme: 'light' | 'dark'
  axe: boolean
  login?: string
  allowlist?: string
  outDir: string
  screenshots: boolean
  updateBaselines: boolean
  baselineDir: string
  mask: string[]
  diffThreshold: number
}

export const HELP = `Usage: pnpm crawl [options]

Visits every screen of the manifest in the React app and checks each for errors, console noise, failed API calls and axe violations.

  --base-url=URL        App to crawl (env CRAWL_BASE_URL, default http://localhost:5174)
  --api-prefix=PATH     Where the manifest lives (default /api/admin)
  --resources=a,b       Only these resources' screens (no home, groups or pages)
  --screens=index,show  Only these kinds: ${SCREEN_KINDS.join(', ')}
  --limit=N             Records whose show page is visited per resource (default 2); edit uses the first
  --concurrency=N       Parallel pages (default 3)
  --timeout=MS          Per-screen wait for a first meaningful render (default 20000)
  --theme=light|dark    Color scheme (default light)
  --headed              Show the browser
  --no-axe              Skip accessibility checks
  --login=FILE          Login hook (env CRAWL_LOGIN; default ./crawl.login.ts when present)
  --allowlist=FILE      Extra allowed API responses, console messages and axe rules (env CRAWL_ALLOWLIST; default ./crawl.allowlist.json when present)
  --out=DIR             Report directory (default ./crawl-report)
  --screenshots         Compare against baselines, creating missing ones (off by default)
  --update-baselines    With --screenshots: overwrite baselines instead of comparing
  --baseline-dir=DIR    Baselines (env CRAWL_BASELINE_DIR, default ~/.cache/reactiveadmin-crawl/baselines)
  --mask=SEL,SEL        Extra selectors to mask in screenshots
  --diff-threshold=R    Fraction of pixels allowed to differ (default 0.001)

Auth: env CRAWL_COOKIE ("name=value; other=value") and/or a login hook. See docs/guide/testing.md.`

const list = (value: string | undefined) => value?.split(',').map((s) => s.trim()).filter(Boolean)
const number = (name: string, value: string | undefined, fallback: number) => {
  if (value === undefined) return fallback
  const n = Number(value)
  if (!Number.isFinite(n) || n < 0) throw new Error(`--${name} must be a non-negative number`)
  return n
}
const present = (file: string) => (existsSync(file) ? file : undefined)

export function parseOptions(argv: string[], env: NodeJS.ProcessEnv = process.env): Options | 'help' {
  const { values } = parseArgs({
    args: argv,
    options: {
      'base-url': { type: 'string' },
      'api-prefix': { type: 'string' },
      resources: { type: 'string' },
      screens: { type: 'string' },
      limit: { type: 'string' },
      concurrency: { type: 'string' },
      timeout: { type: 'string' },
      theme: { type: 'string' },
      headed: { type: 'boolean' },
      'no-axe': { type: 'boolean' },
      login: { type: 'string' },
      allowlist: { type: 'string' },
      out: { type: 'string' },
      screenshots: { type: 'boolean' },
      'update-baselines': { type: 'boolean' },
      'baseline-dir': { type: 'string' },
      mask: { type: 'string' },
      'diff-threshold': { type: 'string' },
      help: { type: 'boolean', short: 'h' },
    },
  })
  if (values.help) return 'help'

  const kinds = (list(values.screens) ?? SCREEN_KINDS) as ScreenKind[]
  const unknown = kinds.filter((k) => !SCREEN_KINDS.includes(k))
  if (unknown.length) throw new Error(`unknown screen kind: ${unknown.join(', ')}`)
  const theme = values.theme ?? 'light'
  if (theme !== 'light' && theme !== 'dark') throw new Error('--theme must be light or dark')

  const login = values.login ?? env.CRAWL_LOGIN ?? present('crawl.login.ts')
  return {
    baseUrl: (values['base-url'] ?? env.CRAWL_BASE_URL ?? 'http://localhost:5174').replace(/\/$/, ''),
    apiPrefix: values['api-prefix'] ?? '/api/admin',
    resources: list(values.resources),
    kinds,
    limit: number('limit', values.limit, 2),
    concurrency: Math.max(1, number('concurrency', values.concurrency, 3)),
    headed: !!values.headed,
    timeoutMs: number('timeout', values.timeout, 20_000),
    theme,
    axe: !values['no-axe'],
    login: login && path.resolve(login),
    allowlist: values.allowlist ?? env.CRAWL_ALLOWLIST ?? present('crawl.allowlist.json'),
    outDir: path.resolve(values.out ?? 'crawl-report'),
    screenshots: !!values.screenshots || !!values['update-baselines'],
    updateBaselines: !!values['update-baselines'],
    baselineDir: path.resolve(values['baseline-dir'] ?? env.CRAWL_BASELINE_DIR ?? path.join(homedir(), '.cache/reactiveadmin-crawl/baselines')),
    mask: list(values.mask) ?? [],
    diffThreshold: number('diff-threshold', values['diff-threshold'], 0.001),
  }
}
