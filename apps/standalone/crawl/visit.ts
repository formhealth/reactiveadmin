import { createRequire } from 'node:module'
import type { Browser, BrowserContext, Page } from 'playwright'
import { AXE_TAGS, BLOCKING_IMPACTS, MODAL_SIBLINGS } from '../.storybook/a11yConfig.ts'
import { a11yAllowed, apiAllowed, consoleAllowed, type Allowlist } from './allowlist.ts'
import { compareBaseline, DEFAULT_MASKS } from './baselines.ts'
import type { Options } from './options.ts'
import type { Screen } from './plan.ts'
import { scrub, stripQuery, truncate } from './sanitize.ts'

export type FailureType = 'timeout' | 'ui' | 'console' | 'pageerror' | 'request' | 'api' | 'a11y' | 'screenshot'
export type Failure = { type: FailureType; message: string }
export type ScreenResult = {
  id: string
  kind: Screen['kind']
  resource?: string
  url: string
  status: 'pass' | 'fail'
  readyMs?: number
  apiCalls: number
  failures: Failure[]
  a11yMinor: number
  screenshot?: string
}

const AXE_SOURCE = createRequire(import.meta.url).resolve('axe-core/axe.min.js')
// What the client shows when a screen can't render; a 403 or 404 notice is judged by the API check instead.
const ERROR_TEXT = /couldn't load|couldn't display|something went wrong|sign in to continue|admin updated/i
const QUIET_MS = 300
const SETTLE_CAP_MS = 3000
const MAX_PER_TYPE = 5

// Inside the page: the shell and its first content are painted and nothing is still a skeleton or busy.
const firstMeaningfulRender = () => {
  const main = document.querySelector('main')
  const loading = main?.querySelector('[data-slot="skeleton"], [aria-busy="true"], [role="status"][aria-label^="Loading"]')
  return !!main && main.childElementCount > 0 && !loading && performance.now()
}

const settle = ([quietMs, capMs]: [number, number]) =>
  new Promise<void>((resolve) => {
    let timer = setTimeout(done, quietMs)
    const cap = setTimeout(done, capMs)
    const observer = new MutationObserver(() => {
      clearTimeout(timer)
      timer = setTimeout(done, quietMs)
    })
    observer.observe(document.body, { subtree: true, childList: true, attributes: true, characterData: true })
    function done() {
      observer.disconnect()
      clearTimeout(timer)
      clearTimeout(cap)
      resolve()
    }
  })

const visibleErrors = () => {
  const text = (el: Element) => (el as HTMLElement).innerText.replace(/\s+/g, ' ').trim()
  const alerts = [...document.querySelectorAll('[role="alert"]')].map(text)
  const toasts = [...document.querySelectorAll('[data-sonner-toast][data-type="error"]')].map(text)
  return { alerts, toasts, body: text(document.body).includes('Something went wrong') }
}

type AxeViolation = { id: string; impact?: string | null; nodes: { target: unknown[] }[] }
type AxeApi = { run: (context: unknown, options: unknown) => Promise<{ violations: AxeViolation[] }>; configure: (config: unknown) => void }

async function runAxe(page: Page) {
  await page.addScriptTag({ path: AXE_SOURCE })
  return page.evaluate(
    async ({ tags, modalSiblings }) => {
      const axe = (window as unknown as { axe: AxeApi }).axe
      axe.configure({ rules: modalSiblings })
      const { violations } = await axe.run(document.body, { runOnly: { type: 'tag', values: tags } })
      return violations.map(({ id, impact, nodes }) => ({ id, impact, targets: nodes.slice(0, 3).map((n) => n.target.join(' ')), count: nodes.length }))
    },
    { tags: AXE_TAGS, modalSiblings: MODAL_SIBLINGS },
  )
}

type Seen = { status: number; method: string; path: string; type: string; code?: string; message?: string }

function watch(page: Page, apiPrefix: string, home: string) {
  const consoleErrors: { text: string; url: string }[] = []
  const pageErrors: string[] = []
  const failedRequests: string[] = []
  const responses: Seen[] = []
  const reading: Promise<void>[] = []
  let apiCalls = 0

  page.on('console', (msg) => msg.type() === 'error' && consoleErrors.push({ text: msg.text(), url: stripQuery(msg.location().url, home) }))
  page.on('pageerror', (error) => pageErrors.push(error.message))
  page.on('request', (request) => new URL(request.url()).pathname.startsWith(`${apiPrefix}/`) && apiCalls++)
  page.on('requestfailed', (request) => {
    const reason = request.failure()?.errorText ?? 'failed'
    if (!reason.includes('ERR_ABORTED')) failedRequests.push(`${request.method()} ${stripQuery(request.url(), home)}: ${reason}`)
  })
  page.on('response', (response) => {
    if (response.status() < 400) return
    const seen: Seen = { status: response.status(), method: response.request().method(), path: stripQuery(response.url(), home), type: response.request().resourceType() }
    responses.push(seen)
    reading.push(
      response
        .json()
        .then((body: { code?: unknown; message?: unknown }) => {
          if (typeof body.code === 'string') seen.code = body.code.slice(0, 40)
          if (typeof body.message === 'string') seen.message = scrub(body.message, 120)
        })
        .catch(() => {}),
    )
  })
  return { consoleErrors, pageErrors, failedRequests, responses, calls: () => apiCalls, settled: () => Promise.all(reading) }
}

const capped = (type: FailureType, messages: string[]): Failure[] => {
  const unique = [...new Set(messages)]
  const shown = unique.slice(0, MAX_PER_TYPE).map((message) => ({ type, message }))
  return unique.length > MAX_PER_TYPE ? [...shown, { type, message: `... and ${unique.length - MAX_PER_TYPE} more` }] : shown
}

export type VisitContext = { browser: Browser; storageState: Awaited<ReturnType<BrowserContext['storageState']>>; options: Options; allowlist: Allowlist; baselineDir: string }

export async function visit(screen: Screen, { browser, storageState, options, allowlist, baselineDir }: VisitContext): Promise<ScreenResult> {
  // A context per screen keeps timings cold and comparable: nothing cached by an earlier screen (manifest, chunks, local storage).
  const context = await browser.newContext({ storageState, colorScheme: options.theme, viewport: { width: 1280, height: 800 }, locale: 'en-US', timezoneId: 'UTC' })
  await context.addInitScript(() => {
    addEventListener('DOMContentLoaded', () => document.head.insertAdjacentHTML('beforeend', '<style>*,*::before,*::after{animation:none!important;transition:none!important}</style>'))
  })
  const page = await context.newPage()
  const home = new URL(options.baseUrl).origin
  const seen = watch(page, options.apiPrefix, home)
  const failures: Failure[] = []
  const result: ScreenResult = { id: screen.id, kind: screen.kind, resource: screen.resource, url: screen.path, status: 'pass', apiCalls: 0, failures, a11yMinor: 0 }

  try {
    await page.goto(`${options.baseUrl}${screen.path}`, { waitUntil: 'domcontentloaded', timeout: options.timeoutMs })
    try {
      result.readyMs = Math.round((await (await page.waitForFunction(firstMeaningfulRender, undefined, { polling: 'raf', timeout: options.timeoutMs })).jsonValue()) as number)
    } catch {
      failures.push({ type: 'timeout', message: `no meaningful render within ${options.timeoutMs} ms` })
    }
    await page.evaluate(settle, [QUIET_MS, SETTLE_CAP_MS] as [number, number])
    await seen.settled()

    const shown = await page.evaluate(visibleErrors)
    failures.push(
      ...capped('ui', [...shown.alerts.filter((t) => ERROR_TEXT.test(t)), ...shown.toasts, ...(shown.body ? ['page text contains "Something went wrong"'] : [])].map((t) => scrub(t, 160, home))),
    )

    const apiResponses = seen.responses.filter((r) => !apiAllowed(r, allowlist.api))
    failures.push(...capped('api', apiResponses.map((r) => `${r.status} ${r.method} ${r.path}${r.code ? ` ${r.code}` : ''}${r.message ? ` (${r.message})` : ''}`)))

    // The browser logs every failed response as a console error; the API check above already judged those.
    const logsResponse = (text: string) => /^Failed to load resource: the server responded with a status of \d+/.test(text)
    failures.push(...capped('console', seen.consoleErrors.filter((c) => !logsResponse(c.text) && !consoleAllowed(c.text, allowlist.console)).map((c) => scrub(c.text, 200, home))))
    failures.push(...capped('pageerror', seen.pageErrors.filter((t) => !consoleAllowed(t, allowlist.console)).map((t) => scrub(t, 200, home))))
    failures.push(...capped('request', seen.failedRequests.map((t) => scrub(t, 200, home))))

    if (options.axe) {
      const violations = await runAxe(page)
      const blocking = violations.filter((v) => BLOCKING_IMPACTS.includes(v.impact ?? '') && !a11yAllowed(v.id, screen.path, allowlist.a11y))
      result.a11yMinor = violations.length - blocking.length
      failures.push(...capped('a11y', blocking.map((v) => truncate(`${v.id} (${v.impact}, ${v.count}): ${v.targets.join(' | ')}`, 240))))
    }

    if (options.screenshots && result.readyMs !== undefined) {
      const mask = [...DEFAULT_MASKS, ...options.mask].map((selector) => page.locator(selector))
      const shot = await page.screenshot({ fullPage: true, mask, maskColor: '#ff00ff', animations: 'disabled' })
      const { outcome, message } = compareBaseline(screen.id, shot, { baselineDir, outDir: options.outDir, update: options.updateBaselines, threshold: options.diffThreshold })
      result.screenshot = outcome
      if (outcome === 'diff') failures.push({ type: 'screenshot', message: message ?? 'differs from baseline' })
    }
  } catch (error) {
    failures.push({ type: 'ui', message: scrub(`visit failed: ${error instanceof Error ? error.message : String(error)}`) })
  } finally {
    result.apiCalls = seen.calls()
    await context.close()
  }
  if (failures.length) result.status = 'fail'
  return result
}
