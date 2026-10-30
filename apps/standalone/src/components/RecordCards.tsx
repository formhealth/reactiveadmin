import { Link, useLocation } from 'react-router'
import type { Column, Row } from '@/api/generated/model'
import { RowMenu } from '@/components/RowMenu'
import { Checkbox } from '@/components/ui/checkbox'
import type { Selection } from '@/hooks/useSelection'
import { cn } from '@/lib/utils'
import { rowTone } from '@/lib/tone'
import { NamedNode } from '@/nodes/Node'

const MAX_FIELDS = 6

type RecordCardsProps = { resource: string; columns: Column[]; rows: Row[]; stale?: boolean; selection?: Selection; defaultRowActions?: boolean }

export function RecordCards({ resource, columns, rows, stale, selection, defaultRowActions = true }: RecordCardsProps) {
  const { search } = useLocation()
  const primary = columns.find((c) => c.key !== 'id') ?? columns[0]

  return (
    <ul className={stale ? 'flex flex-col gap-2 opacity-60' : 'flex flex-col gap-2'}>
      {rows.map((row) => {
        // AA's display_name heads the card; without one the first real column does, and isn't repeated below.
        const others = columns.filter((c) => (row.display_name ? c.key !== 'id' && row.cells[c.key]?.text !== row.display_name : c !== primary))
        return (
        <li
          key={row.id}
          className={cn('relative rounded-lg border bg-card p-3 [&_a]:relative [&_a]:z-10 [&_[data-relative]]:hidden', row.tone && rowTone[row.tone], selection?.ids.has(row.id) && 'border-primary/50 bg-info-soft')}
        >
          {row.permissions.show && (
            <Link
              to={`/${resource}/${row.id}`}
              state={{ search }}
              data-row-link
              aria-label={`Open record ${row.id}`}
              className="absolute inset-0 z-0 rounded-lg outline-none focus-visible:ring-2 focus-visible:ring-ring"
            />
          )}
          <div className="flex items-start justify-between gap-2">
            <div className="flex min-w-0 items-center gap-2.5">
              {selection && (
                <Checkbox
                  aria-label={`Select record ${row.id}`}
                  checked={selection.ids.has(row.id)}
                  onCheckedChange={() => selection.toggle(row.id)}
                  className="relative z-10"
                />
              )}
              <h2 className="min-w-0 text-base font-semibold">
                {row.display_name ?? <NamedNode node={row.cells[primary.key] ?? { type: 'empty' }} names={[primary.key, primary.label]} />}
              </h2>
            </div>
            <RowMenu resource={resource} row={row} defaults={defaultRowActions} className="-mt-1 -mr-1 relative z-10" />
          </div>
          <dl className="mt-2 grid grid-cols-[minmax(0,auto)_1fr] gap-x-4 gap-y-1">
            {others.slice(0, MAX_FIELDS).map((column) => (
              <div key={column.key} className="col-span-2 grid grid-cols-subgrid items-baseline">
                <dt className="text-muted-foreground">{column.label}</dt>
                <dd className="min-w-0 break-words">
                  <NamedNode node={row.cells[column.key] ?? { type: 'empty' }} names={[column.key, column.label]} />
                </dd>
              </div>
            ))}
          </dl>
          {others.length > MAX_FIELDS && (
            <p className="mt-1 text-muted-foreground" title="More fields on the record page">
              …
            </p>
          )}
        </li>
        )
      })}
    </ul>
  )
}
