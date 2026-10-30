import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const respond = (body: unknown, status = 200) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })
const opt = (value: string) => ({ label: `Label ${value}`, value })

const load = async (options?: { cache?: boolean }) => {
  vi.resetModules()
  const { createOptionLookup } = await import('./optionLookup')
  return createOptionLookup(options)
}

const PATH = (field: string, extra = '') => `/api/admin/posts/_options?field=${field}&context=form${extra}`

describe('option lookup', () => {
  const fetchMock = vi.fn<typeof fetch>()
  const urls = () => fetchMock.mock.calls.map(([url]) => new URL(String(url), 'http://local'))
  const wanted = (url: URL) =>
    Object.fromEntries([...url.searchParams].filter(([key]) => key.startsWith('fields[')).map(([key, v]) => [key.slice(7, -1), v.split(',')]))

  beforeEach(() => {
    fetchMock.mockReset()
    fetchMock.mockImplementation(async (url) => {
      const fields = wanted(new URL(String(url), 'http://local'))
      return respond({ lookups: Object.fromEntries(Object.entries(fields).map(([field, values]) => [field, values.map(opt)])) })
    })
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  it('answers every field of a form with one request', async () => {
    const lookup = await load()
    const [author, category, tags] = await Promise.all([
      lookup.load(PATH('author', '&id=7'), ['1']),
      lookup.load(PATH('category', '&id=7'), ['2']),
      lookup.load(PATH('tags', '&id=7'), ['3', '4']),
    ])
    expect(fetchMock).toHaveBeenCalledTimes(1)
    const [url] = urls()
    expect(url.pathname).toBe('/api/admin/posts/_options/lookup')
    expect(url.searchParams.get('context')).toBe('form')
    expect(url.searchParams.get('id')).toBe('7')
    expect(wanted(url)).toEqual({ author: ['1'], category: ['2'], tags: ['3', '4'] })
    expect([author, category, tags].map((o) => o.map((x) => x.value))).toEqual([['1'], ['2'], ['3', '4']])
  })

  it('merges repeated values of a field and leaves out what was not found', async () => {
    fetchMock.mockImplementation(async () => respond({ lookups: { author: [opt('1')] } }))
    const lookup = await load()
    const [a, b] = await Promise.all([lookup.load(PATH('author'), ['1', '9']), lookup.load(PATH('author'), ['1'])])
    expect(wanted(urls()[0])).toEqual({ author: ['1', '9'] })
    expect(a).toEqual([opt('1')])
    expect(b).toEqual([opt('1')])
  })

  it('keeps answers per resource, field and value, including values that matched nothing', async () => {
    fetchMock.mockImplementation(async () => respond({ lookups: { author: [opt('1')] } }))
    const lookup = await load()
    await lookup.load(PATH('author'), ['1', '9'])
    await expect(lookup.load(PATH('author'), ['1', '9'])).resolves.toEqual([opt('1')])
    expect(fetchMock).toHaveBeenCalledTimes(1)
    await lookup.load(PATH('category'), ['1'])
    expect(fetchMock).toHaveBeenCalledTimes(2)
  })

  it('asks again after a reset or when not caching', async () => {
    const lookup = await load()
    await lookup.load(PATH('author'), ['1'])
    lookup.reset()
    await lookup.load(PATH('author'), ['1'])
    const plain = await load({ cache: false })
    await plain.load(PATH('author'), ['1'])
    await plain.load(PATH('author'), ['1'])
    expect(fetchMock).toHaveBeenCalledTimes(4)
  })

  it('keeps each resource and form record in its own request', async () => {
    const lookup = await load()
    await Promise.all([
      lookup.load(PATH('author'), ['1']),
      lookup.load('/api/admin/comments/_options?field=post&context=filter', ['2']),
      lookup.load(PATH('author', '&id=3'), ['4']),
    ])
    expect(fetchMock).toHaveBeenCalledTimes(3)
  })

  it('splits what the server would refuse: 25 values per field, 100 in total', async () => {
    const values = (from: number, count: number) => Array.from({ length: count }, (_, i) => String(from + i))
    const lookup = await load()
    await Promise.all([
      lookup.load(PATH('a'), values(0, 60)),
      lookup.load(PATH('b'), values(100, 25)),
      lookup.load(PATH('c'), values(200, 25)),
      lookup.load(PATH('d'), values(300, 25)),
    ])
    const requests = urls().map(wanted)
    for (const request of requests) {
      expect(Object.values(request).every((v) => v.length <= 25)).toBe(true)
      expect(Object.values(request).flat().length).toBeLessThanOrEqual(100)
    }
    expect(requests.flatMap((r) => r.a)).toHaveLength(60)
    expect(new Set(requests.flatMap((r) => Object.values(r).flat())).size).toBe(135)
  })

  it('rejects every waiter when the request fails, and leaves nothing cached', async () => {
    fetchMock.mockResolvedValueOnce(respond({ code: 'server_error' }, 500))
    const lookup = await load()
    const results = await Promise.allSettled([lookup.load(PATH('a'), ['1']), lookup.load(PATH('b'), ['1'])])
    expect(results.map((r) => r.status)).toEqual(['rejected', 'rejected'])
    expect(fetchMock).toHaveBeenCalledTimes(1)
    await expect(lookup.load(PATH('a'), ['1'])).resolves.toEqual([opt('1')])
  })

  it('does not ask while the lookup endpoint is rate limited', async () => {
    fetchMock.mockResolvedValueOnce(respond({ code: 'rate_limited' }, 429))
    const lookup = await load()
    await expect(lookup.load(PATH('a'), ['1'])).rejects.toMatchObject({ status: 429 })
    await expect(lookup.load(PATH('b'), ['1'])).rejects.toMatchObject({ status: 429 })
    expect(fetchMock).toHaveBeenCalledTimes(1)
  })

  it('asks a path it cannot batch directly, within the value cap', async () => {
    fetchMock.mockImplementation(async () => respond({ options: [], truncated: false }))
    const lookup = await load()
    await lookup.load('/api/admin/desks/new?context=template&field=x', Array.from({ length: 30 }, (_, i) => String(i)))
    const calls = urls()
    expect(calls).toHaveLength(2)
    expect(calls.map((u) => u.searchParams.get('value')!.split(',').length)).toEqual([25, 5])
  })
})
