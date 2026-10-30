import { describe, expect, it } from 'vitest'
import { a11yAllowed, apiAllowed, consoleAllowed, DEFAULT_ALLOWLIST, mergeAllowlists } from './allowlist.ts'
import { parseCookies } from './auth.ts'
import { parseOptions, type Options } from './options.ts'
import { scrub, stripQuery, truncate } from './sanitize.ts'

const options = (argv: string[], env: NodeJS.ProcessEnv = {}) => parseOptions(argv, env) as Options

describe('allowlist', () => {
  it('allows only a 403 api_denied by default', () => {
    expect(apiAllowed({ status: 403, code: 'api_denied', path: '/api/admin/x' }, DEFAULT_ALLOWLIST.api)).toBe(true)
    expect(apiAllowed({ status: 403, code: 'forbidden', path: '/api/admin/x' }, DEFAULT_ALLOWLIST.api)).toBe(false)
    expect(apiAllowed({ status: 404, code: 'not_found', path: '/api/admin/x' }, DEFAULT_ALLOWLIST.api)).toBe(false)
  })

  it('scopes rules by path', () => {
    const { api, a11y } = mergeAllowlists(DEFAULT_ALLOWLIST, {
      api: [{ status: 404, path: '/_options/', reason: 'empty' }],
      a11y: [{ rule: 'listitem', path: '^/sketches/', reason: 'fixture' }],
    })
    expect(apiAllowed({ status: 404, path: '/api/admin/posts/_options/lookup' }, api)).toBe(true)
    expect(apiAllowed({ status: 404, path: '/api/admin/posts/1' }, api)).toBe(false)
    expect(a11yAllowed('listitem', '/sketches/new', a11y)).toBe(true)
    expect(a11yAllowed('listitem', '/posts/new', a11y)).toBe(false)
  })

  it('matches console messages by pattern', () => {
    expect(consoleAllowed('Encountered a script tag while rendering React component. x', DEFAULT_ALLOWLIST.console)).toBe(true)
    expect(consoleAllowed('TypeError: x is undefined', DEFAULT_ALLOWLIST.console)).toBe(false)
  })
})

describe('sanitize', () => {
  it('drops query strings and, for the crawled origin, the host', () => {
    expect(stripQuery('http://localhost:5174/api/admin/posts?q[name]=Jane', 'http://localhost:5174')).toBe('/api/admin/posts')
    expect(stripQuery('https://cdn.example.com/a.js?v=1#x')).toBe('https://cdn.example.com/a.js')
  })

  it('scrubs urls inside messages and truncates', () => {
    expect(scrub('Failed https://h.test/api/p?email=a@b.c now', 200)).toBe('Failed https://h.test/api/p now')
    expect(truncate('a'.repeat(300), 20)).toHaveLength(20)
  })
})

describe('parseCookies', () => {
  it('reads one or several name=value pairs, keeping = in values', () => {
    expect(parseCookies('a=1; b=x=y')).toEqual([
      { name: 'a', value: '1' },
      { name: 'b', value: 'x=y' },
    ])
    expect(() => parseCookies('oops')).toThrow(/name=value/)
  })
})

describe('parseOptions', () => {
  it('defaults, with the base url from the environment', () => {
    expect(options([], { CRAWL_BASE_URL: 'http://h.test/' })).toMatchObject({ baseUrl: 'http://h.test', limit: 2, concurrency: 3, axe: true, screenshots: false, headed: false })
  })

  it('reads flags', () => {
    expect(options(['--resources=a,b', '--limit=5', '--screens=index,show', '--concurrency=1', '--headed', '--no-axe', '--update-baselines'])).toMatchObject({
      resources: ['a', 'b'],
      limit: 5,
      kinds: ['index', 'show'],
      concurrency: 1,
      headed: true,
      axe: false,
      screenshots: true,
      updateBaselines: true,
    })
  })

  it('rejects unknown kinds and bad numbers', () => {
    expect(() => options(['--screens=nope'])).toThrow(/unknown screen kind/)
    expect(() => options(['--limit=-1'])).toThrow(/--limit/)
  })
})
