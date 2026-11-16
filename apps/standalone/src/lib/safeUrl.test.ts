import { describe, expect, it } from 'vitest'
import type { Action, FormResponse } from '@/api/generated/model'
import { safeAction, safeEmbedSrc, safeFormAction, safeFrameWrite, safeHref } from './safeUrl'

const from = 'https://app.test/admin'

describe('safeEmbedSrc', () => {
  it('keeps same-origin pages and forces the chrome-free embed', () => {
    expect(safeEmbedSrc('/admin/posts/1?embed=1', from)).toBe('/admin/posts/1?embed=1')
    expect(safeEmbedSrc('/admin/posts/1', from)).toBe('/admin/posts/1?embed=1')
    expect(safeEmbedSrc('https://app.test/admin/posts/1', from)).toBe('/admin/posts/1?embed=1')
  })

  it.each([
    '/rails/active_storage/blobs/x/evil.html',
    '/uploads/evil.html',
    '/administrator',
    '/admin/../uploads/evil.html',
    '/admin/%2e%2e/uploads/evil.html',
    'https://evil.example/admin/posts/1',
    'https://evil.example/phish',
    '//evil.example/x',
    'javascript:alert(1)',
    'data:text/html,<script>alert(1)</script>',
    'blob:https://app.test/x',
    '',
    undefined,
    null,
  ])('rejects %s', (src) => expect(safeEmbedSrc(src, from)).toBeUndefined())
})

describe('safeHref', () => {
  it('allows same-origin admin paths', () => {
    expect(safeHref('/admin/authors/1', false, from)).toBe('/admin/authors/1')
    expect(safeHref('/admin', false, from)).toBe('/admin')
    expect(safeHref('https://app.test/admin/x?y=1', undefined, from)).toBe('https://app.test/admin/x?y=1')
  })

  it.each(['/elsewhere', '/administrator', 'https://evil.example/admin/x', '//evil.example/admin', 'javascript:alert(1)', 'data:text/html,x', ' javascript:alert(1)', 'JaVaScRiPt:alert(1)'])(
    'rejects %s as an internal link',
    (href) => expect(safeHref(href, false, from)).toBeUndefined(),
  )

  it('allows http(s), mailto and tel only when marked external', () => {
    for (const href of ['https://example.org/x', 'http://example.org', 'mailto:a@b.co', 'tel:123']) {
      expect(safeHref(href, true, from)).toBe(href)
      expect(safeHref(href, false, from)).toBeUndefined()
    }
  })

  it('allows an absolute link to a non-admin path of the API origin when the app runs on another origin', () => {
    const dev = 'http://localhost:5174/admin/authors'
    const href = 'http://localhost:3003/sidekiq/retries?substr=Foo'

    expect(safeHref(href, true, dev)).toBe(href)
    expect(safeHref(href, false, dev)).toBeUndefined()
    expect(safeAction({ key: 'sidekiq', label: 'Sidekiq Dashboard', kind: 'link', enabled: true, href: 'http://localhost:3003/sidekiq', external: true }, dev)).toBe(true)
  })

  it.each(['javascript:alert(1)', 'JAVASCRIPT:alert(1)', 'data:text/html,x', 'vbscript:x', 'blob:https://app.test/x', 'file:///etc/passwd', '', null, undefined])(
    'rejects %s even when marked external',
    (href) => expect(safeHref(href, true, from)).toBeUndefined(),
  )
})

describe('safeAction', () => {
  const action = (extra: Partial<Action>): Action => ({ key: 'x', label: 'X', kind: 'member', enabled: true, ...extra })

  it('accepts same-origin targets and explicit external links', () => {
    expect(safeAction(action({ api_path: '/api/admin/posts/1/publish', method: 'post', href: '/admin/posts/1/publish' }), from)).toBe(true)
    expect(safeAction(action({ href: 'https://example.org', external: true }), from)).toBe(true)
  })

  it.each([
    { api_path: 'https://evil.example/api' },
    { form_path: '//evil.example/f' },
    { href: 'javascript:alert(1)' },
    { href: 'https://evil.example/x' },
    { href: 'javascript:alert(1)', external: true },
    { view: { mode: 'iframe', path: 'https://evil.example/p' } },
  ] as Partial<Action>[])('rejects %o', (extra) => expect(safeAction(action(extra), from)).toBe(false))
})

describe('safeFormAction', () => {
  const form = (path: string, options_path?: string): FormResponse => ({
    resource: 'bulk_messages',
    title: '',
    action: { method: 'post', path },
    form: { sections: [{ kind: 'inputs', fields: [{ name: 'a', param: 'm[a]', label: 'A', control: 'typeahead', required: false, options_path }] }] },
    permissions: {},
  })

  it('accepts a form that posts, and searches, on this origin', () => {
    expect(safeFormAction(form('/api/admin/bulk_messages/create', '/api/admin/_pages/bulk_messages?field=a'), from)).toBe(true)
  })

  it.each([
    ['https://evil.example/api', undefined],
    ['//evil.example/x', undefined],
    ['/api/admin/x', 'https://evil.example/options'],
    ['javascript:alert(1)', undefined],
  ])('rejects %s %s', (path, options) => expect(safeFormAction(form(path, options), from)).toBe(false))

  it('accepts a filter form that only reads', () => {
    expect(safeFormAction({ ...form('/api/admin/_pages/reports'), action: { method: 'get', path: '/api/admin/_pages/reports' } }, from)).toBe(true)
  })
})

describe('safeAction for a navigating POST', () => {
  const connect = (extra: Partial<Action> = {}): Action => ({
    key: 'connect',
    label: 'Connect',
    kind: 'link',
    method: 'post',
    navigate: true,
    enabled: true,
    href: 'https://app.test/auth/provider',
    ...extra,
  })

  it.each(['https://app.test/auth/provider', '/auth/provider', 'https://app.test/auth/provider?origin=%2Fadmin%2Fusers', '/users/auth/google_oauth2'])('accepts %s', (href) =>
    expect(safeAction(connect({ href }), from)).toBe(true),
  )

  it.each([
    'https://evil.example/auth/provider',
    '//evil.example/auth/provider',
    'http://app.test:8080/auth/provider',
    'javascript:alert(1)',
    'data:text/html,x',
    '/admin/posts/1/destroy',
    '/api/admin/posts/1',
    'https://app.test/admin',
    '/auth/../admin/posts',
    '/auth/%2e%2e/admin',
    '/auth%2f..%2fadmin',
    '/auth\\..\\admin',
    '/auth/%2\nfadmin',
    '/auth/.\t./admin',
    '',
  ])('rejects %j', (href) => expect(safeAction(connect({ href }), from)).toBe(false))

  it('rejects an encoded separator inherited from the base path', () => {
    expect(safeAction(connect({ href: 'provider' }), 'https://app.test/auth%2fx/page')).toBe(false)
    expect(safeAction(connect({ href: 'provider' }), 'https://app.test/auth/page')).toBe(true)
  })

  it('is a post that reaches no API of ours', () => {
    expect(safeAction(connect({ method: 'get' }), from)).toBe(false)
    expect(safeAction(connect({ api_path: '/api/admin/x' }), from)).toBe(false)
    expect(safeAction(connect({ view: { mode: 'frame', path: '/admin/x' } }), from)).toBe(false)
  })

  it('is not an external link', () => expect(safeAction(connect({ external: true, href: 'https://evil.example/x' }), from)).toBe(false))
})

describe('safeFrameWrite', () => {
  const page = 'https://app.test/admin/posts/1'

  it.each(['/admin/posts/1', 'https://app.test/admin/posts/1/publish?x=1#y', '/admin', 'publish', '  /admin/posts/1', '/admin/a%20b'])('accepts %j', (url) =>
    expect(safeFrameWrite(url, page)).toBe(true),
  )

  it.each([
    '/auth/sign_out',
    '/administrator/x',
    '/api/admin/posts',
    'https://evil.test/admin/x',
    '//evil.test/admin/x',
    'https://app.test@evil.test/admin/x',
    'https://evil.test\\@app.test/admin/x',
    '/\\evil.test/admin/x',
    'http://app.test:8080/admin/x',
    'javascript:alert(1)',
    'data:text/html,x',
    'blob:https://app.test/admin/x',
    '/auth/../admin/x',
    '/admin/../auth/x',
    '/admin/./x',
    '/admin/..',
    '/admin/%2e%2e/auth',
    '/admin/..%2fauth',
    '/admin%2f..%2fauth',
    '/admin/a%2fb',
    '/admin/a%2Fb',
    '/admin/a%5cb',
    '/admin\\x',
  ])('rejects %j', (url) => expect(safeFrameWrite(url, page)).toBe(false))

  it.each(['/admin/%2\nfsecret', '/admin/%2\tf', '/admin/%\r2f', '/admin/%2\r\nf', '/admin/.\n./auth', '/admin/.\t./auth', '/admin/\u0000x', '/admin/\u0001x', '/admin/\u007fx', 'https://app.test/admin/%2\nf'])(
    'rejects %j, whose control characters the URL parser strips',
    (url) => expect(safeFrameWrite(url, page)).toBe(false),
  )

  it.each(['https://app.test/admin/a%2fb/page', 'https://app.test/admin/a%2Fb/page', 'https://app.test/admin/a%5cb/page', 'https://app.test/admin/%2e%2e/page'])(
    'rejects a relative reference resolved against %s',
    (base) => {
      for (const url of ['save', './save', '?x=1', '#frag', '']) expect(safeFrameWrite(url, base), url).toBe(false)
    },
  )
})
