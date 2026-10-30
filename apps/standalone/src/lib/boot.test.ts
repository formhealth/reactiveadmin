import { QueryClient } from '@tanstack/react-query'
import { describe, expect, it, vi } from 'vitest'
import { ApiError } from '@/api/fetcher'
import { getGetSessionQueryOptions } from '@/api/generated/core'
import type { Manifest, ResourceSummary, Session } from '@/api/generated/model'
import { boundedSession, lacksScreen, leaveIfUnavailable } from './boot'

const session = (ui?: Session['ui']) => () => Promise.resolve({ ui })

describe('leaveIfUnavailable', () => {
  const run = (read: () => Promise<Pick<Session, 'ui'>>, hosted = true) => {
    const go = vi.fn()
    const store = vi.fn()
    return leaveIfUnavailable(read, hosted, go, store).then((leaving) => ({ leaving, go, store }))
  }

  it('seeds the session cache so the switch components do not request it again', async () => {
    const fetch = vi.spyOn(globalThis, 'fetch')
    const client = new QueryClient()
    const available = { ui: { available: true, default: 'classic' } } as Session

    await leaveIfUnavailable(() => Promise.resolve(available), true, vi.fn(), vi.fn(), client)
    const seen = await client.fetchQuery(getGetSessionQueryOptions({ query: { staleTime: Infinity } }))

    expect(seen).toBe(available)
    expect(fetch).not.toHaveBeenCalled()
    fetch.mockRestore()
  })

  it('lets an available user stay', async () => {
    const { leaving, go, store } = await run(session({ available: true, default: 'classic' }))

    expect([leaving, go.mock.calls.length, store.mock.calls.length]).toEqual([false, 0, 0])
  })

  it('sends a user who may not use the new admin back to classic, and forgets the choice', async () => {
    const { leaving, go, store } = await run(session({ available: false, default: 'new' }))

    expect(leaving).toBe(true)
    expect(store).toHaveBeenCalledWith(undefined)
    expect(go).toHaveBeenCalledOnce()
  })

  it('treats a session that says nothing as unavailable', async () => {
    expect((await run(session())).leaving).toBe(true)
  })

  it('sends a signed-out user to classic, where the host asks them to sign in', async () => {
    const { leaving, go, store } = await run(() => Promise.reject(new ApiError(401, 'unauthorized')))

    expect(leaving).toBe(true)
    expect(go).toHaveBeenCalledOnce()
    expect(store).not.toHaveBeenCalled()
  })

  it('renders for any other failure, which the app reports itself', async () => {
    expect((await run(() => Promise.reject(new ApiError(500)))).leaving).toBe(false)
    expect((await run(() => Promise.reject(new Error('offline')))).leaving).toBe(false)
  })

  it('renders the app when the session never answers', async () => {
    const { leaving, go, store } = await run(boundedSession(() => new Promise<Session>(() => undefined), 10))

    expect([leaving, go.mock.calls.length, store.mock.calls.length]).toEqual([false, 0, 0])
  })

  it('still sends a signed-out user to classic through the bound', async () => {
    const { leaving, go } = await run(boundedSession(() => Promise.reject(new ApiError(401, 'unauthorized')), 10))

    expect(leaving).toBe(true)
    expect(go).toHaveBeenCalledOnce()
  })

  it('does nothing outside a Rails host', async () => {
    const read = vi.fn()
    const { leaving } = await run(read, false)

    expect(leaving).toBe(false)
    expect(read).not.toHaveBeenCalled()
  })
})

describe('boundedSession', () => {
  const stalled = () => new Promise<Session>(() => undefined)

  it('rejects when the session does not answer in time', async () => {
    await expect(boundedSession(stalled, 10)()).rejects.toThrow('timed out')
  })

  it('reads once and hands every caller the same outcome, so a stall costs one wait', async () => {
    const read = vi.fn(stalled)
    const session = boundedSession(read, 10)
    const outcomes = await Promise.allSettled([session(), session()])
    await expect(session()).rejects.toThrow('timed out')

    expect(outcomes.map((o) => o.status)).toEqual(['rejected', 'rejected'])
    expect(read).toHaveBeenCalledOnce()
  })

  it('passes through the answer and the failure of a session that responds', async () => {
    const answer = { ui: { available: true, default: 'classic' } } as Session

    await expect(boundedSession(() => Promise.resolve(answer), 10)()).resolves.toBe(answer)
    await expect(boundedSession(() => Promise.reject(new ApiError(401, 'unauthorized')), 10)()).rejects.toMatchObject({ status: 401 })
  })
})

describe('lacksScreen', () => {
  const resource = (key: string, extra: Partial<ResourceSummary> = {}) =>
    ({ key, label: key, plural_label: key, actions: ['index', 'show', 'new', 'edit'], permissions: {}, meta_path: '', ...extra }) as ResourceSummary
  const manifest = {
    resources: [
      resource('authors'),
      resource('audits', { actions: ['index', 'show'] }),
      resource('admin_users', { api_denied: { actions: ['new', 'create'], classic_url: '/admin/admin_users' } }),
      resource('secrets', { api_denied: { actions: ['index'] } }),
      resource('hidden', { actions: ['show'] }),
    ],
    menu: [
      { id: 'dashboard', label: 'Dashboard', page: 'dashboard', children: [] },
      { id: 'tools', label: 'Tools', page: 'tools', api_denied: true, children: [] },
      { id: 'setup', label: 'Setup', kind: 'group', children: [{ id: 'jobs', label: 'Jobs', page: 'jobs', children: [] }] },
    ],
    site: { utility_menu: [{ id: 'status', label: 'Status', page: 'status', children: [] }] },
  } as unknown as Pick<Manifest, 'resources' | 'menu' | 'site'>
  const lacks = (path: string) => lacksScreen(path, manifest)

  it('has a screen for every shape of a listed resource', () => {
    ;['/authors', '/authors/new', '/authors/9', '/authors/9/edit', '/authors/actions/import', '/authors/9/actions/archive'].forEach((path) => expect(lacks(path), path).toBe(false))
  })

  it('has one for home, group overviews, and pages in either menu', () => {
    ;['/', '/groups/setup', '/groups/setup/billing', '/dashboard', '/jobs', '/status'].forEach((path) => expect(lacks(path), path).toBe(false))
  })

  it('has none for a resource or page the manifest does not list', () => {
    ;['/nothing', '/nothing/1', '/dashboard/1'].forEach((path) => expect(lacks(path), path).toBe(true))
  })

  it('has none for a page an api guard refuses', () => {
    expect(lacks('/tools')).toBe(true)
  })

  it("has none for an action the resource doesn't have", () => {
    expect(lacks('/audits')).toBe(false)
    expect(lacks('/audits/9')).toBe(false)
    expect(lacks('/audits/new')).toBe(true)
    expect(lacks('/audits/9/edit')).toBe(true)
  })

  it('has none for what an api guard refuses, only for that action', () => {
    expect(lacks('/admin_users/new')).toBe(true)
    expect(lacks('/admin_users')).toBe(false)
    expect(lacks('/admin_users/3')).toBe(false)
    expect(lacks('/secrets')).toBe(true)
    expect(lacks('/secrets/3')).toBe(true)
  })

  it('has none for a resource nobody can list', () => {
    expect(lacks('/hidden/3')).toBe(true)
  })

  it('has none for nested resources and member actions', () => {
    ;['/authors/9/notes', '/authors/9/notes/4', '/authors/9/archive', '/authors/9/edit/more', '/authors/actions', '/authors/123/comments', '/authors/123/preview'].forEach((path) => expect(lacks(path), path).toBe(true))
  })
})
