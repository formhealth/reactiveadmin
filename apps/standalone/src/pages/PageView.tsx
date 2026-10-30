import { useQuery } from '@tanstack/react-query'
import { useParams } from 'react-router'
import { apiFetch } from '@/api/fetcher'
import { getGetPageQueryKey, getGetPageUrl } from '@/api/generated/core'
import type { PageResponse } from '@/api/generated/model'
import { ActionBar } from '@/components/ActionBar'
import { DegradedNotice } from '@/components/DegradedNotice'
import { ErrorState } from '@/components/ErrorState'
import { PageHeader } from '@/components/PageHeader'
import { Skeleton } from '@/components/ui/skeleton'
import { withSearch } from '@/forms/query'
import { useDocumentTitle } from '@/hooks/useManifest'
import { ValueRefreshContext } from '@/json/expand'
import { classicUrl } from '@/lib/classic'
import { NodeContext, useViewQuery } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'

// An AA `register_page`: its layout is walked into nodes, with anything interactive as frame or iframe nodes.
// `page` is given where the route can't name it: classic URLs are `/admin/:page` and `/admin/:resource` alike.
export function PageView({ page: named }: { page?: string }) {
  const params = useParams()
  const page = named ?? params.page ?? ''
  // A GET form in the content replaces the query. It lives in the address bar, so results can be bookmarked.
  const { search } = useViewQuery()
  const [key] = getGetPageQueryKey(page)
  const { data, error, refetch, isFetching } = useQuery({
    queryKey: [key, search],
    queryFn: ({ signal }) => apiFetch<PageResponse>(withSearch(getGetPageUrl(page), search), { signal }),
    // The results stay up while the next query loads, but another page never stands in for this one.
    placeholderData: (previous, previousQuery) => (previousQuery?.queryKey[0] === key ? previous : undefined),
  })
  useDocumentTitle(data?.title)
  const refreshValues = () => refetch().then((result) => result.data)

  if (error) return <ErrorState error={error} label="this page" onRetry={refetch} />

  return (
    <div className="flex flex-col gap-5">
      <PageHeader title={data?.title ?? <Skeleton className="h-8 w-64" />}>{data && data.actions.length > 0 && <ActionBar actions={data.actions} />}</PageHeader>

      <DegradedNotice degraded={data?.degraded} classicHref={classicUrl(page)} />

      {data ? (
        <NodeContext value={{}}>
          <ValueRefreshContext value={refreshValues}>
            <div aria-busy={isFetching} className="flex flex-col gap-4">
              <NodeList nodes={data.layout} />
            </div>
          </ValueRefreshContext>
        </NodeContext>
      ) : (
        <div className="flex flex-col gap-3">
          {Array.from({ length: 5 }, (_, i) => (
            <Skeleton key={i} className="h-6 w-full max-w-2xl" />
          ))}
        </div>
      )}
    </div>
  )
}
