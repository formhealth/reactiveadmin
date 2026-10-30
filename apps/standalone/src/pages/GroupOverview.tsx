import { Fragment } from 'react'
import { ExternalLink, FileText, Folder, Plus } from 'lucide-react'
import { Link, useParams } from 'react-router'
import type { MenuItem, ResourceSummary } from '@/api/generated/model'
import { ApiError } from '@/api/fetcher'
import { ClassicLink } from '@/components/ApiDenied'
import { MenuIcon } from '@/components/menu/MenuIcon'
import { ErrorState } from '@/components/ErrorState'
import { PageHeader } from '@/components/PageHeader'
import { Breadcrumb, BreadcrumbItem, BreadcrumbLink, BreadcrumbList, BreadcrumbPage, BreadcrumbSeparator } from '@/components/ui/breadcrumb'
import { Skeleton } from '@/components/ui/skeleton'
import { useDocumentTitle, useManifest, useMapClassic } from '@/hooks/useManifest'
import { classicPage, isDenied } from '@/lib/apiDenied'
import { findGroup, groupRoute, menuRoute, pruneMenu } from '@/lib/menu'

const QUICK_LINKS = 5

const leavesOf = (item: MenuItem): MenuItem[] => (item.children.length ? item.children.flatMap(leavesOf) : [item])

const newLink =
  'inline-flex h-8 shrink-0 items-center gap-1 rounded-md border px-2.5 text-sm outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring [&_svg:last-child]:size-3.5'

const quickLink = 'rounded-md border px-2 py-0.5 text-xs text-muted-foreground outline-none hover:bg-muted hover:text-foreground focus-visible:ring-2 focus-visible:ring-ring'

type RowProps = { item: MenuItem; resources: ResourceSummary[]; mapUrl: (url: string) => string | undefined }

function Row({ item, resources, mapUrl }: RowProps) {
  const isGroup = item.children.length > 0
  const to = isGroup ? groupRoute(item.id) : menuRoute(item, mapUrl)
  const summary = item.resource ? resources.find((r) => r.key === item.resource) : undefined
  const canCreate = !!summary?.permissions.create && summary.actions.includes('new') && (!isDenied(summary, 'new') || !!classicPage(summary, 'new', '/new'))
  const classicNew = classicPage(summary, 'new', '/new')
  const leaves = isGroup ? leavesOf(item) : []
  const external = !to && !!item.url

  return (
    <li className="flex items-start gap-3 px-4 py-3">
      <span aria-hidden className="mt-0.5 flex size-8 shrink-0 items-center justify-center rounded-md bg-muted text-muted-foreground">
        <MenuIcon name={item.icon} fallback={isGroup ? Folder : FileText} />
      </span>
      <div className="flex min-w-0 flex-1 flex-col gap-1">
        <div className="flex flex-wrap items-center gap-x-3 gap-y-1">
          {to ? (
            <Link to={to} className="font-semibold underline-offset-4 outline-none hover:underline focus-visible:ring-2 focus-visible:ring-ring">
              {item.label}
            </Link>
          ) : (
            <a href={item.url ?? undefined} target="_blank" rel="noopener noreferrer" className="inline-flex items-center gap-1 font-semibold underline-offset-4 hover:underline">
              {item.label}
              <ExternalLink aria-hidden className="size-3.5 text-muted-foreground" />
              <span className="sr-only">(opens in a new tab)</span>
            </a>
          )}
          {isGroup && <span className="text-xs text-muted-foreground">{leaves.length} {leaves.length === 1 ? 'page' : 'pages'}</span>}
          {external && <span className="text-xs text-muted-foreground">Classic admin</span>}
        </div>
        {item.description && <p className="text-muted-foreground">{item.description}</p>}
        {isGroup && (
          <ul aria-label={`Pages in ${item.label}`} className="flex flex-wrap gap-1.5 pt-1">
            {leaves.slice(0, QUICK_LINKS).map((leaf) => {
              const target = menuRoute(leaf, mapUrl)
              return (
                <li key={leaf.id}>
                  {target ? (
                    <Link to={target} className={quickLink}>
                      {leaf.label}
                    </Link>
                  ) : (
                    <a href={leaf.url ?? undefined} target="_blank" rel="noopener noreferrer" className={quickLink}>
                      {leaf.label}
                    </a>
                  )}
                </li>
              )
            })}
            {leaves.length > QUICK_LINKS && (
              <li>
                <Link to={groupRoute(item.id)} className={quickLink}>
                  +{leaves.length - QUICK_LINKS} more
                </Link>
              </li>
            )}
          </ul>
        )}
      </div>
      {canCreate &&
        summary &&
        (classicNew ? (
          <ClassicLink href={classicNew} className={newLink}>
            <Plus aria-hidden className="size-3.5" />
            New {summary.label}
          </ClassicLink>
        ) : (
          <Link to={`/${summary.key}/new`} className={newLink}>
            <Plus aria-hidden className="size-3.5" />
            New {summary.label}
          </Link>
        ))}
    </li>
  )
}

// A group header opened as a page: what lives in the section, with a line on each child and quick links into it.
export function GroupOverview() {
  const { '*': id = '' } = useParams()
  const { data, error } = useManifest()
  const mapUrl = useMapClassic()
  const found = data && findGroup(pruneMenu(data.menu), id)
  useDocumentTitle(found?.group.label)

  if (error && !data) return <ErrorState error={error} label="this section" />
  if (data && !found) return <ErrorState error={new ApiError(404)} label="this section" backTo={{ to: '/', label: 'Back to home' }} />

  return (
    <div className="flex flex-col gap-5">
      {found && found.path.length > 0 && (
        <Breadcrumb>
          <BreadcrumbList>
            {found.path.map((ancestor) => (
              <Fragment key={ancestor.id}>
                <BreadcrumbItem>
                  <BreadcrumbLink asChild>
                    <Link to={groupRoute(ancestor.id)}>{ancestor.label}</Link>
                  </BreadcrumbLink>
                </BreadcrumbItem>
                <BreadcrumbSeparator />
              </Fragment>
            ))}
            <BreadcrumbItem>
              <BreadcrumbPage>{found.group.label}</BreadcrumbPage>
            </BreadcrumbItem>
          </BreadcrumbList>
        </Breadcrumb>
      )}

      <div className="flex flex-col gap-1">
        <PageHeader title={found?.group.label ?? <Skeleton className="h-8 w-48" />} />
        {found?.group.description && <p className="max-w-2xl text-base text-muted-foreground">{found.group.description}</p>}
      </div>

      {found && data ? (
        <ul className="max-w-4xl divide-y rounded-lg border bg-card">
          {found.group.children.map((child) => (
            <Row key={child.id} item={child} resources={data.resources} mapUrl={mapUrl} />
          ))}
        </ul>
      ) : (
        <div className="flex max-w-4xl flex-col gap-3">
          {Array.from({ length: 4 }, (_, i) => (
            <Skeleton key={i} className="h-14 w-full" />
          ))}
        </div>
      )}
    </div>
  )
}
