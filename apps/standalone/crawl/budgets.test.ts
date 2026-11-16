import { describe, expect, it } from 'vitest'
import { checkBudgets, hasBudgets, mergeBudgets, parseBudgetFile, parseBudgetFlags } from './budgets.ts'
import type { ScreenResult } from './visit.ts'

const screen = (url: string, kind: ScreenResult['kind'], readyMs?: number): ScreenResult => ({ id: url, kind, url, readyMs, apiCalls: 0, a11yMinor: 0, failures: [], status: 'pass' })

describe('parseBudgetFlags', () => {
  it('reads an overall and a per-kind budget', () => {
    expect(parseBudgetFlags(['p95=1500', 'index.max=4000'])).toEqual({ all: { p95: 1500 }, index: { max: 4000 } })
  })

  it.each(['p99=100', 'p95', 'p95=fast', 'p95=0', 'sidebar.p95=100'])('rejects %s', (flag) => {
    expect(() => parseBudgetFlags([flag])).toThrow(/--budget/)
  })
})

describe('parseBudgetFile', () => {
  it('reads budgets keyed by screen kind', () => {
    expect(parseBudgetFile('{"all":{"p95":1500},"show":{"p50":400,"max":2000}}')).toEqual({ all: { p95: 1500 }, show: { p50: 400, max: 2000 } })
  })

  it('names the file in its errors', () => {
    expect(() => parseBudgetFile('{"all":{"p95":"1s"}}', 'budgets.json')).toThrow('budgets.json: all.p95')
    expect(() => parseBudgetFile('[]', 'budgets.json')).toThrow('budgets.json must be a JSON object')
    expect(() => parseBudgetFile('{"all":{"mean":1}}', 'b.json')).toThrow('unknown metric "mean"')
  })
})

describe('mergeBudgets', () => {
  it('lets later budgets win per metric', () => {
    const merged = mergeBudgets({ all: { p95: 1000, max: 5000 } }, { all: { p95: 800 }, index: { p50: 300 } })
    expect(merged).toEqual({ all: { p95: 800, max: 5000 }, index: { p50: 300 } })
    expect(hasBudgets(merged)).toBe(true)
    expect(hasBudgets({})).toBe(false)
  })
})

describe('checkBudgets', () => {
  const screens = [screen('/', 'home', 100), screen('/posts', 'index', 900), screen('/authors', 'index', 1200), screen('/posts/1', 'show', 300), screen('/broken', 'show')]

  it('passes at or under the limit', () => {
    expect(checkBudgets({ all: { max: 1200 }, index: { p50: 900 } }, screens)).toEqual([])
  })

  it('reports the screens over the limit, slowest first', () => {
    const [violation] = checkBudgets({ all: { max: 500 } }, screens)
    expect(violation).toMatchObject({ scope: 'all', metric: 'max', limit: 500, actual: 1200 })
    expect(violation.screens).toEqual([
      { url: '/authors', readyMs: 1200 },
      { url: '/posts', readyMs: 900 },
    ])
  })

  it('judges a kind on its own screens', () => {
    const violations = checkBudgets({ index: { p95: 1000 }, show: { p95: 1000 } }, screens)
    expect(violations.map((v) => `${v.scope}.${v.metric}`)).toEqual(['index.p95'])
  })

  it('ignores screens with no render time and scopes with no screens', () => {
    expect(checkBudgets({ page: { p95: 1 }, show: { max: 300 } }, screens)).toEqual([])
  })
})
