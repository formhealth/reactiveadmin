import type { Filter } from '@/api/generated/model'

// Ransack predicates by param. Multi-valued predicates (`..._in`) travel as `q[param][]=a&q[param][]=b`.
export type Query = Record<string, string | string[]>

export type ListQuery = { q?: Query; scope?: string; order?: string; page?: number; per_page?: number; as?: string }

export const asList = (value?: string | string[]) => (Array.isArray(value) ? value : value ? [value] : [])

export const asText = (value?: string | string[]) => (Array.isArray(value) ? value.join(', ') : (value ?? ''))

export function listSearch({ q = {}, scope, order, page, per_page, as }: ListQuery) {
  const params = new URLSearchParams()
  for (const [param, value] of Object.entries(q)) {
    if (Array.isArray(value)) value.forEach((v) => params.append(`q[${param}][]`, v))
    else params.set(`q[${param}]`, value)
  }
  const rest = { scope, order, page, per_page, as }
  for (const [key, value] of Object.entries(rest)) if (value !== undefined && value !== '') params.set(key, String(value))
  return params
}

export const listUrl = (resource: string, query: ListQuery) => {
  const search = listSearch(query).toString()
  return `/admin/${resource}${search && `?${search}`}`
}

// The ransack params a resource declares; the server answers 400 to any other `q[...]` key.
export function declaredParams(filters: Filter[] = []) {
  const declared = new Set<string>()
  for (const filter of filters) {
    if (filter.param) declared.add(filter.param)
    filter.predicates?.forEach((p) => declared.add(p.param))
    if (filter.range) {
      declared.add(filter.range.from)
      declared.add(filter.range.to)
    }
    if (!filter.param && !filter.predicates?.length && !filter.range) declared.add(filter.name)
  }
  return declared
}

export const undeclared = (q: Query, filters?: Filter[]) => {
  const declared = declaredParams(filters)
  return Object.keys(q).filter((param) => !declared.has(param))
}
