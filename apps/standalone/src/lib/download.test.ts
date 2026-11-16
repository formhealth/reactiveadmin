// @vitest-environment jsdom
import { afterEach, describe, expect, it, vi } from 'vitest'
import { fetchDownload } from './download'

describe('fetchDownload', () => {
  afterEach(() => {
    vi.unstubAllGlobals()
    vi.restoreAllMocks()
  })

  it('fetches the href and saves the blob under its file name', async () => {
    const fetchMock = vi.fn().mockResolvedValue(new Response('id\n1\n'))
    vi.stubGlobal('fetch', fetchMock)
    const createObjectURL = vi.fn(() => 'blob:csv')
    const revokeObjectURL = vi.fn()
    vi.stubGlobal('URL', Object.assign(URL, { createObjectURL, revokeObjectURL }))
    const saved: { href: string; download: string }[] = []
    vi.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function (this: HTMLAnchorElement) {
      saved.push({ href: this.href, download: this.download })
    })
    const event = { preventDefault: vi.fn() }

    await fetchDownload('/api/admin/posts.csv?scope=embargoed')(event as never)

    expect(event.preventDefault).toHaveBeenCalled()
    expect(fetchMock).toHaveBeenCalledWith('/api/admin/posts.csv?scope=embargoed')
    expect(saved).toEqual([{ href: 'blob:csv', download: 'posts.csv' }])
    expect(revokeObjectURL).toHaveBeenCalledWith('blob:csv')
  })
})
