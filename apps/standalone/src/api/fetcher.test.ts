import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

const load = async () => {
  vi.resetModules()
  return import('./fetcher')
}

describe('apiFetch', () => {
  const fetchMock = vi.fn<typeof fetch>()

  beforeEach(() => {
    fetchMock.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  const headersOf = (call: number) => fetchMock.mock.calls[call][1]?.headers as Record<string, string>

  it('does not fetch a token for reads', async () => {
    fetchMock.mockResolvedValueOnce(json(200, { ok: 1 }))
    const { apiFetch } = await load()
    await apiFetch('/admin/posts')
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(fetchMock.mock.calls[0][0]).toBe('/api/admin/posts')
    expect(headersOf(0)).not.toHaveProperty('X-CSRF-Token')
  })

  it('sends the session token on writes and reuses it', async () => {
    fetchMock.mockResolvedValueOnce(json(200, { csrf_token: 't1' })).mockResolvedValue(json(200, { ok: true }))
    const { apiFetch } = await load()
    await apiFetch('/admin/desks', { method: 'POST' })
    await apiFetch('/admin/desks', { method: 'POST' })
    expect(fetchMock.mock.calls.map(([url]) => url)).toEqual(['/api/admin/_session', '/api/admin/desks', '/api/admin/desks'])
    expect(headersOf(1)['X-CSRF-Token']).toBe('t1')
    expect(headersOf(2)['X-CSRF-Token']).toBe('t1')
  })

  it('does not double-prefix paths that already include the mount', async () => {
    fetchMock.mockResolvedValueOnce(json(200, {}))
    const { apiFetch } = await load()
    await apiFetch('/api/admin/desks/1/edit')
    expect(fetchMock.mock.calls[0][0]).toBe('/api/admin/desks/1/edit')
  })

  it('refetches the session and retries once on invalid_csrf', async () => {
    fetchMock
      .mockResolvedValueOnce(json(200, { csrf_token: 'stale' }))
      .mockResolvedValueOnce(json(422, { code: 'invalid_csrf', message: 'expired' }))
      .mockResolvedValueOnce(json(200, { csrf_token: 'fresh' }))
      .mockResolvedValueOnce(json(200, { ok: true }))
    const { apiFetch } = await load()
    await expect(apiFetch('/admin/desks', { method: 'POST' })).resolves.toEqual({ ok: true })
    expect(headersOf(3)['X-CSRF-Token']).toBe('fresh')
  })

  it('gives up after one retry', async () => {
    fetchMock.mockImplementation(async (url) => (String(url).endsWith('_session') ? json(200, { csrf_token: 'x' }) : json(422, { code: 'invalid_csrf', message: 'expired' })))
    const { apiFetch, ApiError } = await load()
    await expect(apiFetch('/admin/desks', { method: 'POST' })).rejects.toBeInstanceOf(ApiError)
    expect(fetchMock.mock.calls.filter(([url]) => url === '/api/admin/desks')).toHaveLength(2)
  })

  it('exposes validation errors on ApiError', async () => {
    fetchMock
      .mockResolvedValueOnce(json(200, { csrf_token: 't' }))
      .mockResolvedValueOnce(json(422, { code: 'invalid', message: 'Review failed', errors: { name: ["can't be blank"] }, base: ['Nope'] }))
    const { apiFetch } = await load()
    const error = await apiFetch('/admin/desks', { method: 'POST' }).catch((e) => e)
    expect(error).toMatchObject({ status: 422, code: 'invalid', body: { errors: { name: ["can't be blank"] }, base: ['Nope'] } })
  })

  it('carries Retry-After on a retry 409 and tells it apart from stale', async () => {
    fetchMock
      .mockResolvedValueOnce(json(200, { csrf_token: 't' }))
      .mockResolvedValueOnce(new Response(JSON.stringify({ code: 'retry', message: 'busy' }), { status: 409, headers: { 'Retry-After': '1' } }))
      .mockResolvedValueOnce(json(409, { code: 'stale', message: 'changed' }))
    const { apiFetch, isRetry, isStale } = await load()
    const busy = await apiFetch('/admin/desks/1', { method: 'PATCH' }).catch((e) => e)
    expect(busy).toMatchObject({ status: 409, code: 'retry', retryAfter: 1 })
    expect([isRetry(busy), isStale(busy)]).toEqual([true, false])
    const changed = await apiFetch('/admin/desks/1', { method: 'PATCH' }).catch((e) => e)
    expect([isRetry(changed), isStale(changed)]).toEqual([false, true])
  })

  describe('background reads', () => {
    const marked = (call: number) => headersOf(call)['X-Reactiveadmin-Background']

    it.each(['/admin/authors/_meta', '/admin/authors/_options?field=x&context=form&term=ab', '/admin/_session', '/admin/_manifest', '/admin/authors/4/desks/_options?field=x', '/admin/authors/_labels?ids=1,2'])(
      'marks %s',
      async (url) => {
        fetchMock.mockResolvedValueOnce(json(200, {}))
        const { apiFetch } = await load()
        await apiFetch(url)
        expect(marked(0)).toBe('1')
      },
    )

    it.each(['/admin/authors', '/admin/authors?q[name_cont]=_meta', '/admin/authors/7', '/admin/authors/7/edit', '/admin/authors/7/_value?field=x', '/admin/authors.csv', '/admin/_pages/batch_operations'])('leaves the page load %s alone', async (url) => {
      fetchMock.mockResolvedValueOnce(json(200, {}))
      const { apiFetch } = await load()
      await apiFetch(url)
      expect(headersOf(0)).not.toHaveProperty('X-Reactiveadmin-Background')
    })

    it('never marks writes, even to a background-looking path', async () => {
      fetchMock.mockResolvedValueOnce(json(200, { csrf_token: 't' })).mockResolvedValueOnce(json(200, {}))
      const { apiFetch } = await load()
      await apiFetch('/admin/authors/_options', { method: 'POST' })
      expect(marked(1)).toBeUndefined()
    })

    it('marks the session read that supplies the CSRF token', async () => {
      fetchMock.mockResolvedValueOnce(json(200, { csrf_token: 't' })).mockResolvedValueOnce(json(200, {}))
      const { apiFetch } = await load()
      await apiFetch('/admin/desks', { method: 'POST' })
      expect(marked(0)).toBe('1')
      expect(marked(1)).toBeUndefined()
    })
  })

  it('drops the persisted client state on a 401', async () => {
    const { stubLocalStorage } = await import('@/test/memoryStorage')
    const store = stubLocalStorage()
    store.set('ra:recent', '[]')
    store.set('theme', 'dark')
    fetchMock.mockResolvedValueOnce(json(401, { code: 'unauthorized', message: 'Sign in' }))
    const { apiFetch } = await load()
    await expect(apiFetch('/admin/authors')).rejects.toMatchObject({ status: 401 })
    expect([...store.keys()]).toEqual(['theme'])
  })
})
