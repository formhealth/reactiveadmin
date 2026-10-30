import { describe, expect, it } from 'vitest'
import { exportHref } from './export'

describe('exportHref', () => {
  it('keeps the current q, scope and order and drops paging', () => {
    const href = exportHref('posts', 'csv', { q: { author_id_eq: '100' }, scope: 'embargoed', order: 'created_at_desc' })
    const url = new URL(href, 'https://app.test')
    expect(url.pathname).toBe('/api/admin/posts.csv')
    expect(url.searchParams.get('q[author_id_eq]')).toBe('100')
    expect(url.searchParams.get('scope')).toBe('embargoed')
    expect(url.searchParams.get('order')).toBe('created_at_desc')
  })

  it('is a bare path without filters', () => {
    expect(exportHref('authors', 'csv', {})).toBe('/api/admin/authors.csv')
  })
})
