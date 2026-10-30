import { describe, expect, it } from 'vitest'
import type { Action } from '@/api/generated/model'
import { navigationFields } from './navigate'

const connect: Action = { key: 'connect', label: 'Connect', kind: 'link', method: 'post', navigate: true, href: 'https://app.test/auth/provider', enabled: true }

describe('navigationFields', () => {
  it('sends the session token', () => {
    expect(navigationFields(connect, 'tok')).toEqual([['authenticity_token', 'tok']])
  })

  it('carries the form fields the action names, ahead of the token', () => {
    expect(navigationFields({ ...connect, params: { origin: '/admin/users' } }, 'tok')).toEqual([['origin', '/admin/users'], ['authenticity_token', 'tok']])
  })

  it('never lets a carried field replace the token', () => {
    expect(navigationFields({ ...connect, params: { authenticity_token: 'forged' } }, 'tok')).toEqual([['authenticity_token', 'tok']])
  })
})
