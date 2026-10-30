import { describe, expect, it } from 'vitest'
import { isIdLike, isIdentifierName, isUuid, shortId } from './ids'

const UUID = '573a4e98-1c2d-4f6a-9b0e-7d3f2a1b4c5d'

describe('ids', () => {
  it('detects UUIDs', () => {
    expect(isUuid(UUID)).toBe(true)
    expect(isUuid(UUID.toUpperCase())).toBe(true)
    expect(isUuid('5000')).toBe(false)
    expect(isUuid(`${UUID}x`)).toBe(false)
    expect(isUuid(undefined)).toBe(false)
  })

  it('shortens to the first 8 characters', () => {
    expect(shortId(UUID)).toBe('573a4e98')
  })

  it('recognizes identifier names', () => {
    for (const name of ['id', 'ID', 'author_id', 'ref_id', 'external_id', 'External ID', 'Ref ID']) expect(isIdentifierName(name)).toBe(true)
    for (const name of ['Author', 'Editor', 'valid', 'identity', '', null]) expect(isIdentifierName(name)).toBe(false)
  })
})

describe('isIdLike', () => {
  it('accepts uuids and integer keys only', () => {
    expect(isIdLike('9e3817e8-9e38-4e39-ae39-9e3a90c49e3b')).toBe(true)
    expect(isIdLike('5001')).toBe(true)
    expect(isIdLike('Alex')).toBe(false)
    expect(isIdLike('12 34')).toBe(false)
  })
})
