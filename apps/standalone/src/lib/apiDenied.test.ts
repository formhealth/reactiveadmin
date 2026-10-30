import { describe, expect, it } from 'vitest'
import { ApiError } from '@/api/fetcher'
import type { ResourceSummary } from '@/api/generated/model'
import { classicPage, isApiDenied, isDenied } from './apiDenied'

const summary = (api_denied?: ResourceSummary['api_denied']): ResourceSummary => ({
  key: 'admin_users',
  label: 'Admin user',
  plural_label: 'Admin users',
  actions: ['index', 'show', 'new', 'edit'],
  permissions: { index: true },
  meta_path: '/api/admin/admin_users/_meta',
  api_denied,
})

describe('classicPage', () => {
  const reserved = summary({ actions: ['new', 'create'], classic_url: '/admin/admin_users' })

  it('points at the classic page of an action the host reserved', () => {
    expect(classicPage(reserved, 'new', '/new')).toBe('/admin/admin_users/new')
    expect(isDenied(reserved, 'new')).toBe(true)
  })

  it('has nothing for an action that is not reserved, or a resource with no classic page', () => {
    expect(classicPage(reserved, 'edit', '/1/edit')).toBeUndefined()
    expect(isDenied(reserved, 'edit')).toBe(false)
    expect(classicPage(summary({ actions: ['new'] }), 'new', '/new')).toBeUndefined()
    expect(isDenied(summary({ actions: ['new'] }), 'new')).toBe(true)
    expect(classicPage(summary(), 'new', '/new')).toBeUndefined()
    expect(isDenied(undefined, 'new')).toBe(false)
  })
})

describe('isApiDenied', () => {
  it('recognises the server refusing what is reserved for the classic admin', () => {
    expect(isApiDenied(new ApiError(403, 'api_denied', 'Only in classic'))).toBe(true)
    expect(isApiDenied(new ApiError(403, 'forbidden'))).toBe(false)
    expect(isApiDenied(new Error('api_denied'))).toBe(false)
  })
})
