import type { Skipped } from './plan.ts'
import { timing, type Timing } from './stats.ts'
import type { ScreenResult } from './visit.ts'

export type Report = {
  origin: string
  startedAt: string
  durationMs: number
  totals: { screens: number; passed: number; failed: number; skipped: number }
  readyMs: Timing & { byKind: Record<string, Timing> }
  skipped: Skipped[]
  screens: ScreenResult[]
}

export function buildReport(origin: string, startedAt: Date, screens: ScreenResult[], skipped: Skipped[]): Report {
  const timed = (list: ScreenResult[]) => timing(list.flatMap((s) => (s.readyMs === undefined ? [] : [s.readyMs])))
  const kinds = [...new Set(screens.map((s) => s.kind))]
  const failed = screens.filter((s) => s.status === 'fail').length
  return {
    origin,
    startedAt: startedAt.toISOString(),
    durationMs: Date.now() - startedAt.getTime(),
    totals: { screens: screens.length, passed: screens.length - failed, failed, skipped: skipped.length },
    readyMs: { ...timed(screens), byKind: Object.fromEntries(kinds.map((kind) => [kind, timed(screens.filter((s) => s.kind === kind))])) },
    skipped,
    screens,
  }
}

const ms = (value?: number) => (value === undefined ? '-' : String(value))
const row = (cells: (string | number)[]) => `| ${cells.join(' | ')} |`
const cell = (text: string) => text.replace(/\|/g, '\\|')

export function toMarkdown(report: Report): string {
  const { totals, readyMs, screens, skipped } = report
  const failures = screens.filter((s) => s.status === 'fail')
  const lines = [
    '# Crawl report',
    '',
    `${report.origin}, ${report.startedAt}, ${(report.durationMs / 1000).toFixed(1)} s`,
    '',
    `**${totals.failed ? 'FAILED' : 'PASSED'}**: ${totals.screens} screens, ${totals.passed} passed, ${totals.failed} failed, ${totals.skipped} skipped`,
    '',
    '## Time to first meaningful render (ms)',
    '',
    row(['kind', 'n', 'p50', 'p95', 'max']),
    row(['---', '---', '---', '---', '---']),
    ...Object.entries({ all: readyMs, ...readyMs.byKind }).map(([kind, t]) => row([kind, t.n, ms(t.p50), ms(t.p95), ms(t.max)])),
    '',
  ]
  if (failures.length) {
    lines.push('## Failures', '')
    for (const s of failures) {
      lines.push(`### ${s.kind} \`${s.url}\``, '')
      lines.push(...s.failures.map((f) => `- **${f.type}**: ${f.message}`), '')
    }
  }
  if (skipped.length) lines.push('## Skipped', '', ...skipped.map((s) => `- \`${s.id}\`: ${s.reason}`), '')
  lines.push('## Screens', '', row(['status', 'kind', 'url', 'ready ms', 'api calls', 'minor a11y']), row(['---', '---', '---', '---', '---', '---']))
  lines.push(...screens.map((s) => row([s.status, s.kind, `\`${cell(s.url)}\``, ms(s.readyMs), s.apiCalls, s.a11yMinor])), '')
  return lines.join('\n')
}
