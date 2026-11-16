import { SCREEN_KINDS, type ScreenKind } from './plan.ts'
import { timing } from './stats.ts'
import type { ScreenResult } from './visit.ts'

export const METRICS = ['p50', 'p95', 'max'] as const
export type Metric = (typeof METRICS)[number]
export type Scope = 'all' | ScreenKind
export type Budgets = Partial<Record<Scope, Partial<Record<Metric, number>>>>
export type Violation = { scope: Scope; metric: Metric; limit: number; actual: number; screens: { url: string; readyMs: number }[] }

const SCOPES: Scope[] = ['all', ...SCREEN_KINDS]
const MAX_OFFENDERS = 10

const set = (budgets: Budgets, scope: string, metric: string, value: unknown, source: string) => {
  if (!SCOPES.includes(scope as Scope)) throw new Error(`${source}: unknown screen kind "${scope}" (use ${SCOPES.join(', ')})`)
  if (!METRICS.includes(metric as Metric)) throw new Error(`${source}: unknown metric "${metric}" (use ${METRICS.join(', ')})`)
  if (typeof value !== 'number' || !Number.isFinite(value) || value <= 0) throw new Error(`${source}: ${scope}.${metric} must be a positive number of milliseconds`)
  ;(budgets[scope as Scope] ??= {})[metric as Metric] = value
}

// `p95=1500` budgets every screen; `index.p95=1200` budgets one kind.
export function parseBudgetFlags(flags: string[]): Budgets {
  const budgets: Budgets = {}
  for (const flag of flags) {
    const [, scope = 'all', metric, value] = /^(?:(\w+)\.)?(\w+)=(.+)$/.exec(flag) ?? []
    if (!metric) throw new Error(`--budget "${flag}" must look like p95=1500 or index.p95=1200`)
    set(budgets, scope, metric, Number(value), '--budget')
  }
  return budgets
}

// { "all": { "p95": 1500 }, "index": { "p95": 1000, "max": 3000 } }
export function parseBudgetFile(text: string, source = 'budget file'): Budgets {
  const parsed: unknown = JSON.parse(text)
  if (typeof parsed !== 'object' || parsed === null || Array.isArray(parsed)) throw new Error(`${source} must be a JSON object keyed by screen kind`)
  const budgets: Budgets = {}
  for (const [scope, metrics] of Object.entries(parsed)) {
    if (typeof metrics !== 'object' || metrics === null) throw new Error(`${source}: ${scope} must be an object of metrics`)
    for (const [metric, value] of Object.entries(metrics)) set(budgets, scope, metric, value, source)
  }
  return budgets
}

export const mergeBudgets = (...all: Budgets[]): Budgets =>
  all.reduce<Budgets>((merged, next) => {
    for (const [scope, metrics] of Object.entries(next)) merged[scope as Scope] = { ...merged[scope as Scope], ...metrics }
    return merged
  }, {})

export const hasBudgets = (budgets: Budgets) => Object.values(budgets).some((metrics) => Object.keys(metrics).length)

// A p50 or p95 budget fails its scope as a whole; the screens listed are the ones over the limit, slowest first.
export function checkBudgets(budgets: Budgets, screens: ScreenResult[]): Violation[] {
  return SCOPES.flatMap((scope) => {
    const inScope = screens.filter((s) => s.readyMs !== undefined && (scope === 'all' || s.kind === scope))
    const stats = timing(inScope.map((s) => s.readyMs!))
    return METRICS.flatMap((metric) => {
      const limit = budgets[scope]?.[metric]
      const actual = stats[metric]
      if (limit === undefined || actual === undefined || actual <= limit) return []
      const over = inScope.filter((s) => s.readyMs! > limit).sort((a, b) => b.readyMs! - a.readyMs!)
      return [{ scope, metric, limit, actual, screens: over.slice(0, MAX_OFFENDERS).map((s) => ({ url: s.url, readyMs: s.readyMs! })) }]
    })
  })
}
