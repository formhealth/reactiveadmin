import { useCallback, useMemo } from 'react'
import { useSearchParams } from 'react-router'
import type { ListQuery, Query } from '@/lib/list'

const Q_KEY = /^q\[([^\]]+)\](\[\])?$/

export type QChanges = Record<string, string | string[] | undefined>

// The URL search params are the single source of truth for list state.
export function useListState() {
  const [sp, setSp] = useSearchParams()

  const state = useMemo(() => {
    const q: Query = {}
    sp.forEach((value, key) => {
      const [, param, many] = Q_KEY.exec(key) ?? []
      if (!param || !value) return
      q[param] = many ? [...(Array.isArray(q[param]) ? q[param] : []), value] : value
    })
    const num = (key: string) => Number(sp.get(key)) || undefined
    return { q, scope: sp.get('scope') ?? undefined, order: sp.get('order') ?? undefined, page: num('page'), perPage: num('per_page'), as: sp.get('as') ?? undefined }
  }, [sp])

  const update = useCallback(
    (fn: (next: URLSearchParams) => void, { replace = false, resetPage = true, state }: { replace?: boolean; resetPage?: boolean; state?: unknown } = {}) =>
      setSp(
        (prev) => {
          const next = new URLSearchParams(prev)
          fn(next)
          if (resetPage) next.delete('page')
          return next
        },
        { replace, state },
      ),
    [setSp],
  )

  const setQ = useCallback(
    (changes: QChanges, replace = false) =>
      update((next) => {
        for (const [param, value] of Object.entries(changes)) {
          next.delete(`q[${param}]`)
          next.delete(`q[${param}][]`)
          if (Array.isArray(value)) value.forEach((v) => next.append(`q[${param}][]`, v))
          else if (value) next.set(`q[${param}]`, value)
        }
      }, { replace }),
    [update],
  )

  // Keys the resource doesn't declare would only draw a 400, so they are taken off the URL.
  const dropKeys = useCallback(
    (params: string[]) =>
      update(
        (next) => {
          for (const param of params) {
            next.delete(`q[${param}]`)
            next.delete(`q[${param}][]`)
          }
        },
        { replace: true, resetPage: false, state: { dropped: params } },
      ),
    [update],
  )

  const setParam = useCallback(
    (key: string, value: string | number | undefined, resetPage = true) =>
      update((next) => (value === undefined ? next.delete(key) : next.set(key, String(value))), { resetPage }),
    [update],
  )

  const clearFilters = useCallback(
    () =>
      update((next) => {
        for (const key of [...next.keys()]) if (Q_KEY.test(key)) next.delete(key)
      }),
    [update],
  )

  const params: ListQuery = {
    q: state.q,
    scope: state.scope,
    order: state.order,
    page: state.page,
    per_page: state.perPage,
    as: state.as,
  }

  return { ...state, params, setQ, setParam, clearFilters, dropKeys }
}
