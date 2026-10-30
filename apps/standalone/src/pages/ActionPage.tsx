import { Link, useLocation, useNavigate, useParams } from 'react-router'
import { useGetRecord } from '@/api/generated/core'
import type { Action } from '@/api/generated/model'
import { ErrorState } from '@/components/ErrorState'
import { PageHeader } from '@/components/PageHeader'
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from '@/components/ui/breadcrumb'
import { Skeleton } from '@/components/ui/skeleton'
import { useActionDone } from '@/hooks/useRecordAction'
import { useDocumentTitle, useResourceMeta, useResourceSummary } from '@/hooks/useManifest'
import { isUuid, shortId } from '@/lib/ids'
import { ActionViewBody } from '@/views/ActionView'
import { pluralLabel } from '@/lib/humanize'

// A GET action presented as a page: `/:resource/:id/actions/:key`, or `/:resource/actions/:key` for collection actions.
// The action arrives in router state from the click; on a reload it is looked up again in the record or resource meta.
export function ActionPage() {
  const { resource = '', id, key = '' } = useParams()
  const { state } = useLocation()
  const navigate = useNavigate()
  const record = useGetRecord(resource, id ?? '', { query: { enabled: !!id } })
  const { summary } = useResourceSummary(resource)
  const { meta } = useResourceMeta(id ? '' : resource)
  const action: Action | undefined = state?.action ?? record.data?.actions.find((a) => a.key === key) ?? meta?.action_items?.find((a) => a.key === key)
  const name = record.data?.display_name ?? (id ? (isUuid(id) ? `${shortId(id)}…` : `#${id}`) : undefined)
  const done = useActionDone({ resource, id, name: record.data?.display_name })
  const label = pluralLabel(summary ?? meta, resource)
  const backTo = id ? `/${resource}/${id}` : `/${resource}`
  useDocumentTitle(action?.label)

  const missing = !action && (id ? !record.isPending : !!meta)
  if (record.error || missing) return <ErrorState error={record.error ?? new Error('That action is not available')} label="this action" backTo={{ to: backTo, label: `Back to ${label}` }} />

  return (
    <div className="flex flex-col gap-5">
      <Breadcrumb>
        <BreadcrumbList>
          <BreadcrumbItem>
            <BreadcrumbLink asChild>
              <Link to={`/${resource}`}>{label}</Link>
            </BreadcrumbLink>
          </BreadcrumbItem>
          <BreadcrumbSeparator />
          {name && (
            <>
              <BreadcrumbItem>
                <BreadcrumbLink asChild>
                  <Link to={backTo}>{name}</Link>
                </BreadcrumbLink>
              </BreadcrumbItem>
              <BreadcrumbSeparator />
            </>
          )}
          <BreadcrumbItem>
            <BreadcrumbPage>{action?.label ?? key}</BreadcrumbPage>
          </BreadcrumbItem>
        </BreadcrumbList>
      </Breadcrumb>

      <PageHeader title={action?.label ?? <Skeleton className="h-8 w-64" />} />

      {action ? (
        <ActionViewBody
          action={action}
          resource={resource}
          id={id}
          container="page"
          onClose={() => navigate(backTo)}
          onResult={(result) => {
            done(action, result)
            if (!result.location) navigate(backTo)
          }}
        />
      ) : (
        <Skeleton className="h-40 w-full max-w-3xl" />
      )}
    </div>
  )
}
