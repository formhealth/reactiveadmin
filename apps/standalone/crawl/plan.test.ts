import { describe, expect, it } from 'vitest'
import { buildPlan, planResourceKeys, SCREEN_KINDS, type ManifestLike } from './plan.ts'

const resource = (key: string, actions: string[], belongs_to?: { optional: boolean }) => ({ key, actions, belongs_to })
const item = (id: string, extra: object = {}) => ({ id, children: [], ...extra })

const manifest: ManifestLike = {
  menu: [
    item('dashboard', { kind: 'page', page: 'dashboard' }),
    item('posts', { kind: 'resource', resource: 'posts' }),
    { id: 'setup', kind: 'group', children: [item('setup/legacy', { kind: 'link', resource: 'legacy', api_denied: true }), item('docs', { url: '/docs' })] },
  ],
  resources: [
    resource('posts', ['index', 'show', 'new', 'edit']),
    resource('tags', ['index', 'show']),
    resource('comments', ['index', 'show'], { optional: false }),
    resource('notes', ['index', 'new'], { optional: true }),
  ],
}
const ids = { posts: ['1', '2', '3'], tags: ['7'], comments: ['9'], notes: ['4'] }

describe('buildPlan', () => {
  it('covers home, groups, pages, and each resource screen', () => {
    const { screens } = buildPlan(manifest, ids, { kinds: SCREEN_KINDS, limit: 2 })
    expect(screens.map((s) => s.path)).toEqual([
      '/',
      '/groups/setup',
      '/dashboard',
      '/legacy',
      '/posts',
      '/posts/1',
      '/posts/2',
      '/posts/new',
      '/posts/1/edit',
      '/tags',
      '/tags/7',
      '/notes',
      '/notes/new',
    ])
  })

  it('visits a resource the manifest left out because a guard denies it', () => {
    expect(buildPlan(manifest, ids, { kinds: ['index'], limit: 2 }).screens.map((s) => s.id)).toContain('index:legacy')
  })

  it('skips resources nested under a required parent and says why', () => {
    expect(buildPlan(manifest, ids, { kinds: SCREEN_KINDS, limit: 2 }).skipped).toEqual([{ id: 'comments', reason: 'nested under a required parent' }])
    expect(planResourceKeys(manifest, {})).toEqual(['posts', 'tags', 'notes'])
  })

  it('limits show pages and filters by resource and kind', () => {
    const { screens } = buildPlan(manifest, ids, { resources: ['posts'], kinds: ['show', 'edit'], limit: 1 })
    expect(screens.map((s) => s.path)).toEqual(['/posts/1', '/posts/1/edit'])
  })

  it('opens nothing for a resource without records', () => {
    expect(buildPlan(manifest, {}, { resources: ['posts'], kinds: ['show', 'edit'], limit: 2 }).screens).toEqual([])
  })

  it('encodes ids that are not path-safe', () => {
    const { screens } = buildPlan({ menu: [], resources: [resource('stock', ['index', 'show'])] }, { stock: ['east/A 1'] }, { kinds: ['show'], limit: 1 })
    expect(screens[0].path).toBe('/stock/east%2FA%201')
  })
})
