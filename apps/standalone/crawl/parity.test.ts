// @vitest-environment jsdom
import { describe, expect, it } from 'vitest'
import { classicRowIds, compareRows, isIndexUrl, reactRowIds } from './parity.ts'

describe('compareRows', () => {
  it('matches the same ids in any order', () => {
    expect(compareRows('posts', ['3', '1', '2'], ['1', '2', '3'])).toEqual({ resource: 'posts', status: 'match', classicCount: 3, reactCount: 3, onlyClassic: [], onlyReact: [] })
  })

  it('matches two empty indexes', () => {
    expect(compareRows('posts', [], []).status).toBe('match')
  })

  it('lists the ids only one side shows', () => {
    expect(compareRows('posts', ['1', '2', '3'], ['1', '2', '4'])).toMatchObject({ status: 'mismatch', onlyClassic: ['3'], onlyReact: ['4'] })
  })

  it('flags a different row count even with the same ids', () => {
    expect(compareRows('posts', ['1', '1', '2'], ['1', '2'])).toMatchObject({ status: 'mismatch', classicCount: 3, reactCount: 2, onlyClassic: [], onlyReact: [] })
  })

  it('caps the ids it lists', () => {
    const ids = Array.from({ length: 40 }, (_, i) => String(i))
    expect(compareRows('posts', ids, []).onlyClassic).toHaveLength(10)
  })

  it('does not compare what it could not read', () => {
    expect(compareRows('taggings', undefined, ['1'])).toMatchObject({ status: 'unsupported', reactCount: 1, reason: expect.stringContaining('classic') })
    expect(compareRows('posts', ['1'], undefined)).toMatchObject({ status: 'unsupported', classicCount: 1, reason: expect.stringContaining('React') })
  })
})

describe('reactRowIds', () => {
  const page = (html: string) => (document.body.innerHTML = `<main>${html}</main>`)

  it('reads the ids of the rendered records', () => {
    page('<div data-row-count="2"><ul><li data-row-id="a_1"></li><li data-row-id="2"></li></ul></div>')
    expect(reactRowIds()).toEqual(['a_1', '2'])
  })

  it('reports a confirmed empty index as empty', () => {
    page('<div data-row-count="0"><p>No posts in this view</p></div>')
    expect(reactRowIds()).toEqual([])
  })

  it('cannot read a page without the row count or with ids missing', () => {
    page('<table><tr><td>1</td></tr></table>')
    expect(reactRowIds()).toBeUndefined()
    page('<div data-row-count="3"><li data-row-id="1"></li></div>')
    expect(reactRowIds()).toBeUndefined()
  })
})

describe('classicRowIds', () => {
  const base = '/admin/posts/'
  const table = (rows: string) => {
    document.body.innerHTML = `<div id="main_content"><div class="paginated_collection"><table class="index_table"><tbody>${rows}</tbody></table></div></div>`
    return classicRowIds(base)
  }
  const row = (id: string, cells: string, pk = '') => `<tr id="${id}"><td>${pk && `<input class="collection_selection" value="${pk}">`}</td>${cells}</tr>`
  const link = (path: string, cls = '') => `<td><a class="${cls}" href="${path}">x</a></td>`

  it('reads the route id from the row own links, not the checkbox primary key', () => {
    expect(table(row('post_42', link('/admin/posts/hello-world', 'member_link'), '42'))).toEqual(['hello-world'])
  })

  it('ignores an associated record linked before the row own actions', () => {
    const cells = link('/admin/posts/7') + link('/admin/posts/42', 'view_link member_link') + link('/admin/posts/42/edit', 'edit_link member_link')
    expect(table(row('post_42', cells))).toEqual(['42'])
  })

  it('picks the own link by the row primary key when there are no member links', () => {
    expect(table(row('post_42', link('/admin/posts/7') + link('/admin/posts/42'), '42'))).toEqual(['42'])
    expect(table(row('stock_level_eu_widget', link('/admin/posts/eu_widget'), 'eu_widget'))).toEqual(['eu_widget'])
  })

  it('does not guess the key from the row dom id, whose model prefix it cannot tell apart', () => {
    expect(table(row('category_eu_widget', link('/admin/posts/widget')))).toBeUndefined()
    expect(table(row('post_42', link('/admin/posts/42')))).toBeUndefined()
  })

  it('is unsupported when the own record cannot be told from an associated one', () => {
    expect(table(row('post_42', link('/admin/posts/7', 'member_link') + link('/admin/posts/9', 'member_link')))).toBeUndefined()
    expect(table(row('post_42', link('/admin/posts/7') + link('/admin/posts/9')))).toBeUndefined()
  })

  it('does not trust a primary key that no link confirms', () => {
    expect(table(row('post_42', link('/admin/posts/hello-world'), '42'))).toBeUndefined()
    expect(table(row('post_42', '', '42'))).toBeUndefined()
  })
})

describe('isIndexUrl', () => {
  const index = (url: string) => isIndexUrl(url, 'https://app.test', '/admin/posts')

  it('accepts the index itself, with or without a query or trailing slash', () => {
    expect(index('https://app.test/admin/posts?classic=1')).toBe(true)
    expect(index('https://app.test/admin/posts/')).toBe(true)
  })

  it('rejects a redirect to another resource, sign-in page or host', () => {
    expect(index('https://app.test/admin/authors')).toBe(false)
    expect(index('https://app.test/admin/login')).toBe(false)
    expect(index('https://sso.test/admin/posts')).toBe(false)
  })
})
