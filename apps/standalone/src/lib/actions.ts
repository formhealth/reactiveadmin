import type { Action } from '@/api/generated/model'

export type Plan = 'none' | 'edit' | 'view' | 'external' | 'form' | 'api' | 'classic' | 'navigate'

// How an action runs. A GET runs the action on the server, so it happens exactly once: in the container the server
// chose (`view`), or by the browser at the classic URL. It is never tried through the API first with the classic page
// as a fallback, which would run it twice. Only writes go to `api_path`.
export function planOf(action: Action): Plan {
  if (action.supported === false || action.api_denied) return 'none'
  if (action.navigate && action.href) return 'navigate'
  if (action.kind === 'edit') return 'edit'
  if (action.view) return 'view'
  if (action.external && action.href) return 'external'
  if (action.form_path) return 'form'
  const read = (action.method ?? 'get') === 'get'
  return read || !action.api_path ? 'classic' : 'api'
}
