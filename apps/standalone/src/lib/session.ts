import { csrfToken } from '@/api/fetcher'
import type { Site } from '@/api/generated/model'
import { clearClientStorage } from './storage'

// Non-GET logouts (Devise's DELETE) must be a real form submission so the browser follows the redirect.
export async function signOut({ url, method }: NonNullable<Site['logout']>) {
  clearClientStorage()
  if (method === 'get') return window.location.assign(url)
  const form = Object.assign(document.createElement('form'), { method: 'post', action: url, hidden: true })
  const field = (name: string, value: string) => form.append(Object.assign(document.createElement('input'), { type: 'hidden', name, value }))
  field('_method', method)
  field('authenticity_token', await csrfToken())
  document.body.append(form)
  form.submit()
}
