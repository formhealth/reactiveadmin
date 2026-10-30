import { Link, useLocation, useParams } from 'react-router'
import { useGetRecord } from '@/api/generated/core'
import { openedRecordQuery } from '@/api/recordQuery'
import { ActionBar } from '@/components/ActionBar'
import { TextWithIds } from '@/components/IdValue'
import { DegradedNotice } from '@/components/DegradedNotice'
import { ErrorState } from '@/components/ErrorState'
import { PageHeader } from '@/components/PageHeader'
import { SidebarSections } from '@/components/Sidebars'
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from '@/components/ui/breadcrumb'
import { Skeleton } from '@/components/ui/skeleton'
import { useDocumentTitle, useResourceSummary } from '@/hooks/useManifest'
import { useRecordVisit } from '@/hooks/useRecordVisit'
import { ValueRefreshContext } from '@/json/expand'
import { classicUrl } from '@/lib/classic'
import { isUuid, shortId } from '@/lib/ids'
import { NodeContext } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'
import { pluralLabel } from '@/lib/humanize'

export function ResourceShow() {
  const { resource = '', id = '' } = useParams()
  const { state } = useLocation()
  const { summary } = useResourceSummary(resource)
  const { data, error, refetch } = useGetRecord(resource, id, { query: openedRecordQuery })
  const listPath = `/${resource}${state?.search ?? ''}`
  const label = pluralLabel(summary, resource)
  const name = data?.display_name
  useDocumentTitle(name ?? data?.title)
  useRecordVisit(!!data, resource, id)
  const refreshValues = () => refetch().then((result) => result.data)

  if (error) return <ErrorState error={error} label={label} onRetry={refetch} backTo={{ to: listPath, label: `Back to ${label}` }} />

  return (
    <div className="flex flex-col gap-5">
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink asChild>
              <Link to={listPath}>{label}</Link>
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          <BreadcrumbItem>
            <BreadcrumbPage className={name ? undefined : 'font-mono'}>{name ?? (isUuid(id) ? `${shortId(id)}…` : `#${id}`)}</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <PageHeader title={data ? <TextWithIds text={data.title} /> : <Skeleton className="h-8 w-64" />}>
        {data && data.actions.length > 0 && <ActionBar actions={data.actions} ctx={{ resource, id, name }} />}
      </PageHeader>

      <DegradedNotice degraded={data?.degraded} classicHref={classicUrl(resource, id)} />

      {data ? (
        <NodeContext value={{ resource, id, name }}>
          <ValueRefreshContext value={refreshValues}>
            <div className="flex flex-col gap-4">
              <NodeList nodes={data.layout} />
              {data.sidebars && data.sidebars.length > 0 && <SidebarSections sidebars={data.sidebars} ctx={{ resource, id, name }} />}
            </div>
          </ValueRefreshContext>
        </NodeContext>
      ) : (
        <div className="flex flex-col gap-3">
          {Array.from({ length: 6 }, (_, i) => (
            <Skeleton key={i} className="h-6 w-full max-w-2xl" />
          ))}
        </div>
      )}
    </div>
  )
}
