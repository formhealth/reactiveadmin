import type { Session, ValidationErrorRowErrors } from '@/api/generated/model'
import { mountPath as BASE_URL } from '@/lib/base'
import { toastRateLimited } from '@/lib/rateLimit'
import { clearClientStorage } from '@/lib/storage'

const BACKGROUND_HEADER = 'X-Reactiveadmin-Background'
const backgroundRequest = { [BACKGROUND_HEADER]: '1' }

// Metadata the operator didn't ask for: option lookups, labels, session and manifest revalidation. Hosts keep
// them out of their access audit. Record data (show, index, edit, _value) is never marked: the server treats
// it as a view whatever the header says, and a record must not be served from a read nobody audited.
const BACKGROUND_PATH = /\/_(meta|options\/lookup|options|session|manifest|labels)(\?|$)/
// The endpoint a background read belongs to; a 429 only holds back reads of the same one.
const backgroundBucket = (url: string, method = 'GET') => (method.toUpperCase() === 'GET' ? BACKGROUND_PATH.exec(url)?.[1] : undefined)
export const isBackgroundRead = (url: string, method = 'GET') => backgroundBucket(url, method) !== undefined

type ErrorBody = { errors?: Record<string, string[]>; row_errors?: ValidationErrorRowErrors; base?: string[]; classic_url?: string; attributes?: string[]; guard?: string }

export class ApiError extends Error {
  status: number
  code?: string
  body?: ErrorBody
  // Seconds, from `Retry-After` on a 429 or a `retry` 409.
  retryAfter?: number

  constructor(status: number, code?: string, message?: string, body?: ErrorBody, retryAfter?: number) {
    super(message ?? `Request failed (${status})`)
    this.status = status
    this.code = code
    this.body = body
    this.retryAfter = retryAfter
  }
}

export const isStale = (error: unknown): error is ApiError => error instanceof ApiError && error.status === 409 && error.code === 'stale'

// A host concurrency guard lost a race: nothing changed under the user, so the same write can be sent again.
export const isRetry = (error: unknown): error is ApiError => error instanceof ApiError && error.status === 409 && error.code === 'retry'

export const isRateLimited = (error: unknown): error is ApiError => error instanceof ApiError && error.status === 429

// `Retry-After` is delay-seconds or an HTTP date.
export function parseRetryAfter(value: string | null, now = Date.now()) {
  const text = value?.trim()
  if (!text) return undefined
  const seconds = /^\d+$/.test(text) ? Number(text) : (Date.parse(text) - now) / 1000
  return Number.isFinite(seconds) ? Math.max(1, Math.ceil(seconds)) : undefined
}

const DEFAULT_BACKOFF = 5
const backoffUntil = new Map<string, number>()
const backoffLeft = (bucket: string) => Math.ceil(((backoffUntil.get(bucket) ?? 0) - Date.now()) / 1000)

export const errorMessage = (error: unknown) =>
  error instanceof ApiError ? error.body?.base?.join(' ') || error.message : error instanceof Error ? error.message : 'Something went wrong'

let session: Promise<Session> | undefined

// Cached for the page's lifetime; dropped when the server rejects it.
export const fetchSession = () =>
  (session ??= request<Session>('/admin/_session').catch((error) => {
    session = undefined
    throw error
  }))

export const csrfToken = () => fetchSession().then((s) => s.csrf_token)

export const resetCsrf = () => {
  session = undefined
}

// Paths from the API (`FormResponse.action.path`, `Action.api_path`) already include the mount.
const withMount = (url: string) => (url.startsWith(`${BASE_URL}/`) ? url : `${BASE_URL}${url}`)

async function request<T>(url: string, options: RequestInit = {}, retried = false): Promise<T> {
  const write = !['GET', 'HEAD'].includes((options.method ?? 'GET').toUpperCase())
  const bucket = backgroundBucket(url, options.method)
  const background = bucket !== undefined
  // After a 429 the reads nobody asked for (option lookups, metadata) wait it out per endpoint instead of hammering the server.
  if (bucket && backoffLeft(bucket) > 0) throw new ApiError(429, 'rate_limited', undefined, undefined, backoffLeft(bucket))
  const headers = {
    Accept: 'application/json',
    ...(background && backgroundRequest),
    ...(options.headers as Record<string, string>),
  }
  if (write) Object.assign(headers, { 'X-CSRF-Token': await csrfToken() })

  const res = await fetch(withMount(url), { credentials: 'include', ...options, headers })
  const body = await res.json().catch(() => null)
  if (res.status === 422 && body?.code === 'invalid_csrf' && !retried) {
    resetCsrf()
    return request(url, options, true)
  }
  if (res.status === 401) clearClientStorage()
  if (res.status === 429) {
    const retryAfter = parseRetryAfter(res.headers.get('Retry-After'))
    if (bucket) backoffUntil.set(bucket, Date.now() + (retryAfter ?? DEFAULT_BACKOFF) * 1000)
    toastRateLimited(retryAfter)
    throw new ApiError(429, body?.code ?? 'rate_limited', body?.message, body ?? undefined, retryAfter)
  }
  if (!res.ok) throw new ApiError(res.status, body?.code, body?.message, body ?? undefined, parseRetryAfter(res.headers.get('Retry-After')))
  return body as T
}

export const apiFetch = <T>(url: string, options: RequestInit = {}) => request<T>(url, options)
