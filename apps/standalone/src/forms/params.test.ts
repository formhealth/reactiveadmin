import { describe, expect, it } from 'vitest'
import { hasFile, paramsToObject, toFormData } from './params'

describe('paramsToObject', () => {
  it('nests bracketed params', () => {
    expect(paramsToObject([['post[details]', { a: 1 }], ['post[embargo_until]', '2026-10-20']])).toEqual({
      post: { details: { a: 1 }, embargo_until: '2026-10-20' },
    })
  })

  it('keeps numeric segments as index-keyed objects for nested attributes', () => {
    expect(
      paramsToObject([
        ['desk[desk_members_attributes][0][user_email]', 'a@x.co'],
        ['desk[desk_members_attributes][0][id]', 'u1'],
        ['desk[desk_members_attributes][1][user_email]', 'b@x.co'],
        ['desk[desk_members_attributes][1][_destroy]', '1'],
      ]),
    ).toEqual({
      desk: {
        desk_members_attributes: {
          0: { user_email: 'a@x.co', id: 'u1' },
          1: { user_email: 'b@x.co', _destroy: '1' },
        },
      },
    })
  })

  it('collects trailing [] params into arrays', () => {
    expect(paramsToObject([['desk[region_ids][]', ['1', '2']], ['desk[tag][]', 'x'], ['desk[tag][]', 'y']])).toEqual({
      desk: { region_ids: ['1', '2'], tag: ['x', 'y'] },
    })
  })

  it('handles flat params and ignores empty ones', () => {
    expect(paramsToObject([['embargo_until', '2026-10-20'], ['', 'ignored']])).toEqual({ embargo_until: '2026-10-20' })
  })

  it('overwrites a scalar with a later nested value instead of throwing', () => {
    expect(paramsToObject([['a', 'x'], ['a[b]', 'y']])).toEqual({ a: { b: 'y' } })
  })
})

describe('multipart', () => {
  const file = new File(['x'], 'scan.pdf', { type: 'application/pdf' })

  it('detects files', () => {
    expect(hasFile([['a[b]', 'x']])).toBe(false)
    expect(hasFile([['a[doc]', file]])).toBe(true)
  })

  it('appends bracketed names as-is, JSON for structured values and each array item', () => {
    const data = toFormData([['a[doc]', file], ['a[details]', { k: 1 }], ['a[ids][]', ['1', '2']], ['a[empty]', null], ['a[skip]', undefined], ['a[on]', true]])
    expect(data.get('a[doc]')).toBeInstanceOf(File)
    expect(data.get('a[details]')).toBe('{"k":1}')
    expect(data.getAll('a[ids][]')).toEqual(['1', '2'])
    expect(data.get('a[empty]')).toBe('')
    expect(data.has('a[skip]')).toBe(false)
    expect(data.get('a[on]')).toBe('true')
  })
})
