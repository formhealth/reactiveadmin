import { QueryClient, QueryObserver } from '@tanstack/react-query'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { getGetRecordQueryOptions } from '@/api/generated/core'
import { openedRecordQuery } from '@/api/recordQuery'

const json = (body: unknown) => new Response(JSON.stringify(body), { status: 200, headers: { 'Content-Type': 'application/json' } })

describe('opening a record', () => {
  const fetchMock = vi.fn<typeof fetch>()

  beforeEach(() => {
    fetchMock.mockReset()
    fetchMock.mockImplementation(async () => json({ id: '7' }))
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  const open = (client: QueryClient) => {
    const observer = new QueryObserver(client, getGetRecordQueryOptions('authors', '7', { query: openedRecordQuery }))
    const unsubscribe = observer.subscribe(() => {})
    return () => unsubscribe()
  }

  it('refetches a record that is fresh in the cache, so every open is a real request', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { staleTime: 30_000 } } })
    await client.prefetchQuery(getGetRecordQueryOptions('authors', '7'))
    expect(fetchMock).toHaveBeenCalledTimes(1)

    open(client)
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(2))
  })

  it('shows what is cached while the fresh request is in flight', async () => {
    const client = new QueryClient({ defaultOptions: { queries: { staleTime: 30_000 } } })
    await client.prefetchQuery(getGetRecordQueryOptions('authors', '7'))

    const observer = new QueryObserver(client, getGetRecordQueryOptions('authors', '7', { query: openedRecordQuery }))
    expect(observer.getCurrentResult().data).toEqual({ id: '7' })
  })

  it('sends no background marker on a record request', async () => {
    const client = new QueryClient()
    open(client)
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1))

    expect(fetchMock.mock.calls[0][0]).toBe('/api/admin/authors/7')
    expect(fetchMock.mock.calls[0][1]?.headers).not.toHaveProperty('X-Reactiveadmin-Background')
  })
})
