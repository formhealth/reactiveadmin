import type { QueryClient } from '@tanstack/react-query'
import { ApiError, fetchSession } from '@/api/fetcher'
import { getGetSessionQueryKey } from '@/api/generated/core'
import type { Manifest, Session } from '@/api/generated/model'
import { queryClient } from '@/api/queryClient'
import { classicHereNow } from '@/boundaries/urls'
import { isDenied } from './apiDenied'
import { hosted } from './base'
import { menuLeaves } from './menu'
import { storeUiChoice } from './uiMode'

// The server serves this page to anyone whose cookie says `new`, and nothing more: it is here that a user who may not
// use the new admin, or a URL it has no screen for, goes back to the same URL in classic. `classic=1` keeps that
// request from coming straight back.
export const goClassic = (url = classicHereNow()) => location.replace(url)

const SESSION_TIMEOUT = 3000

// One bounded read of `_session` for everything that runs before the first render: a stalled request costs one wait,
// and its timeout takes the same path as any other failure to answer.
export function boundedSession(read: () => Promise<Session> = fetchSession, timeout = SESSION_TIMEOUT) {
  let bounded: Promise<Session> | undefined
  return () =>
    (bounded ??= new Promise<Session>((resolve, reject) => {
      const timer = setTimeout(() => reject(new Error('session check timed out')), timeout)
      read().then(resolve, reject).finally(() => clearTimeout(timer))
    }))
}

// Runs before the first render. True when the browser is on its way to classic.
export async function leaveIfUnavailable(session: () => Promise<Pick<Session, 'ui'>> = fetchSession, isHosted = hosted, go = goClassic, store = storeUiChoice, cache: Pick<QueryClient, 'setQueryData'> = queryClient) {
  if (!isHosted) return false
  try {
    const current = await session()
    if (current.ui?.available) {
      // The switch components read the same session; seeding saves them a second request.
      cache.setQueryData(getGetSessionQueryKey(), current)
      return false
    }
    store(undefined)
  } catch (error) {
    // Signed out: classic redirects to the host's own sign-in.
    if (!(error instanceof ApiError && error.status === 401)) return false
  }
  go()
  return true
}

type Screen = 'index' | 'new' | 'show' | 'edit' | 'action'

const screenOf = (rest: string[]): Screen | undefined => {
  if (rest.length === 0) return 'index'
  if (rest.length === 1) return rest[0] === 'new' ? 'new' : rest[0] === 'actions' ? undefined : 'show'
  if (rest.length === 2) return rest[0] === 'actions' ? 'action' : rest[1] === 'edit' ? 'edit' : undefined
  return rest.length === 3 && rest[1] === 'actions' ? 'action' : undefined
}

// Whether the client has no screen for this route (a path relative to the router) for this manifest: a resource or
// page it doesn't list, an action the resource lacks or the API refuses (`api` guards), nested resources and member
// actions. An in-app route the server serves in classic only never gets here: the client links those out.
export function lacksScreen(pathname: string, { resources, menu, site }: Pick<Manifest, 'resources' | 'menu' | 'site'>) {
  const [first, ...rest] = pathname.split('/').filter(Boolean)
  if (!first || first === 'groups') return false

  const resource = resources.find((r) => r.key === first)
  if (!resource) {
    const page = menuLeaves([...menu, ...site.utility_menu]).find((leaf) => leaf.page === first)
    return !page || page.api_denied === true || rest.length > 0
  }

  const screen = screenOf(rest)
  const served = (action: string) => (resource.actions as string[]).includes(action) && !isDenied(resource, action)
  return !screen || !served('index') || (screen !== 'action' && !served(screen))
}
