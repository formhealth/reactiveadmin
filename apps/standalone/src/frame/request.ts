import { sameOrigin, withClassic } from '@/lib/classic'

export const FRAME_HEADER = 'X-Reactiveadmin-Frame'

export type FrameRequest = { url: string; init: RequestInit }

const base = () => globalThis.location?.href

const headers = (extra: Record<string, string> = {}) => ({ [FRAME_HEADER]: '1', Accept: 'text/html, application/json', ...extra })

type Submit = { action?: string | null; method?: string | null; enctype?: string | null; data: FormData; base?: string }

// Mirrors what the browser would send for the form: `_method` and the submitter stay in the body (Rack's method
// override reads them), the CSRF token moves to a header (added by the caller), and GET forms become a query.
export function buildFrameRequest({ action, method, enctype, data, base: from = base() }: Submit): FrameRequest | undefined {
  const target = sameOrigin(action || from, from)
  if (!target) return undefined
  data.delete('authenticity_token')

  if (!method || method.toLowerCase() === 'get') {
    target.search = ''
    for (const [key, value] of data) if (typeof value === 'string') target.searchParams.append(key, value)
    return { url: target.pathname + target.search, init: { method: 'GET', headers: headers() } }
  }

  // Browsers only submit GET and POST. A form that names another verb gets it as `_method`, as Rack expects.
  const verb = method.toLowerCase()
  if (verb !== 'post' && !data.has('_method')) data.set('_method', verb)
  const multipart = enctype?.toLowerCase() === 'multipart/form-data'
  const body = multipart ? data : new URLSearchParams([...data].map(([key, value]) => [key, typeof value === 'string' ? value : value.name]))
  const extra: Record<string, string> = multipart ? {} : { 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' }
  return { url: target.pathname + target.search, init: { method: 'POST', headers: headers(extra), body } }
}

// rails-ujs turns `a[data-method]` into a POST form carrying `_method`; non-GET links do the same here.
export function buildLinkRequest(href: string, method = 'get', from = base()): FrameRequest | undefined {
  const target = sameOrigin(href, from)
  if (!target) return undefined
  const verb = method.toLowerCase()
  const url = target.pathname + target.search
  if (verb === 'get') return { url, init: { method: 'GET', headers: headers() } }
  const body = new URLSearchParams(verb === 'post' ? {} : { _method: verb })
  return { url, init: { method: 'POST', headers: headers({ 'Content-Type': 'application/x-www-form-urlencoded;charset=UTF-8' }), body } }
}

// The same page in the classic admin: the chrome-free `embed` flag is dropped, and `classic` keeps the server from
// answering with the client again.
export function classicLink(url: string, from = base()) {
  const target = new URL(url, from)
  target.searchParams.delete('embed')
  return withClassic(target.pathname + target.search)
}

const squash = (text?: string | null) => (text ?? '').toLowerCase().replace(/[^a-z0-9]+/g, '')

// Classic pages repeat the page title as a heading; the app already shows it.
export const sameTitle = (heading?: string | null, title?: string | null) => !!squash(title) && squash(heading) === squash(title)

export const filenameOf = (disposition: string | null) =>
  /filename\*?=(?:UTF-8'')?"?([^";]+)"?/i.exec(disposition ?? '')?.[1]?.replace(/%20/g, ' ')
