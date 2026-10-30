import { adminPath } from './base'

export const isAdminPath = (pathname: string) => pathname === adminPath || pathname.startsWith(`${adminPath}/`)

export type ClassicTargets = { resources: ReadonlySet<string>; pages: ReadonlySet<string> }

const here = () => globalThis.location?.origin
const PARSE_BASE = 'http://admin.local'

// Parsed URL when it points at the same origin, undefined for other origins and unparsable input.
export function sameOrigin(url: string, origin = here()) {
  try {
    const parsed = new URL(url, origin)
    // `blob:` URLs report their creator's origin, so the scheme has to be checked too.
    const web = parsed.protocol === 'http:' || parsed.protocol === 'https:'
    return web && parsed.origin === new URL(origin ?? parsed.origin).origin ? parsed : undefined
  } catch {
    return undefined
  }
}

// A link out of the client to the classic admin. `classic=1` is the server's per-request escape hatch: without it a user
// who chose the new admin is sent straight back, since both UIs share these URLs. Other URLs pass unchanged.
export function withClassic(url: string) {
  const target = sameOrigin(url, here() ?? PARSE_BASE)
  if (!target || !isAdminPath(target.pathname)) return url
  target.searchParams.set('classic', '1')
  return target.pathname + target.search + target.hash
}

export const classicUrl = (resource: string, id?: string, tail = '') => withClassic(`${adminPath}/${resource}${id ? `/${id}` : ''}${tail}`)

// Maps a classic admin URL to the equivalent in-app route, or undefined when the client has no screen for it
// (member actions, nested resources, unknown pages): callers then load it in a frame or open it in a new tab.
export function mapClassicUrl(url: string, { resources, pages }: ClassicTargets, origin = here()) {
  const parsed = sameOrigin(url, origin)
  if (!parsed || !isAdminPath(parsed.pathname) || parsed.searchParams.get('classic') === '1') return undefined
  const [first, second, third, ...rest] = parsed.pathname.slice(adminPath.length).split('/').filter(Boolean)
  if (!first) return '/'
  if (pages.has(first)) return second ? undefined : `/${first}`
  if (!resources.has(first) || rest.length) return undefined
  if (!second) return `/${first}${parsed.search}`
  if (!third) return `/${first}/${second}`
  return third === 'edit' && second !== 'new' ? `/${first}/${second}/edit` : undefined
}
