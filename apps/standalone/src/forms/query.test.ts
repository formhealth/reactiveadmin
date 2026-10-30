import { describe, expect, it } from 'vitest'
import { entriesToSearch, withSearch } from './query'

describe('entriesToSearch', () => {
  it('names fields as Rails nests them', () => {
    expect(entriesToSearch([['simulation[date]', '2026-10-01'], ['simulation[channel]', 'initial']])).toBe('?simulation[date]=2026-10-01&simulation[channel]=initial')
  })

  it('keeps blanks, as a browser sends them', () => {
    expect(entriesToSearch([['q[name]', ''], ['q[note]', null], ['q[x]', undefined]])).toBe('?q[name]=&q[note]=&q[x]=')
  })

  it('repeats array params and sends booleans as the checkbox does', () => {
    expect(entriesToSearch([['f[tag_ids][]', ['1', '2']], ['f[urgent]', true], ['f[open]', false]])).toBe('?f[tag_ids][]=1&f[tag_ids][]=2&f[urgent]=1&f[open]=0')
  })

  it('encodes values', () => {
    expect(entriesToSearch([['q[name]', 'a&b=c d']])).toBe('?q[name]=a%26b%3Dc+d')
  })

  it('is empty without fields', () => expect(entriesToSearch([])).toBe(''))
})

describe('withSearch', () => {
  it('replaces the path query when there is a search', () => {
    expect(withSearch('/api/admin/x?old=1', '?a=1')).toBe('/api/admin/x?a=1')
    expect(withSearch('/api/admin/x', 'a=1')).toBe('/api/admin/x?a=1')
  })

  it('keeps the path as it is without one', () => {
    expect(withSearch('/api/admin/x?old=1', '')).toBe('/api/admin/x?old=1')
    expect(withSearch('/api/admin/x', '?')).toBe('/api/admin/x')
  })
})
