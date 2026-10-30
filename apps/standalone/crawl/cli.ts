import { mkdirSync, writeFileSync } from 'node:fs'
import path from 'node:path'
import { chromium, type BrowserContext } from 'playwright'
import { loadAllowlist } from './allowlist.ts'
import { signIn } from './auth.ts'
import { HELP, parseOptions, type Options } from './options.ts'
import { buildPlan, needsRecords, planResourceKeys, type ManifestLike } from './plan.ts'
import { buildReport, toMarkdown } from './report.ts'
import { visit, type ScreenResult } from './visit.ts'

class SetupError extends Error {}

const pool = async <T, R>(items: T[], size: number, work: (item: T) => Promise<R>) => {
  const results: R[] = new Array(items.length)
  let next = 0
  await Promise.all(
    Array.from({ length: Math.min(size, items.length) }, async () => {
      while (next < items.length) {
        const at = next++
        results[at] = await work(items[at])
      }
    }),
  )
  return results
}

// Reads are marked as background so a host doesn't count the crawler's metadata reads as admin activity.
const getJson = async (context: BrowserContext, url: string, background: boolean) => {
  const response = await context.request.get(url, { headers: { Accept: 'application/json', ...(background && { 'X-Reactiveadmin-Background': '1' }) } })
  if (response.status() === 401 || response.status() === 403) throw new SetupError(`${response.status()} from ${new URL(url).pathname}: not signed in as an admin. Set CRAWL_COOKIE or a login hook (docs/guide/testing.md).`)
  if (!response.ok()) throw new SetupError(`${response.status()} from ${new URL(url).pathname}`)
  return response.json() as Promise<unknown>
}

async function recordIds(context: BrowserContext, { baseUrl, apiPrefix, limit }: Options, key: string) {
  try {
    const body = (await getJson(context, `${baseUrl}${apiPrefix}/${encodeURIComponent(key)}?per_page=${Math.max(limit, 1)}`, false)) as { rows?: { id: string }[] }
    return (body.rows ?? []).map((row) => String(row.id))
  } catch {
    // The index screen reports why; there are just no records to open.
    return []
  }
}

const line = (r: ScreenResult) => {
  const head = `${r.status === 'pass' ? 'PASS' : 'FAIL'}  ${r.kind.padEnd(5)} ${r.url}  ${r.readyMs ?? '-'} ms`
  return [head, ...r.failures.map((f) => `        ${f.type}: ${f.message}`)].join('\n')
}

async function main(argv: string[]) {
  const options = parseOptions(argv)
  if (options === 'help') return console.log(HELP), 0

  const startedAt = new Date()
  const browser = await chromium.launch({ headless: !options.headed })
  try {
    const setup = await browser.newContext({ baseURL: options.baseUrl })
    await signIn({ baseUrl: options.baseUrl, context: setup, env: process.env }, options.login)
    const manifest = (await getJson(setup, `${options.baseUrl}${options.apiPrefix}/_manifest`, true)) as ManifestLike
    if (!Array.isArray(manifest.resources) || !Array.isArray(manifest.menu)) throw new SetupError('the manifest has no resources or menu; is --api-prefix right?')

    const keys = needsRecords(options.kinds) ? planResourceKeys(manifest, options) : []
    const ids = Object.fromEntries(await pool(keys, options.concurrency, async (key) => [key, await recordIds(setup, options, key)] as const))
    const { screens, skipped } = buildPlan(manifest, ids, options)
    const storageState = await setup.storageState()
    await setup.close()
    if (!screens.length) throw new SetupError('nothing to crawl: check --resources and --screens')

    const allowlist = loadAllowlist(options.allowlist)
    const baselineDir = path.join(options.baselineDir, new URL(options.baseUrl).host.replace(/[^\w.-]/g, '_'))
    console.log(`Crawling ${screens.length} screens at ${options.baseUrl} (concurrency ${options.concurrency})`)
    const results = await pool(screens, options.concurrency, async (screen) => {
      const result = await visit(screen, { browser, storageState, options, allowlist, baselineDir })
      console.log(line(result))
      return result
    })

    const report = buildReport(options.baseUrl, startedAt, results, skipped)
    mkdirSync(options.outDir, { recursive: true })
    writeFileSync(path.join(options.outDir, 'crawl-report.json'), `${JSON.stringify(report, null, 2)}\n`)
    writeFileSync(path.join(options.outDir, 'crawl-report.md'), toMarkdown(report))
    const { totals, readyMs } = report
    console.log(`\n${totals.screens} screens, ${totals.passed} passed, ${totals.failed} failed, ${totals.skipped} skipped. ready p50 ${readyMs.p50} ms, p95 ${readyMs.p95} ms`)
    console.log(`Report: ${path.join(options.outDir, 'crawl-report.md')}`)
    return totals.failed ? 1 : 0
  } finally {
    await browser.close()
  }
}

main(process.argv.slice(2)).then(
  (code) => process.exit(code),
  (error: unknown) => {
    console.error(error instanceof SetupError ? `crawl: ${error.message}` : error)
    process.exit(2)
  },
)
