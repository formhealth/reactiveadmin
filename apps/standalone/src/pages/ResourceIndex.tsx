import { useEffect, useMemo } from 'react'
import { Info, Plus, X } from 'lucide-react'
import { Link, useLocation, useNavigate, useParams } from 'react-router'
import { ApiError } from '@/api/fetcher'
import type { IndexMetaBlankSlate, ResourceSummary } from '@/api/generated/model'
import { ActionBar, type BarAction } from '@/components/ActionBar'
import { BatchBar } from '@/components/BatchBar'
import { ClassicLink } from '@/components/ApiDenied'
import { CardsSkeleton, DataTable, TableSkeleton } from '@/components/DataTable'
import { DegradedNotice } from '@/components/DegradedNotice'
import { ErrorState } from '@/components/ErrorState'
import { FilterBar } from '@/components/filters/FilterBar'
import { PageHeader } from '@/components/PageHeader'
import { Pagination } from '@/components/Pagination'
import { RecordCards } from '@/components/RecordCards'
import { RecordViews } from '@/components/RecordViews'
import { ScopeTabs } from '@/components/ScopeTabs'
import { WithSidebars } from '@/components/Sidebars'
import { Alert, AlertDescription } from '@/components/ui/alert'
import { Button } from '@/components/ui/button'
import { Skeleton } from '@/components/ui/skeleton'
import { ViewSwitcher } from '@/components/ViewSwitcher'
import { useBatchAction } from '@/hooks/useBatchAction'
import { useHotkeys } from '@/hooks/useHotkeys'
import { useIndex } from '@/hooks/useIndex'
import { useListState } from '@/hooks/useListState'
import { useIsDesktop, useIsWide } from '@/hooks/useMediaQuery'
import { useDocumentTitle, useMapClassic, useResourceMeta, useResourceSummary, useSite } from '@/hooks/useManifest'
import { useSelection } from '@/hooks/useSelection'
import { classicUrl } from '@/lib/classic'
import { classicPage, isDenied } from '@/lib/apiDenied'
import { exportHref } from '@/lib/export'
import { undeclared } from '@/lib/list'
import { pluralLabel } from '@/lib/humanize'

const rowLinks = () => [...document.querySelectorAll<HTMLElement>('[data-row-link]')]

const moveRow = (step: 1 | -1) => () => {
  const links = rowLinks()
  const current = links.indexOf(document.activeElement as HTMLElement)
  links[current < 0 ? (step > 0 ? 0 : links.length - 1) : Math.min(Math.max(current + step, 0), links.length - 1)]?.focus()
}

// New is a link to the classic admin when the host reserved creating for it, and absent when there is none to link to.
function NewButton({ summary, variant }: { summary: ResourceSummary; variant?: 'outline' }) {
  const reserved = isDenied(summary, 'new')
  const href = classicPage(summary, 'new', '/new')
  if (reserved && !href) return null
  return (
    <Button asChild variant={variant}>
      {href ? (
        <ClassicLink href={href}>
          <Plus />
          New {summary.label}
        </ClassicLink>
      ) : (
        <Link to={`/${summary.key}/new`}>
          <Plus />
          New {summary.label}
        </Link>
      )}
    </Button>
  )
}

type BlankSlateProps = { label: string; summary?: ResourceSummary; slate?: IndexMetaBlankSlate }

// AA's `blank_slate_link:` when the resource declared one (null label and href: none), else a create link if allowed.
function BlankSlate({ label, summary, slate }: BlankSlateProps) {
  const mapUrl = useMapClassic()
  const declared = slate && slate.label && slate.href
  const to = declared ? mapUrl(slate.href!) : undefined
  return (
    <div className="flex flex-col items-start gap-3 rounded-lg border border-dashed bg-card p-8">
      <p className="text-base">No {label.toLowerCase()} in this view</p>
      {declared ? (
        <Button asChild variant="outline">
          {to ? <Link to={to}>{slate.label}</Link> : <a href={slate.href!}>{slate.label}</a>}
        </Button>
      ) : (
        !slate &&
        summary?.permissions.create && (
          <NewButton summary={summary} variant="outline" />
        )
      )}
    </div>
  )
}

export function ResourceIndex() {
  const params = useParams()
  const { resource = '' } = params
  const desktop = useIsDesktop()
  const wide = useIsWide()
  const { summary: known } = useResourceSummary(resource)
  const parentParam = known?.belongs_to?.param
  const list = useListState()
  const parent = parentParam && params[parentParam] ? { param: parentParam, id: params[parentParam]! } : undefined
  const { meta, summary, manifestPending, error: metaError } = useResourceMeta(resource, { scope: list.scope, parent })
  const site = useSite()
  const location = useLocation()
  const navigate = useNavigate()
  const dropped: string[] = location.state?.dropped ?? []
  const batchActions = meta?.batch_actions ?? []
  const selection = useSelection(`${resource}|${list.scope}|${JSON.stringify(list.q)}`)
  const batch = useBatchAction(resource, [...selection.ids], selection.clear)
  const forbidden = (meta ?? summary)?.permissions.index === false
  useDocumentTitle((meta ?? summary)?.plural_label)

  // The server answers 400 to filters the resource doesn't declare (classic links carry arbitrary q[...]), so they
  // come off the URL before the list is asked for.
  const unknown = useMemo(() => (meta ? undeclared(list.q, meta.filters) : []), [meta, list.q])
  const hasQuery = Object.keys(list.q).length > 0
  const { dropKeys } = list
  useEffect(() => {
    if (unknown.length > 0) dropKeys(unknown)
  }, [unknown, dropKeys])

  const { data, error, isPlaceholderData, refetch } = useIndex(resource, list.params, !forbidden && (!hasQuery || !!meta) && unknown.length === 0)

  useHotkeys({
    '/': (e) => {
      e.preventDefault()
      const first = document.querySelector<HTMLElement>('#filters > :first-child')
      ;(first?.querySelector<HTMLElement>('input') ?? first)?.focus()
    },
    j: moveRow(1),
    k: moveRow(-1),
  })

  const label = pluralLabel(meta ?? summary, resource)
  const failure = metaError ?? error
  if (forbidden) return <ErrorState error={new ApiError(403)} label={label} />
  if (failure) return <ErrorState error={failure} label={label} onRetry={refetch} />
  if (!manifestPending && !summary) return <ErrorState error={new Error(`Unknown resource "${resource}"`)} />

  const csv = meta?.download_formats?.includes('csv')
  const headerActions: BarAction[] = [
    ...(csv ? [{ key: 'export_csv', label: 'Export CSV', kind: 'link' as const, enabled: true, href: exportHref(resource, 'csv', list), download: true }] : []),
    ...(meta?.action_items ?? []).filter((action) => action.key !== 'new'),
  ]
  const maxPerPage = site?.max_per_page
  const perPageOptions = (data?.meta.per_page_options ?? meta?.per_page_options ?? []).filter((n) => !maxPerPage || n <= maxPerPage)

  const scopes = data?.meta.scopes ?? meta?.scopes ?? []
  const currentScope = list.scope ?? data?.meta.current_scope ?? meta?.default_scope ?? scopes[0]?.id
  const filtered = Object.keys(list.q).length > 0
  const view = data?.meta.view ?? 'table'
  const views = meta?.index_views ?? []
  const defaults = data?.meta.default_row_actions !== false
  const actionsLabel = data?.meta.row_actions_label
  const title = data?.meta.title ?? summary?.plural_label

  return (
    <div className="flex flex-col gap-4">
      <WithSidebars
        sidebars={data?.meta.sidebars}
        ctx={{ resource }}
        header={(sidebarButton) => (
          <PageHeader title={title ?? <Skeleton className="h-8 w-48" />}>
            {views.length > 1 && <ViewSwitcher views={views} current={data?.meta.as ?? list.as} onChange={(as) => list.setParam('as', views.find((v) => v.as === as)?.default ? undefined : as)} />}
            {sidebarButton}
            <ActionBar
              actions={headerActions}
              ctx={{ resource }}
              lead={
                summary?.permissions.create && <NewButton summary={summary} />
              }
            />
          </PageHeader>
        )}
      >
        <DegradedNotice degraded={data?.degraded} classicHref={classicUrl(resource)} />

        {dropped.length > 0 && (
          <Alert>
            <Info />
            <AlertDescription className="flex items-start justify-between gap-3">
              <span>
                This link had filters {label} can't be filtered by, so they were ignored:{' '}
                {dropped.map((param, i) => (
                  <span key={param}>
                    {i > 0 && ', '}
                    <code className="rounded-sm bg-muted px-1 font-mono text-xs">{param}</code>
                  </span>
                ))}
              </span>
              <Button variant="ghost" size="icon-xs" aria-label="Dismiss" onClick={() => navigate({ search: location.search }, { replace: true, state: null })}>
                <X />
              </Button>
            </AlertDescription>
          </Alert>
        )}

        {scopes.length > 0 && <ScopeTabs scopes={scopes} current={currentScope} onChange={(scope) => list.setParam('scope', scope)} />}

        {meta && meta.filters.length > 0 && (
          <FilterBar filters={meta.filters} q={list.q} setQ={list.setQ} clearAll={list.clearFilters} compact={!desktop} />
        )}

        {selection.ids.size > 0 && (
          <BatchBar count={selection.ids.size} actions={batchActions} onRun={batch.run} onClear={selection.clear} />
        )}

        {!data || !meta ? (
          wide ? <TableSkeleton /> : <CardsSkeleton />
        ) : data.rows.length === 0 ? (
          filtered ? (
            <div className="flex flex-col items-start gap-3 rounded-lg border border-dashed bg-card p-8">
              <p className="text-base">No {label.toLowerCase()} match these filters</p>
              <Button variant="outline" onClick={list.clearFilters}>
                Clear filters
              </Button>
            </div>
          ) : (
            <BlankSlate label={label} summary={summary} slate={data.meta.blank_slate} />
          )
        ) : (
          <>
            {view !== 'table' ? (
              <RecordViews resource={resource} view={view} rows={data.rows} gridColumns={data.meta.grid_columns} stale={isPlaceholderData} defaultRowActions={defaults} />
            ) : wide ? (
              <DataTable
                resource={resource}
                columns={data.columns}
                rows={data.rows}
                order={data.meta.order}
                onOrder={(order) => list.setParam('order', order)}
                stale={isPlaceholderData}
                selection={batchActions.length ? selection : undefined}
                defaultRowActions={defaults}
                rowActionsLabel={actionsLabel}
              />
            ) : (
              <RecordCards resource={resource} columns={data.columns} rows={data.rows} stale={isPlaceholderData} selection={batchActions.length ? selection : undefined} defaultRowActions={defaults} />
            )}
            {data.meta.paginator !== false && (
              <Pagination
                meta={data.meta}
                rowCount={data.rows.length}
                perPageOptions={perPageOptions}
                onPage={(page) => list.setParam('page', page, false)}
                onPerPage={(perPage) => list.setParam('per_page', perPage)}
              />
            )}
          </>
        )}
        {batch.dialogs}
      </WithSidebars>
    </div>
  )
}
