import { describe, expect, it } from 'vitest'
import { classicHere, classicHereNow, embedded } from './urls'

describe('classicHere', () => {
  it('maps in-app paths back to the classic admin, which the escape hatch keeps from coming back here', () => {
    expect(classicHere('/')).toBe('/admin?classic=1')
    expect(classicHere('/posts/5001/edit')).toBe('/admin/posts/5001/edit?classic=1')
    expect(classicHere('/batch_operations')).toBe('/admin/batch_operations?classic=1')
  })
})

describe('classicHereNow', () => {
  it('reads the browser location, which is the in-app path when the router sits at the root', () => {
    expect(classicHereNow({ pathname: '/authors/9' } as Location)).toBe('/admin/authors/9?classic=1')
    expect(classicHereNow({ pathname: '/' } as Location)).toBe('/admin?classic=1')
    expect(classicHereNow({ pathname: '/authors', search: '?scope=embargoed' } as Location)).toBe('/admin/authors?scope=embargoed&classic=1')
  })
})

describe('embedded', () => {
  it('adds embed=1 and keeps the rest of the query', () => {
    expect(embedded('/admin/authors/9?scope=embargoed')).toBe('/admin/authors/9?scope=embargoed&embed=1')
    expect(embedded('/admin/authors/9?embed=0')).toBe('/admin/authors/9?embed=1')
  })
})
