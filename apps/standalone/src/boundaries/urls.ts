import { adminPath, routerBase } from '@/lib/base'
import { withClassic } from '@/lib/classic'

// In-app routes mirror classic paths under the admin's path, so this is the same page in the classic admin.
export const classicHere = (pathname: string, search = '') => withClassic(`${adminPath}${pathname === '/' ? '' : pathname}${search}`)

// The classic page of whatever the browser shows now, for the last-resort boundary that sits above the router.
export const classicHereNow = (location = globalThis.location) => classicHere(location.pathname.slice(routerBase.length) || '/', location.search)

// Same page, rendered without the admin chrome. Only the path and query are kept, so the base is arbitrary.
export function embedded(src: string) {
  const url = new URL(src, 'http://admin.local')
  url.searchParams.set('embed', '1')
  return url.pathname + url.search
}
