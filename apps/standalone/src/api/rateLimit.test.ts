import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const toastWarning = vi.fn()
vi.mock('sonner', () => ({ toast: { warning: (...args: unknown[]) => toastWarning(...args), error: vi.fn(), success: vi.fn() } }))

const respond = (status: number, body: unknown, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } })

const load = async () => {
  vi.resetModules()
  return { ...(await import('./fetcher')), ...(await import('./retry')) }
}

describe('rate limiting', () => {
  const fetchMock = vi.fn<typeof fetch>()

  beforeEach(() => {
    fetchMock.mockReset()
    toastWarning.mockReset()
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  describe('parseRetryAfter', () => {
    it('reads seconds and HTTP dates, rounding up to at least a second', async () => {
      const { parseRetryAfter } = await load()
      const now = Date.parse('2026-10-18T12:00:00Z')
      expect(parseRetryAfter('7')).toBe(7)
      expect(parseRetryAfter('0')).toBe(1)
      expect(parseRetryAfter('Sun, 18 Oct 2026 12:00:12 GMT', now)).toBe(12)
      expect(parseRetryAfter('soon')).toBeUndefined()
      expect(parseRetryAfter(null)).toBeUndefined()
    })
  })

  it('turns a 429 into an ApiError carrying Retry-After, and tells the operator once', async () => {
    fetchMock.mockResolvedValueOnce(respond(429, { code: 'rate_limited', message: 'Slow down' }, { 'Retry-After': '9' }))
    const { apiFetch, isRateLimited } = await load()
    const error = await apiFetch('/admin/authors').catch((e) => e)
    expect(isRateLimited(error)).toBe(true)
    expect(error).toMatchObject({ status: 429, code: 'rate_limited', retryAfter: 9 })
    expect(toastWarning).toHaveBeenCalledTimes(1)
    expect(toastWarning).toHaveBeenCalledWith("You're doing that too fast — try again in 9s", expect.objectContaining({ id: 'rate-limited' }))
  })

  it('copes with a 429 that has no header or body', async () => {
    fetchMock.mockResolvedValueOnce(new Response('', { status: 429 }))
    const { apiFetch } = await load()
    const error = await apiFetch('/admin/authors').catch((e) => e)
    expect(error).toMatchObject({ status: 429, code: 'rate_limited', retryAfter: undefined })
    expect(toastWarning).toHaveBeenCalledWith("You're doing that too fast — try again in a moment", expect.anything())
  })

  it('holds back background reads (typeahead lookups) until the wait is over', async () => {
    fetchMock.mockResolvedValueOnce(respond(429, { code: 'rate_limited', message: 'Slow down' }, { 'Retry-After': '30' }))
    const { apiFetch } = await load()
    await apiFetch('/admin/desks/_options?field=x&term=a').catch(() => undefined)
    const held = await apiFetch('/admin/desks/_options?field=x&term=ab').catch((e) => e)
    expect(held).toMatchObject({ status: 429, retryAfter: expect.any(Number) })
    expect(fetchMock).toHaveBeenCalledTimes(1)
    expect(toastWarning).toHaveBeenCalledTimes(1)
  })

  it('only holds back the endpoint that was limited', async () => {
    fetchMock.mockResolvedValueOnce(respond(429, {}, { 'Retry-After': '30' })).mockImplementation(async () => respond(200, { ok: true }))
    const { apiFetch } = await load()
    await apiFetch('/admin/desks/_options?field=x&term=a').catch(() => undefined)
    await expect(apiFetch('/admin/desks/_options/lookup?context=form&fields[x]=1')).resolves.toEqual({ ok: true })
    await expect(apiFetch('/admin/desks/_meta')).resolves.toEqual({ ok: true })
    await expect(apiFetch('/admin/_session')).resolves.toEqual({ ok: true })
    const held = await apiFetch('/admin/other/_options?field=y&term=b').catch((e) => e)
    expect(held).toMatchObject({ status: 429 })
    expect(fetchMock).toHaveBeenCalledTimes(4)
  })

  it('does not hold anything back after a limited read the operator asked for', async () => {
    fetchMock.mockResolvedValueOnce(respond(429, {}, { 'Retry-After': '30' })).mockImplementation(async () => respond(200, { ok: true }))
    const { apiFetch } = await load()
    await apiFetch('/admin/desks').catch(() => undefined)
    await expect(apiFetch('/admin/desks/_options?field=x&term=a')).resolves.toEqual({ ok: true })
    await expect(apiFetch('/admin/desks/_meta')).resolves.toEqual({ ok: true })
  })

  it('lets reads the operator asked for through', async () => {
    fetchMock.mockResolvedValueOnce(respond(429, {}, { 'Retry-After': '30' })).mockResolvedValueOnce(respond(200, { ok: true }))
    const { apiFetch } = await load()
    await apiFetch('/admin/desks/_options?term=a').catch(() => undefined)
    await expect(apiFetch('/admin/desks')).resolves.toEqual({ ok: true })
  })

  describe('query retries', () => {
    it('retries a 429 once, after the Retry-After wait', async () => {
      const { ApiError, retryQuery, retryDelay } = await load()
      const limited = new ApiError(429, 'rate_limited', undefined, undefined, 8)
      expect(retryQuery(0, limited)).toBe(true)
      expect(retryQuery(1, limited)).toBe(false)
      expect(retryDelay(0, limited)).toBe(8000)
    })

    it('does not retry when the wait is long', async () => {
      const { ApiError, retryQuery } = await load()
      expect(retryQuery(0, new ApiError(429, 'rate_limited', undefined, undefined, 120))).toBe(false)
    })

    it('keeps the previous policy for everything else', async () => {
      const { ApiError, retryQuery, retryDelay } = await load()
      expect(retryQuery(0, new ApiError(404))).toBe(false)
      expect(retryQuery(0, new ApiError(409, 'stale'))).toBe(false)
      expect(retryQuery(1, new ApiError(500))).toBe(true)
      expect(retryQuery(2, new ApiError(500))).toBe(false)
      expect(retryQuery(1, new TypeError('network'))).toBe(true)
      expect(retryDelay(2, new ApiError(500))).toBe(4000)
    })
  })
})
