import { describe, expect, it } from 'vitest'
import { embedUrl, navigation, parseBridgeMessage, trustedOrigin } from './bridge'

const from = 'https://app.test/authors/9/actions/simulate'
const mapUrl = (url: string) => (url === '/admin/authors/9' ? '/authors/9' : undefined)

describe('parseBridgeMessage', () => {
  it('reads the reported body height', () => {
    expect(parseBridgeMessage({ type: 'reactiveadmin:resize', height: 420.2 })).toEqual({ kind: 'resize', height: 421 })
    expect(parseBridgeMessage({ type: 'reactiveadmin:resize', height: 'tall' })).toBeUndefined()
    expect(parseBridgeMessage({ type: 'reactiveadmin:resize', height: -4 })).toBeUndefined()
  })

  it('turns the bridge flashes into toast levels', () => {
    const event = parseBridgeMessage({ type: 'reactiveadmin:flash', flashes: [{ type: 'notice', message: 'Saved' }, { type: 'alert', message: 'Nope' }, { type: 'notice', message: '  ' }] })
    expect(event).toEqual({ kind: 'flash', flashes: [{ level: 'success', message: 'Saved' }, { level: 'error', message: 'Nope' }] })
    expect(parseBridgeMessage({ type: 'reactiveadmin:flash', message: 'Oops', level: 'error' })).toEqual({ kind: 'flash', flashes: [{ level: 'error', message: 'Oops' }] })
    expect(parseBridgeMessage({ type: 'reactiveadmin:flash', flashes: [] })).toBeUndefined()
  })

  it('ignores anything else', () => {
    expect(parseBridgeMessage(null)).toBeUndefined()
    expect(parseBridgeMessage('reactiveadmin:resize')).toBeUndefined()
    expect(parseBridgeMessage({ type: 'webpackOk' })).toBeUndefined()
  })
})

describe('trustedOrigin', () => {
  it('accepts only the app origin', () => {
    expect(trustedOrigin('https://app.test', 'https://app.test')).toBe(true)
    expect(trustedOrigin('https://evil.test', 'https://app.test')).toBe(false)
    expect(trustedOrigin('null', 'https://app.test')).toBe(false)
  })
})

describe('navigation', () => {
  const navigate = (message: object) => navigation(parseBridgeMessage({ type: 'reactiveadmin:navigate', ...message }) as never, mapUrl, from)

  it('leaves the iframe for an admin URL the app has a screen for', () => {
    expect(navigate({ url: '/admin/authors/9' })).toEqual({ to: '/authors/9' })
    expect(navigate({ resource: 'authors', id: '9', view: 'show' })).toEqual({ to: '/authors/9' })
  })

  it('keeps other admin pages inside the iframe, as an embed', () => {
    expect(navigate({ url: '/admin/authors/9/team_history?page=2' })).toEqual({ stay: '/admin/authors/9/team_history?page=2&embed=1' })
  })

  it('does not reload a page the iframe already shows after a redirect', () => {
    expect(navigate({ url: '/admin/authors/9/team_history', redirected: true })).toBeUndefined()
    expect(navigate({ url: '/admin/authors/9', redirected: true })).toEqual({ to: '/authors/9' })
  })

  it('never follows another origin', () => {
    expect(navigate({ url: 'https://evil.test/admin' })).toBeUndefined()
    expect(embedUrl('https://evil.test/admin', from)).toBeUndefined()
  })
})
