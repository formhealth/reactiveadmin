import type { Location } from '@/api/generated/model'
import { sameOrigin } from '@/lib/classic'
import { routeFor } from '@/lib/records'

export type Flash = { level: 'success' | 'error'; message: string }

export type BridgeEvent =
  | { kind: 'resize'; height: number }
  | { kind: 'flash'; flashes: Flash[] }
  | { kind: 'navigate'; url?: string; location: Partial<Location>; redirected: boolean }

const asLevel = (kind: unknown): Flash['level'] => (/alert|error/.test(String(kind)) ? 'error' : 'success')

const text = (value: unknown) => (typeof value === 'string' && value.trim() ? value : undefined)

// What the classic page's bridge script posts (`reactiveadmin:resize|flash|navigate`). Origin and source are checked by
// the caller; this only decides what a payload means, and ignores anything malformed.
export function parseBridgeMessage(data: unknown): BridgeEvent | undefined {
  const message = (typeof data === 'object' && data !== null ? data : {}) as Record<string, unknown>
  switch (message.type) {
    case 'reactiveadmin:resize':
      return typeof message.height === 'number' && Number.isFinite(message.height) && message.height >= 0 ? { kind: 'resize', height: Math.ceil(message.height) } : undefined
    case 'reactiveadmin:flash': {
      const listed = Array.isArray(message.flashes) ? message.flashes : [{ type: message.level, message: message.message }]
      const flashes = listed.flatMap((flash: { type?: unknown; message?: unknown }) => (text(flash?.message) ? [{ level: asLevel(flash.type), message: text(flash.message)! }] : []))
      return flashes.length ? { kind: 'flash', flashes } : undefined
    }
    case 'reactiveadmin:navigate': {
      const { resource, id, view } = message as Partial<Location>
      return { kind: 'navigate', url: text(message.url), location: { resource, id, view }, redirected: message.redirected === true }
    }
  }
}

export const trustedOrigin = (origin: string, own = globalThis.location?.origin) => origin === own

// The same page with the chrome-free layout; undefined for other origins.
export function embedUrl(url: string, from = globalThis.location?.href) {
  const target = sameOrigin(url, from)
  if (!target) return undefined
  target.searchParams.set('embed', '1')
  return target.pathname + target.search + target.hash
}

export type Navigation = { to: string } | { stay: string } | undefined

// An admin URL with an in-app screen leaves the iframe for it. Anything else stays inside: the page is loaded again
// as an embed, unless the iframe is already showing it (a redirect after a submit).
export function navigation(event: Extract<BridgeEvent, { kind: 'navigate' }>, mapUrl: (url: string) => string | undefined, from?: string): Navigation {
  const to = routeFor({ url: event.url ?? '', ...event.location }) || (event.url ? mapUrl(event.url) : undefined)
  if (to) return { to }
  const next = event.url && !event.redirected ? embedUrl(event.url, from) : undefined
  return next ? { stay: next } : undefined
}
