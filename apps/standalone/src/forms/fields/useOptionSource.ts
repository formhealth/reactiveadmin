import { useState } from 'react'
import { keepPreviousData, useInfiniteQuery, useQuery } from '@tanstack/react-query'
import { apiFetch, isRateLimited } from '@/api/fetcher'
import type { Option, OptionsResponse } from '@/api/generated/model'
import { useOptionLookup } from './optionLookupContext'
import { useDebounced } from '@/hooks/useDebounced'
import { readRecentOptions, rememberOption } from '@/lib/recentOptions'

export const PAGE = 30
const SEARCH_DELAY = 200

export const optionsUrl = (path: string, params: Record<string, string | undefined>) => {
  const search = new URLSearchParams(Object.entries(params).filter((entry): entry is [string, string] => entry[1] !== undefined))
  return `${path}${path.includes('?') ? '&' : '?'}${search}`
}

const unique = (options: Option[]) => [...new Map(options.map((o) => [o.value, o])).values()]

type SourceArgs = { path?: string | null; inline?: Option[]; selected: string[]; open: boolean }

// Everything a picker needs from an options endpoint: paged search, labels for the selected and recent values
// (by batched value lookup, so a saved id shows its name), and a per-field memory of what was picked last.
export function useOptionSource({ path, inline = [], selected, open }: SourceArgs) {
  const [term, setTerm] = useState('')
  const [picked, setPicked] = useState<Record<string, Option>>({})
  const [recent, setRecent] = useState<string[]>(() => (path ? readRecentOptions(path) : []))
  const debounced = useDebounced(term, SEARCH_DELAY)
  const optionLookup = useOptionLookup()

  const search = useInfiniteQuery({
    queryKey: ['options', path, debounced],
    queryFn: ({ pageParam, signal }) => apiFetch<OptionsResponse>(optionsUrl(path!, { term: debounced, limit: String(PAGE), cursor: pageParam }), { signal }),
    initialPageParam: undefined as string | undefined,
    getNextPageParam: (last) => last.next_cursor ?? undefined,
    enabled: !!path && open,
    placeholderData: keepPreviousData,
  })
  const found = unique(search.data?.pages.flatMap((page) => page.options) ?? [])
  const lastPage = search.data?.pages.at(-1)

  const known = new Map<string, Option>([...inline, ...found, ...Object.values(picked)].map((o) => [o.value, o]))
  const missing = [...new Set([...selected, ...(open ? recent : [])])].filter((value) => !known.has(value))
  const resolved = useQuery({
    queryKey: ['options', path, 'values', missing],
    queryFn: () => optionLookup.load(path!, missing),
    enabled: !!path && missing.length > 0,
  })
  resolved.data?.forEach((o) => known.set(o.value, o))

  const remember = (option: Option) => {
    setPicked((p) => ({ ...p, [option.value]: option }))
    if (!path) return
    rememberOption(path, option.value)
    setRecent(readRecentOptions(path))
  }

  const lookup = async (value: string) => {
    if (!path) return undefined
    return (await optionLookup.load(path, [value]))[0]
  }

  return {
    term,
    setTerm,
    found,
    searching: !!path && search.isFetching && !search.isFetchingNextPage,
    // Searches wait out the server's `Retry-After` (the fetcher refuses them until then); say so instead of "No matches".
    rateLimited: isRateLimited(search.error),
    loadingMore: search.isFetchingNextPage,
    hasMore: !!search.hasNextPage,
    loadMore: () => search.fetchNextPage(),
    truncated: !!lastPage?.truncated,
    optionOf: (value: string) => known.get(value),
    labelOf: (value: string) => known.get(value)?.label ?? value,
    recent: recent.flatMap((value) => known.get(value) ?? []),
    remember,
    lookup,
  }
}

export type OptionSource = ReturnType<typeof useOptionSource>
