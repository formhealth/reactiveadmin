import { afterEach, describe, expect, it, vi } from 'vitest'

const DEMO_ADMIN = '/reactiveadmin/demo/admin'

const strings = (value: unknown): string[] =>
  typeof value === 'string' ? [value] : value && typeof value === 'object' ? Object.values(value).flatMap(strings) : []

describe('mocks under a moved admin path', () => {
  afterEach(() => {
    vi.unstubAllEnvs()
    vi.resetModules()
  })

  const load = async () => {
    vi.stubEnv('VITE_ADMIN_PATH', DEMO_ADMIN)
    vi.resetModules()
    const [fixtures, forms, domain, authors, handlers] = await Promise.all([import('./fixtures'), import('./forms'), import('./domain'), import('./authors'), import('./handlers')])
    return { fixtures, forms, domain, authors, handlers }
  }

  it('keeps API paths at /api/admin and browser hrefs under the admin path', async () => {
    const { fixtures, forms, domain, authors } = await load()
    const post = fixtures.posts[0]
    const emitted = strings([
      fixtures.postActions(post),
      fixtures.postRowActions(post),
      fixtures.resourceSummaries,
      forms.postForm(post),
      forms.rescheduleForm(post),
      forms.deskForm(),
      domain.pages,
      authors.authorActions('a1', 'header'),
    ])

    const apiPaths = emitted.filter((s) => s.startsWith('/api'))
    expect(apiPaths.length).toBeGreaterThan(20)
    expect(apiPaths.filter((s) => !s.startsWith('/api/admin/'))).toEqual([])
    expect(emitted.filter((s) => /^\/admin(\/|$)/.test(s))).toEqual([])
  })

  it('serves every handler from /api/admin or the admin path', async () => {
    const { handlers } = await load()
    const paths = handlers.handlers.map((h) => String(h.info.path).replaceAll('\\', ''))

    expect(paths.filter((p) => !p.includes('/api/admin') && !p.startsWith(DEMO_ADMIN))).toEqual([])
  })
})
