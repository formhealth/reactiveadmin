import { describe, expect, it } from 'vitest'
import { buildReport, toMarkdown } from './report.ts'
import { percentile, timing } from './stats.ts'
import type { ScreenResult } from './visit.ts'

const screen = (url: string, kind: ScreenResult['kind'], readyMs: number, failures: ScreenResult['failures'] = []): ScreenResult => ({
  id: url,
  kind,
  url,
  readyMs,
  apiCalls: 2,
  a11yMinor: 0,
  failures,
  status: failures.length ? 'fail' : 'pass',
})

describe('percentile', () => {
  it('uses the nearest rank', () => {
    const values = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    expect(percentile(values, 50)).toBe(50)
    expect(percentile(values, 95)).toBe(100)
    expect(timing([3, 1, 2])).toEqual({ n: 3, p50: 2, p95: 3, max: 3 })
    expect(timing([])).toEqual({ n: 0, p50: undefined, p95: undefined, max: undefined })
  })
})

describe('report', () => {
  const screens = [screen('/', 'home', 100), screen('/posts', 'index', 300), screen('/posts/1', 'show', 200, [{ type: 'api', message: '500 GET /api/admin/posts/1' }])]
  const report = buildReport('http://localhost:5174', new Date('2026-10-19T00:00:00Z'), screens, [{ id: 'comments', reason: 'nested' }])

  it('totals and times the screens', () => {
    expect(report.totals).toEqual({ screens: 3, passed: 2, failed: 1, skipped: 1 })
    expect(report.readyMs).toMatchObject({ n: 3, p50: 200, p95: 300 })
    expect(report.readyMs.byKind.index).toMatchObject({ n: 1, p50: 300 })
  })

  it('lists failures with their url and message in the markdown', () => {
    const md = toMarkdown(report)
    expect(md).toContain('**FAILED**')
    expect(md).toContain('### show `/posts/1`')
    expect(md).toContain('- **api**: 500 GET /api/admin/posts/1')
    expect(md).toContain('`comments`: nested')
  })

  it('reports a clean run as passed', () => {
    expect(toMarkdown(buildReport('http://x', new Date(), [screen('/', 'home', 1)], []))).toContain('**PASSED**')
  })
})
