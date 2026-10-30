import { describe, expect, it } from 'vitest'
import { actionRoute, classicDestination } from './classicDestination'

const ORIGIN = 'https://a.test'
const to = (pathname: string, href?: string | null) => classicDestination(pathname, href === undefined ? undefined : { href }, ORIGIN)

describe('actionRoute', () => {
  it('reads collection and member action pages', () => {
    expect(actionRoute('/authors/actions/import')).toEqual({ resource: 'authors', id: undefined, key: 'import' })
    expect(actionRoute('/authors/9/actions/archive')).toEqual({ resource: 'authors', id: '9', key: 'archive' })
  })

  it('has none for the routes both UIs serve', () => {
    ;['/', '/authors', '/authors/9', '/authors/new', '/authors/9/edit', '/authors/actions', '/authors/9/actions', '/authors/9/notes/actions/x'].forEach((path) =>
      expect(actionRoute(path), path).toBeUndefined(),
    )
  })
})

describe('classicDestination', () => {
  it('sends a group overview to the admin root', () => {
    expect(to('/groups/setup')).toBe('/admin')
    expect(to('/groups/setup/billing')).toBe('/admin')
  })

  it("sends an action page to the action's classic page", () => {
    expect(to('/authors/9/actions/archive', '/admin/authors/9/archive')).toBe('/admin/authors/9/archive')
    expect(to('/authors/actions/import', 'https://a.test/admin/authors/import?kind=csv#top')).toBe('/admin/authors/import?kind=csv#top')
  })

  it('drops the escape hatch from that page, since the user has chosen classic', () => {
    expect(to('/authors/9/actions/archive', '/admin/authors/9/archive?classic=1&x=1')).toBe('/admin/authors/9/archive?x=1')
  })

  it('falls back to the record, or the resource for a collection action', () => {
    expect(to('/authors/9/actions/archive')).toBe('/admin/authors/9')
    expect(to('/authors/actions/import')).toBe('/admin/authors')
    expect(to('/authors/9/actions/archive', null)).toBe('/admin/authors/9')
  })

  it('does not follow an href that leaves the admin', () => {
    ;['https://evil.test/admin/authors/9', '//evil.test/admin/authors/9', '/auth/provider', '/administrator/x', 'javascript:alert(1)', '/admin/../auth'].forEach((href) =>
      expect(to('/authors/9/actions/archive', href), href).toBe('/admin/authors/9'),
    )
  })

  it('keeps the same address for the routes both UIs serve', () => {
    ;['/', '/authors', '/authors/new', '/authors/9', '/authors/9/edit', '/dashboard'].forEach((path) => expect(to(path, '/admin/x'), path).toBeUndefined())
  })
})
