import { useMemo } from 'react'
import { flexRender, getCoreRowModel, useReactTable, type ColumnDef } from '@tanstack/react-table'
import { ArrowDown, ArrowUp, ChevronsUpDown } from 'lucide-react'
import { Link, useLocation, useNavigate } from 'react-router'
import type { Column, Row } from '@/api/generated/model'
import { RowMenu } from '@/components/RowMenu'
import { Checkbox } from '@/components/ui/checkbox'
import { Skeleton } from '@/components/ui/skeleton'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import type { Selection } from '@/hooks/useSelection'
import { hasRowActions } from '@/lib/permissions'
import { isUuid } from '@/lib/ids'
import { alignClass, columnTextClass, rowTone } from '@/lib/tone'
import { NamedNode } from '@/nodes/Node'
import { cn } from '@/lib/utils'

type DataTableProps = {
  resource: string
  columns: Column[]
  rows: Row[]
  order?: string | null
  onOrder: (order: string | undefined) => void
  stale?: boolean
  selection?: Selection
  // AA `actions defaults: false` leaves only the row's own actions; `actions name:` titles the column.
  defaultRowActions?: boolean
  rowActionsLabel?: string
}

const SORT = /^(.+)_(asc|desc)$/

// asc -> desc -> unsorted (falls back to the server default)
const nextOrder = (sortKey: string, order?: string | null) => {
  const [, key, dir] = SORT.exec(order ?? '') ?? []
  if (key !== sortKey) return `${sortKey}_asc`
  return dir === 'asc' ? `${sortKey}_desc` : undefined
}

// Headers may wrap so long labels don't widen their column past what the cells need (and clip the last one).
const headCell = 'sticky top-0 z-20 bg-card whitespace-normal shadow-[inset_0_-1px_0_var(--border)]'

function SortHeader({ column, order, onOrder }: { column: Column; order?: string | null; onOrder: DataTableProps['onOrder'] }) {
  if (!column.sortable) return column.label
  const sortKey = column.sort_key ?? column.key
  const [, key, dir] = SORT.exec(order ?? '') ?? []
  const Icon = key !== sortKey ? ChevronsUpDown : dir === 'asc' ? ArrowUp : ArrowDown
  return (
    <button
      type="button"
      onClick={() => onOrder(nextOrder(sortKey, order))}
      className="-mx-1.5 inline-flex items-center gap-1 rounded-sm text-left px-1.5 py-0.5 outline-none hover:bg-muted focus-visible:ring-2 focus-visible:ring-ring"
      aria-label={`Sort by ${column.label}`}
    >
      {column.label}
      <Icon className={cn('size-3.5', key !== sortKey && 'opacity-40')} />
    </button>
  )
}

export function DataTable({ resource, columns, rows, order, onOrder, stale, selection, defaultRowActions = true, rowActionsLabel }: DataTableProps) {
  const navigate = useNavigate()
  const { search } = useLocation()
  const hasActions = rows.some((row) => hasRowActions(row, defaultRowActions))
  const pageIds = rows.map((r) => r.id)
  const onPage = selection ? pageIds.filter((id) => selection.ids.has(id)).length : 0
  const uuidColumns = new Set(columns.filter((c) => rows.some((r) => isUuid(r.cells[c.key]?.text))).map((c) => c.key))
  const firstLeft = selection ? 'left-10' : 'left-0'

  const defs = useMemo<ColumnDef<Row>[]>(
    () =>
      columns.map((column) => ({
        id: column.key,
        header: () => <SortHeader column={column} order={order} onOrder={onOrder} />,
        cell: ({ row }) => <NamedNode node={row.original.cells[column.key] ?? { type: 'empty' }} names={[column.key, column.label]} />,
      })),
    [columns, order, onOrder],
  )
  // oxlint-disable-next-line react/incompatible-library -- TanStack Table's instance is stable and not passed to memoized children
  const table = useReactTable({ data: rows, columns: defs, getCoreRowModel: getCoreRowModel(), manualSorting: true, getRowId: (r) => r.id })

  return (
    <div className={cn('rounded-lg border bg-card', stale && 'opacity-60')}>
      <Table containerClassName="max-h-[max(24rem,calc(100dvh-18rem))] overflow-auto rounded-lg">
        <TableHeader>
          {table.getHeaderGroups().map((group) => (
            <TableRow key={group.id} className="hover:bg-transparent">
              {selection && (
                <TableHead className={cn(headCell, 'left-0 z-30 w-10 pr-0')}>
                  <Checkbox
                    aria-label="Select all on this page"
                    checked={onPage === 0 ? false : onPage === pageIds.length ? true : 'indeterminate'}
                    onCheckedChange={(on) => selection.togglePage(pageIds, on === true)}
                  />
                </TableHead>
              )}
              {group.headers.map((header, i) => (
                <TableHead
                  key={header.id}
                  aria-sort={sortAria(header.id, columns, order)}
                  className={cn(headCell, i === 0 && `${firstLeft} z-30`, uuidColumns.has(header.id) && 'w-24', columns[i]?.kind === 'index' && 'w-12', alignClass(columns[i]?.align))}
                >
                  {flexRender(header.column.columnDef.header, header.getContext())}
                </TableHead>
              ))}
              {hasActions && (
                <TableHead className={cn(headCell, 'right-0 z-30', rowActionsLabel ? 'text-right' : 'w-10')}>
                  <span className={rowActionsLabel ? undefined : 'sr-only'}>{rowActionsLabel ?? 'Actions'}</span>
                </TableHead>
              )}
            </TableRow>
          ))}
        </TableHeader>
        <TableBody>
          {table.getRowModel().rows.map((row) => {
            const canShow = !!row.original.permissions.show
            const path = `/${resource}/${row.id}`
            return (
              <TableRow
                key={row.id}
                data-state={selection?.ids.has(row.id) ? 'selected' : undefined}
                className={cn('bg-card transition-none hover:bg-muted focus-within:bg-muted data-[state=selected]:bg-info-soft', row.original.tone && rowTone[row.original.tone], canShow && 'cursor-pointer')}
                onClick={(e) => canShow && e.currentTarget.contains(e.target as Node) && !(e.target as HTMLElement).closest('a,button') && navigate(path, { state: { search } })}
              >
                {selection && (
                  <TableCell className="sticky left-0 z-20 w-10 bg-inherit pr-0">
                    <Checkbox aria-label={`Select record ${row.id}`} checked={selection.ids.has(row.id)} onCheckedChange={() => selection.toggle(row.id)} />
                  </TableCell>
                )}
                {row.getVisibleCells().map((cell, i) => (
                  <TableCell
                    key={cell.id}
                    className={cn(
                      'whitespace-normal [&_a]:relative [&_a]:z-10 [&_[data-relative]]:hidden',
                      i === 0 && `sticky ${firstLeft} z-10 bg-inherit font-semibold`,
                      alignClass(columns[i]?.align),
                      columnTextClass(columns[i]?.class_name),
                      columns[i]?.kind === 'index' && 'tabular-nums text-muted-foreground',
                    )}
                  >
                    {i === 0 && canShow && (
                      <Link
                        to={path}
                        state={{ search }}
                        data-row-link
                        aria-label={`Open record ${row.id}`}
                        className="absolute inset-0 z-0 outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-inset"
                      />
                    )}
                    {flexRender(cell.column.columnDef.cell, cell.getContext())}
                  </TableCell>
                ))}
                {hasActions && (
                  <TableCell className="sticky right-0 z-10 bg-inherit py-1 text-right">
                    <RowMenu resource={resource} row={row.original} defaults={defaultRowActions} />
                  </TableCell>
                )}
              </TableRow>
            )
          })}
        </TableBody>
      </Table>
    </div>
  )
}

function sortAria(columnId: string, columns: Column[], order?: string | null) {
  const column = columns.find((c) => c.key === columnId)
  const [, key, dir] = SORT.exec(order ?? '') ?? []
  if (!column || key !== (column.sort_key ?? column.key)) return undefined
  return dir === 'asc' ? 'ascending' : 'descending'
}

export function TableSkeleton({ columns = 6, rows = 10 }: { columns?: number; rows?: number }) {
  return (
    <div className="rounded-lg border bg-card" aria-hidden>
      <Table focusable={false}>
        <TableHeader>
          <TableRow>
            {Array.from({ length: columns }, (_, i) => (
              <TableHead key={i}>
                <Skeleton className="h-4 w-20" />
              </TableHead>
            ))}
          </TableRow>
        </TableHeader>
        <TableBody>
          {Array.from({ length: rows }, (_, r) => (
            <TableRow key={r} className="hover:bg-transparent">
              {Array.from({ length: columns }, (_, c) => (
                <TableCell key={c}>
                  <Skeleton className="h-4 w-full max-w-32" />
                </TableCell>
              ))}
            </TableRow>
          ))}
        </TableBody>
      </Table>
    </div>
  )
}

export function CardsSkeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div className="flex flex-col gap-2" aria-hidden>
      {Array.from({ length: rows }, (_, i) => (
        <div key={i} className="flex flex-col gap-2 rounded-lg border bg-card p-3">
          <Skeleton className="h-5 w-40" />
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-3/4" />
        </div>
      ))}
    </div>
  )
}
