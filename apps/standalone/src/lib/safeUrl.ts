import type { Action, FormResponse } from '@/api/generated/model'
import { embedUrl } from '@/frame/bridge'
import { adminPath, mountPath } from './base'
import { isAdminPath, sameOrigin } from './classic'

const EXTERNAL_SCHEMES = new Set(['http:', 'https:', 'mailto:', 'tel:'])

const parse = (url: string, base: string | undefined) => {
  try {
    return new URL(url, base)
  } catch {
    return undefined
  }
}

// Server nodes are untrusted at the edge: markup can name any URL, so each target is checked again here. A
// `javascript:` or `data:` URL has an opaque origin, which fails every same-origin test below.

// A same-origin admin page for an iframe, always chrome-free (`?embed=1`); undefined for anything else. The sandbox
// grants same-origin scripts, so what loads must be an admin page, never an upload or another same-origin path.
export function safeEmbedSrc(src: string | null | undefined, from?: string) {
  const embedded = src ? embedUrl(src, from) : undefined
  return embedded && isAdminPath(embedded.split(/[?#]/, 1)[0]) ? embedded : undefined
}

// An in-app admin path, or an http(s), mailto or tel URL that the server explicitly marked external.
export function safeHref(href: string | null | undefined, external?: boolean, from = globalThis.location?.href) {
  if (!href) return undefined
  if (external) return EXTERNAL_SCHEMES.has(parse(href, from)?.protocol ?? '') ? href : undefined
  const target = sameOrigin(href, from)
  return target && isAdminPath(target.pathname) ? href : undefined
}

const escape = (path: string) => path.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

// A POST that navigates the window needs a URL this origin serves outside the admin and the API: never a
// request the page could forge for either, and never another site.
const RESERVED = new RegExp(`^(${[...new Set(['/admin', '/api', adminPath, mountPath])].filter(Boolean).map(escape).join('|')})(/|$)`, 'i')

// URL parsing resolves dot segments and drops tabs and newlines, which would let `/auth/../admin/x` or `/admin/%2\nf`
// pass as something else. So the raw path must be free of both, and the resolved path (which also carries any
// encoded separator inherited from the base) must have no encoded separators either.
const UNRESOLVED_PATH = /(^|\/)\.\.?(\/|$)|%2e|%2f|%5c|\\/i
const CONTROL_CHARS = /\p{Cc}/u

const plainPath = (url: string, target: URL) => {
  const raw = url.trim().split(/[?#]/, 1)[0]
  return !CONTROL_CHARS.test(raw) && !UNRESOLVED_PATH.test(raw) && !UNRESOLVED_PATH.test(target.pathname)
}

// A frame's write carries this session's CSRF token, so it only goes to an admin page of this origin.
export function safeFrameWrite(url: string, from = globalThis.location?.href): boolean {
  const target = sameOrigin(url, from)
  return !!target && isAdminPath(target.pathname) && plainPath(url, target)
}

export function safeNavigation(action: Action, from = globalThis.location?.href): boolean {
  const target = action.href ? sameOrigin(action.href, from) : undefined
  return !!target && !RESERVED.test(target.pathname) && plainPath(action.href!, target) && action.method === 'post' && !action.api_path && !action.form_path && !action.view
}

// Actions run against our own API, or open a classic page or an external site.
export function safeAction(action: Action, from = globalThis.location?.href): boolean {
  if (action.navigate) return safeNavigation(action, from)
  const own = (path?: string | null) => !path || !!sameOrigin(path, from)
  return own(action.api_path) && own(action.form_path) && own(action.view?.path) && (!action.href || !!safeHref(action.href, action.external, from))
}

// A form node posts to our own API, and its typeahead searches are the same.
export function safeFormAction(form: FormResponse, from = globalThis.location?.href): boolean {
  const own = (path?: string | null) => !path || !!sameOrigin(path, from)
  return own(form.action.path) && form.form.sections.every((section) => section.fields.every((field) => own(field.options_path)))
}
