import type { Action } from '@/api/generated/model'
import { adminPath } from './base'
import { isAdminPath, sameOrigin } from './classic'

// `/:resource/actions/:key` and `/:resource/:id/actions/:key`; segments stay encoded, as in the address bar.
export function actionRoute(pathname: string) {
  const [resource, ...rest] = pathname.split('/').filter(Boolean)
  const at = rest.indexOf('actions')
  return at >= 0 && at <= 1 && at === rest.length - 2 ? { resource, id: at ? rest[0] : undefined, key: rest[at + 1] } : undefined
}

// Where the classic admin has the page the client shows at this route (relative to the router). Group overviews and
// action pages exist only in the client; every other route is served by both at the same address, so undefined.
export function classicDestination(pathname: string, action?: Pick<Action, 'href'>, origin?: string) {
  if (pathname.split('/').filter(Boolean)[0] === 'groups') return adminPath
  const page = actionRoute(pathname)
  if (!page) return undefined

  const href = action?.href && sameOrigin(action.href, origin)
  if (href && isAdminPath(href.pathname)) {
    href.searchParams.delete('classic')
    return href.pathname + href.search + href.hash
  }
  return `${adminPath}/${page.resource}${page.id ? `/${page.id}` : ''}`
}
