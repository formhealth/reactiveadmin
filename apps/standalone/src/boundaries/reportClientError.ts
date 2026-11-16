import { matchRoutes, type RouteObject } from 'react-router'
import { lastRequestId, quietSession } from '@/api/fetcher'
import type { ClientErrorReport } from '@/api/generated/model'
import { mountPath, routerBase } from '@/lib/base'

// Only names go in. Props, record data and error text can carry sensitive data, so callers pass `error.name`, never `error.message`.
export type ClientError = { where: string; name: string; componentStack?: string | null }

const NAME = /^[A-Za-z_$][\w$]{0,63}$/
const MAX_COMPONENTS = 20
// A render loop would otherwise post on every frame.
const MAX_REPORTS = 5

// Set by the route table itself: importing it here would be a cycle, since its pages use the boundaries.
let routes: RouteObject[] = []
export const registerRoutes = (table: RouteObject[]) => {
  routes = table
}

// The matched pattern (`/:resource/:id/edit`) never carries the ids or slugs of the URL, and the query is dropped.
export function routeOf(pathname: string) {
  const matches = matchRoutes(routes, pathname, routerBase || undefined)
  if (!matches) return {}
  const pattern = matches
    .map((m) => m.route.path)
    .filter(Boolean)
    .join('/')
  return { route: `/${pattern}`, resource: matches.at(-1)?.params.resource }
}

// React's stack reads `at Name (url)` in V8 and `Name@url` elsewhere. Only the names are kept.
export function componentNames(stack?: string | null) {
  return (stack ?? '')
    .split('\n')
    .map((line) => /^\s*(?:at\s+)?([^\s@(]+)/.exec(line)?.[1])
    .filter((name): name is string => !!name && NAME.test(name))
    .slice(0, MAX_COMPONENTS)
}

export function buildReport(error: ClientError, pathname: string, requestId = lastRequestId()): ClientErrorReport {
  const { route, resource } = routeOf(pathname)
  return {
    error_name: NAME.test(error.name) ? error.name : 'Error',
    boundary: error.where,
    components: componentNames(error.componentStack),
    route,
    resource,
    client_version: __CLIENT_VERSION__,
    request_id: requestId,
  }
}

const sent = new Set<string>()

// Not `apiFetch`: it toasts a 429 and drops client storage on a 401, and a report shouldn't disturb the person whose page just broke.
// Undefined when the host turned reporting off (`config.ui.client_errors = false`), so nothing is sent.
const post = async (report: ClientErrorReport, fresh = false) => {
  const current = await quietSession({ fresh })
  if (current?.ui?.client_errors === false) return undefined
  return fetch(`${mountPath}/admin/_client_errors`, {
    method: 'POST',
    credentials: 'include',
    keepalive: true,
    headers: { 'Content-Type': 'application/json', Accept: 'application/json', 'X-CSRF-Token': current?.csrf_token ?? '' },
    body: JSON.stringify(report),
  })
}

async function send(report: ClientErrorReport) {
  const key = [report.boundary, report.error_name, report.route, report.resource].join('|')
  if (sent.has(key) || sent.size >= MAX_REPORTS) return
  sent.add(key)
  const res = await post(report)
  // The cached session can outlive its token; refresh it once, since the dedupe above would drop a second report.
  if (res?.status === 422 && (await res.json().catch(() => null))?.code === 'invalid_csrf') {
    await post(report, true)
  }
}

export function reportClientError(error: ClientError) {
  if (import.meta.env.DEV) console.error('[client-error]', error)
  if (import.meta.env.PROD) send(buildReport(error, globalThis.location.pathname)).catch(() => {})
}
