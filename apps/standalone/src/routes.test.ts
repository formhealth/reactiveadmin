import { matchRoutes } from 'react-router'
import { describe, expect, it } from 'vitest'
import { Layout } from '@/components/Layout'
import { routes } from './routes'

const matched = (pathname: string) => matchRoutes(routes, pathname) ?? []

describe('routes', () => {
  it.each(['/authors/9/comments', '/authors/9/preview', '/authors/9/notes/4', '/a/b/c/d'])('mounts Layout around %s, so an address the client lacks reaches the classic fallback', (pathname) => {
    const [layout, page] = matched(pathname)

    expect(layout.route.element).toMatchObject({ type: Layout })
    expect(page.route.path).toBe('*')
  })

  it('keeps the specific routes ahead of the catch-all', () => {
    const paths = ['/', '/groups/setup', '/authors', '/authors/new', '/authors/9', '/authors/9/edit', '/authors/actions/x', '/authors/9/actions/x'].map((pathname) => matched(pathname).at(-1)?.route.path)

    expect(paths).toEqual([undefined, 'groups/*', ':resource', ':resource/new', ':resource/:id', ':resource/:id/edit', ':resource/actions/:key', ':resource/:id/actions/:key'])
  })
})
