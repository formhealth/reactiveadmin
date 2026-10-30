import { listSearch, type ListQuery } from './list'

// The CSV (or other download format) of the list as currently filtered, scoped and sorted. Paging is left out: it exports everything.
export function exportHref(resource: string, format: string, { q, scope, order }: ListQuery) {
  const params = listSearch({ q, scope, order })
  return `/api/admin/${resource}.${format}${params.size ? `?${params}` : ''}`
}
