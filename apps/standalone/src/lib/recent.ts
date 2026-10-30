import { STORAGE_PREFIX } from './storage'

// Only a pointer is persisted: names and labels can be sensitive, so the palette fetches them when it opens.
export type Recent = { resource: string; id: string; at: number }

const KEY = `${STORAGE_PREFIX}recent`
const LIMIT = 10

const save = (recents: Recent[]) => {
  try {
    localStorage.setItem(KEY, JSON.stringify(recents))
  } catch {
    // storage unavailable: recents are a convenience
  }
}

const isRecent = (value: unknown): value is Recent => {
  const { resource, id, at } = (value ?? {}) as Partial<Record<keyof Recent, unknown>>
  return typeof resource === 'string' && typeof id === 'string' && typeof at === 'number'
}

// Entries written by older builds carried display text; they are cut back to the pointer on first read.
export function readRecents(): Recent[] {
  try {
    const stored: unknown[] = JSON.parse(localStorage.getItem(KEY) ?? '[]')
    const recents = stored.filter(isRecent).map(({ resource, id, at }) => ({ resource, id, at }))
    if (stored.some((entry, i) => JSON.stringify(entry) !== JSON.stringify(recents[i]))) save(recents)
    return recents
  } catch {
    return []
  }
}

export const recordVisit = ({ resource, id }: Pick<Recent, 'resource' | 'id'>, at = Date.now()) =>
  save([{ resource, id, at }, ...readRecents().filter((r) => r.resource !== resource || r.id !== id)].slice(0, LIMIT))

export const forgetVisit = ({ resource, id }: Pick<Recent, 'resource' | 'id'>) =>
  save(readRecents().filter((r) => r.resource !== resource || r.id !== id))
