import type { QueryClient } from '@tanstack/react-query'
import type { NavigateFunction } from 'react-router'
import type { Location } from '@/api/generated/model'
import { mountPath } from '@/lib/base'

const isData = (key: unknown) => !/\/(_meta|_manifest|_session)$/.test(String(key))

// Keys of hooks generated from a host's document carry the mount (`/api/admin/authors`); the client's own don't.
// Both forms are tried: with a mount of `/admin`, stripping it from a client key would drop the namespace.
const resourceKeys = (key: unknown) => {
  const path = String(key)
  return path.startsWith(`${mountPath}/`) ? [path, path.slice(mountPath.length)] : [path]
}

// `/<namespace>/comments...` or, nested under parents, `/<namespace>/posts/7/comments...`, whatever the namespace is.
const routeOf = (resource: string) => new RegExp(`^/[^/]+(?:/[^/]+/[^/]+)*/${resource.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?:[/?]|$)`)

// `refetchType: 'none'` when the caller is about to leave the page: stale data refetches on next mount.
// Meta is cached server-side per permission set, so a record write never invalidates it.
export const invalidateResource = (queryClient: QueryClient, resource: string, refetchType: 'active' | 'none' = 'active') =>
  queryClient.invalidateQueries({ predicate: (q) => resourceKeys(q.queryKey[0]).some((key) => routeOf(resource).test(key)) && isData(q.queryKey[0]), refetchType })

// For writes whose reach is unknown (frames, pages): everything on screen refetches.
export const invalidateData = (queryClient: QueryClient) => queryClient.invalidateQueries({ predicate: (q) => isData(q.queryKey[0]) })

export const routeFor = ({ resource, id, view }: Location) =>
  resource && (view === 'new' ? `/${resource}/new` : id && view === 'edit' ? `/${resource}/${id}/edit` : id && view !== 'index' ? `/${resource}/${id}` : `/${resource}`)

// Follows where the classic admin would have redirected: an in-app route when it maps to a resource or page,
// otherwise the classic page in a new tab while the app falls back to `fallback`.
export function follow(navigate: NavigateFunction, location: Location | undefined, fallback: string, mapUrl?: (url: string) => string | undefined) {
  const to = location && (routeFor(location) || (location.url ? mapUrl?.(location.url) : undefined))
  if (to) return navigate(to)
  if (location?.url) window.open(location.url, '_blank', 'noopener')
  navigate(fallback)
}
