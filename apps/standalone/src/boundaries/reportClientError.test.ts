import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'

const json = (status: number, body: unknown, headers: Record<string, string> = {}) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json', ...headers } })

const load = async () => {
  vi.resetModules()
  const reporter = await import('./reportClientError')
  const { routes } = await import('@/routes')
  reporter.registerRoutes(routes)
  return reporter
}

const stack = `
    at Pill (https://admin.example/assets/index-abc.js:1:2)
    at div
    at ResourceShow (https://admin.example/assets/index-abc.js:3:4)
    at <anonymous>
Table@https://admin.example/assets/index-abc.js:5:6
    at Not-A-Name (https://admin.example/assets/index-abc.js:7:8)`

describe('componentNames', () => {
  it('keeps names from V8 and Firefox stacks, and drops urls and anything that is not an identifier', async () => {
    const { componentNames } = await load()

    expect(componentNames(stack)).toEqual(['Pill', 'div', 'ResourceShow', 'Table'])
  })

  it('caps the list and tolerates no stack', async () => {
    const { componentNames } = await load()

    expect(componentNames(Array.from({ length: 50 }, (_, i) => `    at C${i} (x)`).join('\n'))).toHaveLength(20)
    expect(componentNames(undefined)).toEqual([])
  })
})

describe('routeOf', () => {
  it.each([
    ['/authors', '/:resource', 'authors'],
    ['/authors/42/edit', '/:resource/:id/edit', 'authors'],
    ['/authors/new', '/:resource/new', 'authors'],
    ['/authors/42/actions/archive', '/:resource/:id/actions/:key', 'authors'],
    ['/groups/people/staff', '/groups/*', undefined],
  ])('names %s by its pattern, with no ids', async (pathname, route, resource) => {
    const { routeOf } = await load()

    expect(routeOf(pathname)).toEqual({ route, resource })
  })

  it('gives the catch-all for an address the client lacks', async () => {
    const { routeOf } = await load()

    expect(routeOf('/a/b/c/d')).toEqual({ route: '/*', resource: undefined })
  })
})

describe('buildReport', () => {
  it('holds names only: no url, no query, no message', async () => {
    const { buildReport } = await load()
    const report = buildReport({ where: 'route', name: 'TypeError', componentStack: stack }, '/patients/8123/edit', 'req-1')

    expect(report).toEqual({
      error_name: 'TypeError',
      boundary: 'route',
      components: ['Pill', 'div', 'ResourceShow', 'Table'],
      route: '/:resource/:id/edit',
      resource: 'patients',
      client_version: expect.any(String),
      request_id: 'req-1',
    })
    expect(JSON.stringify(report)).not.toContain('8123')
  })

  it('replaces a name that is not an identifier, since a name is the one free-text field', async () => {
    const { buildReport } = await load()

    expect(buildReport({ where: 'app', name: 'Failed for jane@example.com' }, '/', undefined).error_name).toBe('Error')
  })
})

describe('reportClientError', () => {
  const fetchMock = vi.fn<typeof fetch>()
  const posts = () => fetchMock.mock.calls.filter(([url]) => String(url).endsWith('_client_errors'))
  const flush = () => new Promise((resolve) => setTimeout(resolve))

  beforeEach(() => {
    fetchMock.mockReset()
    fetchMock.mockImplementation(async (url) => (String(url).endsWith('_session') ? json(200, { csrf_token: 't1', ui: { available: true, default: 'classic', client_errors: true } }) : new Response(null, { status: 204 })))
    vi.stubGlobal('fetch', fetchMock)
    vi.stubGlobal('location', { pathname: '/authors/9', search: '?q[name_eq]=Jane' })
  })
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.unstubAllEnvs()
  })

  it('posts a scrubbed report with the session token in production', async () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    const { reportClientError } = await load()
    reportClientError({ where: 'node:text', name: 'RangeError', componentStack: stack })
    await flush()

    const [, sessionInit] = fetchMock.mock.calls.find(([u]) => String(u).endsWith('_session'))!
    expect(sessionInit?.headers).toMatchObject({ 'X-Reactiveadmin-Background': '1' })
    const [url, init] = posts()[0]
    expect(url).toBe('/api/admin/_client_errors')
    expect(init?.headers).toMatchObject({ 'X-CSRF-Token': 't1' })
    const body = JSON.parse(String(init?.body))
    expect(body).toMatchObject({ error_name: 'RangeError', boundary: 'node:text', route: '/:resource/:id', resource: 'authors' })
    expect(JSON.stringify(body)).not.toMatch(/Jane|name_eq|\/9/)
  })

  it('reports each distinct failure once, and no more than a handful per page', async () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    const { reportClientError } = await load()
    for (let i = 0; i < 3; i++) reportClientError({ where: 'route', name: 'TypeError' })
    for (let i = 0; i < 10; i++) reportClientError({ where: `node:t${i}`, name: 'TypeError' })
    await flush()

    expect(posts()).toHaveLength(5)
  })

  it('reports the same failure on another resource, which shares a route pattern', async () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    const { reportClientError } = await load()
    vi.stubGlobal('location', { pathname: '/posts/1/edit' })
    reportClientError({ where: 'route', name: 'TypeError' })
    vi.stubGlobal('location', { pathname: '/authors/2/edit' })
    reportClientError({ where: 'route', name: 'TypeError' })
    await flush()

    expect(posts().map(([, init]) => JSON.parse(String(init?.body)).resource)).toEqual(['posts', 'authors'])
  })

  it('refreshes a stale session token and retries once', async () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    let token = 0
    const tokenOf = (init?: RequestInit) => new Headers(init?.headers).get('X-CSRF-Token')
    fetchMock.mockImplementation(async (url, init) => {
      if (String(url).endsWith('_session')) return json(200, { csrf_token: `t${++token}`, ui: { available: true, default: 'classic', client_errors: true } })
      return tokenOf(init) === 't1' ? json(422, { code: 'invalid_csrf' }) : new Response(null, { status: 204 })
    })
    const { reportClientError } = await load()
    reportClientError({ where: 'route', name: 'TypeError' })
    await flush()

    expect(posts().map(([, init]) => tokenOf(init))).toEqual(['t1', 't2'])
  })

  it.each([401, 429])("doesn't clear client storage or toast when the session read answers %i", async (status) => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    const cleared = vi.fn()
    const toasted = vi.fn()
    vi.doMock('@/lib/storage', async (original) => ({ ...(await original<object>()), clearClientStorage: cleared }))
    vi.doMock('@/lib/rateLimit', async (original) => ({ ...(await original<object>()), toastRateLimited: toasted }))
    fetchMock.mockImplementation(async (url) => (String(url).endsWith('_session') ? json(status, { code: 'nope' }) : json(422, { code: 'invalid_csrf' })))
    try {
      const { reportClientError } = await load()
      reportClientError({ where: 'route', name: 'TypeError' })
      await flush()

      expect(posts()).toHaveLength(2)
      expect(cleared).not.toHaveBeenCalled()
      expect(toasted).not.toHaveBeenCalled()
    } finally {
      vi.doUnmock('@/lib/storage')
      vi.doUnmock('@/lib/rateLimit')
    }
  })

  it('sends nothing when the host turned client errors off', async () => {
    vi.stubEnv('PROD', true)
    vi.stubEnv('DEV', false)
    fetchMock.mockImplementation(async (url) =>
      String(url).endsWith('_session') ? json(200, { csrf_token: 't1', ui: { available: true, default: 'classic', client_errors: false } }) : new Response(null, { status: 204 }),
    )
    const { reportClientError } = await load()
    reportClientError({ where: 'route', name: 'TypeError' })
    await flush()

    expect(posts()).toHaveLength(0)
  })

  it('sends nothing outside production, and never lets a failed report throw', async () => {
    const { reportClientError } = await load()
    vi.spyOn(console, 'error').mockImplementation(() => {})
    reportClientError({ where: 'route', name: 'TypeError' })
    await flush()
    expect(fetchMock).not.toHaveBeenCalled()

    vi.stubEnv('PROD', true)
    fetchMock.mockRejectedValue(new Error('offline'))
    expect(() => reportClientError({ where: 'app', name: 'TypeError' })).not.toThrow()
    await flush()
  })
})
