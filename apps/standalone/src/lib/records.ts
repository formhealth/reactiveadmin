import type { QueryClient } from '@tanstack/react-query'
import type { NavigateFunction } from 'react-router'
import type { Location } from '@/api/generated/model'

const isData = (key: unknown) => !/\/(_meta|_manifest|_session)$/.test(String(key))

// `refetchType: 'none'` when the caller is about to leave the page: stale data refetches on next mount.
// Meta is cached server-side per permission set, so a record write never invalidates it.
export const invalidateResource = (queryClient: QueryClient, resource: string, refetchType: 'active' | 'none' = 'active') =>
  queryClient.invalidateQueries({ predicate: (q) => String(q.queryKey[0]).startsWith(`/admin/${resource}`) && isData(q.queryKey[0]), refetchType })

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
