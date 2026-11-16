import { QueryClient } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'

const base = vi.hoisted(() => ({ mountPath: '/api' }))
vi.mock('@/lib/base', () => base)

const { invalidateResource } = await import('./records')

describe('invalidateResource', () => {
  it('invalidates the client keys and the mounted keys of host-generated hooks, but not metadata or other resources', async () => {
    const queryClient = new QueryClient()
    const keys = ['/admin/authors', '/api/admin/authors', '/api/admin/authors/7', '/api/admin/authors/_meta', '/api/admin/posts']
    keys.forEach((key) => queryClient.setQueryData([key], {}))
    await invalidateResource(queryClient, 'authors', 'none')
    const stale = keys.filter((key) => queryClient.getQueryState([key])?.isInvalidated)
    expect(stale).toEqual(['/admin/authors', '/api/admin/authors', '/api/admin/authors/7'])
  })

  it('invalidates a resource nested under a parent, under any namespace', async () => {
    base.mountPath = '/api'
    const queryClient = new QueryClient()
    const keys = ['/api/admin/posts/7/comments', '/api/ops/comments', '/api/admin/posts/7', '/api/admin/comments/_meta', '/api/admin/commenters']
    keys.forEach((key) => queryClient.setQueryData([key], {}))
    await invalidateResource(queryClient, 'comments', 'none')
    const stale = keys.filter((key) => queryClient.getQueryState([key])?.isInvalidated)
    expect(stale).toEqual(['/api/admin/posts/7/comments', '/api/ops/comments'])
  })

  it('keeps the namespace of client keys when the mount is `/admin`', async () => {
    base.mountPath = '/admin'
    const queryClient = new QueryClient()
    const keys = ['/admin/authors', '/admin/authors/7', '/admin/admin/authors', '/admin/posts']
    keys.forEach((key) => queryClient.setQueryData([key], {}))
    await invalidateResource(queryClient, 'authors', 'none')
    const stale = keys.filter((key) => queryClient.getQueryState([key])?.isInvalidated)
    expect(stale).toEqual(['/admin/authors', '/admin/authors/7', '/admin/admin/authors'])
  })
})
