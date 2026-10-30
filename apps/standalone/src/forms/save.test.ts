import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { isStale } from '@/api/fetcher'
import type { FormResponse } from '@/api/generated/model'
import { saveRecord } from './save'

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

const form = (overrides: Partial<FormResponse> = {}): FormResponse => ({
  resource: 'desks',
  id: '7',
  title: 'Edit desk',
  action: { method: 'patch', path: '/api/admin/desks/7' },
  form: { sections: [] },
  permissions: { update: true },
  ...overrides,
})

const lock = { field: 'lock_version', value: '3' } as const

describe('saveRecord', () => {
  const fetchMock = vi.fn<typeof fetch>()
  const writes = () => fetchMock.mock.calls.filter(([url]) => String(url).endsWith('/desks/7'))
  const body = () => JSON.parse(String(writes()[0][1]?.body))

  beforeEach(() => {
    fetchMock.mockReset()
    fetchMock.mockImplementation(async (url) => (String(url).endsWith('_session') ? json(200, { csrf_token: 't' }) : json(200, { ok: true, id: '7' })))
    vi.stubGlobal('fetch', fetchMock)
  })
  afterEach(() => vi.unstubAllGlobals())

  it('sends the lock from the form with an update', async () => {
    await saveRecord(form({ lock }), [['desk[name]', 'East']])
    expect(writes()[0][1]?.method).toBe('PATCH')
    expect(body()).toEqual({ desk: { name: 'East' }, lock: { field: 'lock_version', value: '3' } })
  })

  it('sends the lock in multipart bodies too', async () => {
    const file = new File(['x'], 'a.txt')
    await saveRecord(form({ lock }), [['desk[doc]', file]])
    const data = writes()[0][1]?.body as FormData
    expect(data.get('lock[field]')).toBe('lock_version')
    expect(data.get('lock[value]')).toBe('3')
  })

  it('leaves the body alone when the form has no lock', async () => {
    await saveRecord(form(), [['desk[name]', 'East']])
    expect(body()).toEqual({ desk: { name: 'East' } })
  })

  it('never writes when the form is not submittable', async () => {
    await expect(saveRecord(form({ submittable: false, lock }), [['desk[name]', 'East']])).rejects.toThrow("can't be saved")
    expect(fetchMock).not.toHaveBeenCalled()
  })

  it('writes when the form is explicitly submittable', async () => {
    await saveRecord(form({ submittable: true }), [['desk[name]', 'East']])
    expect(writes()).toHaveLength(1)
  })

  it('surfaces a stale write as a 409 the form can recognise', async () => {
    fetchMock.mockImplementation(async (url) => (String(url).endsWith('_session') ? json(200, { csrf_token: 't' }) : json(409, { code: 'stale', message: 'Record changed' })))
    const error = await saveRecord(form({ lock }), [['desk[name]', 'East']]).catch((e) => e)
    expect(isStale(error)).toBe(true)
  })
})
