import { http, HttpResponse } from 'msw'
import { setupServer } from 'msw/node'
import { afterAll, beforeAll, describe, expect, it } from 'vitest'
import { fixtureHandlers } from './fixtureHandlers'

const base = 'http://fixtures.test/api/admin'
const files = {
  './fixtures/_manifest.json': { schema_version: 2, resources: [{ key: 'posts' }] },
  './fixtures/posts/meta.json': { key: 'posts' },
  './fixtures/posts/index.json': { resource: 'posts', rows: [{ id: '7394' }] },
  './fixtures/posts/show.json': { resource: 'posts', id: '7394', layout: [] },
  './fixtures/posts/new.json': { resource: 'posts', title: 'New Post' },
  './fixtures/posts/edit.json': { resource: 'posts', id: '7394', title: 'Edit Post' },
  './fixtures/notes/index.json': { resource: 'notes', rows: [] },
}

const server = setupServer(...fixtureHandlers(files, { base }), http.get(`${base}/*`, () => HttpResponse.json({ fallback: true })))
const get = (path: string) => fetch(`${base}${path}`).catch(() => undefined)
const json = async (path: string) => (await get(path))?.json()

beforeAll(() => server.listen())
afterAll(() => server.close())

describe('fixtureHandlers', () => {
  it('serves the manifest and each resource section', async () => {
    expect(await json('/_manifest')).toMatchObject({ schema_version: 2 })
    expect(await json('/posts/_meta')).toEqual({ key: 'posts' })
    expect(await json('/posts?page=2&q[title_cont]=x')).toMatchObject({ rows: [{ id: '7394' }] })
    expect(await json('/posts/new')).toMatchObject({ title: 'New Post' })
    expect(await json('/notes')).toMatchObject({ resource: 'notes' })
  })

  it('serves show and edit for the recorded record only', async () => {
    expect(await json('/posts/7394')).toMatchObject({ id: '7394', layout: [] })
    expect(await json('/posts/7394/edit')).toMatchObject({ title: 'Edit Post' })
    expect(await json('/posts/1')).toEqual({ fallback: true })
  })

  it('leaves what was not recorded to the next handler', async () => {
    expect(await json('/notes/_meta')).toEqual({ fallback: true })
    expect(await json('/posts/_options?field=author')).toEqual({ fallback: true })
    expect(await json('/posts/7394/_value')).toEqual({ fallback: true })
  })
})
