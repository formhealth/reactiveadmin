import { beforeEach, describe, expect, it } from 'vitest'
import type { Manifest } from '@/api/generated/model'
import { stubLocalStorage } from '@/test/memoryStorage'
import { clearManifest, loadManifest, saveManifest, verifyCachedManifest } from './manifestCache'

const manifest = (user: string, schema_version = 2) =>
  ({ schema_version, site: { title: 'Acme Admin', current_user: { id: user, display_name: user } }, menu: [], resources: [] }) as unknown as Manifest

describe('manifest cache', () => {
  let store: Map<string, string>
  beforeEach(() => {
    store = stubLocalStorage()
  })

  it('round-trips the last manifest for the current user', () => {
    saveManifest(manifest('u-1'))
    expect(loadManifest()?.site.current_user?.id).toBe('u-1')
  })

  it('follows the most recent sign-in and drops the previous entry', () => {
    saveManifest(manifest('u-1'))
    saveManifest(manifest('u-2'))
    expect(loadManifest()?.site.current_user?.id).toBe('u-2')
    expect(localStorage.getItem('ra:manifest:v2:u-1')).toBeNull()
  })

  it('ignores manifests from another schema version', () => {
    saveManifest(manifest('u-1', 3))
    expect(loadManifest()).toBeUndefined()
    localStorage.setItem('ra:manifest:user', JSON.stringify('u-9'))
    localStorage.setItem('ra:manifest:v2:u-9', JSON.stringify(manifest('u-9', 1)))
    expect(loadManifest()).toBeUndefined()
  })

  it('clears everything it wrote', () => {
    saveManifest(manifest('u-1'))
    clearManifest()
    expect(loadManifest()).toBeUndefined()
  })

  describe('verifyCachedManifest', () => {
    const seed = () => {
      saveManifest(manifest('u-1'))
      store.set('ra:recent', '[{"resource":"authors","id":"1","at":1}]')
      store.set('ra:menu:open', '["billing"]')
    }
    const session = (id: string) => () => Promise.resolve({ user: { id, display_name: id } })

    it('trusts the cache when the live session is the same user', async () => {
      seed()
      await verifyCachedManifest(session('u-1'))
      expect(loadManifest()?.site.current_user?.id).toBe('u-1')
      expect(store.has('ra:recent')).toBe(true)
    })

    it('clears every reactiveadmin key when the user differs', async () => {
      seed()
      store.set('theme', 'dark')
      await verifyCachedManifest(session('u-2'))
      expect(loadManifest()).toBeUndefined()
      expect([...store.keys()]).toEqual(['theme'])
    })

    it('clears them when the session check fails', async () => {
      seed()
      await verifyCachedManifest(() => Promise.reject(new Error('401')))
      expect([...store.keys()]).toEqual([])
    })

    it('does nothing without a cached manifest', async () => {
      let asked = false
      await verifyCachedManifest(() => ((asked = true), session('u-1')()))
      expect(asked).toBe(false)
    })
  })
})
