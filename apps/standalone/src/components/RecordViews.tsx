import type { CSSProperties } from 'react'
import { Link, useLocation } from 'react-router'
import type { IndexMetaView, Row } from '@/api/generated/model'
import { RowMenu } from '@/components/RowMenu'
import { Card, CardContent, CardFooter } from '@/components/ui/card'
import { hasRowActions } from '@/lib/permissions'
import { rowTone } from '@/lib/tone'
import { cn } from '@/lib/utils'
import { NodeContext } from '@/nodes/context'
import { NodeList } from '@/nodes/Node'

type RecordViewsProps = {
  resource: string
  view: Exclude<IndexMetaView, 'table'>
  rows: Row[]
  gridColumns?: number
  stale?: boolean
  defaultRowActions?: boolean
}

const grid = (n: number) => `repeat(${n}, minmax(0, 1fr))`

// Grid, blog and block presenters: each record is the layout the server walked out of the presenter's block.
export function RecordViews({ resource, view, rows, gridColumns = 3, stale, defaultRowActions = true }: RecordViewsProps) {
  const { search } = useLocation()
  const layout =
    view === 'grid'
      ? 'grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-(--columns)'
      : view === 'blog'
        ? 'mx-auto flex w-full max-w-3xl flex-col gap-6'
        : 'flex flex-col gap-4'

  return (
    <ul className={cn(layout, stale && 'opacity-60')} style={{ '--columns': grid(gridColumns) } as CSSProperties}>
      {rows.map((row) => (
        <li key={row.id} className="flex min-w-0">
          <Card className={cn('h-full w-full', row.tone && rowTone[row.tone])}>
            <CardContent className={cn('flex flex-1 flex-col gap-3', view === 'blog' && 'gap-4')}>
              <NodeContext value={{ resource, id: row.id, name: row.display_name }}>
                <NodeList nodes={row.layout} />
              </NodeContext>
            </CardContent>
            {(row.permissions.show || hasRowActions(row, defaultRowActions)) && (
              <CardFooter className="justify-between">
                {row.permissions.show ? (
                  <Link to={`/${resource}/${row.id}`} state={{ search }} className="text-sm underline underline-offset-4 outline-none hover:decoration-foreground focus-visible:ring-2 focus-visible:ring-ring">
                    Open{row.display_name ? <span className="sr-only"> {row.display_name}</span> : null}
                  </Link>
                ) : (
                  <span />
                )}
                <RowMenu resource={resource} row={row} defaults={defaultRowActions} />
              </CardFooter>
            )}
          </Card>
        </li>
      ))}
    </ul>
  )
}
