import { describe, expect, it } from 'vitest'
import type { Node as NodeData } from '@/api/generated/model'
import { tabParams } from './tabParams'

const tabs = (...titles: string[]): NodeData => ({ type: 'tabs', children: titles.map((title) => ({ type: 'tab', title, children: [] })) })
const panel = (...children: NodeData[]): NodeData => ({ type: 'panel', title: 'Panel', children })

describe('tabParams', () => {
  it('keeps `tab` for the first group and numbers the rest in page order', () => {
    const nested = tabs('Drafts', 'Published')
    const first: NodeData = { type: 'tabs', children: [{ type: 'tab', title: 'Overview', children: [] }, { type: 'tab', title: 'Posts', children: [nested] }] }
    const last = tabs('Overview', 'History')
    const params = tabParams([panel(first), { type: 'box', children: [last] }])
    expect([params.get(first), params.get(nested), params.get(last)]).toEqual(['tab', 'tab2', 'tab3'])
  })

  it('prefixes the params of a scope of its own', () => {
    const first = tabs('A', 'B')
    const second = tabs('C', 'D')
    const params = tabParams([first, second], 'comments.0.body.tab')
    expect([params.get(first), params.get(second)]).toEqual(['comments.0.body.tab', 'comments.0.body.tab2'])
  })

  it('names nothing on a page without tabs', () => {
    expect(tabParams([panel({ type: 'text', text: 'Hello' })]).size).toBe(0)
  })

  it('looks inside table cells and attribute values', () => {
    const inCell = tabs('A', 'B')
    const inRow = tabs('C', 'D')
    const params = tabParams([
      { type: 'table', headers: ['Body'], rows: [[inCell]] },
      { type: 'attributes_table', rows: [{ label: 'Body', value: [inRow] }] },
    ])
    expect([params.get(inCell), params.get(inRow)]).toEqual(['tab', 'tab2'])
  })
})
