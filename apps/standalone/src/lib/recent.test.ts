import { beforeEach, describe, expect, it } from 'vitest'
import { stubLocalStorage } from '@/test/memoryStorage'
import { forgetVisit, readRecents, recordVisit } from './recent'

describe('recents', () => {
  let store: Map<string, string>
  beforeEach(() => {
    store = stubLocalStorage()
  })

  it('persists only the resource, id and a timestamp', () => {
    recordVisit({ resource: 'authors', id: 'p-1', name: 'Alex Nguyen', label: 'Author' } as never, 1000)
    expect(JSON.parse(store.get('ra:recent')!)).toEqual([{ resource: 'authors', id: 'p-1', at: 1000 }])
  })

  it('moves a revisited record to the front without duplicating it, and keeps ten', () => {
    for (let i = 0; i < 12; i++) recordVisit({ resource: 'authors', id: `p-${i}` }, i)
    recordVisit({ resource: 'authors', id: 'p-5' }, 99)
    const recents = readRecents()
    expect(recents).toHaveLength(10)
    expect(recents[0]).toMatchObject({ id: 'p-5', at: 99 })
    expect(recents.filter((r) => r.id === 'p-5')).toHaveLength(1)
  })

  it('strips display text left by older builds and rewrites the entry', () => {
    store.set('ra:recent', JSON.stringify([{ resource: 'authors', id: 'p-1', name: 'Alex Nguyen', label: 'Author', at: 5 }, { resource: 'authors', id: 'p-2', name: 'Only name' }]))
    expect(readRecents()).toEqual([{ resource: 'authors', id: 'p-1', at: 5 }])
    expect(store.get('ra:recent')).not.toContain('Alex')
  })

  it('forgets a record that is gone', () => {
    recordVisit({ resource: 'authors', id: 'p-1' })
    recordVisit({ resource: 'authors', id: 'p-2' })
    forgetVisit({ resource: 'authors', id: 'p-1' })
    expect(readRecents().map((r) => r.id)).toEqual(['p-2'])
  })

  it('survives unreadable storage', () => {
    store.set('ra:recent', '{not json')
    expect(readRecents()).toEqual([])
  })
})
