import { useCallback, useEffect, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '@/api/fetcher'
import { getGetManifestQueryOptions, getGetResourceMetaQueryKey, useGetManifest } from '@/api/generated/core'
import type { MenuItem, ResourceMeta } from '@/api/generated/model'
import { mapClassicUrl } from '@/lib/classic'
import type { Formats } from '@/lib/datetime'
import { loadManifest } from '@/lib/manifestCache'

// Never stale: the Layout revalidates once per load, and the last manifest paints the shell meanwhile.
export const useManifest = () => useGetManifest({ query: { staleTime: Infinity, initialData: loadManifest, initialDataUpdatedAt: 0 } })

// Observes the manifest without ever fetching it, for consumers that only format with what the shell loaded.
const useLoadedManifest = () => useQuery({ ...getGetManifestQueryOptions(), enabled: false, staleTime: Infinity }).data

export const useSite = () => useLoadedManifest()?.site

const NO_HOSTS: string[] = []

// Hosts besides this site that images and documents may load from; none until the manifest has loaded.
export const useTrustedMediaHosts = () => useSite()?.trusted_media_hosts ?? NO_HOSTS

export function useFormats(): Formats {
  const site = useSite()
  return useMemo(
    () => ({ timeZone: site?.time_zone, locale: site?.locale, dateFormat: site?.date_format, dateTimeFormat: site?.datetime_format }),
    [site],
  )
}

export const useResourceSummary = (key?: string) => {
  const { data, ...rest } = useManifest()
  return { summary: data?.resources.find((r) => r.key === key), ...rest }
}

export const META_STALE = 5 * 60_000

// Server procs (scope-dependent filters, nested parents) read request params, so `_meta` carries the scope and the
// parent's id. Without either the key is the plain one, which menu hover prefetches.
export type MetaContext = { scope?: string; parent?: { param: string; id: string } }

export const metaParams = ({ scope, parent }: MetaContext = {}): Record<string, string> => ({
  ...(scope && { scope }),
  ...(parent && { [parent.param]: parent.id }),
})

// Meta is fetched per resource when its route mounts (or ahead of time, from menu hover).
export const useResourceMeta = (key = '', context?: MetaContext) => {
  const { summary, isPending: manifestPending } = useResourceSummary(key)
  const params = metaParams(context)
  const query = new URLSearchParams(params).toString()
  const { data: meta, error, isPending, refetch } = useQuery({
    queryKey: query ? [...getGetResourceMetaQueryKey(key), params] : getGetResourceMetaQueryKey(key),
    queryFn: ({ signal }) => apiFetch<ResourceMeta>(`/admin/${key}/_meta${query && `?${query}`}`, { signal }),
    enabled: !!key,
    staleTime: META_STALE,
    // Keeps the previous scope's meta on screen, never another resource's.
    placeholderData: (previous, previousQuery) => (previousQuery?.queryKey[0] === getGetResourceMetaQueryKey(key)[0] ? previous : undefined),
  })
  return { summary, meta, error, refetch, isPending, manifestPending }
}

const pageKeys = (items: MenuItem[]): string[] => items.flatMap((i) => [...(i.page ? [i.page] : []), ...pageKeys(i.children)])

// Resolves classic admin URLs (action hrefs, links inside frames) to in-app routes where the client has a screen.
export function useMapClassic() {
  const manifest = useLoadedManifest()
  const targets = useMemo(
    () => ({ resources: new Set(manifest?.resources.map((r) => r.key)), pages: new Set(pageKeys([...(manifest?.menu ?? []), ...(manifest?.site.utility_menu ?? [])])) }),
    [manifest],
  )
  return useCallback((url: string) => mapClassicUrl(url, targets), [targets])
}

export function useDocumentTitle(page?: string | null) {
  const site = useSite()?.title
  useEffect(() => {
    document.title = [page, site].filter(Boolean).join(' – ') || 'Admin'
  }, [page, site])
}
