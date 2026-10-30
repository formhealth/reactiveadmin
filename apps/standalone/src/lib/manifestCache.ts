import { fetchSession } from '@/api/fetcher'
import type { Manifest, Session } from '@/api/generated/model'
import { clearClientStorage, STORAGE_PREFIX } from './storage'

// The shell paints from the last manifest while a fresh one loads. Entries are keyed by schema version and user,
// so neither a contract bump nor a different sign-in can render another menu.
export const SCHEMA_VERSION = 2

const PREFIX = `${STORAGE_PREFIX}manifest`
const USER = `${PREFIX}:user`
const keyFor = (user: string) => `${PREFIX}:v${SCHEMA_VERSION}:${user}`
const read = <T>(key: string) => JSON.parse(localStorage.getItem(key) ?? 'null') as T | null

export function loadManifest(): Manifest | undefined {
  try {
    const user = read<string>(USER)
    const manifest = user && read<Manifest>(keyFor(user))
    return manifest && manifest.schema_version === SCHEMA_VERSION ? manifest : undefined
  } catch {
    return undefined
  }
}

export function saveManifest(manifest: Manifest) {
  if (manifest.schema_version !== SCHEMA_VERSION) return
  const user = manifest.site.current_user?.id ?? 'anonymous'
  clearManifest()
  try {
    localStorage.setItem(USER, JSON.stringify(user))
    localStorage.setItem(keyFor(user), JSON.stringify(manifest))
  } catch {
    // quota or private mode: the next load just fetches
  }
}

export function clearManifest() {
  try {
    Array.from({ length: localStorage.length }, (_, i) => localStorage.key(i) ?? '')
      .filter((key) => key.startsWith(PREFIX))
      .forEach((key) => localStorage.removeItem(key))
  } catch {
    // storage unavailable
  }
}

// The cached menu and permissions belong to whoever signed in last. Before the shell may paint from them the live
// session must name the same user; any other outcome (another user, 401, no answer) drops everything persisted.
// The caller bounds `session`, so an answer that never comes arrives here as a failure.
export async function verifyCachedManifest(session: () => Promise<Pick<Session, 'user'>> = fetchSession) {
  const cached = loadManifest()
  if (!cached) return
  try {
    const { user } = await session()
    if (user.id !== cached.site.current_user?.id) clearClientStorage()
  } catch {
    clearClientStorage()
  }
}
