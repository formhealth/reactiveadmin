import { useQuery } from '@tanstack/react-query'
import { apiFetch } from '@/api/fetcher'
import { getListRecordsQueryKey } from '@/api/generated/core'
import type { IndexResponse, ListRecordsParams } from '@/api/generated/model'
import { listUrl, type ListQuery } from '@/lib/list'

// The generated hook can't send multi-valued predicates (`q[x_in][]=a&q[x_in][]=b`) or `as`, so the URL is built here.
// The key keeps the generated shape, which is what invalidation by resource matches on.
// Previous rows stay up while paging or filtering, but never carry over to another resource.
export const useIndex = (resource: string, query: ListQuery, enabled = true) =>
  useQuery({
    queryKey: getListRecordsQueryKey(resource, query as ListRecordsParams),
    queryFn: ({ signal }) => apiFetch<IndexResponse>(listUrl(resource, query), { signal }),
    placeholderData: (prev, prevQuery) => (prevQuery?.queryKey[0] === `/admin/${resource}` ? prev : undefined),
    enabled,
  })
