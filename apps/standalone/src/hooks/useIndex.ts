import { keepPreviousData, useQuery } from '@tanstack/react-query'
import { apiFetch } from '@/api/fetcher'
import { getListRecordsQueryKey } from '@/api/generated/core'
import type { IndexResponse, ListRecordsParams } from '@/api/generated/model'
import { listUrl, type ListQuery } from '@/lib/list'

// The generated hook can't send multi-valued predicates (`q[x_in][]=a&q[x_in][]=b`) or `as`, so the URL is built here.
// The key keeps the generated shape, which is what invalidation by resource matches on.
export const useIndex = (resource: string, query: ListQuery, enabled = true) =>
  useQuery({
    queryKey: getListRecordsQueryKey(resource, query as ListRecordsParams),
    queryFn: ({ signal }) => apiFetch<IndexResponse>(listUrl(resource, query), { signal }),
    placeholderData: keepPreviousData,
    enabled,
  })
