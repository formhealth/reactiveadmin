import { createContext, useCallback, useContext, useEffect, useReducer, useRef } from 'react'
import { ApiError, apiFetch } from '@/api/fetcher'
import type { ValueResponse } from '@/api/generated/model'

// Same-origin API path ending in the value endpoint; anything else is never fetched with our credentials.
const EXPAND_PATH = /^\/(?!\/)[\w\-./%]+\/_value(\?[\w\-.%=&[\]]*)?$/
export const isExpandPath = (path: string | null | undefined): path is string => !!path && EXPAND_PATH.test(path)

export type Fetcher = <T>(url: string, options?: RequestInit) => Promise<T>

// Refetches the query that owns the page's expand paths and resolves with its fresh payload.
export type RefreshOwner = () => Promise<unknown>
export const ValueRefreshContext = createContext<RefreshOwner | undefined>(undefined)

// The token is short-lived, so two paths for the same field differ only in it.
const withoutToken = (path: string) => path.replace(/([?&])token=[^&]*&?/, '$1').replace(/[?&]$/, '')

export function findFreshPath(payload: unknown, stale: string): string | undefined {
  const key = withoutToken(stale)
  const visit = (value: unknown): string | undefined => {
    if (!value || typeof value !== 'object') return
    for (const [name, child] of Object.entries(value)) {
      if (name === 'expand_path' && typeof child === 'string' && withoutToken(child) === key) return child
      const found = visit(child)
      if (found) return found
    }
  }
  return visit(payload)
}

async function fetchValue(path: string, signal: AbortSignal | undefined, fetcher: Fetcher) {
  if (!isExpandPath(path)) throw new ApiError(400, 'invalid_path', 'Invalid value path')
  return (await fetcher<ValueResponse>(path, { signal })).value
}

// A 403 may only mean the signed token expired: refetch the owning query for a fresh path and retry once.
export async function loadFullValue(expandPath: string, signal?: AbortSignal, fetcher: Fetcher = apiFetch, refresh?: RefreshOwner) {
  try {
    return await fetchValue(expandPath, signal, fetcher)
  } catch (error) {
    if (!refresh || !(error instanceof ApiError && error.status === 403)) throw error
    const fresh = findFreshPath(await refresh(), expandPath)
    if (!fresh || fresh === expandPath || signal?.aborted) throw error
    return fetchValue(fresh, signal, fetcher)
  }
}

export type ExpandState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'loaded'; value: unknown }
  | { status: 'error'; forbidden: boolean }

type Action = { type: 'load' } | { type: 'loaded'; value: unknown } | { type: 'failed'; error: unknown } | { type: 'hide' }

export function expandReducer(_: ExpandState, action: Action): ExpandState {
  switch (action.type) {
    case 'load':
      return { status: 'loading' }
    case 'loaded':
      return { status: 'loaded', value: action.value }
    case 'failed':
      return { status: 'error', forbidden: action.error instanceof ApiError && action.error.status === 403 }
    case 'hide':
      return { status: 'idle' }
  }
}

// An audited sensitive-data view: runs only from `load()` (an explicit click), is held in component state alone
// (no query cache, no storage), and is dropped on `hide()` or unmount.
export function useFullValue(expandPath: string | null | undefined, fetcher?: Fetcher) {
  const [state, dispatch] = useReducer(expandReducer, { status: 'idle' })
  const abort = useRef<AbortController>(undefined)
  const refresh = useContext(ValueRefreshContext)

  useEffect(() => () => abort.current?.abort(), [])

  const load = useCallback(() => {
    if (!expandPath) return
    abort.current?.abort()
    const controller = (abort.current = new AbortController())
    dispatch({ type: 'load' })
    loadFullValue(expandPath, controller.signal, fetcher, refresh).then(
      (value) => !controller.signal.aborted && dispatch({ type: 'loaded', value }),
      (error) => !controller.signal.aborted && dispatch({ type: 'failed', error }),
    )
  }, [expandPath, fetcher, refresh])

  const hide = useCallback(() => {
    abort.current?.abort()
    dispatch({ type: 'hide' })
  }, [])

  return { state, load, hide }
}
