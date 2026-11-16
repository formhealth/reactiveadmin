import { describe, expect, it } from 'vitest'
import { writeBody } from './writeBody'

describe('writeBody', () => {
  it('sends multipart with Rails names when the body holds a file', () => {
    const avatar = new File(['png'], 'a.png', { type: 'image/png' })
    const body = writeBody({ author: { name: 'Ann', avatar, tag_ids: ['1', '2'], bio: null, active: true } })
    expect(body).toBeInstanceOf(FormData)
    const data = body as FormData
    expect([...data.keys()]).toEqual(['author[name]', 'author[avatar]', 'author[tag_ids][]', 'author[tag_ids][]', 'author[bio]', 'author[active]'])
    expect(data.get('author[avatar]')).toBeInstanceOf(File)
    expect((data.get('author[avatar]') as File).name).toBe('a.png')
    expect(data.getAll('author[tag_ids][]')).toEqual(['1', '2'])
    expect(data.get('author[bio]')).toBe('')
  })

  it('sends an emptied list as a clear, but no entry for emptied nested rows', () => {
    const avatar = new File(['png'], 'a.png', { type: 'image/png' })
    const data = writeBody({ author: { avatar, tag_ids: [], posts_attributes: [], metadata: '{}' } }) as FormData
    expect([...data.entries()].filter(([name]) => name !== 'author[avatar]')).toEqual([
      ['author[tag_ids][]', ''],
      ['author[metadata]', '{}'],
    ])
  })

  it('sends JSON without a file', async () => {
    const body = writeBody({ author: { name: 'Ann', bio: null } })
    expect(body).not.toBeInstanceOf(FormData)
    expect((body as Blob).type).toBe('application/json')
    expect(JSON.parse(await (body as Blob).text())).toEqual({ author: { name: 'Ann', bio: null } })
  })
})
