import { apiFetch } from '@/api/fetcher'
import type { LookupResponse, Option, OptionsResponse } from '@/api/generated/model'

// Server caps: values per field and per request.
const MAX_PER_FIELD = 25
const MAX_TOTAL = 100
const BATCH_DELAY = 0

const OPTIONS_PATH = /^(.*\/_options)$/

const chunk = <T>(items: T[], size: number) => Array.from({ length: Math.ceil(items.length / size) }, (_, i) => items.slice(i * size, (i + 1) * size))

// `<mount>/<resource>/_options?field=&context=&id=` becomes the batch endpoint and the field it asks about.
const parse = (path: string) => {
  const url = new URL(path, 'http://local')
  const base = OPTIONS_PATH.exec(url.pathname)?.[1]
  const field = url.searchParams.get('field')
  if (!base || !field) return undefined
  const query = new URLSearchParams()
  for (const key of ['context', 'id']) if (url.searchParams.has(key)) query.set(key, url.searchParams.get(key)!)
  return { group: `${base}/lookup?${query}`, field }
}

type Group = { fields: Map<string, Set<string>>; done: Promise<Map<string, Option>> }

// Labels for selected values. Lookups asked for in the same moment (every typeahead of a form mounting) share
// one `_options/lookup` request per resource; answers are kept per (resource, field, value) while `cache` is on.
export function createOptionLookup({ cache = true } = {}) {
  const known = new Map<string, Option | null>()
  let pending = new Map<string, Group>()
  const keyOf = (group: string, field: string, value: string) => [group, field, value].join('\0')

  const send = async (group: string, wanted: Record<string, string[]>) => {
    const query = new URLSearchParams(group.split('?')[1])
    for (const [field, values] of Object.entries(wanted)) query.set(`fields[${field}]`, values.join(','))
    const { lookups } = await apiFetch<LookupResponse>(`${group.split('?')[0]}?${query}`)
    return lookups
  }

  const flush = async (group: string, fields: Map<string, Set<string>>) => {
    const pieces = [...fields].flatMap(([field, values]) => chunk([...values], MAX_PER_FIELD).map((vals) => [field, vals] as const))
    const requests: Record<string, string[]>[] = []
    const total = (request: Record<string, string[]>) => Object.values(request).reduce((sum, vals) => sum + vals.length, 0)
    for (const [field, vals] of pieces) {
      let request = requests.find((r) => !(field in r) && total(r) + vals.length <= MAX_TOTAL)
      if (!request) requests.push((request = {}))
      request[field] = vals
    }
    const found = new Map<string, Option>()
    for (const lookups of await Promise.all(requests.map((wanted) => send(group, wanted)))) {
      for (const [field, options] of Object.entries(lookups)) options.forEach((o) => found.set(keyOf(group, field, o.value), o))
    }
    if (cache) for (const [field, values] of fields) values.forEach((v) => known.set(keyOf(group, field, v), found.get(keyOf(group, field, v)) ?? null))
    return found
  }

  const enqueue = (group: string, field: string, values: string[]) => {
    let entry = pending.get(group)
    if (!entry) {
      const fields = new Map<string, Set<string>>()
      const done = new Promise<Map<string, Option>>((resolve, reject) => {
        setTimeout(() => {
          pending.delete(group)
          flush(group, fields).then(resolve, reject)
        }, BATCH_DELAY)
      })
      done.catch(() => undefined)
      entry = { fields, done }
      pending.set(group, entry)
    }
    entry.fields.set(field, new Set([...(entry.fields.get(field) ?? []), ...values]))
    return entry.done
  }

  // Options for `values` of the field `path` (an `_options` URL) serves; values that match nothing are left out.
  const load = async (path: string, values: string[]): Promise<Option[]> => {
    const target = parse(path)
    if (!target) return loadEach(path, values)

    const { group, field } = target
    const unknown = values.filter((v) => !known.has(keyOf(group, field, v)))
    const found = unknown.length ? await enqueue(group, field, unknown) : new Map<string, Option>()
    return values.flatMap((v) => known.get(keyOf(group, field, v)) ?? found.get(keyOf(group, field, v)) ?? [])
  }

  // Paths this can't batch (a template form's own action) are asked directly, within the server's value cap.
  const loadEach = async (path: string, values: string[]) => {
    const pages = await Promise.all(chunk(values, MAX_PER_FIELD).map((vals) => apiFetch<OptionsResponse>(`${path}${path.includes('?') ? '&' : '?'}${new URLSearchParams({ value: vals.join(',') })}`)))
    return pages.flatMap((page) => page.options)
  }

  const reset = () => {
    known.clear()
    pending = new Map()
  }

  return { load, reset }
}

export type OptionLookup = ReturnType<typeof createOptionLookup>

// Without a form around it (filters) lookups are still batched, but nothing is kept.
export const sharedOptionLookup = createOptionLookup({ cache: false })
