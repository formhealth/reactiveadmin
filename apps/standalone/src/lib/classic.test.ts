import { describe, expect, it } from 'vitest'
import { classicUrl, isAdminPath, mapClassicUrl, sameOrigin, withClassic } from './classic'

const origin = 'https://app.test'
const targets = { resources: new Set(['posts', 'authors']), pages: new Set(['batch_operations']) }
const map = (url: string) => mapClassicUrl(url, targets, origin)

describe('mapClassicUrl', () => {
  it('maps resource screens, keeping list state', () => {
    expect(map('/admin/posts')).toBe('/posts')
    expect(map('/admin/posts?scope=embargoed&q[author_id_eq]=3')).toBe('/posts?scope=embargoed&q[author_id_eq]=3')
    expect(map('/admin/posts/new')).toBe('/posts/new')
    expect(map('/admin/posts/5001')).toBe('/posts/5001')
    expect(map('/admin/authors/1b2c/edit')).toBe('/authors/1b2c/edit')
    expect(map(`${origin}/admin/authors/9`)).toBe('/authors/9')
  })

  it('maps the dashboard and pages', () => {
    expect(map('/admin')).toBe('/')
    expect(map('/admin/')).toBe('/')
    expect(map('/admin/batch_operations')).toBe('/batch_operations')
  })

  it('leaves everything else to the caller', () => {
    expect(map('/admin/authors/9/team_history')).toBeUndefined()
    expect(map('/admin/authors/9/edit/extra')).toBeUndefined()
    expect(map('/admin/posts.csv')).toBeUndefined()
    expect(map('/admin/unknown_resource')).toBeUndefined()
    expect(map('/admin/new/edit')).toBeUndefined()
    expect(map('/rails/active_storage/blobs/1')).toBeUndefined()
    expect(map('https://elsewhere.test/admin/authors/9')).toBeUndefined()
  })

  it('leaves a link that asked for the classic page to the browser', () => {
    expect(map('/admin/authors/9?classic=1')).toBeUndefined()
    expect(map('/admin?classic=1')).toBeUndefined()
  })

  it('does not take a sibling path for the admin', () => {
    expect(map('/administrator/authors')).toBeUndefined()
    expect(isAdminPath('/admin_users')).toBe(false)
    expect(isAdminPath('/admin')).toBe(true)
  })
})

describe('withClassic', () => {
  it('marks admin links so the server answers with the classic page, whatever UI the user chose', () => {
    expect(withClassic('/admin/authors/9')).toBe('/admin/authors/9?classic=1')
    expect(withClassic('/admin/authors?scope=embargoed&classic=0#top')).toBe('/admin/authors?scope=embargoed&classic=1#top')
    expect(withClassic('/admin')).toBe('/admin?classic=1')
  })

  it('leaves everything else alone', () => {
    expect(withClassic('https://elsewhere.test/admin/x')).toBe('https://elsewhere.test/admin/x')
    expect(withClassic('/sign_in')).toBe('/sign_in')
    expect(withClassic('mailto:a@b.test')).toBe('mailto:a@b.test')
  })
})

describe('classicUrl', () => {
  it('is the classic page of a record, marked', () => {
    expect(classicUrl('authors')).toBe('/admin/authors?classic=1')
    expect(classicUrl('authors', '9', '/edit')).toBe('/admin/authors/9/edit?classic=1')
    expect(classicUrl('authors', undefined, '/new')).toBe('/admin/authors/new?classic=1')
  })
})

describe('sameOrigin', () => {
  it('resolves relative URLs and rejects other origins', () => {
    expect(sameOrigin('/admin/x?y=1', origin)?.pathname).toBe('/admin/x')
    expect(sameOrigin('https://elsewhere.test/', origin)).toBeUndefined()
  })
})
