import { QueryClient } from '@tanstack/react-query'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { labelGroups, labelQueryOptions, labelsByKey } from './recentLabels'

const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })

describe('recent record labels', () => {
  const recents = [
    { resource: 'authors', id: 'p-1' },
    { resource: 'posts', id: '5001' },
    { resource: 'authors', id: 'p-2' },
  ]

  it('groups ids per resource', () => {
    expect(labelGroups(recents)).toEqual([
      { resource: 'authors', ids: ['p-1', 'p-2'] },
      { resource: 'posts', ids: ['5001'] },
    ])
  })

  it('keys display names by resource and id', () => {
    const names = labelsByKey([{ labels: [{ resource: 'authors', id: 'p-1', display_name: 'Alex Nguyen' }] }, undefined])
    expect(names.get('authors/p-1')).toBe('Alex Nguyen')
    expect(names.get('authors/p-2')).toBeUndefined()
  })

  describe('requests', () => {
    const fetchMock = vi.fn<typeof fetch>()

    beforeEach(() => {
      fetchMock.mockReset()
      fetchMock.mockImplementation(async () => json({ labels: [] }))
      vi.stubGlobal('fetch', fetchMock)
    })
    afterEach(() => vi.unstubAllGlobals())

    it('asks _labels, never the record, and marks it as metadata', async () => {
      const client = new QueryClient()
      await Promise.all(labelGroups(recents).map((group) => client.fetchQuery(labelQueryOptions(group))))

      expect(fetchMock.mock.calls.map(([url]) => url)).toEqual(['/api/admin/authors/_labels?ids=p-1%2Cp-2', '/api/admin/posts/_labels?ids=5001'])
      const marked = fetchMock.mock.calls.map(([, init]) => (init?.headers as Record<string, string> | undefined)?.['X-Reactiveadmin-Background'])
      expect(marked).toEqual(['1', '1'])
    })
  })
})
