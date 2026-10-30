import { describe, expect, it } from 'vitest'
import type { Action } from '@/api/generated/model'
import { planOf } from './actions'

const action = (extra: Partial<Action>): Action => ({ key: 'run', label: 'Run', kind: 'member', enabled: true, ...extra })

describe('planOf', () => {
  it('never routes a GET through the API: it would run, then run again at the classic URL', () => {
    expect(planOf(action({ method: 'get', href: '/admin/payouts/1/receipt', api_path: '/api/admin/payouts/1/receipt' }))).toBe('classic')
    expect(planOf(action({ href: '/admin/payouts/1/receipt', api_path: '/api/admin/payouts/1/receipt' }))).toBe('classic')
  })

  it('lets the ladder view decide the container for a GET', () => {
    expect(planOf(action({ method: 'get', api_path: '/api/x', view: { mode: 'frame', path: '/admin/x' } }))).toBe('view')
  })

  it('sends writes to the API', () => {
    expect(planOf(action({ method: 'post', api_path: '/api/admin/payouts/1/retry' }))).toBe('api')
    expect(planOf(action({ method: 'delete', api_path: '/api/admin/payouts/1' }))).toBe('api')
  })

  it('falls back to the classic page for a write with no API path', () => {
    expect(planOf(action({ method: 'post', href: '/admin/x/run' }))).toBe('classic')
  })

  it('opens declared forms, external links and unsupported actions as such', () => {
    expect(planOf(action({ method: 'get', form_path: '/api/admin/x/hold' }))).toBe('form')
    expect(planOf(action({ external: true, href: 'https://example.test' }))).toBe('external')
    expect(planOf(action({ supported: false }))).toBe('none')
    expect(planOf(action({ kind: 'edit' }))).toBe('edit')
  })

  it('never runs what the host reserved for the classic admin, whatever else it carries', () => {
    expect(planOf(action({ api_denied: true, classic_url: '/admin/x', method: 'post', api_path: '/api/admin/x/run' }))).toBe('none')
    expect(planOf(action({ api_denied: true, kind: 'edit', view: { mode: 'frame', path: '/admin/x' } }))).toBe('none')
  })

  it('navigates for a post to a route outside the admin, ahead of any other plan', () => {
    const connect: Partial<Action> = { kind: 'link', method: 'post', navigate: true, href: 'https://app.test/auth/provider' }
    expect(planOf(action(connect))).toBe('navigate')
    expect(planOf(action({ ...connect, supported: false }))).toBe('none')
    expect(planOf(action({ ...connect, api_denied: true }))).toBe('none')
  })
})
