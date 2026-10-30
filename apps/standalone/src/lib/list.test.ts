import { describe, expect, it } from 'vitest'
import type { Filter } from '@/api/generated/model'
import { declaredParams, listSearch, listUrl, undeclared } from './list'

const filters: Filter[] = [
  { name: 'status', label: 'Status', control: 'select', param: 'status_eq' },
  { name: 'views', label: 'Views', control: 'number', predicates: [{ param: 'views_gteq', label: '>=' }, { param: 'views_lteq', label: '<=' }] },
  { name: 'created', label: 'Created', control: 'date_range', range: { from: 'created_at_gteq', to: 'created_at_lteq' } },
  { name: 'tags', label: 'Tags', control: 'checkboxes', multiple: true, param: 'tag_in' },
]

describe('list queries', () => {
  it('sends multi-valued predicates as q[param][]', () => {
    const search = listSearch({ q: { tag_in: ['a', 'b'], status_eq: 'open' }, scope: 'mine', per_page: 25, as: 'grid' })
    expect(search.getAll('q[tag_in][]')).toEqual(['a', 'b'])
    expect(search.get('q[status_eq]')).toBe('open')
    expect(search.get('as')).toBe('grid')
    expect(search.get('per_page')).toBe('25')
  })

  it('leaves out empty parts', () => {
    expect(listUrl('authors', {})).toBe('/admin/authors')
    expect(listUrl('authors', { scope: '' })).toBe('/admin/authors')
  })
})

describe('declared filters', () => {
  it('collects params, predicates and range ends', () => {
    expect([...declaredParams(filters)].sort()).toEqual(['created_at_gteq', 'created_at_lteq', 'status_eq', 'tag_in', 'views_gteq', 'views_lteq'])
  })

  it('names the keys a classic link carried that the server would reject', () => {
    expect(undeclared({ author_id_eq: '9', status_eq: 'open', tag_in: ['a'] }, filters)).toEqual(['author_id_eq'])
    expect(undeclared({}, filters)).toEqual([])
  })
})
