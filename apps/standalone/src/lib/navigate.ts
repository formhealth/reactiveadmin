import { csrfToken } from '@/api/fetcher'
import type { Action } from '@/api/generated/model'
import { safeNavigation } from './safeUrl'

export const CSRF_FIELD = 'authenticity_token'

// The token comes last and from the session, so a field the action carries can't stand in for it.
export const navigationFields = (action: Action, token: string): [name: string, value: string][] => [
  ...Object.entries(action.params ?? {}).filter(([name]) => name !== CSRF_FIELD),
  [CSRF_FIELD, token],
]

// A real form submit in the top window, not a fetch: an OAuth start answers with a redirect to another site, which
// only a navigation can follow. Rails reads the token from the form like any other post.
export async function submitNavigation(action: Action) {
  if (!safeNavigation(action)) throw new Error("This action can't run from here")
  const token = await csrfToken()
  const form = Object.assign(document.createElement('form'), { method: 'post', action: action.href, target: '_top', hidden: true })
  for (const [name, value] of navigationFields(action, token)) form.append(Object.assign(document.createElement('input'), { type: 'hidden', name, value }))
  document.body.append(form)
  form.submit()
}
