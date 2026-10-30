import { STORAGE_PREFIX } from './storage'

const LIMIT = 5

// A field is its options endpoint plus `field` and `context`; the record id and search term are not part of it.
export function optionsKey(path: string) {
  const url = new URL(path, 'http://local')
  return [url.pathname, url.searchParams.get('field'), url.searchParams.get('context')].join('|')
}

const storageKey = (path: string) => `${STORAGE_PREFIX}options:${optionsKey(path)}`

// Values only: a value is an id, while labels can be names. The picker looks the labels up when it opens.
export function readRecentOptions(path: string): string[] {
  try {
    const stored: unknown = JSON.parse(localStorage.getItem(storageKey(path)) ?? '[]')
    return Array.isArray(stored) ? stored.filter((v): v is string => typeof v === 'string') : []
  } catch {
    return []
  }
}

export function rememberOption(path: string, value: string) {
  try {
    localStorage.setItem(storageKey(path), JSON.stringify([value, ...readRecentOptions(path).filter((v) => v !== value)].slice(0, LIMIT)))
  } catch {
    // storage unavailable: recents are a convenience
  }
}
