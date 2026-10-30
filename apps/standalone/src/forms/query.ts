import type { Entry } from './params'

const flag = (value: unknown) => (value === true ? '1' : value === false ? '0' : String(value ?? ''))

// A browser's GET submit: every field is sent, blanks included, named as Rails nests them. Brackets stay readable
// in the address bar; they are legal in a query.
export function entriesToSearch(entries: Entry[]) {
  const query = new URLSearchParams()
  for (const [param, value] of entries) {
    for (const item of param.endsWith('[]') ? [value].flat() : [value]) query.append(param, flag(item))
  }
  const search = query.toString().replace(/%5B/gi, '[').replace(/%5D/gi, ']')
  return search && `?${search}`
}

// The view's own query is replaced, as submitting a GET form replaces its action's.
export function withSearch(path: string, search: string) {
  const query = search.replace(/^\?/, '')
  return query ? `${path.split('?', 1)[0]}?${query}` : path
}
