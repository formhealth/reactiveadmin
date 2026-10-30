import { beforeEach, describe, expect, it } from 'vitest'
import { stubLocalStorage } from '@/test/memoryStorage'
import { optionsKey, readRecentOptions, rememberOption } from './recentOptions'

const path = '/api/admin/posts/_options?field=editor&context=form'

describe('recent option picks', () => {
  let store: Map<string, string>
  beforeEach(() => {
    store = stubLocalStorage()
  })

  it('keys a field by endpoint, field and context, not by record or term', () => {
    expect(optionsKey(`${path}&id=5001&term=ab`)).toBe(optionsKey(path))
    expect(optionsKey(path.replace('editor', 'publisher'))).not.toBe(optionsKey(path))
  })

  it('stores values only, newest first, five at most', () => {
    ;['1', '2', '3', '4', '5', '6', '3'].forEach((value) => rememberOption(path, value))
    expect(readRecentOptions(path)).toEqual(['3', '6', '5', '4', '2'])
    expect(JSON.stringify([...store.values()])).not.toMatch(/label/)
  })

  it('is empty for a field never picked from', () => {
    expect(readRecentOptions(path)).toEqual([])
  })
})
